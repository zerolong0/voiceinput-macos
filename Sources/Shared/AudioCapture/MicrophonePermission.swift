//
//  MicrophonePermission.swift
//  VoiceInput
//
//  Microphone permission handling
//

import Foundation
import AVFoundation
import AVKit
import AppKit

/// Microphone permission status
public enum MicrophonePermissionStatus {
    case notDetermined
    case denied
    case granted

    public var isGranted: Bool {
        self == .granted
    }
}

/// Microphone permission helper
public final class MicrophonePermission {

    // MARK: - Singleton

    public static let shared = MicrophonePermission()

    // MARK: - Properties

    /// Current permission status
    public var status: MicrophonePermissionStatus {
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

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Request microphone permission
    public func request() async -> Bool {
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

    /// Request permission with callback
    public func request(completion: @escaping (Bool) -> Void) {
        #if os(macOS)
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
        #else
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
        #endif
    }

    /// Open system settings (macOS)
    public func openSystemSettings() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    /// Open system settings (iOS)
    public func openSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}
