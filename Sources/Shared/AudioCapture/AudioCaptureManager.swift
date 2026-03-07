//
//  AudioCaptureManager.swift
//  VoiceInput
//
//  Audio capture manager using AVAudioEngine for system microphone input
//

import AVFoundation
import Combine
import AVKit

/// Audio capture state
public enum AudioCaptureState: Equatable {
    case idle
    case recording
    case paused
    case error(String)

    public static func == (lhs: AudioCaptureState, rhs: AudioCaptureState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.recording, .recording), (.paused, .paused):
            return true
        case (.error(let lhsMsg), .error(let rhsMsg)):
            return lhsMsg == rhsMsg
        default:
            return false
        }
    }
}

/// Audio capture delegate
public protocol AudioCaptureDelegate: AnyObject {
    func audioCaptureDidStart()
    func audioCaptureDidStop()
    func audioCaptureDidReceiveBuffer(_ buffer: AVAudioPCMBuffer)
    func audioCaptureDidDetectVoiceStart()
    func audioCaptureDidDetectVoiceEnd()
    func audioCaptureDidFail(error: Error)
}

/// Default implementations for optional delegate methods
public extension AudioCaptureDelegate {
    func audioCaptureDidStart() {}
    func audioCaptureDidStop() {}
    func audioCaptureDidReceiveBuffer(_ buffer: AVAudioPCMBuffer) {}
    func audioCaptureDidDetectVoiceStart() {}
    func audioCaptureDidDetectVoiceEnd() {}
    func audioCaptureDidFail(error: Error) {}
}

/// Main audio capture manager using AVAudioEngine
public final class AudioCaptureManager: NSObject {

    // MARK: - Properties

    private let audioEngine = AVAudioEngine()
    private var inputNode: AVAudioInputNode { audioEngine.inputNode }

    /// Current capture state
    @Published public private(set) var state: AudioCaptureState = .idle

    /// Delegate for audio capture events
    public weak var delegate: AudioCaptureDelegate?

    /// VAD detector
    public let vadDetector: VADetector

    /// Audio format for output (16kHz, mono, float32)
    public let outputFormat: AVAudioFormat

    /// Whether VAD is enabled
    public var isVADEnabled: Bool = true {
        didSet {
            vadDetector.isEnabled = isVADEnabled
        }
    }

    /// Whether currently capturing audio
    public var isCapturing: Bool {
        state == .recording
    }

    // MARK: - Initialization

    public override init() {
        // Create output format: 16kHz, mono, float32
        self.outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!

        // Initialize VAD detector
        self.vadDetector = VADetector()

        super.init()

        // Setup VAD callbacks
        setupVADCallbacks()
    }

    // MARK: - Public Methods

    /// Request microphone permission
    public func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            #if os(macOS)
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
            #else
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
            #endif
        }
    }

    /// Check microphone permission status
    public var permissionStatus: MicrophonePermissionStatus {
        #if os(macOS)
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted:
            return .denied
        case .authorized:
            return .granted
        @unknown default:
            return .denied
        }
        #else
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .granted:
            return .granted
        @unknown default:
            return .denied
        }
        #endif
    }

    /// Start audio capture
    public func startCapture() throws {
        guard state != .recording else { return }

        // Check permission
        guard permissionStatus.isGranted else {
            throw AudioCaptureError.permissionDenied
        }

        // Get input format
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Validate input format
        guard inputFormat.sampleRate > 0 else {
            throw AudioCaptureError.invalidFormat
        }

        do {
            // Configure audio session (macOS doesn't have AVAudioSession like iOS)
            try configureAudioSession()

            // Install tap on input node
            inputNode.installTap(
                onBus: 0,
                bufferSize: 1024,
                format: inputFormat
            ) { [weak self] buffer, time in
                self?.processAudioBuffer(buffer)
            }

            // Start the audio engine
            try audioEngine.start()

            state = .recording
            delegate?.audioCaptureDidStart()

        } catch {
            state = .error(error.localizedDescription)
            delegate?.audioCaptureDidFail(error: error)
            throw error
        }
    }

    /// Stop audio capture
    public func stopCapture() {
        guard state == .recording else { return }

        inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        // Reset VAD state
        vadDetector.reset()

        state = .idle
        delegate?.audioCaptureDidStop()
    }

    /// Pause audio capture
    public func pauseCapture() {
        guard state == .recording else { return }

        audioEngine.pause()
        state = .paused
    }

    /// Resume audio capture
    public func resumeCapture() throws {
        guard state == .paused else { return }

        try audioEngine.start()
        state = .recording
    }

    // MARK: - Private Methods

    private func configureAudioSession() throws {
        // Audio session configuration
        // On macOS, audio session is managed by the system
        // No additional configuration needed for input methods
    }

    private func setupVADCallbacks() {
        vadDetector.onVoiceStart = { [weak self] in
            self?.delegate?.audioCaptureDidDetectVoiceStart()
        }

        vadDetector.onVoiceEnd = { [weak self] in
            self?.delegate?.audioCaptureDidDetectVoiceEnd()
        }
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Convert to output format if needed
        guard let convertedBuffer = convertFormat(buffer) else { return }

        // Process with VAD
        if let floatData = convertedBuffer.floatChannelData?[0] {
            let frameCount = Int(convertedBuffer.frameLength)
            _ = vadDetector.processAudioData(floatData, frameCount: frameCount)
        }

        // Notify delegate
        delegate?.audioCaptureDidReceiveBuffer(convertedBuffer)
    }

    private func convertFormat(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        // If already in correct format, return as-is
        if buffer.format.sampleRate == outputFormat.sampleRate &&
           buffer.format.channelCount == outputFormat.channelCount &&
           buffer.format.commonFormat == outputFormat.commonFormat {
            return buffer
        }

        // Create converter
        guard let converter = AVAudioConverter(from: buffer.format, to: outputFormat) else {
            return nil
        }

        // Calculate output frame capacity
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputFrameCapacity
        ) else {
            return nil
        }

        // Convert
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            delegate?.audioCaptureDidFail(error: error)
            return nil
        }

        return outputBuffer
    }
}

// MARK: - Errors

public enum AudioCaptureError: LocalizedError {
    case permissionDenied
    case invalidFormat
    case engineStartFailed
    case bufferConversionFailed

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission denied"
        case .invalidFormat:
            return "Invalid audio format"
        case .engineStartFailed:
            return "Failed to start audio engine"
        case .bufferConversionFailed:
            return "Failed to convert audio buffer"
        }
    }
}
