//
//  AudioBufferManager.swift
//  VoiceInput
//
//  Manages audio buffer for streaming to speech recognition
//

import Foundation
import AVFoundation

/// Audio buffer manager for streaming audio
public final class AudioBufferManager {

    // MARK: - Properties

    /// Maximum buffer duration in seconds (default: 60 seconds)
    public var maxDuration: TimeInterval = 60

    /// Current buffer duration in seconds
    public var currentDuration: TimeInterval {
        guard !buffers.isEmpty else { return 0 }
        return Double(totalFrames) / outputFormat.sampleRate
    }

    /// Total frames in buffer
    private var totalFrames: AVAudioFrameCount = 0

    /// Audio format (16kHz, mono, float32)
    private let outputFormat: AVAudioFormat

    /// Buffered PCM buffers
    private var buffers: [AVAudioPCMBuffer] = []

    /// Lock for thread safety
    private let lock = NSLock()

    /// Whether to append to buffer
    public var isBuffering: Bool = true

    // MARK: - Initialization

    public init(format: AVAudioFormat? = nil) {
        // Default to 16kHz mono float32
        self.outputFormat = format ?? AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!
    }

    // MARK: - Public Methods

    /// Append a buffer to the buffer list
    public func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }

        guard isBuffering else { return }

        // Check if format matches
        guard buffer.format.sampleRate == outputFormat.sampleRate &&
              buffer.format.channelCount == outputFormat.channelCount else {
            return
        }

        // Add buffer
        buffers.append(buffer)
        totalFrames += buffer.frameLength

        // Trim if exceeds max duration
        trimIfNeeded()
    }

    /// Get all buffered data as a single buffer
    public func getBufferedData() -> Data? {
        lock.lock()
        defer { lock.unlock() }

        guard !buffers.isEmpty else { return nil }

        // Get all float data
        var allData: [Float] = []

        for buffer in buffers {
            guard let channelData = buffer.floatChannelData?[0] else { continue }
            let frameCount = Int(buffer.frameLength)
            let data = UnsafeBufferPointer(start: channelData, count: frameCount)
            allData.append(contentsOf: data)
        }

        // Convert to Data
        return allData.withUnsafeBytes { Data($0) }
    }

    /// Get all buffered data as a single PCM buffer
    public func getBufferedPCMBuffer() -> AVAudioPCMBuffer? {
        lock.lock()
        defer { lock.unlock() }

        guard !buffers.isEmpty else { return nil }
        let totalFrameCount = buffers.reduce(0) { $0 + $1.frameLength }

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: totalFrameCount
        ) else {
            return nil
        }

        outputBuffer.frameLength = totalFrameCount

        guard let outputData = outputBuffer.floatChannelData?[0] else {
            return nil
        }

        var offset: Int = 0
        for buffer in buffers {
            guard let channelData = buffer.floatChannelData?[0] else { continue }
            let frameCount = Int(buffer.frameLength)
            outputData.advanced(by: offset).update(from: channelData, count: frameCount)
            offset += frameCount
        }

        return outputBuffer
    }

    /// Clear all buffers
    public func clear() {
        lock.lock()
        defer { lock.unlock() }

        buffers.removeAll()
        totalFrames = 0
    }

    /// Get last N seconds of audio
    public func getLastSeconds(_ seconds: TimeInterval) -> AVAudioPCMBuffer? {
        lock.lock()
        defer { lock.unlock() }

        let targetFrames = AVAudioFrameCount(seconds * outputFormat.sampleRate)

        // If total is less than target, return all
        guard totalFrames > targetFrames else {
            return getBufferedPCMBufferInternal()
        }

        // Collect frames from the end
        var neededFrames = Int(targetFrames)
        var allData: [Float] = []

        for buffer in buffers.reversed() {
            guard let channelData = buffer.floatChannelData?[0] else { continue }
            let frameCount = Int(buffer.frameLength)

            if neededFrames >= frameCount {
                let data = UnsafeBufferPointer(start: channelData, count: frameCount)
                allData.insert(contentsOf: data, at: 0)
                neededFrames -= frameCount
            } else {
                let startIndex = frameCount - neededFrames
                let data = UnsafeBufferPointer(start: channelData.advanced(by: startIndex), count: neededFrames)
                allData.insert(contentsOf: data, at: 0)
                neededFrames = 0
                break
            }
        }

        // Create buffer
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: targetFrames
        ) else {
            return nil
        }

        outputBuffer.frameLength = targetFrames

        if let outputData = outputBuffer.floatChannelData?[0] {
            outputData.update(from: allData, count: Int(targetFrames))
        }

        return outputBuffer
    }

    // MARK: - Private Methods

    private func trimIfNeeded() {
        while currentDuration > maxDuration && buffers.count > 1 {
            buffers.removeFirst()
            if !buffers.isEmpty {
                totalFrames = buffers.reduce(0) { $0 + $1.frameLength }
            }
        }
    }

    private func getBufferedPCMBufferInternal() -> AVAudioPCMBuffer? {
        guard !buffers.isEmpty else { return nil }

        let totalFrameCount = buffers.reduce(0) { $0 + $1.frameLength }

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: totalFrameCount
        ) else {
            return nil
        }

        outputBuffer.frameLength = totalFrameCount

        guard let outputData = outputBuffer.floatChannelData?[0] else {
            return nil
        }

        var offset: Int = 0
        for buffer in buffers {
            guard let channelData = buffer.floatChannelData?[0] else { continue }
            let frameCount = Int(buffer.frameLength)
            outputData.advanced(by: offset).update(from: channelData, count: frameCount)
            offset += frameCount
        }

        return outputBuffer
    }
}
