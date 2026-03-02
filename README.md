# VoiceInput - macOS Voice Input Method

A macOS input method for voice input, built with Input Method Kit (IMK).

## Features

- **Global Hotkey**: Press Option+Space to activate voice input
- **Candidate Window**: Shows recognized text in a floating window
- **Menu Bar**: Access preferences and about from the input method menu

## Installation

1. **Build the project**:
   ```bash
   cd voiceinput-macos
   xcodebuild -scheme VoiceInput -configuration Debug build
   ```

2. **Copy to Input Methods folder**:
   ```bash
   cp -R build/Debug/VoiceInput.app ~/Library/Input\ Methods/
   ```

3. **Enable the input method**:
   - Open System Settings → Keyboard → Input Sources
   - Click the + button
   - Search for "VoiceInput" and add it

4. **Grant Accessibility permissions** (required for global hotkey):
   - Open System Settings → Privacy & Security → Accessibility
   - Add VoiceInput to the allowed apps list

5. **Switch to VoiceInput**:
   - Use the input method menu in the menu bar or press Ctrl+Space to switch

## Usage

- **Option+Space**: Toggle voice input mode
- **Escape**: Cancel voice input
- **Return**: Confirm and insert recognized text

## Project Structure

```
voiceinput-macos/
├── Sources/
│   ├── main.swift           # Entry point, initializes IMKServer
│   ├── VoiceInputController.swift  # Main input controller
│   └── Info.plist           # Input method configuration
├── Resources/
│   └── Assets.xcassets/     # App icons
├── project.yml              # XcodeGen configuration
└── VoiceInput.xcodeproj/    # Generated Xcode project
```

## Technical Details

- **Framework**: InputMethodKit
- **Target**: macOS 12.0+
- **Bundle ID**: com.voiceinput.inputmethod
- **Connection Name**: VoiceInput_Connection

## Building

```bash
# Using XcodeGen
xcodegen generate
xcodebuild -scheme VoiceInput -configuration Debug build

# The built app will be at:
# build/Debug/VoiceInput.app
```
