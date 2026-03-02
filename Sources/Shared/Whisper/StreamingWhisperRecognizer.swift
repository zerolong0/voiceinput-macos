//
//  StreamingWhisperRecognizer.swift
//  VoiceInput
//
//  Real-time streaming speech recognition using whisper.cpp
//

import Foundation
import AVFoundation
import Combine

/// Streaming recognition state
public enum StreamingRecognitionState: Equatable {
    case idle
    case listening
    case processing
    case error(String)

    public static func == (lhs: StreamingRecognitionState, rhs: StreamingRecognitionState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.listening, .listening), (.processing, .processing):
            return true
        case (.error(let lhsMsg), .error(let rhsMsg)):
            return lhsMsg == rhsMsg
        default:
            return false
        }
    }
}

/// Streaming speech recognizer using whisper
public final class StreamingWhisperRecognizer: NSObject {

    // MARK: - Properties

    /// Current recognition state
    @Published public private(set) var state: StreamingRecognitionState = .idle

    /// Whether voice is currently detected
    @Published public private(set) var isVoiceDetected: Bool = false

    /// Current recognized text (partial)
    @Published public private(set) var currentText: String = ""

    /// Final transcription result
    @Published public private(set) var finalResult: TranscriptionResult?

    /// Whisper engine
    public let whisperEngine: WhisperEngine

    /// Audio capture manager
    public let audioCaptureManager: AudioCaptureManager

    /// Minimum audio duration to process (seconds)
    public var minAudioDuration: Double = 0.5

    /// Maximum silence duration before stopping (seconds)
    public var maxSilenceDuration: Double = 2.0

    /// Whether to use VAD for automatic start/stop
    public var useVAD: Bool = true

    /// Delegate
    public weak var delegate: StreamingWhisperRecognizerDelegate?

    // MARK: - Private Properties

    private var silenceTimer: Timer?
    private var voiceStartTime: Date?
    private var lastAudioBuffer: [Float] = []
    private let bufferLock = NSLock()

    // MARK: - Initialization

    public init(whisperEngine: WhisperEngine, audioCaptureManager: AudioCaptureManager) {
        self.whisperEngine = whisperEngine
        self.audioCaptureManager = audioCaptureManager
        super.init()

        setupAudioCapture()
    }

    deinit {
        stop()
    }

    // MARK: - Setup

    private func setupAudioCapture() {
        audioCaptureManager.delegate = self

        // Configure audio capture for whisper input
        // Output format is already 16kHz mono float32
    }

    // MARK: - Public Methods

    /// Start streaming recognition
    public func start() throws {
        guard whisperEngine.isLoaded else {
            throw WhisperError.contextNotInitialized
        }

        guard state != .listening && state != .processing else {
            return
        }

        // Start audio capture
        try audioCaptureManager.startCapture()

        // Clear previous results
        currentText = ""
        finalResult = nil
        clearAudioBuffer()

        state = .listening
        delegate?.streamingRecognizerDidStart(self)

        print("[StreamingWhisperRecognizer] Started listening")
    }

    /// Stop streaming recognition
    public func stop() {
        // Stop audio capture
        audioCaptureManager.stopCapture()

        // Cancel silence timer
        silenceTimer?.invalidate()
        silenceTimer = nil

        // Process remaining audio
        if !lastAudioBuffer.isEmpty {
            processAudioBuffer(lastAudioBuffer)
        }

        state = .idle
        isVoiceDetected = false
        voiceStartTime = nil

        delegate?.streamingRecognizerDidStop(self)

        print("[StreamingWhisperRecognizer] Stopped")
    }

    /// Cancel current recognition without processing
    public func cancel() {
        audioCaptureManager.stopCapture()

        silenceTimer?.invalidate()
        silenceTimer = nil

        clearAudioBuffer()
        currentText = ""
        state = .idle
        isVoiceDetected = false
        voiceStartTime = nil

        print("[StreamingWhisperRecognizer] Cancelled")
    }

    // MARK: - Private Methods

    private func clearAudioBuffer() {
        bufferLock.lock()
        lastAudioBuffer.removeAll()
        bufferLock.unlock()
    }

    private func processAudioBuffer(_ buffer: [Float]) {
        guard !buffer.isEmpty else { return }

        state = .processing

        do {
            let result = try buffer.withUnsafeBufferPointer { ptr in
                try whisperEngine.transcribe(samples: ptr.baseAddress!, sampleCount: buffer.count)
            }

            currentText = result.text

            if !result.text.isEmpty {
                finalResult = result
                delegate?.streamingRecognizer(self, didTranscribe: result)
            }

            state = .listening

        } catch {
            state = .error(error.localizedDescription)
            delegate?.streamingRecognizer(self, didFailWithError: error)
        }
    }

    private func startSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: maxSilenceDuration, repeats: false) { [weak self] _ in
            self?.handleSilenceTimeout()
        }
    }

    private func stopSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil
    }

    private func handleSilenceTimeout() {
        guard state == .listening || state == .processing else { return }

        // Process any remaining audio
        bufferLock.lock()
        let buffer = lastAudioBuffer
        lastAudioBuffer.removeAll()
        bufferLock.unlock()

        if !buffer.isEmpty {
            processAudioBuffer(buffer)
        }

        // Stop if we have results
        if finalResult != nil {
            stop()
        }
    }
}

// MARK: - AudioCaptureDelegate

extension StreamingWhisperRecognizer: AudioCaptureDelegate {

    public func audioCaptureDidStart() {
        print("[StreamingWhisperRecognizer] Audio capture started")
    }

    public func audioCaptureDidStop() {
        print("[StreamingWhisperRecognizer] Audio capture stopped")
    }

    public func audioCaptureDidReceiveBuffer(_ buffer: AVAudioPCMBuffer) {
        // Get float data from buffer
        guard let floatData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)

        // Convert to array for processing
        let samples = Array(UnsafeBufferPointer(start: floatData, count: frameCount))

        // Append to buffer
        bufferLock.lock()
        lastAudioBuffer.append(contentsOf: samples)
        let currentBufferSize = lastAudioBuffer.count
        bufferLock.unlock()

        // Calculate audio duration in seconds
        let sampleRate = 16000.0
        let duration = Double(currentBufferSize) / sampleRate

        // If voice detected and we have enough audio, process it
        if useVAD && isVoiceDetected && duration >= minAudioDuration {
            // Process in chunks for real-time feedback
            let chunkSize = Int(sampleRate * 0.5)  // 500ms chunks

            bufferLock.lock()
            if lastAudioBuffer.count >= chunkSize {
                let chunk = Array(lastAudioBuffer.prefix(chunkSize))
                lastAudioBuffer.removeFirst(chunkSize)
                bufferLock.unlock()

                processAudioBuffer(chunk)
            } else {
                bufferLock.unlock()
            }

            // Reset silence timer when we have voice
            startSilenceTimer()
        }
    }

    public func audioCaptureDidDetectVoiceStart() {
        guard useVAD else { return }

        isVoiceDetected = true
        voiceStartTime = Date()
        stopSilenceTimer()

        delegate?.streamingRecognizer(self, didDetectVoiceStart: ())

        print("[StreamingWhisperRecognizer] Voice detected")
    }

    public func audioCaptureDidDetectVoiceEnd() {
        guard useVAD else { return }

        isVoiceDetected = false
        startSilenceTimer()

        delegate?.streamingRecognizer(self, didDetectVoiceEnd: ())

        print("[StreamingWhisperRecognizer] Voice ended, waiting for silence")
    }

    public func audioCaptureDidFail(error: Error) {
        state = .error(error.localizedDescription)
        delegate?.streamingRecognizer(self, didFailWithError: error)

        print("[StreamingWhisperRecognizer] Audio capture error: \(error.localizedDescription)")
    }
}

// MARK: - Delegate Protocol

public protocol StreamingWhisperRecognizerDelegate: AnyObject {
    func streamingRecognizerDidStart(_ recognizer: StreamingWhisperRecognizer)
    func streamingRecognizerDidStop(_ recognizer: StreamingWhisperRecognizer)
    func streamingRecognizer(_ recognizer: StreamingWhisperRecognizer, didTranscribe result: TranscriptionResult)
    func streamingRecognizer(_ recognizer: StreamingWhisperRecognizer, didDetectVoiceStart: ())
    func streamingRecognizer(_ recognizer: StreamingWhisperRecognizer, didDetectVoiceEnd: ())
    func streamingRecognizer(_ recognizer: StreamingWhisperRecognizer, didFailWithError error: Error)
}

public extension StreamingWhisperRecognizerDelegate {
    func streamingRecognizerDidStart(_ recognizer: StreamingWhisperRecognizer) {}
    func streamingRecognizerDidStop(_ recognizer: StreamingWhisperRecognizer) {}
    func streamingRecognizer(_ recognizer: StreamingWhisperRecognizer, didTranscribe result: TranscriptionResult) {}
    func streamingRecognizer(_ recognizer: StreamingWhisperRecognizer, didDetectVoiceStart: ()) {}
    func streamingRecognizer(_ recognizer: StreamingWhisperRecognizer, didDetectVoiceEnd: ()) {}
    func streamingRecognizer(_ recognizer: StreamingWhisperRecognizer, didFailWithError error: Error) {}
}
