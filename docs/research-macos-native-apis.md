# macOS Native APIs for System Automation - Research Report

**Date**: 2026-03-04
**Purpose**: Comprehensive research of macOS native APIs that can be used by the Voice Terminal app for system automation via voice commands.

**Current State**: The app already implements `CalendarAgent` (EventKit), `NotesAgent` (AppleScript), `AppLauncherAgent` (NSWorkspace), and `CLIAgent` (Process). The `IntentRecognizer` uses LLM-based intent classification with 4 intent types: `addCalendar`, `createNote`, `openApp`, `runCommand`.

---

## Table of Contents

1. [EventKit - Calendar & Reminders](#1-eventkit---calendar--reminders)
2. [Contacts Framework](#2-contacts-framework)
3. [FileManager / NSWorkspace](#3-filemanager--nsworkspace)
4. [Accessibility API (AXUIElement)](#4-accessibility-api-axuielement)
5. [AppleScript / JXA](#5-applescript--jxa)
6. [Shortcuts / App Intents Framework](#6-shortcuts--app-intents-framework)
7. [CoreSpotlight](#7-corespotlight)
8. [IOKit - Hardware Control](#8-iokit---hardware-control)
9. [MediaPlayer / NowPlaying](#9-mediaplayer--nowplaying)
10. [SystemConfiguration / Network](#10-systemconfiguration--network)
11. [CoreLocation](#11-corelocation)
12. [UNUserNotificationCenter](#12-unusernotificationcenter)
13. [ScreenCaptureKit](#13-screencapturekit)
14. [CoreBluetooth](#14-corebluetooth)
15. [NSAppleScript vs OSAScript](#15-nsapplescript-vs-osascript)
16. [Focus Modes API](#16-focus-modes-api)
17. [System Volume & Brightness Control](#17-system-volume--brightness-control)

---

## 1. EventKit - Calendar & Reminders

**Status**: Partially implemented (CalendarAgent exists)

### Capabilities
- Create, read, update, delete calendar events
- Create, read, update, delete reminders
- Fetch events by date range
- Create/manage reminder lists
- Set alarms and recurrence rules
- Support for multiple calendar accounts (iCloud, Google, Exchange)
- Async/await support with modern Swift concurrency

### Authorization Requirements
- `NSCalendarsUsageDescription` in Info.plist (read/write calendars)
- `NSRemindersUsageDescription` in Info.plist (read/write reminders)
- Runtime permission prompt via `requestFullAccessToEvents()` / `requestFullAccessToReminders()`
- App Sandbox: enable Calendar and/or Contacts entitlements

### macOS Version Availability
- EventKit: macOS 10.8+
- Full access APIs (replacing old `requestAccess`): macOS 14.0+
- Async/await variants: macOS 12.0+

### Voice Command Use Cases
- "Add a meeting tomorrow at 3pm" (already implemented)
- "What's on my calendar today?"
- "Remind me to buy groceries at 5pm"
- "Show my reminders for this week"
- "Delete the 2pm meeting"
- "Create a reminder list called Work"

### Swift Code Pattern
```swift
import EventKit

let store = EKEventStore()

// Request access (macOS 14+)
try await store.requestFullAccessToEvents()
try await store.requestFullAccessToReminders()

// Create event
let event = EKEvent(eventStore: store)
event.title = "Team Meeting"
event.startDate = Date().addingTimeInterval(3600)
event.endDate = Date().addingTimeInterval(7200)
event.calendar = store.defaultCalendarForNewEvents
try store.save(event, span: .thisEvent)

// Create reminder
let reminder = EKReminder(eventStore: store)
reminder.title = "Buy groceries"
reminder.calendar = store.defaultCalendarForNewReminders()
reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour], from: Date())
try store.save(reminder, commit: true)

// Fetch reminders
let predicate = store.predicateForReminders(in: nil)
let reminders = try await store.reminders(matching: predicate)
```

### Expansion Opportunities
- **Reminders**: Not yet implemented. Add `RemindersAgent` alongside `CalendarAgent`.
- **Calendar queries**: Add read capabilities ("what's on my calendar?")

---

## 2. Contacts Framework

**Status**: Not implemented

### Capabilities
- Read contacts (name, phone, email, address, birthday, etc.)
- Create new contacts
- Update existing contacts
- Delete contacts
- Search contacts by name, phone number, email
- Group management
- Contact images
- Unified contacts (merged across accounts)

### Authorization Requirements
- `NSContactsUsageDescription` in Info.plist
- Runtime permission via `CNContactStore().requestAccess(for: .contacts)`
- App Sandbox: enable "Contacts" under Signing & Capabilities
- Special entitlement `com.apple.developer.contacts.notes` for reading contact notes (macOS 13+)

### macOS Version Availability
- Contacts framework: macOS 10.11+
- Replaces AddressBook framework

### Voice Command Use Cases
- "What's John's phone number?"
- "Add a new contact: Jane Doe, 555-1234"
- "Find contacts named Smith"
- "What's my wife's email?"
- "Send John's number to clipboard"

### Swift Code Pattern
```swift
import Contacts

let store = CNContactStore()

// Request access
try await store.requestAccess(for: .contacts)

// Search contacts
let predicate = CNContact.predicateForContacts(matchingName: "John")
let keysToFetch: [CNKeyDescriptor] = [
    CNContactGivenNameKey as CNKeyDescriptor,
    CNContactFamilyNameKey as CNKeyDescriptor,
    CNContactPhoneNumbersKey as CNKeyDescriptor,
    CNContactEmailAddressesKey as CNKeyDescriptor
]
let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)

// Create contact
let newContact = CNMutableContact()
newContact.givenName = "Jane"
newContact.familyName = "Doe"
newContact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "555-1234"))]
let saveRequest = CNSaveRequest()
saveRequest.add(newContact, toContainerWithIdentifier: nil)
try store.execute(saveRequest)
```

### Priority: MEDIUM
- Useful for voice lookups ("what's X's phone number")
- Read-only operations are low-risk and high-value

---

## 3. FileManager / NSWorkspace

**Status**: Partially implemented (AppLauncherAgent uses NSWorkspace)

### Capabilities

**FileManager:**
- Create, read, write, delete files and directories
- Move, copy files
- Check file existence and attributes
- Enumerate directory contents
- Search for files
- Trash items (move to Trash instead of permanent delete)
- Access special directories (Documents, Downloads, Desktop, etc.)

**NSWorkspace:**
- Launch applications by name, URL, or bundle identifier
- Open files with specific applications
- Open URLs in default browser
- Reveal files in Finder
- Get running applications list
- Get app icons
- Monitor app launches/terminations via notification center
- File type/UTI information
- Recycle items to Trash

### Authorization Requirements
- **FileManager (sandboxed)**: Limited to app container unless user grants access via Open/Save panels or security-scoped bookmarks
- **FileManager (non-sandboxed)**: Full file system access
- **NSWorkspace**: No special entitlements for basic use; `com.apple.security.automation.apple-events` for inter-app scripting

### macOS Version Availability
- FileManager: macOS 10.0+ (Foundation)
- NSWorkspace: macOS 10.0+ (AppKit)
- `openApplication(at:configuration:)`: macOS 11.0+ (replaces deprecated `launchApplication`)

### Voice Command Use Cases
- "Open Safari" (already implemented)
- "Open my Downloads folder"
- "Create a folder called Projects on Desktop"
- "Move file X to folder Y"
- "Delete file X" (move to Trash)
- "Show file X in Finder"
- "What apps are running?"
- "Quit Safari"

### Swift Code Pattern
```swift
import AppKit

// Launch app by name (modern API)
let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari")!
try await NSWorkspace.shared.openApplication(at: url, configuration: .init())

// Open URL in browser
NSWorkspace.shared.open(URL(string: "https://example.com")!)

// Reveal file in Finder
NSWorkspace.shared.activateFileViewerSelecting([fileURL])

// Running apps
let runningApps = NSWorkspace.shared.runningApplications
    .filter { $0.activationPolicy == .regular }
    .map { $0.localizedName ?? "Unknown" }

// File operations
let fm = FileManager.default
try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
try fm.moveItem(at: sourceURL, to: destURL)
try fm.trashItem(at: fileURL, resultingItemURL: nil) // safe delete
```

### Expansion Opportunities
- **File operations agent**: Create, move, delete files via voice
- **App management**: List running apps, quit apps, switch to app
- **URL opening**: "Open google.com"

---

## 4. Accessibility API (AXUIElement)

**Status**: Not implemented (but AccessibilityTrust.swift exists for permission checking)

### Capabilities
- Read UI element tree of any application
- Get text content from UI elements (labels, text fields, buttons)
- Click buttons programmatically
- Type text into fields
- Read window positions and sizes
- Move/resize windows
- Get focused element
- Monitor UI changes via AXObserver
- Simulate keyboard/mouse events (via CGEvent)
- Full UI automation of third-party apps

### Authorization Requirements
- **Accessibility permission required** (System Settings > Privacy & Security > Accessibility)
- Must be granted per-app; user must manually enable
- **Cannot use App Sandbox** (incompatible with Mac App Store)
- No Info.plist key needed; checked at runtime via `AXIsProcessTrusted()`
- For CGEvent-based input simulation: additional "Input Monitoring" permission may be needed

### macOS Version Availability
- AXUIElement: macOS 10.2+ (ApplicationServices framework)
- AXObserver: macOS 10.2+
- CGEvent: macOS 10.4+

### Voice Command Use Cases
- "Click the Send button" (UI automation)
- "Read what's on the screen"
- "Type 'Hello World' in the search box"
- "Move this window to the left side"
- "Close this window"
- "What app is in the foreground?"
- "Read the notification on screen"
- "Resize the window to half screen"

### Swift Code Pattern
```swift
import ApplicationServices

// Check accessibility permission
guard AXIsProcessTrusted() else {
    // Prompt user to enable in System Settings
    let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
    AXIsProcessTrustedWithOptions(options)
    return
}

// Get frontmost app's UI elements
let app = NSWorkspace.shared.frontmostApplication!
let appElement = AXUIElementCreateApplication(app.processIdentifier)

// Get window
var windowValue: AnyObject?
AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowValue)

// Get all buttons in window
var childrenValue: AnyObject?
AXUIElementCopyAttributeValue(windowValue as! AXUIElement, kAXChildrenAttribute as CFString, &childrenValue)

// Perform click action on element
AXUIElementPerformAction(buttonElement, kAXPressAction as CFString)

// Read element text
var titleValue: AnyObject?
AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
let title = titleValue as? String
```

### Third-Party Libraries
- **AXorcist** (github.com/steipete/AXorcist): Modern Swift wrapper with async/await, fuzzy matching
- **AXSwift** (github.com/tmandry/AXSwift): Swift wrapper for accessibility clients
- **Nudge**: MCP server for AI agents using AX APIs

### Priority: HIGH
- Most powerful API for general-purpose automation
- Enables controlling ANY app's UI via voice
- Already have accessibility permission infrastructure

---

## 5. AppleScript / JXA

**Status**: Partially implemented (NotesAgent uses AppleScript via Process)

### Capabilities
- Control any scriptable macOS application
- Send Apple Events to apps
- GUI scripting (click menus, buttons via System Events)
- File system operations
- Shell command execution
- Network requests
- Inter-app communication
- Clipboard manipulation
- System dialogs and prompts
- Desktop and Finder automation

### Authorization Requirements
- `com.apple.security.automation.apple-events` entitlement
- `NSAppleEventsUsageDescription` in Info.plist
- Per-app automation permissions (user prompted on first use per target app)
- For GUI scripting: Accessibility permission required

### macOS Version Availability
- AppleScript: macOS 10.0+
- JXA (JavaScript for Automation): macOS 10.10+
- NSAppleScript: macOS 10.0+

### Voice Command Use Cases
- "Send an email to John about the meeting" (Mail.app scripting)
- "Play the next song" (Music.app)
- "Save the current document" (any scriptable app)
- "Create a new tab in Safari"
- "Take a screenshot"
- "Empty the trash"
- "Set desktop wallpaper"

### Swift Code Pattern
```swift
import Foundation

// Using NSAppleScript directly
let script = NSAppleScript(source: """
    tell application "Music"
        play
    end tell
""")!
var error: NSDictionary?
script.executeAndReturnError(&error)

// Using Process to run osascript (current approach in NotesAgent)
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
process.arguments = ["-e", """
    tell application "Notes"
        make new note at folder "Notes" with properties {name:"Title", body:"Content"}
    end tell
"""]
try process.run()

// Using JXA via osascript
let jxaProcess = Process()
jxaProcess.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
jxaProcess.arguments = ["-l", "JavaScript", "-e", """
    const app = Application("Music");
    app.playpause();
"""]
```

### Priority: HIGH
- Already partially used; expand to more apps
- Most versatile for controlling third-party apps
- Bridge to virtually any scriptable application

---

## 6. Shortcuts / App Intents Framework

**Status**: Not implemented

### Capabilities
- **App Intents**: Expose app actions to Siri, Shortcuts, and Spotlight
- **Shortcuts execution**: Run existing Shortcuts automations programmatically
- **System intents**: Leverage built-in system actions (send message, create event, etc.)
- **Entity queries**: Make app data searchable and actionable
- **Parameter resolution**: Interactive parameter collection via Siri
- **Spotlight integration**: App actions appear directly in Spotlight (macOS)
- **WWDC25 updates**: Swift Packages support, interactive snippets, deferred properties

### Authorization Requirements
- No special entitlements for basic App Intents
- Individual intents may require their own permissions (e.g., Contacts, Calendar)
- Shortcuts execution via URL scheme or `WKExtension`

### macOS Version Availability
- App Intents: macOS 13.0+ (Ventura)
- Shortcuts app on macOS: macOS 12.0+ (Monterey)
- Enhanced Spotlight integration: macOS 14.0+
- Swift Package support: macOS 16.0+ (WWDC25)

### Voice Command Use Cases
- "Run my Morning Routine shortcut"
- "Hey Siri, add to Voice Terminal" (expose app actions to Siri)
- "Run the backup shortcut"
- "List my shortcuts"
- User-created automations triggered by voice

### Swift Code Pattern
```swift
import AppIntents

// Define an App Intent
struct CreateReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Reminder"
    static var description = IntentDescription("Creates a reminder via Voice Terminal")

    @Parameter(title: "Title")
    var reminderTitle: String

    @Parameter(title: "Due Date")
    var dueDate: Date?

    func perform() async throws -> some IntentResult {
        // Create reminder using EventKit
        let store = EKEventStore()
        let reminder = EKReminder(eventStore: store)
        reminder.title = reminderTitle
        try store.save(reminder, commit: true)
        return .result(dialog: "Created reminder: \(reminderTitle)")
    }
}

// Run a Shortcut programmatically (via URL scheme)
if let url = URL(string: "shortcuts://run-shortcut?name=Morning%20Routine") {
    NSWorkspace.shared.open(url)
}
```

### Priority: MEDIUM-HIGH
- Enables bidirectional integration: Voice Terminal can both expose AND consume Shortcuts
- Running existing user Shortcuts extends capabilities massively
- Siri integration for free

---

## 7. CoreSpotlight

**Status**: Not implemented

### Capabilities
- Index app content for Spotlight search
- Make voice commands/history searchable via Spotlight
- Custom metadata for search items (title, description, dates, images)
- Semantic search support (macOS 15+)
- Deep linking from Spotlight results back to app
- Batch indexing and deletion
- Domain-based content organization
- Continuation of search from Spotlight into app

### Authorization Requirements
- No special entitlements required
- Works with App Sandbox
- `NSUserActivityTypes` in Info.plist for Handoff/deep linking

### macOS Version Availability
- CoreSpotlight: macOS 10.11+
- Semantic search: macOS 15.0+ (WWDC24)
- CSSearchQuery: macOS 10.12+

### Voice Command Use Cases
- "Search for meeting notes about Project X" (search indexed content)
- Index voice command history for quick re-execution
- Make app content discoverable via Spotlight
- "Find my note about shopping list"

### Swift Code Pattern
```swift
import CoreSpotlight

// Index an item
let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
attributeSet.title = "Shopping List"
attributeSet.contentDescription = "Buy milk, eggs, bread"
attributeSet.lastUsedDate = Date()

let item = CSSearchableItem(
    uniqueIdentifier: "note-123",
    domainIdentifier: "com.voiceterminal.notes",
    attributeSet: attributeSet
)

CSSearchableIndex.default().indexSearchableItems([item])

// Search programmatically
let query = CSSearchQuery(queryString: "shopping", attributes: ["title", "contentDescription"])
query.foundItemsHandler = { items in
    for item in items {
        print(item.attributeSet.title ?? "")
    }
}
query.start()
```

### Priority: LOW-MEDIUM
- Nice to have for making app content searchable
- Not a core automation capability
- Best used alongside other features (index command history, notes)

---

## 8. IOKit - Hardware Control

**Status**: Not implemented

### Capabilities
- Display brightness control (via private CoreDisplay API)
- Keyboard backlight control
- Battery status information
- USB device detection
- Power management
- Display sleep/wake
- Hardware sensor data (ambient light, temperature)
- Disk information

### Authorization Requirements
- No entitlements for reading hardware info
- Root or specific entitlements for some write operations
- **Brightness control uses private APIs** (CoreDisplay) - not suitable for App Store
- App Sandbox compatible for read-only operations

### macOS Version Availability
- IOKit: macOS 10.0+
- CoreDisplay (private): macOS 10.12.4+ (undocumented, changes between versions)
- M1/Apple Silicon requires different APIs than Intel for brightness

### Voice Command Use Cases
- "Set brightness to 50%"
- "Turn down the brightness"
- "What's my battery level?"
- "Dim the screen"
- "Turn off keyboard backlight"

### Swift Code Pattern
```swift
import IOKit
import IOKit.pwr_mgt

// Display sleep
let port = IOPMFindPowerManagement(mach_port_t(MACH_PORT_NULL))
IOPMSleepSystem(port)

// Battery info
let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as! [CFTypeRef]
if let source = sources.first {
    let info = IOPSGetPowerSourceDescription(snapshot, source).takeUnretainedValue() as! [String: Any]
    let capacity = info[kIOPSCurrentCapacityKey] as? Int // Battery percentage
}

// Brightness (via private CoreDisplay API - not recommended for App Store)
// Requires dynamic loading of CoreDisplay framework
typealias SetBrightnessFunc = @convention(c) (UInt32, Float) -> Void
let lib = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_NOW)
let setBrightness = unsafeBitCast(dlsym(lib, "CoreDisplay_Display_SetUserBrightness"), to: SetBrightnessFunc.self)
setBrightness(0, 0.5) // Set main display to 50%
```

### Priority: MEDIUM
- Battery info is useful and safe
- Brightness control relies on private APIs (fragile)
- Alternative: Use AppleScript to toggle System Settings or simulate keyboard brightness keys

---

## 9. MediaPlayer / NowPlaying (MRMediaRemote)

**Status**: Not implemented

### Capabilities

**Public APIs (MediaPlayer framework):**
- MPNowPlayingInfoCenter: Set/read now playing metadata
- MPRemoteCommandCenter: Respond to play/pause/next/prev commands
- MPMusicPlayerController: Control Apple Music playback

**Private APIs (MediaRemote.framework):**
- MRMediaRemoteSendCommand: Send play/pause/next/prev to any media app
- MRMediaRemoteGetNowPlayingInfo: Get currently playing track info
- MRMediaRemoteRegisterForNowPlayingNotifications: Monitor playback changes
- Control any media player (Spotify, YouTube in browser, etc.)

### Authorization Requirements
- **Public MediaPlayer**: No special entitlements
- **Private MRMediaRemote**: No entitlements needed (was working without), BUT **macOS 15.4+ added entitlement verification** in mediaremoted daemon
- App Store: Private framework usage will be rejected

### macOS Version Availability
- MediaPlayer: macOS 10.12.1+
- MRMediaRemote (private): macOS 10.12+ (broken on macOS 15.4+ without entitlement)

### Voice Command Use Cases
- "Play music" / "Pause music"
- "Next song" / "Previous song"
- "What's playing now?"
- "Volume up" / "Volume down"
- "Skip 15 seconds"
- "Play my Liked Songs playlist"

### Swift Code Pattern
```swift
// Option 1: AppleScript (recommended, works reliably)
let script = NSAppleScript(source: """
    tell application "Music" to playpause
""")!
script.executeAndReturnError(nil)

// Option 2: Simulate media keys (universal, works for any player)
func sendMediaKey(_ key: Int32) {
    let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key), keyDown: true)
    keyDown?.flags = .maskNonCoalesced
    let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key), keyDown: false)
    keyUp?.flags = .maskNonCoalesced
    keyDown?.post(tap: .cghidEventTap)
    keyUp?.post(tap: .cghidEventTap)
}
// NX_KEYTYPE_PLAY = 16, NX_KEYTYPE_NEXT = 17, NX_KEYTYPE_PREVIOUS = 18

// Option 3: MRMediaRemote (private, may break in future macOS versions)
// Load via dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote")
```

### Priority: HIGH
- Media control is one of the most requested voice commands
- AppleScript approach for Music.app is reliable
- Media key simulation works universally for any player
- Avoid private MRMediaRemote API due to macOS 15.4+ restrictions

---

## 10. SystemConfiguration / Network

**Status**: Not implemented

### Capabilities

**SystemConfiguration (legacy):**
- Network reachability monitoring
- Network interface information
- Proxy configuration
- DNS settings
- VPN detection

**Network framework (modern replacement):**
- NWPathMonitor: Monitor network path changes
- Interface type detection (Wi-Fi, Ethernet, Cellular)
- Connection quality
- Expensive/constrained path detection

**CoreWLAN:**
- Wi-Fi SSID and network info
- Wi-Fi scanning for available networks
- Connect/disconnect from Wi-Fi networks
- Wi-Fi signal strength (RSSI)

### Authorization Requirements
- **NWPathMonitor**: No entitlements needed
- **CoreWLAN**: `com.apple.developer.networking.wifi-info` entitlement for Wi-Fi info
- **Location permission** required for Wi-Fi SSID on macOS 14+ (privacy protection)
- App Sandbox: enable "Outgoing Connections" and/or "Incoming Connections"

### macOS Version Availability
- SystemConfiguration: macOS 10.1+ (formally deprecated macOS 14.4)
- Network framework (NWPathMonitor): macOS 10.14+
- CoreWLAN: macOS 10.6+

### Voice Command Use Cases
- "Am I connected to WiFi?"
- "What's my WiFi network name?"
- "What's my IP address?"
- "Turn on/off WiFi"
- "Is the internet working?"
- "Connect to home WiFi"

### Swift Code Pattern
```swift
import Network
import CoreWLAN

// Network monitoring
let monitor = NWPathMonitor()
monitor.pathUpdateHandler = { path in
    let isConnected = path.status == .satisfied
    let isWiFi = path.usesInterfaceType(.wifi)
    let isExpensive = path.isExpensive
}
monitor.start(queue: .global())

// WiFi info (requires entitlement)
if let wifiClient = CWWiFiClient.shared().interface() {
    let ssid = wifiClient.ssid() // Current network name
    let rssi = wifiClient.rssiValue() // Signal strength
    let channel = wifiClient.wlanChannel()
}

// Toggle WiFi
let interface = CWWiFiClient.shared().interface()
try interface?.setPower(false) // Turn off WiFi
try interface?.setPower(true)  // Turn on WiFi
```

### Priority: LOW-MEDIUM
- WiFi info is useful but niche
- Network status queries are occasionally helpful
- WiFi toggle could be valuable for quick actions

---

## 11. CoreLocation

**Status**: Not implemented

### Capabilities
- Device geographic coordinates (latitude, longitude)
- Altitude
- Heading/compass direction
- Geocoding (coordinates <-> place names)
- Reverse geocoding (coordinates -> address)
- Region monitoring (geofencing)
- Significant location change monitoring
- Visit detection

### Authorization Requirements
- `NSLocationUsageDescription` in Info.plist
- `NSLocationWhenInUseUsageDescription` for when-in-use
- `NSLocationAlwaysUsageDescription` for background
- Runtime permission via `CLLocationManager.requestWhenInUseAuthorization()`
- App Sandbox compatible

### macOS Version Availability
- CoreLocation: macOS 10.6+
- CLGeocoder: macOS 10.8+
- Modern authorization APIs: macOS 11.0+

### Voice Command Use Cases
- "What's my location?"
- "What's the weather here?" (get coordinates, call weather API)
- "Find coffee shops near me" (get coordinates for search)
- "Navigate to 123 Main Street" (open in Maps)
- "Remind me to buy milk when I get home" (geofence reminder)

### Swift Code Pattern
```swift
import CoreLocation

class LocationService: NSObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()

    func requestLocation() {
        manager.delegate = self
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        // location.coordinate.latitude, location.coordinate.longitude

        // Reverse geocode
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, error in
            if let place = placemarks?.first {
                let address = "\(place.locality ?? ""), \(place.administrativeArea ?? "")"
            }
        }
    }
}
```

### Priority: LOW
- Useful mainly as a supporting capability for weather/map queries
- Mac desktop apps rarely need real-time location
- Could enhance context-aware commands

---

## 12. UNUserNotificationCenter

**Status**: Not implemented

### Capabilities
- Schedule local notifications (immediate, time-based, calendar-based)
- Rich notifications with images, actions, and categories
- Custom notification sounds
- Notification grouping
- Interactive notification actions (buttons, text input)
- Badge management
- Notification management (list, remove pending/delivered)
- Critical alerts (bypass Do Not Disturb)
- Time-sensitive notifications

### Authorization Requirements
- Runtime permission via `requestAuthorization(options:)`
- Options: `.alert`, `.sound`, `.badge`, `.criticalAlert`
- Critical alerts: `com.apple.developer.usernotifications.critical-alerts` entitlement (requires Apple approval)
- Time-sensitive: `com.apple.developer.usernotifications.time-sensitive` entitlement

### macOS Version Availability
- UNUserNotificationCenter: macOS 10.14+
- Time-sensitive: macOS 12.0+
- Communication notifications: macOS 15.0+

### Voice Command Use Cases
- "Remind me in 30 minutes to check the oven"
- "Set a timer for 5 minutes"
- "Notify me at 3pm about the meeting"
- Command execution feedback (success/failure notifications)
- Background task completion alerts

### Swift Code Pattern
```swift
import UserNotifications

let center = UNUserNotificationCenter.current()

// Request permission
try await center.requestAuthorization(options: [.alert, .sound, .badge])

// Schedule notification
let content = UNMutableNotificationContent()
content.title = "Reminder"
content.body = "Check the oven!"
content.sound = .default

let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1800, repeats: false) // 30 min
let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
try await center.add(request)

// Calendar-based trigger
var dateComponents = DateComponents()
dateComponents.hour = 15
dateComponents.minute = 0
let calTrigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
```

### Priority: HIGH
- Essential for timer/reminder features
- Provides feedback for background operations
- Low complexity to implement
- Natural complement to voice commands

---

## 13. ScreenCaptureKit

**Status**: Not implemented

### Capabilities
- Capture screen content (full screen, windows, app-specific)
- Real-time screen streaming
- Audio capture from screen
- Content filtering (include/exclude windows, apps)
- Per-window and per-display capture
- Presenter overlay support
- HDR content capture
- Sample buffer output for processing

### Authorization Requirements
- User must grant Screen Recording permission (System Settings > Privacy & Security > Screen Recording)
- Runtime: `SCShareableContent.current` triggers permission prompt
- `com.apple.security.temporary-exception.screen-capture` for sandboxed apps
- Persistent content capture: `com.apple.developer.screen-capture.persistent` entitlement

### macOS Version Availability
- ScreenCaptureKit: macOS 12.3+
- Enhanced filtering: macOS 13.0+
- Presenter overlay: macOS 14.0+

### Voice Command Use Cases
- "Take a screenshot"
- "Capture this window"
- "Start screen recording"
- "Screen share with AI" (send screen to vision model for analysis)
- "What's on my screen?" (OCR/vision analysis)

### Swift Code Pattern
```swift
import ScreenCaptureKit

// Get shareable content
let content = try await SCShareableContent.current

// Find a specific window
let windows = content.windows.filter { $0.owningApplication?.applicationName == "Safari" }

// Create a filter for a specific display
let display = content.displays.first!
let filter = SCContentFilter(display: display, excludingWindows: [])

// Configure stream
let config = SCStreamConfiguration()
config.width = 1920
config.height = 1080
config.pixelFormat = kCVPixelFormatType_32BGRA

// Create and start stream
let stream = SCStream(filter: filter, configuration: config, delegate: self)
try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global())
try await stream.startCapture()
```

### Priority: LOW-MEDIUM
- Screenshot capability is convenient
- Screen analysis (with AI vision) could be powerful but complex
- Screen recording is niche for voice control

---

## 14. CoreBluetooth

**Status**: Not implemented

### Capabilities
- Scan for BLE (Bluetooth Low Energy) peripherals
- Connect to BLE devices
- Discover services and characteristics
- Read/write BLE characteristics
- Subscribe to notifications from BLE devices
- Act as BLE peripheral (advertise services)
- BR/EDR (Classic Bluetooth) support on macOS

### Authorization Requirements
- `NSBluetoothAlwaysUsageDescription` in Info.plist
- App Sandbox: enable "Bluetooth" under Hardware
- Runtime permission prompt on first use

### macOS Version Availability
- CoreBluetooth: macOS 10.10+
- CBCentralManager state restoration: macOS 10.13+

### Voice Command Use Cases
- "Connect to my headphones"
- "Disconnect Bluetooth"
- "List Bluetooth devices"
- "Toggle Bluetooth on/off" (requires System Events or private API)

### Swift Code Pattern
```swift
import CoreBluetooth

class BluetoothManager: NSObject, CBCentralManagerDelegate {
    var centralManager: CBCentralManager!

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                         advertisementData: [String: Any], rssi RSSI: NSNumber) {
        print("Found: \(peripheral.name ?? "Unknown") RSSI: \(RSSI)")
    }
}

// Toggle Bluetooth on/off via AppleScript (alternative)
// osascript -e 'tell application "System Events" to ...'
```

### Priority: LOW
- BLE device interaction is very niche
- Simple Bluetooth toggle better done via AppleScript/System Events
- Most users manage Bluetooth via Control Center

---

## 15. NSAppleScript vs OSAScript

**Status**: Partially implemented (NotesAgent uses Process + osascript)

### Comparison

| Feature | NSAppleScript | Process + osascript | JXA (osascript -l JavaScript) |
|---------|--------------|-------------------|------------------------------|
| Language | AppleScript | AppleScript | JavaScript |
| Execution | In-process | Subprocess | Subprocess |
| Performance | Faster (compile once, reuse) | Slower (new process each time) | Slower (new process each time) |
| Error handling | NSDictionary errors | Exit code + stderr | Exit code + stderr |
| Return values | NSAppleEventDescriptor | stdout text | stdout text |
| Sandbox | Requires entitlements | Requires entitlements | Requires entitlements |
| Compilation | Can pre-compile and cache | Compiles on each run | Compiles on each run |
| Thread safety | Must run on main thread | Can run on any thread | Can run on any thread |

### Recommendations
- **For performance-critical scripts**: Use `NSAppleScript` with pre-compilation
- **For simplicity and current architecture**: Continue using `Process` + `osascript` (already working)
- **For complex logic**: JXA is easier to maintain than AppleScript syntax
- **For maximum compatibility**: AppleScript has broader app scripting support than JXA

### Swift Code Pattern
```swift
// NSAppleScript (in-process, faster)
let script = NSAppleScript(source: "tell application \"Finder\" to get name of every window")!
var error: NSDictionary?
let result = script.executeAndReturnError(&error)
if let error = error {
    print("Error: \(error)")
} else {
    print("Result: \(result.stringValue ?? "")")
}

// Process + osascript (subprocess, current approach)
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
process.arguments = ["-e", "tell application \"Finder\" to get name of every window"]
let pipe = Pipe()
process.standardOutput = pipe
try process.run()
process.waitUntilExit()
let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)

// JXA (JavaScript for Automation)
let jxaProcess = Process()
jxaProcess.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
jxaProcess.arguments = ["-l", "JavaScript", "-e", """
    const finder = Application("Finder");
    finder.windows().map(w => w.name());
"""]
```

### Priority: MEDIUM
- Consider migrating to NSAppleScript for performance
- Keep osascript as fallback for subprocess isolation
- JXA useful for complex scripting logic

---

## 16. Focus Modes API

**Status**: Not implemented

### Capabilities
- **Read Focus/DND status**: Detect if Do Not Disturb or a custom Focus mode is active
- **Toggle DND**: Enable/disable Do Not Disturb
- **Limited**: No official public API from Apple for programmatic Focus control

### Available Approaches

| Approach | Read | Write | Stability | App Store |
|----------|------|-------|-----------|-----------|
| Read assertion files | Yes | No | Fragile (filesystem paths change) | No |
| sindresorhus/do-not-disturb lib | Yes | Yes (pre-macOS 12) | Limited (broke on Big Sur+) | No |
| AppleScript + System Events | Yes (partial) | Yes (via UI scripting) | Medium | No (needs Accessibility) |
| Shortcuts integration | No | Yes (via Shortcuts) | Good | Yes |
| Private APIs | Yes | Yes | Very fragile | No |

### Authorization Requirements
- No official entitlement exists
- Reading Focus state: May require reading `~/Library/DoNotDisturb/DB/` files
- Writing Focus state: Requires Accessibility permission for UI scripting or private APIs
- sindresorhus library: Does not work with sandboxing

### macOS Version Availability
- Do Not Disturb: macOS 10.8+
- Focus modes: macOS 12.0+ (Monterey)
- Focus APIs have changed significantly between macOS versions

### Voice Command Use Cases
- "Turn on Do Not Disturb"
- "Turn off Do Not Disturb"
- "Enable Work Focus"
- "Am I in Do Not Disturb mode?"
- "Set focus to Sleep"

### Swift Code Pattern
```swift
// Approach 1: AppleScript UI scripting (most reliable for toggle)
let script = NSAppleScript(source: """
    tell application "System Events"
        tell process "Control Center"
            -- Click Focus button in menu bar
            -- This is fragile and depends on macOS version
        end tell
    end tell
""")
script?.executeAndReturnError(nil)

// Approach 2: Read DND state via defaults/files (read-only)
// macOS 12+: Read ~/Library/DoNotDisturb/DB/Assertions.json
let assertionsPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
if let data = try? Data(contentsOf: assertionsPath),
   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
    let isActive = !(json["data"] as? [[String: Any]] ?? []).isEmpty
}

// Approach 3: Shortcuts URL scheme
NSWorkspace.shared.open(URL(string: "shortcuts://run-shortcut?name=Toggle%20DND")!)
```

### Priority: LOW
- No stable public API
- Best approach: Create a Shortcut for DND toggle, invoke it via URL scheme
- Read status is fragile across macOS versions

---

## 17. System Volume & Brightness Control

**Status**: Not implemented

### Volume Control

#### Capabilities
- Get/set system output volume (0.0 - 1.0)
- Mute/unmute system audio
- Get/set per-device volume
- List audio devices
- Get/set input volume (microphone)

#### Approach Options

| Approach | Reliability | App Store | Complexity |
|----------|------------|-----------|------------|
| CoreAudio (AudioObjectSetPropertyData) | High | Yes | Medium |
| AppleScript ("set volume") | High | Yes (with entitlement) | Low |
| NSSound extension | High | Yes | Low |
| Media key simulation | Medium | No (needs accessibility) | Medium |

#### Swift Code Pattern
```swift
// Approach 1: AppleScript (simplest)
let script = NSAppleScript(source: "set volume output volume 50")!
script.executeAndReturnError(nil)

// Get volume
let getScript = NSAppleScript(source: "output volume of (get volume settings)")!
var error: NSDictionary?
let result = getScript.executeAndReturnError(&error)
let volume = result.int32Value // 0-100

// Approach 2: CoreAudio (most reliable)
import CoreAudio

func setSystemVolume(_ volume: Float32) {
    var defaultDevice = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &defaultDevice)

    var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyVolumeScalar,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: 1
    )
    var vol = volume
    AudioObjectSetPropertyData(defaultDevice, &volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &vol)
}

// Mute/unmute
func setMute(_ muted: Bool) {
    var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    var value: UInt32 = muted ? 1 : 0
    AudioObjectSetPropertyData(defaultDevice, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
}
```

### Brightness Control

#### Capabilities
- Get/set display brightness (main display)
- External monitor brightness (limited support via DDC)

#### Approach Options

| Approach | Reliability | App Store | Notes |
|----------|------------|-----------|-------|
| CoreDisplay private API | Medium | No | Changes between macOS versions, different on Intel vs M1 |
| IOKit DisplayServices | Low | No | Deprecated |
| AppleScript key simulation | Medium | No (needs accessibility) | Fragile |
| Keyboard brightness keys (CGEvent) | Medium | No (needs accessibility) | Universal |

#### Swift Code Pattern
```swift
// Approach 1: AppleScript key simulation for brightness
func adjustBrightness(up: Bool) {
    let keyCode: Int32 = up ? 144 : 145 // Brightness up/down key codes
    let script = NSAppleScript(source: """
        tell application "System Events"
            key code \(keyCode)
        end tell
    """)
    script?.executeAndReturnError(nil)
}

// Approach 2: Private CoreDisplay API (fragile, not recommended)
// Requires loading private framework dynamically
```

### Voice Command Use Cases
- "Set volume to 50%"
- "Mute" / "Unmute"
- "Volume up" / "Volume down"
- "Set brightness to 80%"
- "Dim the screen"
- "Turn up the brightness"

### Priority: HIGH (Volume) / MEDIUM (Brightness)
- Volume control via AppleScript is simple and reliable
- CoreAudio approach is more robust for volume
- Brightness control is fragile; recommend AppleScript key simulation

---

## Summary: Priority Matrix

### Tier 1 - High Priority (Implement First)

| API | Use Case | Complexity | Reliability |
|-----|----------|-----------|-------------|
| **UNUserNotificationCenter** | Timers, reminders, feedback | Low | High |
| **System Volume** (CoreAudio/AppleScript) | Volume control | Low | High |
| **MediaPlayer** (AppleScript + key sim) | Music play/pause/next | Low | High |
| **Accessibility API** | Universal UI automation | High | High |
| **AppleScript expansion** | Control any scriptable app | Low | High |

### Tier 2 - Medium Priority

| API | Use Case | Complexity | Reliability |
|-----|----------|-----------|-------------|
| **Contacts Framework** | Contact lookups | Low | High |
| **EventKit Reminders** | Reminder CRUD | Low | High |
| **Shortcuts/App Intents** | Run user shortcuts, Siri | Medium | High |
| **FileManager expansion** | File operations | Medium | High |
| **NSWorkspace expansion** | App management, quit apps | Low | High |
| **IOKit (battery)** | Battery info | Low | High |
| **NSAppleScript migration** | Performance improvement | Medium | High |

### Tier 3 - Low Priority

| API | Use Case | Complexity | Reliability |
|-----|----------|-----------|-------------|
| **CoreSpotlight** | Index app content | Medium | High |
| **CoreLocation** | Location context | Low | High |
| **SystemConfiguration** | Network status | Low | Medium |
| **ScreenCaptureKit** | Screenshots | Medium | High |
| **CoreBluetooth** | BLE device control | High | Medium |
| **Focus Modes** | DND toggle | Medium | Low |
| **Brightness control** | Display brightness | Medium | Low |

---

## Recommended New Intent Types

Based on this research, the following intent types should be added to `IntentRecognizer`:

```swift
enum IntentType: String, Codable {
    // Existing
    case addCalendar
    case createNote
    case openApp
    case runCommand

    // Tier 1 additions
    case setTimer           // "Set a timer for 5 minutes"
    case setReminder        // "Remind me to call mom at 3pm"
    case mediaControl       // "Play music", "Next song", "Pause"
    case volumeControl      // "Set volume to 50%", "Mute"
    case uiAutomation       // "Click the Send button"

    // Tier 2 additions
    case findContact        // "What's John's phone number?"
    case addContact         // "Add contact Jane Doe"
    case fileOperation      // "Create folder on Desktop"
    case appControl         // "Quit Safari", "List running apps"
    case runShortcut        // "Run my Morning Routine shortcut"
    case brightnessControl  // "Set brightness to 50%"
    case batteryStatus      // "What's my battery level?"

    // Tier 3 additions
    case searchContent      // "Search for meeting notes"
    case networkStatus      // "Am I on WiFi?"
    case getLocation        // "What's my location?"
    case toggleDND          // "Turn on Do Not Disturb"
    case screenshot         // "Take a screenshot"

    case unrecognized
}
```

---

## Recommended New Agents

```
Sources/Shared/Terminal/Agents/
  CalendarAgent.swift          (existing)
  NotesAgent.swift             (existing)
  AppLauncherAgent.swift       (existing - expand to AppControlAgent)
  CLIAgent.swift               (existing)

  // New agents
  ReminderAgent.swift          // EventKit reminders
  MediaControlAgent.swift      // Play/pause/next via AppleScript + key sim
  VolumeAgent.swift            // CoreAudio volume + mute
  TimerAgent.swift             // UNUserNotificationCenter timers
  NotificationAgent.swift      // Local notifications
  ContactsAgent.swift          // Contacts framework lookups
  FileAgent.swift              // FileManager operations
  UIAutomationAgent.swift      // AXUIElement UI automation
  ShortcutsAgent.swift         // Run Shortcuts
  SystemInfoAgent.swift        // Battery, WiFi, location (combined)
  BrightnessAgent.swift        // Display brightness
  ScreenshotAgent.swift        // ScreenCaptureKit
```

---

## Key Technical Recommendations

1. **AppleScript as the universal glue**: Many capabilities (volume, media, DND, brightness) are most reliably controlled via AppleScript. Consider building a reusable `AppleScriptExecutor` utility.

2. **Avoid private APIs for critical features**: MRMediaRemote, CoreDisplay brightness, and Focus mode private APIs are fragile. Use AppleScript or simulated key events instead.

3. **Migrate to NSAppleScript for performance**: The current `Process` + `osascript` approach creates a new subprocess for each script. `NSAppleScript` runs in-process and can cache compiled scripts.

4. **Accessibility API is the power tool**: Once accessibility permission is granted, AXUIElement enables controlling ANY app. This should be the strategic investment for advanced automation.

5. **Shortcuts integration is the force multiplier**: By running user-created Shortcuts, the app gains access to hundreds of system actions without implementing each one natively.

6. **Sandbox considerations**: If targeting Mac App Store, many APIs (AXUIElement, CoreDisplay, Focus modes) are unavailable. For a Voice Terminal app, distributing outside the App Store (with notarization) is recommended.
