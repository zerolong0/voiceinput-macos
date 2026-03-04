# Research: Apple Official Documentation for macOS Automation Capabilities

**Date**: 2026-03-04
**Scope**: Apple developer docs, WWDC sessions, frameworks, entitlements, and URL schemes relevant to building a macOS AI agent/automation app.

---

## Table of Contents

1. [App Intents Framework](#1-app-intents-framework)
2. [Shortcuts Integration](#2-shortcuts-integration)
3. [macOS 14 Sonoma Automation Features](#3-macos-14-sonoma-automation-features)
4. [macOS 15 Sequoia & Apple Intelligence](#4-macos-15-sequoia--apple-intelligence)
5. [Foundation Models Framework (WWDC 2025)](#5-foundation-models-framework-wwdc-2025)
6. [SiriKit on macOS](#6-sirikit-on-macos)
7. [Automator Integration](#7-automator-integration)
8. [URL Schemes for System Apps](#8-url-schemes-for-system-apps)
9. [EventKit (Calendar & Reminders)](#9-eventkit-calendar--reminders)
10. [NSUserActivity / Handoff](#10-nsuseractivity--handoff)
11. [Focus Modes API](#11-focus-modes-api)
12. [Accessibility API](#12-accessibility-api)
13. [Entitlements & Sandboxing](#13-entitlements--sandboxing)
14. [WWDC 2024/2025 Key Sessions](#14-wwdc-20242025-key-sessions)
15. [Recommendations for InputLess](#15-recommendations-for-inputless)

---

## 1. App Intents Framework

**Availability**: macOS 13+ (Ventura), iOS 16+
**Docs**: https://developer.apple.com/documentation/appintents

### Overview

App Intents is Apple's modern framework for exposing app functionality to the system. It replaces the older SiriKit Intents framework for most use cases. Swift source code is the source of truth -- no configuration files needed.

### Key Components

| Component | Purpose |
|-----------|---------|
| `AppIntent` protocol | Define an action your app can perform |
| `AppEntity` protocol | Define a dynamic data type (the "nouns") |
| `AppEnum` protocol | Define a static set of values |
| `AppShortcutsProvider` | Declare shortcuts your app provides out-of-box |
| `@Parameter` | Declare typed parameters for intents |
| `IntentResult` | Return values from intent execution |

### How It Works

1. **Define intents** by conforming to `AppIntent`
2. **Provide entities** via `EntityQuery` for dynamic lookups
3. **Register shortcuts** via `AppShortcutsProvider` for zero-config Siri phrases
4. System automatically discovers intents at build time via metadata extraction

### App Intent Domains (iOS 18 / macOS Sequoia)

Apple introduced 12 predefined domains with ~100 actions that integrate with Siri and Apple Intelligence:

1. **Books** - Open/navigate ebooks, play audiobooks, search library
2. **Browser** - Create/close tabs, bookmark URLs, clear history, search web
3. **Camera** - Start/stop capture, switch devices, set modes
4. **Reader** - Open/rotate/resize/enhance documents
5. **Files** - Open/delete/move/rename files, create folders
6. **Journal** - Create text/audio entries, update/delete/search
7. **Mail** - Create/save/send drafts, archive/delete/forward/reply, manage accounts
8. **Photos** - Open/create/delete/duplicate photos/albums, edit media
9. **Presentation** - Create/open/update presentations, manage slides
10. **Spreadsheet** - Create/open/update spreadsheets, manage sheets
11. **Whiteboard** - Create/open/update boards and items
12. **Document** - Create/open/manage documents and pages

### Assistant Schemas

Apps use `@AssistantSchema` macros to conform to Apple's predefined schemas:
- `@AssistantIntent(schema:)` -- validates intent conforms to assistant schema
- `@AssistantEntity(schema:)` -- validates entity shape
- `@AssistantEnum(schema:)` -- validates enum values

This allows Siri + Apple Intelligence to understand your app's actions without custom training.

### Relevance to InputLess

**High relevance**. InputLess should:
- Expose its own intents (e.g., "Start voice input", "Execute command X")
- Consume system intents from other apps to chain actions
- Register `AppShortcutsProvider` for voice-triggered automation
- Conform to relevant domains (e.g., Mail domain for composing emails)

---

## 2. Shortcuts Integration

### Programmatic Triggering Methods

#### Method 1: URL Scheme (`shortcuts://`)
```swift
// Run a shortcut by name
let url = URL(string: "shortcuts://run-shortcut?name=My%20Shortcut")!
NSWorkspace.shared.open(url)

// With x-callback-url for result handling
let url = URL(string: "shortcuts://x-callback-url/run-shortcut?name=My%20Shortcut&x-success=myapp://callback&x-error=myapp://error")!
NSWorkspace.shared.open(url)
```

**x-callback-url parameters**:
- `x-success` -- URL opened on successful completion
- `x-cancel` -- URL opened if shortcut is cancelled
- `x-error` -- URL opened on error

#### Method 2: Command Line (`shortcuts` CLI)
```bash
# Run a shortcut
shortcuts run "Shortcut Name"

# With file input
shortcuts run "Shortcut Name" -i /path/to/input

# With output capture
shortcuts run "Shortcut Name" -o /path/to/output

# List all shortcuts
shortcuts list

# Sign a shortcut
shortcuts sign -i unsigned.shortcut -o signed.shortcut
```

#### Method 3: Process/NSTask from Swift
```swift
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
process.arguments = ["run", "My Shortcut", "-i", inputPath, "-o", outputPath]
try process.run()
process.waitUntilExit()
```

### Known Limitations

- **No public `WFWorkflowController` API** -- The internal API for managing workflows is private
- **Sandboxed app limitation**: The `--input-path` flag for the `shortcuts` CLI does not work when run from a sandboxed app (FB13615584)
- **Best for non-interactive shortcuts**: Shortcuts that don't show alerts or ask for user input work best programmatically

### Relevance to InputLess

**Critical**. The Shortcuts integration gives InputLess a bridge to the entire Shortcuts ecosystem. Users can create custom automations in Shortcuts and trigger them via voice through InputLess. The CLI approach is most robust for a non-sandboxed app.

---

## 3. macOS 14 Sonoma Automation Features

### Key Additions
- **Interactive widgets on desktop** -- Widgets can now be placed on the desktop and interacted with directly
- **Web apps** -- Safari web apps can be added to the Dock
- **Video conferencing improvements** -- Presenter Overlay, screen sharing enhancements
- **App Intents improvements** -- Better entity resolution, transferable support

### Automation-Relevant APIs
- Improved `AppIntents` framework with better entity queries
- Enhanced Spotlight integration for App Intents
- Better Shortcuts app with improved action discovery

---

## 4. macOS 15 Sequoia & Apple Intelligence

**Docs**: https://developer.apple.com/apple-intelligence/

### Apple Intelligence APIs for Developers

1. **Writing Tools API** -- System-wide text rewriting, proofreading, summarization
2. **Genmoji API** -- Custom emoji generation
3. **Image Playground API** -- On-device image generation
4. **Foundation Models Framework** -- Direct access to on-device LLM (see section 5)

### Siri Enhancements
- More natural language understanding via LLM
- On-screen awareness -- Siri can see and act on what's displayed
- App Intents integration with Apple Intelligence for in-app actions
- New "Reduce Interruptions" Focus mode powered by AI

### Automation Enhancements
- **Enhanced Siri**: Can now understand and execute multi-step requests
- **App Intent Domains**: 12 new domains with ~100 predefined actions
- **On-screen context**: Siri can reference visible content
- **Cross-app actions**: Chain actions across multiple apps via App Intents

### Relevance to InputLess

**Very high**. macOS 15 is the ideal target platform. The Foundation Models framework could complement InputLess's own AI capabilities, and App Intent domains provide structured ways to interact with system apps.

---

## 5. Foundation Models Framework (WWDC 2025)

**Docs**: https://developer.apple.com/documentation/FoundationModels
**Availability**: macOS 26 (Tahoe), iOS 26, iPadOS 26

### Overview

Apple's Foundation Models framework gives developers direct access to the ~3B parameter on-device language model at the core of Apple Intelligence.

### Key Capabilities

- **Text generation** -- Summarization, entity extraction, text understanding, refinement
- **Guided generation** -- Structured output with type-safe Swift types
- **Tool calling** -- Model can autonomously decide when to call developer-defined tools
- **Stateful sessions** -- Maintain conversation context
- **Free of cost** -- No API fees, runs entirely on-device
- **Privacy-first** -- Data never leaves the device (or uses Private Cloud Compute)

### Integration Pattern
```swift
import FoundationModels

let session = LanguageModelSession()
let response = try await session.respond(to: "Summarize this text: ...")
print(response.content)
```

### Tool Calling
```swift
@Generable
struct SearchResult {
    let title: String
    let snippet: String
}

// Model can call tools you define to retrieve information or perform actions
```

### Relevance to InputLess

**Game-changing**. When macOS 26 ships, InputLess could use the Foundation Models framework for:
- On-device intent parsing (free, private, no API key needed)
- Tool calling to execute system actions
- Text summarization and extraction
- Reducing dependency on cloud-based LLM APIs

---

## 6. SiriKit on macOS

**Docs**: https://developer.apple.com/documentation/sirikit/

### Current State (2024-2025)

SiriKit's domain-specific intents are **deprecated** in favor of App Intents. However, existing SiriKit integrations in these domains still work:

- **Messaging** -- Send/search messages
- **Lists & Notes** -- Create/search lists and notes
- **Media** -- Play/search media
- **VoIP Calling** -- Start audio/video calls
- **Payments** -- Send/request payments
- **Workouts** -- Start/pause/end workouts
- **Restaurant Reservations** -- Book restaurants
- **Ride Booking** -- Book rides

### Migration Path

Apple recommends migrating to App Intents:
1. **SiriKit domain intents** (messaging, calling) -- Continue using SiriKit for now
2. **Custom intents** -- Migrate to App Intents
3. **New features** -- Always use App Intents

### Deprecated SiriKit Commands

22 SiriKit commands were deprecated starting iOS 15/macOS Monterey. Siri responds with "I can't support that request" for these.

### Relevance to InputLess

**Medium**. InputLess should use App Intents (not SiriKit) for all new integrations. Existing SiriKit domains for messaging and VoIP calling are still useful reference for what actions Siri already handles natively.

---

## 7. Automator Integration

**Docs**: https://developer.apple.com/documentation/automator/amworkflow

### Programmatic Access

#### AMWorkflow API
```swift
import Automator

// Load and run an Automator workflow
let workflowURL = URL(fileURLWithPath: "/path/to/workflow.workflow")
let workflow = try AMWorkflow(contentsOf: workflowURL)
let controller = AMWorkflowController()
controller.workflow = workflow
controller.run(self)
```

#### Via AppleScript
```applescript
tell application "Automator"
    open "/path/to/workflow.workflow"
    run
end tell
```

#### Via NSAppleScript in Swift
```swift
let script = NSAppleScript(source: """
    tell application "Automator"
        open "/path/to/workflow.workflow"
        run
    end tell
""")
var error: NSDictionary?
script?.executeAndReturnError(&error)
```

### Automator to Shortcuts Migration

Apple has been migrating from Automator to Shortcuts:
- macOS Monterey: Shortcuts app introduced on Mac
- Automator workflows can be imported into Shortcuts
- Automator is still available but no longer receiving new features

### Relevance to InputLess

**Low-Medium**. Automator is legacy but still widely used. InputLess should primarily target Shortcuts, but supporting Automator workflow execution provides backward compatibility for power users.

---

## 8. URL Schemes for System Apps

### Calendar
| Scheme | Purpose |
|--------|---------|
| `calshow:` | Open Calendar app at a specific date (Unix timestamp) |
| `calshow:{timestamp}` | Open Calendar at specific date |
| `x-apple-calevent://` | Open/create calendar events |

### Notes
| Scheme | Purpose |
|--------|---------|
| `notes://` | Open Notes app |
| `notes://showNote?identifier={UUID}` | Open a specific note by ID |
| `mobilenotes://` | Alternative Notes scheme |

**Programmatic access via AppleScript/ScriptingBridge**:
```applescript
tell application "Notes"
    make new note at folder "Notes" with properties {name:"Title", body:"Content"}
    -- Search notes
    set matchingNotes to every note whose name contains "search term"
end tell
```

### Mail
| Scheme | Purpose |
|--------|---------|
| `mailto:` | Compose email |
| `mailto:user@example.com?subject=Hello&body=Content` | With prefilled fields |
| `message://` | Open specific email message |

**Programmatic via ScriptingBridge**: Full email composition, sending, folder management.

### Messages
| Scheme | Purpose |
|--------|---------|
| `imessage:` | Open Messages/start iMessage conversation |
| `imessage://phone_or_email` | Message specific contact |
| `sms:` | Open Messages for SMS |
| `sms:phone_number&body=text` | SMS with body |

### Maps
| Scheme | Purpose |
|--------|---------|
| `maps://` | Open Maps |
| `maps://?q={SearchTerm}` | Search for location |
| `maps://?address={Address}` | Show specific address |
| `maps://?daddr={Address}` | Get directions |
| `maps://?ll={lat},{lon}` | Center map at coordinates |
| `http://maps.apple.com/?q=` | Web-compatible scheme |

### Reminders
No direct URL scheme. Access via:
- **EventKit framework** (see section 9)
- **AppleScript/ScriptingBridge**
- **App Intents** (Reminders domain)

### FaceTime
| Scheme | Purpose |
|--------|---------|
| `facetime://` | Start video call |
| `facetime:{phone_or_email}` | Video call specific contact |
| `facetime-audio://` | Start audio call |
| `facetime-audio:{phone_or_email}` | Audio call specific contact |
| `facetime-prompt://` | Video call with confirmation |
| `facetime-audio-prompt://` | Audio call with confirmation |

### Other Useful Schemes
| App | Scheme |
|-----|--------|
| Contacts | `contacts://` |
| Dictionary | `dict://` |
| Music | `music://` |
| Podcasts | `podcasts://` |
| App Store | `macappstore://` |
| System Preferences | `x-apple.systempreferences:` |
| Settings sections | `x-apple.systempreferences:{PaneID}` |

### Relevance to InputLess

**Critical**. URL schemes are the simplest and most reliable way to trigger system app actions from a non-sandboxed app. InputLess can map voice commands to URL scheme invocations with zero permission requirements.

---

## 9. EventKit (Calendar & Reminders)

**Docs**: https://developer.apple.com/documentation/eventkit

### Overview

EventKit provides programmatic access to Calendar and Reminders data. It's the only supported way to create, read, update, and delete calendar events and reminders.

### Key Classes

| Class | Purpose |
|-------|---------|
| `EKEventStore` | Central access point to Calendar database |
| `EKEvent` | Represents a calendar event |
| `EKReminder` | Represents a reminder |
| `EKCalendar` | Represents a calendar or reminder list |
| `EKSource` | Represents an account (iCloud, Exchange, etc.) |

### Usage Pattern
```swift
import EventKit

let store = EKEventStore()

// Request access (macOS 14+)
let granted = try await store.requestFullAccessToEvents()

// Create event
let event = EKEvent(eventStore: store)
event.title = "Meeting"
event.startDate = Date()
event.endDate = Date().addingTimeInterval(3600)
event.calendar = store.defaultCalendarForNewEvents
try store.save(event, span: .thisEvent)

// Create reminder
let reminder = EKReminder(eventStore: store)
reminder.title = "Buy groceries"
reminder.calendar = store.defaultCalendarForNewReminders()
try store.save(reminder, commit: true)

// Fetch events
let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
let events = store.events(matching: predicate)
```

### Required Entitlements
- `com.apple.security.personal-information.calendars` (for calendar access)
- Privacy usage descriptions in Info.plist:
  - `NSCalendarsUsageDescription`
  - `NSRemindersUsageDescription`
  - `NSCalendarsFullAccessUsageDescription` (macOS 14+)

### Relevance to InputLess

**High**. EventKit is the proper way to manage calendar and reminder data. Voice commands like "Create a meeting tomorrow at 3pm" or "Remind me to buy groceries" should use EventKit directly.

---

## 10. NSUserActivity / Handoff

**Docs**: https://developer.apple.com/documentation/foundation/nsuseractivity

### Overview

NSUserActivity represents the state of your app at a moment in time and enables:
- **Handoff** between devices (same iCloud account)
- **Spotlight indexing** of app content
- **Siri suggestions** based on user activity
- **Universal Links** handling

### Implementation
```swift
let activity = NSUserActivity(activityType: "com.myapp.viewDocument")
activity.title = "Viewing Document"
activity.userInfo = ["documentID": "123"]
activity.isEligibleForHandoff = true
activity.isEligibleForSearch = true
activity.isEligibleForPrediction = true // Siri Suggestions
activity.becomeCurrent()
```

### Cross-Device Automation Potential
- Activities advertised via Bluetooth LE/WiFi to nearby devices
- Same iCloud account required
- Responder chain manages activity lifecycle automatically
- Document-based apps get Handoff for free with iCloud documents

### Relevance to InputLess

**Medium**. Useful for:
- Continuing voice command sessions across devices (Mac to iPhone)
- Indexing InputLess commands in Spotlight for quick access
- Siri Suggestions for frequently used commands

---

## 11. Focus Modes API

**Docs**: https://developer.apple.com/documentation/intents/infocusstatuscenter

### API: INFocusStatusCenter

```swift
import Intents

// Check authorization
let status = INFocusStatusCenter.default.authorizationStatus

// Request authorization
INFocusStatusCenter.default.requestAuthorization { status in
    // .authorized, .denied, .notDetermined, .restricted
}

// Check if Focus is active
let isFocused = INFocusStatusCenter.default.focusStatus.isFocused
```

### Capabilities

| Capability | Available? |
|-----------|-----------|
| Read current focus state | Yes (with authorization) |
| Detect focus changes | Yes (via INShareFocusStatusIntent in Intent Extension) |
| Set/change focus mode | No (no public API) |
| Get specific focus mode name | No (only boolean isFocused) |

### Limitations

- **Read-only**: Cannot programmatically activate/deactivate Focus modes
- **Boolean only**: Can only check if _any_ focus is active, not which specific one
- **Requires Intent Extension**: Focus change notifications delivered via `INShareFocusStatusIntent`
- **macOS support**: Available but less documented than iOS

### Relevance to InputLess

**Low-Medium**. InputLess could:
- Adapt behavior when Focus is active (quieter notifications, reduced interruptions)
- Offer a voice command to check Focus status
- Cannot set Focus modes programmatically (would need Shortcuts bridge)

---

## 12. Accessibility API

**Docs**: https://developer.apple.com/documentation/applicationservices/axuielement

### Overview

The macOS Accessibility API (`AXUIElement`) provides programmatic access to UI elements of any running application. It is the most powerful automation API on macOS.

### Key APIs

```swift
import ApplicationServices

// Get system-wide element
let systemWide = AXUIElementCreateSystemWide()

// Get focused application
var focusedApp: AnyObject?
AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp)

// Get focused window
var focusedWindow: AnyObject?
AXUIElementCopyAttributeValue(focusedApp as! AXUIElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)

// Perform actions
AXUIElementPerformAction(element, kAXPressAction as CFString)

// Read attributes
var value: AnyObject?
AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
```

### Apple's Official Stance

Apple's Accessibility API documentation states it is designed for:
1. **Assistive technology** -- Screen readers, voice control, switch control
2. **Testing automation** -- UI testing frameworks
3. **Accessibility auditing** -- Checking app accessibility compliance

Apple does **not** explicitly prohibit using it for general automation, but:
- It requires explicit user permission in System Settings > Privacy & Security > Accessibility
- Sandboxed apps **cannot** use it (`AXIsProcessTrusted()` returns `false`)
- App Store apps cannot request Accessibility permissions

### Permission Requirements

```swift
// Check if app has Accessibility permission
let trusted = AXIsProcessTrusted()

// Prompt user to grant permission (shows System Settings)
let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
let trusted = AXIsProcessTrustedWithOptions(options)
```

### Relevance to InputLess

**Critical for advanced automation**. The Accessibility API is what enables InputLess to:
- Read UI state of any application
- Click buttons, fill text fields, navigate menus
- Perform actions in apps that don't have AppleScript/URL scheme support
- This is the "fallback" mechanism for apps without native integration

**Trade-off**: Requires non-sandboxed distribution (no Mac App Store) and explicit user permission.

---

## 13. Entitlements & Sandboxing

### Key Entitlements for Automation

| Entitlement | Purpose | Sandboxed? |
|-------------|---------|-----------|
| `com.apple.security.automation.apple-events` | Send Apple Events to other apps | Required for hardened runtime |
| `com.apple.security.temporary-exception.apple-events` | Target specific apps via Apple Events | Sandbox exception |
| `com.apple.security.scripting-targets` | Send events to apps with scripting access groups | Preferred for sandbox |
| `com.apple.security.personal-information.calendars` | Calendar/Reminders access | Available in sandbox |
| `com.apple.security.personal-information.contacts` | Contacts access | Available in sandbox |
| `com.apple.security.personal-information.location` | Location access | Available in sandbox |
| `com.apple.security.files.user-selected.read-write` | File access via Open/Save dialogs | Available in sandbox |

### Sandboxed vs Non-Sandboxed

| Capability | Sandboxed | Non-Sandboxed |
|-----------|-----------|---------------|
| Accessibility API (AXUIElement) | Not available | Available (with permission) |
| AppleScript/Apple Events | Limited (scripting-targets) | Full (with entitlement) |
| URL Schemes | Available | Available |
| EventKit | Available (with entitlement) | Available |
| App Intents | Available | Available |
| Shortcuts CLI | Limited (input-path bug) | Full |
| Process/NSTask | Not available | Available |
| ScriptingBridge | Not for App Store | Available |
| File system access | Sandboxed paths only | Full |

### App Store Review Implications

1. **App Sandbox required** for Mac App Store distribution
2. **Accessibility API usage** disqualifies from Mac App Store
3. **Apple Events** require justification to App Review if using temporary exceptions
4. **ScriptingBridge** cannot be used in App Store apps
5. **Direct distribution** (notarized, outside App Store) avoids most restrictions

### Recommendation for InputLess

**Distribute outside the Mac App Store** (notarized + direct download). This enables:
- Full Accessibility API access
- Unrestricted Apple Events
- Process spawning (CLI tools, Shortcuts CLI)
- ScriptingBridge for system apps
- No sandbox restrictions

---

## 14. WWDC 2024/2025 Key Sessions

### WWDC 2024

| Session | Relevance |
|---------|-----------|
| [Bring your app to Siri (10133)](https://developer.apple.com/videos/play/wwdc2024/10133/) | App Intent domains, assistant schemas |
| [What's new in App Intents (10134)](https://developer.apple.com/videos/play/wwdc2024/10134/) | New features: transferable, file representations |
| [Bring your app's core features to users (10210)](https://developer.apple.com/videos/play/wwdc2024/10210/) | Making actions discoverable in Spotlight/Shortcuts/Control Center |

### WWDC 2025

| Session | Relevance |
|---------|-----------|
| [Get to know App Intents (244)](https://developer.apple.com/videos/play/wwdc2025/244/) | Comprehensive intro to App Intents |
| [Develop for Shortcuts and Spotlight (260)](https://developer.apple.com/videos/play/wwdc2025/260/) | Building for Shortcuts and Spotlight on Mac |
| [Explore new advances in App Intents (275)](https://developer.apple.com/videos/play/wwdc2025/275/) | Latest App Intents improvements |
| [Meet the Foundation Models framework (286)](https://developer.apple.com/videos/play/wwdc2025/286/) | On-device LLM access |
| [Deep dive into Foundation Models (301)](https://developer.apple.com/videos/play/wwdc2025/301/) | Advanced FM framework usage |
| [Explore prompt design for on-device models (248)](https://developer.apple.com/videos/play/wwdc2025/248/) | Prompt engineering for Apple's on-device model |

---

## 15. Recommendations for InputLess

### Priority Tier 1: Core Integration (Implement First)

1. **URL Schemes** -- Immediate, zero-permission access to system apps
   - Calendar (`calshow:`), Mail (`mailto:`), FaceTime (`facetime:`/`facetime-audio:`), Messages (`imessage:`/`sms:`), Maps (`maps:`)

2. **Shortcuts CLI** -- Bridge to entire Shortcuts ecosystem
   - `shortcuts run "Name" -i input -o output`
   - Non-sandboxed app has full CLI access

3. **Accessibility API** -- Universal automation fallback
   - Requires user permission grant
   - Works with any app, even those without native integration

4. **EventKit** -- Calendar and Reminders CRUD
   - Proper API for creating/reading/updating events and reminders

### Priority Tier 2: Deep Integration (Next Phase)

5. **App Intents** -- Expose InputLess actions to Siri/Shortcuts/Spotlight
   - Register `AppShortcutsProvider` for common voice commands
   - Conform to assistant schemas for Apple Intelligence integration

6. **AppleScript/ScriptingBridge** -- Deep control of scriptable apps
   - Notes, Mail, Messages, Finder, Safari, etc.
   - Run via `NSAppleScript` or `Process` with `osascript`

7. **NSUserActivity** -- Spotlight indexing and Siri Suggestions
   - Index frequently used commands for quick access

### Priority Tier 3: Future (macOS 26+)

8. **Foundation Models Framework** -- On-device LLM for intent parsing
   - Replace or supplement cloud-based LLM with free on-device model
   - Tool calling for autonomous action execution
   - ~3B parameter model with guided generation

### Distribution Strategy

**Non-sandboxed, notarized, direct distribution** is required to access the full automation stack. Mac App Store distribution would severely limit capabilities (no AX API, restricted Apple Events, no Process spawning).

### Entitlements Needed

```xml
<!-- Info.plist -->
<key>NSCalendarsUsageDescription</key>
<string>InputLess needs calendar access to create and manage events via voice commands.</string>
<key>NSRemindersUsageDescription</key>
<string>InputLess needs reminders access to create and manage reminders via voice commands.</string>
<key>NSContactsUsageDescription</key>
<string>InputLess needs contacts access to look up contacts for calls and messages.</string>
<key>NSMicrophoneUsageDescription</key>
<string>InputLess needs microphone access for voice input.</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>InputLess needs speech recognition for converting voice to text.</string>

<!-- Entitlements -->
<key>com.apple.security.automation.apple-events</key>
<true/>
```

### Architecture Summary

```
Voice Input
    |
    v
Speech Recognition (Apple Speech / Whisper)
    |
    v
Intent Classification (LLM / Foundation Models)
    |
    v
Action Router
    |
    +---> URL Schemes (system apps: Calendar, Mail, Maps, FaceTime, Messages)
    +---> EventKit (Calendar & Reminders CRUD)
    +---> Shortcuts CLI (user-defined automations)
    +---> AppleScript/ScriptingBridge (scriptable apps: Notes, Mail, Finder, Safari)
    +---> Accessibility API (universal fallback for any app)
    +---> App Intents (expose to Siri/Shortcuts/Spotlight)
```

---

## Sources

- [App Intents Documentation](https://developer.apple.com/documentation/appintents)
- [Creating your first App Intent](https://developer.apple.com/documentation/appintents/creating-your-first-app-intent)
- [App Intent Domains](https://developer.apple.com/documentation/appintents/app-intent-domains)
- [Integrating actions with Siri and Apple Intelligence](https://developer.apple.com/documentation/appintents/integrating-actions-with-siri-and-apple-intelligence)
- [SiriKit Documentation](https://developer.apple.com/documentation/sirikit/)
- [Deprecated SiriKit Intent Domains](https://developer.apple.com/support/deprecated-sirikit-intent-domains)
- [EventKit Documentation](https://developer.apple.com/documentation/eventkit)
- [NSUserActivity Documentation](https://developer.apple.com/documentation/foundation/nsuseractivity)
- [INFocusStatusCenter Documentation](https://developer.apple.com/documentation/intents/infocusstatuscenter)
- [AXUIElement Documentation](https://developer.apple.com/documentation/applicationservices/axuielement)
- [Apple Events Entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events)
- [Sandboxing and Automation (QA1888)](https://developer.apple.com/library/archive/qa/qa1888/_index.html)
- [Foundation Models Framework](https://developer.apple.com/documentation/FoundationModels)
- [Apple Intelligence Developer](https://developer.apple.com/apple-intelligence/)
- [Run Shortcuts from Command Line](https://support.apple.com/guide/shortcuts-mac/run-shortcuts-from-the-command-line-apd455c82f02/mac)
- [x-callback-url with Shortcuts](https://support.apple.com/guide/shortcuts-mac/use-x-callback-url-apdcd7f20a6f/5.0/mac/12.0)
- [ScriptingBridge Documentation](https://developer.apple.com/documentation/scriptingbridge)
- [AMWorkflow Documentation](https://developer.apple.com/documentation/automator/amworkflow)
- [macOS URL Schemes (GitHub)](https://github.com/SKaplanOfficial/macOS-URL-Schemes-for-macOS-Applications)
- [WWDC24: Bring your app to Siri](https://developer.apple.com/videos/play/wwdc2024/10133/)
- [WWDC24: What's new in App Intents](https://developer.apple.com/videos/play/wwdc2024/10134/)
- [WWDC25: Get to know App Intents](https://developer.apple.com/videos/play/wwdc2025/244/)
- [WWDC25: Meet the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2025/286/)
- [WWDC25: Develop for Shortcuts and Spotlight](https://developer.apple.com/videos/play/wwdc2025/260/)
