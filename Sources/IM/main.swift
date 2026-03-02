//
//  main.swift
//  VoiceInput
//
//  macOS Input Method entry point
//

import Cocoa
import InputMethodKit

// Global server instance
var server: IMKServer?

// Main entry point for Input Method
autoreleasepool {
    // Initialize the IMK server with connection name from Info.plist
    // The bundle identifier is used to locate the Info.plist
    server = IMKServer(
        name: "VoiceInput_Connection",
        bundleIdentifier: Bundle.main.bundleIdentifier!
    )

    // Run the application
    NSApplication.shared.run()
}
