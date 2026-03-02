//
//  AudioRecorder.swift
//  VoiceInput
//
//  Simplified audio recorder wrapper
//

import Foundation
import AVFoundation
import Combine

/// Audio recording delegate
public protocol AudioRecorderDelegate: AnyObject {
    func audioRecorderDidStartRecording()
    func audioRecorderDidStopRecording()
    func audioRecorderDidReceiveAudioBuffer(_ buffer: AVAudioPCMBuffer)
    func audioRecorderDidFail(error: Error)
}

/// Simplified audio recorder
public final class AudioRecorder: NSObject {

    // MARK: - Properties

    private let captureManager: AudioCaptureManager

    /// Buffer manager for storing recorded audio
    public let bufferManager: AudioBufferManager

    /// Delegate
    public weak var delegate: AudioRecorderDelegate?

    /// Recording state
    @Published public private(set) var isRecording: Bool = false

    /// Recording start time
    public private(set) var recordingStartTime: Date?

    /// Current recording duration
    public var recordingDuration: TimeInterval {
        guard let startTime = recordingStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }

    // MARK: - Initialization

    public init(format: AVAudioFormat? = nil) {
        self.captureManager = AudioCaptureManager()
        self.bufferManager = AudioBufferManager(format: format)
        super.init()

        setupDelegate()
    }

    // MARK: - Public Methods

    /// Request microphone permission
    public func requestPermission() async -> Bool {
        await captureManager.requestPermission()
    }

    /// Check permission status
    public var permissionStatus: MicrophonePermissionStatus {
        captureManager.permissionStatus
    }

    /// Start recording
    public func startRecording() throws {
        guard !isRecording else { return }

        // Clear previous buffer
        bufferManager.clear()

        // Start capture
        try captureManager.startCapture()

        isRecording = true
        recordingStartTime = Date()
        delegate?.audioRecorderDidStartRecording()
    }

    /// Stop recording
    public func stopRecording() {
        guard isRecording else { return }

        captureManager.stopCapture()
        isRecording = false
        delegate?.audioRecorderDidStopRecording()
    }

    /// Pause recording
    public func pauseRecording() {
        captureManager.pauseCapture()
    }

    /// Resume recording
    public func resumeRecording() throws {
        try captureManager.resumeCapture()
    }

    /// Get recorded audio data
    public func getRecordedData() -> Data? {
        bufferManager.getBufferedData()
    }

    /// Get recorded audio buffer
    public func getRecordedBuffer() -> AVAudioPCMBuffer? {
        bufferManager.getBufferedPCMBuffer()
    }

    /// Get last N seconds of recording
    public func getLastSeconds(_ seconds: TimeInterval) -> AVAudioPCMBuffer? {
        bufferManager.getLastSeconds(seconds)
    }

    // MARK: - Private Methods

    private func setupDelegate() {
        captureManager.delegate = self
    }
}

// MARK: - AudioCaptureDelegate

extension AudioRecorder: AudioCaptureDelegate {

    public func audioCaptureDidStart() {
        // Already handled in startRecording
    }

    public func audioCaptureDidStop() {
        // Already handled in stopRecording
    }

    public func audioCaptureDidReceiveBuffer(_ buffer: AVAudioPCMBuffer) {
        // Store in buffer manager
        bufferManager.appendBuffer(buffer)

        // Notify delegate
        delegate?.audioRecorderDidReceiveAudioBuffer(buffer)
    }

    public func audioCaptureDidDetectVoiceStart() {
        // Could notify delegate or update UI
    }

    public func audioCaptureDidDetectVoiceEnd() {
        // Could auto-stop recording here if needed
    }

    public func audioCaptureDidFail(error: Error) {
        delegate?.audioRecorderDidFail(error: error)
    }
}
