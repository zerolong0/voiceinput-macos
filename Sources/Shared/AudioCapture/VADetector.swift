//
//  VADetector.swift
//  VoiceInput
//
//  Voice Activity Detection using energy-based detection
//

import Foundation
import AVFoundation

/// VAD detection result
public enum VADResult {
    case silence
    case voice
    case voiceStart
    case voiceEnd
}

/// VAD detector configuration
public struct VADConfig {
    /// Sample rate (default: 16000)
    public var sampleRate: Double = 16000

    /// Energy threshold for voice detection (0.0-1.0, default: 0.02)
    public var threshold: Float = 0.02

    /// Minimum frames of voice to detect (default: 3)
    public var minVoiceFrames: Int = 3

    /// Minimum frames of silence to end (default: 30 = ~1 second at 16kHz/1024)
    public var minSilenceFrames: Int = 30

    /// Initializer
    public init(
        sampleRate: Double = 16000,
        threshold: Float = 0.02,
        minVoiceFrames: Int = 3,
        minSilenceFrames: Int = 30
    ) {
        self.sampleRate = sampleRate
        self.threshold = threshold
        self.minVoiceFrames = minVoiceFrames
        self.minSilenceFrames = minSilenceFrames
    }
}

/// Voice Activity Detector using energy-based detection
public final class VADetector {

    // MARK: - Properties

    /// Configuration
    public var config: VADConfig

    /// Whether VAD is enabled
    public var isEnabled: Bool = true

    /// Callback when voice starts
    public var onVoiceStart: (() -> Void)?

    /// Callback when voice ends
    public var onVoiceEnd: (() -> Void)?

    /// Current state
    private var isVoiceActive: Bool = false

    /// Counter for consecutive voice frames
    private var voiceFrameCount: Int = 0

    /// Counter for consecutive silence frames
    private var silenceFrameCount: Int = 0

    /// Whether we've detected voice start
    private var hasDetectedVoice: Bool = false

    // MARK: - Initialization

    public init(config: VADConfig = VADConfig()) {
        self.config = config
    }

    // MARK: - Public Methods

    /// Process audio data and return VAD result
    public func processAudioData(_ data: UnsafePointer<Float>, frameCount: Int) -> VADResult {
        guard isEnabled else { return .voice }

        // Calculate RMS energy
        let energy = calculateRMS(data, frameCount: frameCount)

        // Check if above threshold
        let isVoice = energy > config.threshold

        if isVoice {
            silenceFrameCount = 0
            voiceFrameCount += 1

            // Check if we have enough consecutive voice frames
            if !isVoiceActive && voiceFrameCount >= config.minVoiceFrames {
                isVoiceActive = true
                hasDetectedVoice = true

                if !hasDetectedVoice {
                    onVoiceStart?()
                }

                return .voiceStart
            }

            return isVoiceActive ? .voice : .silence
        } else {
            voiceFrameCount = 0
            silenceFrameCount += 1

            // Check if we should end voice detection
            if isVoiceActive && silenceFrameCount >= config.minSilenceFrames {
                isVoiceActive = false

                onVoiceEnd?()

                return .voiceEnd
            }

            return .silence
        }
    }

    /// Reset detector state
    public func reset() {
        isVoiceActive = false
        voiceFrameCount = 0
        silenceFrameCount = 0
        hasDetectedVoice = false
    }

    /// Current VAD state
    public var isVoiceDetected: Bool {
        isVoiceActive
    }

    // MARK: - Private Methods

    /// Calculate RMS (Root Mean Square) energy
    private func calculateRMS(_ data: UnsafePointer<Float>, frameCount: Int) -> Float {
        var sum: Float = 0

        for i in 0..<frameCount {
            let sample = data[i]
            sum += sample * sample
        }

        let rms = sqrt(sum / Float(frameCount))
        return rms
    }
}
