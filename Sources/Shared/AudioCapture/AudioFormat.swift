//
//  AudioFormat.swift
//  VoiceInput
//
//  Audio format definitions and utilities
//

import Foundation
import AVFoundation

/// Audio format configuration
public struct AudioFormatConfig {
    /// Sample rate (default: 16000 for whisper)
    public var sampleRate: Double

    /// Number of channels (default: 1 for mono)
    public var channels: AVAudioChannelCount

    /// Bits per channel
    public var bitsPerChannel: UInt32

    /// Audio format
    public var format: AVAudioFormat

    /// Initializer
    public init(
        sampleRate: Double = 16000,
        channels: AVAudioChannelCount = 1,
        bitsPerChannel: UInt32 = 32
    ) throws {
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitsPerChannel = bitsPerChannel

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        ) else {
            throw AudioFormatError.invalidFormat
        }

        self.format = format
    }
}

/// Common audio format presets
public enum AudioFormatPreset {
    /// 16kHz mono float32 (for whisper)
    case whisper

    /// 16kHz mono int16 (for other speech APIs)
    case whisperInt16

    /// 44.1kHz stereo
    case highQuality

    /// Custom configuration
    case custom(sampleRate: Double, channels: AVAudioChannelCount)

    /// Get format configuration
    public var config: AudioFormatConfig {
        switch self {
        case .whisper:
            return try! AudioFormatConfig(sampleRate: 16000, channels: 1, bitsPerChannel: 32)
        case .whisperInt16:
            return try! AudioFormatConfig(sampleRate: 16000, channels: 1, bitsPerChannel: 16)
        case .highQuality:
            return try! AudioFormatConfig(sampleRate: 44100, channels: 2, bitsPerChannel: 32)
        case .custom(let sampleRate, let channels):
            return try! AudioFormatConfig(sampleRate: sampleRate, channels: channels)
        }
    }

    /// Get AVAudioFormat
    public var format: AVAudioFormat {
        config.format
    }
}

/// Audio format errors
public enum AudioFormatError: LocalizedError {
    case invalidFormat
    case conversionFailed

    public var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid audio format"
        case .conversionFailed:
            return "Audio format conversion failed"
        }
    }
}

/// Audio format utilities
public final class AudioFormatUtils {

    // MARK: - Format Conversion

    /// Convert float32 buffer to int16 data
    public static func floatToInt16(_ floatBuffer: AVAudioPCMBuffer) -> [Int16]? {
        guard let floatData = floatBuffer.floatChannelData?[0] else { return nil }

        let frameCount = Int(floatBuffer.frameLength)
        var int16Data: [Int16] = []

        for i in 0..<frameCount {
            let sample = floatData[i]
            // Clamp to [-1, 1] then convert to int16
            let clamped = max(-1.0, min(1.0, sample))
            let int16 = Int16(clamped * Float(Int16.max))
            int16Data.append(int16)
        }

        return int16Data
    }

    /// Convert int16 data to float32 buffer
    public static func int16ToFloat(_ int16Data: [Int16], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(int16Data.count)
        ) else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(int16Data.count)

        guard let floatData = buffer.floatChannelData?[0] else { return nil }

        for i in 0..<int16Data.count {
            floatData[i] = Float(int16Data[i]) / Float(Int16.max)
        }

        return buffer
    }

    /// Convert buffer to WAV data
    public static func toWAVData(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let floatData = buffer.floatChannelData?[0] else { return nil }

        let frameCount = Int(buffer.frameLength)

        // WAV header + PCM data
        var wavData = Data()

        // RIFF header
        wavData.append(contentsOf: "RIFF".utf8)
        let dataSize = UInt32(frameCount * 2) // 16-bit
        let fileSize = UInt32(36 + dataSize)
        wavData.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        wavData.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        wavData.append(contentsOf: "fmt ".utf8)
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) }) // chunk size
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM format
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // mono
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(16000).littleEndian) { Array($0) }) // sample rate
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(32000).littleEndian) { Array($0) }) // byte rate
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian) { Array($0) }) // block align
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) }) // bits per sample

        // data chunk
        wavData.append(contentsOf: "data".utf8)
        wavData.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        // PCM data (16-bit)
        for i in 0..<frameCount {
            let sample = max(-1.0, min(1.0, floatData[i]))
            let int16 = Int16(sample * Float(Int16.max))
            wavData.append(contentsOf: withUnsafeBytes(of: int16.littleEndian) { Array($0) })
        }

        return wavData
    }
}
