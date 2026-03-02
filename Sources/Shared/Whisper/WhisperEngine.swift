//
//  WhisperEngine.swift
//  VoiceInput
//
//  Swift wrapper for speech recognition - supports both whisper.cpp and Speech framework
//

import Foundation
import AVFoundation
import Speech

// MARK: - Whisper Engine Errors

public enum WhisperError: LocalizedError {
    case modelNotFound(String)
    case modelLoadFailed(String)
    case contextNotInitialized
    case transcriptionFailed(String)
    case invalidAudioFormat
    case notSupported
    case notAuthorized

    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let path):
            return "Model not found at path: \(path)"
        case .modelLoadFailed(let error):
            return "Failed to load model: \(error)"
        case .contextNotInitialized:
            return "Speech recognition not initialized"
        case .transcriptionFailed(let error):
            return "Transcription failed: \(error)"
        case .invalidAudioFormat:
            return "Invalid audio format"
        case .notSupported:
            return "Feature not supported"
        case .notAuthorized:
            return "Speech recognition not authorized"
        }
    }
}

// MARK: - Whisper Language

public enum WhisperLanguage: String, CaseIterable {
    case auto = "auto"
    case chinese = "zh-CN"
    case english = "en-US"
    case japanese = "ja-JP"
    case korean = "ko-KR"
    case french = "fr-FR"
    case german = "de-DE"
    case spanish = "es-ES"

    public var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .chinese: return "Chinese"
        case .english: return "English"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .french: return "French"
        case .german: return "German"
        case .spanish: return "Spanish"
        }
    }

    public var localeIdentifier: String? {
        switch self {
        case .auto: return nil
        case .chinese: return "zh-CN"
        case .english: return "en-US"
        case .japanese: return "ja-JP"
        case .korean: return "ko-KR"
        case .french: return "fr-FR"
        case .german: return "de-DE"
        case .spanish: return "es-ES"
        }
    }
}

// MARK: - Transcription Segment

public struct TranscriptionSegment {
    public let text: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval

    public init(text: String, startTime: TimeInterval, endTime: TimeInterval) {
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
    }
}

// MARK: - Transcription Result

public struct TranscriptionResult {
    public let segments: [TranscriptionSegment]
    public let language: String?
    public let text: String

    public init(segments: [TranscriptionSegment], language: String? = nil) {
        self.segments = segments
        self.language = language
        self.text = segments.map { $0.text }.joined()
    }
}

// MARK: - Whisper Engine Delegate

public protocol WhisperEngineDelegate: AnyObject {
    func whisperEngineDidStart(_ engine: WhisperEngine)
    func whisperEngineDidStop(_ engine: WhisperEngine)
    func whisperEngine(_ engine: WhisperEngine, didTranscribe result: TranscriptionResult)
    func whisperEngine(_ engine: WhisperEngine, didUpdatePartialResult text: String)
    func whisperEngine(_ engine: WhisperEngine, didFailWithError error: WhisperError)
}

// Default implementations
public extension WhisperEngineDelegate {
    func whisperEngineDidStart(_ engine: WhisperEngine) {}
    func whisperEngineDidStop(_ engine: WhisperEngine) {}
    func whisperEngine(_ engine: WhisperEngine, didTranscribe result: TranscriptionResult) {}
    func whisperEngine(_ engine: WhisperEngine, didUpdatePartialResult text: String) {}
    func whisperEngine(_ engine: WhisperEngine, didFailWithError error: WhisperError) {}
}

// MARK: - Whisper Engine

public final class WhisperEngine: NSObject {

    // MARK: - Properties

    public private(set) var isRunning: Bool = false
    public private(set) var isLoaded: Bool = false
    public var language: WhisperLanguage = .chinese
    public var threads: Int = 4
    public weak var delegate: WhisperEngineDelegate?

    // Speech recognition
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // Audio
    private let audioEngine = AVAudioEngine()
    private var audioBuffer: [Float] = []

    // State
    private var isUsingSystemSpeech: Bool = true

    // MARK: - Initialization

    public override init() {
        super.init()
        setupSpeechRecognizer()
    }

    deinit {
        stop()
    }

    // MARK: - Setup

    private func setupSpeechRecognizer() {
        if let locale = language.localeIdentifier {
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: locale))
        } else {
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
        }
    }

    // MARK: - Public Methods

    /// Request speech recognition authorization
    public static func requestAuthorization(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }

    /// Load model (using system Speech framework)
    public func loadModel(from path: String) throws {
        // Using system Speech framework instead of whisper.cpp
        isLoaded = true
        isUsingSystemSpeech = true
        print("[WhisperEngine] Using system Speech framework")
    }

    /// Check authorization status
    public var isAuthorized: Bool {
        return SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    /// Start recognition
    public func start() throws {
        guard isAuthorized else {
            throw WhisperError.notAuthorized
        }

        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            throw WhisperError.notSupported
        }

        // Cancel any existing task
        stop()

        // Note: macOS doesn't require AVAudioSession configuration like iOS

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw WhisperError.transcriptionFailed("Unable to create recognition request")
        }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false

        // Configure audio input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString
                self.delegate?.whisperEngine(self, didUpdatePartialResult: text)

                if result.isFinal {
                    let segments = [TranscriptionSegment(
                        text: text,
                        startTime: 0,
                        endTime: 0
                    )]
                    let transcriptionResult = TranscriptionResult(segments: segments, language: self.language.rawValue)
                    self.delegate?.whisperEngine(self, didTranscribe: transcriptionResult)
                }
            }

            if let error = error {
                self.delegate?.whisperEngine(self, didFailWithError: WhisperError.transcriptionFailed(error.localizedDescription))
                self.stop()
            }
        }

        // Start audio engine
        audioEngine.prepare()
        try audioEngine.start()

        isRunning = true
        delegate?.whisperEngineDidStart(self)
    }

    /// Stop recognition
    public func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil
        audioBuffer.removeAll()

        isRunning = false
        delegate?.whisperEngineDidStop(self)
    }

    /// Transcribe audio buffer
    public func transcribe(samples: UnsafePointer<Float>, sampleCount: Int) throws -> TranscriptionResult {
        // For real-time mode, use start() instead
        throw WhisperError.notSupported
    }

    /// Unload model
    public func unloadModel() {
        stop()
        isLoaded = false
    }

    /// Get model info
    public var modelInfo: String {
        return "Using system Speech framework (SFSpeechRecognizer)"
    }

    // MARK: - Static Methods

    public static func supportedLanguages() -> [WhisperLanguage] {
        return WhisperLanguage.allCases
    }

    public static func defaultModelDirectory() -> URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("VoiceInput/Models")
    }
}
