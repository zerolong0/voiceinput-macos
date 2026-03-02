import Foundation
import AVFoundation
import Speech
import ApplicationServices

struct PermissionDiagnostics {
    let bundleID: String
    let executablePath: String
    let inApplications: Bool
    let speechAuthorized: Bool
    let microphoneAuthorized: Bool
    let accessibilityAXAPI: Bool
    let accessibilityTCC: Bool

    var accessibilityEffective: Bool {
        accessibilityAXAPI
    }

    static func snapshot() -> PermissionDiagnostics {
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown.bundle"
        let executablePath = Bundle.main.executableURL?.path ?? "unknown"
        let resolved = URL(fileURLWithPath: executablePath).resolvingSymlinksInPath().path
        let inApplications =
            executablePath.hasPrefix("/Applications/") ||
            executablePath.hasPrefix("/System/Volumes/Data/Applications/") ||
            resolved.hasPrefix("/Applications/") ||
            resolved.hasPrefix("/System/Volumes/Data/Applications/")
        let speechAuthorized = SFSpeechRecognizer.authorizationStatus() == .authorized
        let microphoneAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let accessibilityAXAPI = AXIsProcessTrusted()
        let accessibilityTCC = AccessibilityTrust.tccAccessibilityAllowed(bundleID: bundleID)
        return PermissionDiagnostics(
            bundleID: bundleID,
            executablePath: executablePath,
            inApplications: inApplications,
            speechAuthorized: speechAuthorized,
            microphoneAuthorized: microphoneAuthorized,
            accessibilityAXAPI: accessibilityAXAPI,
            accessibilityTCC: accessibilityTCC
        )
    }
}
