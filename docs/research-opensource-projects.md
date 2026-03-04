# Open Source macOS AI Agent Projects - Research Report

**Date:** 2026-03-04
**Purpose:** Survey the open source landscape for macOS AI automation projects to inform Voice Terminal expansion strategy.

---

## Table of Contents

1. [AI Desktop Agents (Full Computer Use)](#1-ai-desktop-agents-full-computer-use)
2. [Voice + LLM macOS Control](#2-voice--llm-macos-control)
3. [Accessibility API Automation Libraries](#3-accessibility-api-automation-libraries)
4. [MCP-Based macOS Automation Servers](#4-mcp-based-macos-automation-servers)
5. [macOS Automation Frameworks](#5-macos-automation-frameworks)
6. [Local LLM on Apple Silicon](#6-local-llm-on-apple-silicon)
7. [Key Takeaways for Voice Terminal](#7-key-takeaways-for-voice-terminal)
8. [Recommended Ideas to Adopt](#8-recommended-ideas-to-adopt)

---

## 1. AI Desktop Agents (Full Computer Use)

### 1.1 Agent-S (simular-ai/Agent-S)

- **GitHub:** https://github.com/simular-ai/Agent-S
- **Stars:** ~8,500
- **Last Activity:** Active (2026)
- **License:** Apache 2.0

**Core Capabilities:** Open agentic framework that enables autonomous interaction with computers through an Agent-Computer Interface (ACI). Agent S3 achieves 72.6% on OSWorld benchmark, surpassing human-level performance.

**Tech Stack:** Python, multimodal LLMs (GPT-4o, Claude), screenshot-based + accessibility tree approaches

**Strengths:**
- State-of-the-art benchmark results across OSWorld, WindowsAgentArena, AndroidWorld
- Self-learning from past experiences
- Cross-platform (macOS, Windows, Linux, Android)
- Modular generalist-specialist architecture (Agent S2/S3)

**Weaknesses:**
- Heavy Python framework, not native macOS
- Requires powerful LLM backend (cloud-dependent for best results)
- High latency for real-time voice interaction

**Ideas for Voice Terminal:** The generalist-specialist architecture is compelling -- a "generalist" router that delegates to specialist agents for different domains (file management, browser, system settings).

---

### 1.2 CUA - Computer Use Agent Platform (trycua/cua)

- **GitHub:** https://github.com/trycua/cua
- **Stars:** ~5,000+
- **Last Activity:** Active (2026)
- **License:** MIT

**Core Capabilities:** Open-source infrastructure for Computer-Use Agents. Provides sandboxes (macOS/Linux VMs via Apple Virtualization.Framework), SDKs, and benchmarks.

**Tech Stack:** Python SDK, Swift (Lume VM manager), Apple Virtualization.Framework, H.265 streaming

**Strengths:**
- macOS-native VM sandboxing via Apple's Virtualization.Framework (Lume)
- Near-native performance on Apple Silicon
- Isolated execution environments for safety
- Shared clipboard and audio between host and VM

**Weaknesses:**
- VM overhead adds latency
- Primarily a platform/infrastructure, not an end-user agent
- Complex setup

**Ideas for Voice Terminal:** The sandboxing approach is interesting for safety -- running risky automation commands in an isolated VM. The Lume component for macOS VM management could be useful for testing.

---

### 1.3 macOS-use (browser-use/macOS-use)

- **GitHub:** https://github.com/browser-use/macOS-use
- **Stars:** ~4,000+
- **Last Activity:** Active (2026)

**Core Capabilities:** Makes Mac apps accessible for AI agents. Uses macOS Accessibility APIs to achieve system-level control -- mouse clicks, keyboard input, window management.

**Tech Stack:** Python, macOS Accessibility APIs, OpenAI/Anthropic APIs, future goal: MLX for local inference

**Strengths:**
- Deep macOS Accessibility API integration
- Works with any macOS app (not just browser)
- Active community from browser-use ecosystem
- Goal of fully local inference via MLX

**Weaknesses:**
- Security warning: can access stored passwords and auth services
- Not recommended for unsupervised operation
- Currently cloud-dependent (best results with OAI/Anthropic)
- Under heavy development, not production-ready

**Ideas for Voice Terminal:** Their Accessibility API approach for reading app state and simulating user actions is directly applicable. The vision of MLX-powered local inference aligns well with our privacy goals.

---

### 1.4 Open-Interface (AmberSahdev/Open-Interface)

- **GitHub:** https://github.com/AmberSahdev/Open-Interface
- **Stars:** ~3,500+
- **Last Activity:** 2025

**Core Capabilities:** Self-drives your computer by sending requests to LLM backend (GPT-4o, Gemini), figures out steps, and executes via keyboard/mouse simulation. Course-corrects using updated screenshots.

**Tech Stack:** Python, GPT-4o/Gemini, PyAutoGUI, screenshot-based progress tracking

**Strengths:**
- Simple architecture: screenshot -> LLM -> action loop
- macOS binary available for easy installation
- Supports custom LLM backends (including local via API)
- Course-correction via progress screenshots

**Weaknesses:**
- Accuracy issues with spatial reasoning and complex GUIs
- Slow due to screenshot round-trips
- No accessibility tree integration

**Ideas for Voice Terminal:** The screenshot-based course-correction loop is a useful pattern. Could be combined with accessibility tree data for more reliable action targeting.

---

### 1.5 Self-Operating Computer (OthersideAI)

- **GitHub:** https://github.com/OthersideAI/self-operating-computer
- **Stars:** ~8,000+
- **Last Activity:** 2025

**Core Capabilities:** Framework enabling multimodal models to operate a computer using same inputs/outputs as human -- views screen, decides mouse/keyboard actions. Includes OCR mode.

**Tech Stack:** Python, GPT-4V/GPT-4o, OCR integration, cross-platform

**Strengths:**
- Pioneering project in the "computer use" space
- Clean architecture with clear vision
- OCR mode improves text-based interactions
- Cross-platform (macOS, Windows, Linux)

**Weaknesses:**
- Screenshot-only approach (no accessibility API)
- Requires high-capability multimodal LLM
- Slow iteration loop

**Ideas for Voice Terminal:** OCR integration as a fallback when accessibility API doesn't provide needed text content.

---

### 1.6 UI-TARS Desktop (bytedance/UI-TARS-desktop)

- **GitHub:** https://github.com/bytedance/UI-TARS-desktop
- **Stars:** ~10,000+
- **Last Activity:** Active (2026)

**Core Capabilities:** Open-source multimodal AI agent stack from ByteDance. Agent TARS provides GUI Agent and Vision capabilities for terminal, computer, browser, and product use.

**Tech Stack:** TypeScript/Electron, multimodal LLMs, browser automation, MCP integration

**Strengths:**
- Backed by ByteDance with strong R&D
- Rich multimodal capabilities (GUI Agent + Vision)
- MCP tool integration
- Remote Computer/Browser Operator features
- CLI + Web UI interfaces

**Weaknesses:**
- Electron-based (heavy resource usage)
- Complex architecture
- Primarily focused on browser/web tasks

**Ideas for Voice Terminal:** MCP integration pattern and the way they combine GUI Agent with Vision for multi-step task execution.

---

### 1.7 Computer-Agent (suitedaces/computer-agent)

- **GitHub:** https://github.com/suitedaces/computer-agent
- **Stars:** ~2,000+
- **Last Activity:** Active (2025-2026)

**Core Capabilities:** Desktop app to control computer with AI using terminal, browser, mouse & keyboard. Two modes: Computer Use (full screen takeover) and Background Mode (headless web + terminal).

**Tech Stack:** Tauri (Rust), React, Anthropic API, Chrome DevTools Protocol

**Strengths:**
- Dual-mode operation (Computer Use vs Background)
- Background mode doesn't steal focus -- works while you do other things
- Tauri-based = lightweight native app
- Chrome DevTools Protocol for reliable web automation

**Weaknesses:**
- Requires Anthropic API key
- Computer Use mode takes over mouse/keyboard
- Less mature than other options

**Ideas for Voice Terminal:** The dual-mode concept is excellent -- "Background Mode" for tasks that don't need screen control (web scraping, terminal commands) and "Computer Use Mode" for GUI automation. This could be a great UX pattern.

---

## 2. Voice + LLM macOS Control

### 2.1 GPT-Automator (chidiwilliams/GPT-Automator)

- **GitHub:** https://github.com/chidiwilliams/GPT-Automator
- **Stars:** ~900+
- **Last Activity:** 2023 (proof of concept)

**Core Capabilities:** Voice-controlled Mac assistant. Converts audio to text via Whisper, uses LangChain Agent to choose actions, generates AppleScript (desktop) and JavaScript (browser) commands.

**Tech Stack:** Python, OpenAI Whisper (STT), GPT-3/4, LangChain, AppleScript, JavaScript

**Strengths:**
- **Closest architecture to our Voice Terminal** -- voice -> LLM -> system action pipeline
- Clean separation: STT -> Agent -> AppleScript/JS execution
- LangChain for tool orchestration

**Weaknesses:**
- Proof of concept only, not production-ready
- Outdated (2023, pre-GPT-4o)
- Susceptible to prompt injection
- Cloud-only (no local model support)

**Ideas for Voice Terminal:** This is essentially the same concept as our project. Key learnings: use LangChain/tool-calling pattern for action routing, separate desktop automation (AppleScript) from browser automation (JavaScript).

---

### 2.2 macOSpilot (elfvingralf/macOSpilot-ai-assistant)

- **GitHub:** https://github.com/elfvingralf/macOSpilot-ai-assistant
- **Stars:** ~1,200+
- **Last Activity:** 2024

**Core Capabilities:** Voice + Vision powered AI assistant. Keyboard shortcut triggers screenshot of active window, sends to GPT Vision with voice question, returns answer in text + audio (TTS).

**Tech Stack:** NodeJS/Electron, OpenAI Whisper (STT), GPT-4 Vision, OpenAI TTS

**Strengths:**
- Clever architecture: screenshot of active window + voice question = contextual answers
- Application-agnostic (works with any app)
- Both voice and text input
- Audio responses via TTS

**Weaknesses:**
- Read-only (answers questions, doesn't take actions)
- Cloud-dependent (OpenAI APIs)
- Electron overhead

**Ideas for Voice Terminal:** The "screenshot active window for context" approach is brilliant for understanding user intent. Combining this with our action execution could create a much smarter assistant -- "I see you have Xcode open, do you want me to build the project?"

---

### 2.3 MacEcho (realtime-ai/mac-echo)

- **GitHub:** https://github.com/realtime-ai/mac-echo
- **Stars:** ~500+
- **Last Activity:** 2025

**Core Capabilities:** Voice assistant that runs completely locally on macOS. Optimized for Apple Silicon with MLX framework.

**Tech Stack:** Python, MLX Whisper (STT), MLX LLM (e.g., Qwen2.5-7B-Instruct-4bit), local TTS

**Strengths:**
- **100% local** -- no cloud, no API keys, complete privacy
- Optimized for Apple Silicon (MLX)
- Configurable local LLM (various quantized models)
- Full voice pipeline: STT -> LLM -> TTS

**Weaknesses:**
- Conversational only -- no system automation capability
- Quality depends on local model size
- Limited to what the local LLM can do

**Ideas for Voice Terminal:** Their local STT + LLM pipeline on MLX is exactly what we'd want for privacy-focused voice input. The Qwen2.5-7B-Instruct-4bit model choice and MLX integration could be directly adopted for our local mode.

---

### 2.4 Jarvis (isair/jarvis)

- **GitHub:** https://github.com/isair/jarvis
- **Stars:** ~2,000+
- **Last Activity:** Active (2025-2026)

**Core Capabilities:** 100% private voice assistant that runs locally. Remembers preferences, helps with code, manages health goals, searches the web, connects to 500+ tools via MCP.

**Tech Stack:** Python, local STT, local LLM, MCP integration, persistent memory

**Strengths:**
- Wake word detection ("Jarvis")
- Persistent memory across sessions
- MCP tool ecosystem (500+ tools)
- Automatic redaction of sensitive information
- Natural conversation (not rigid commands)

**Weaknesses:**
- Under active development, not fully stable
- macOS-first but cross-platform ambitions may dilute focus
- Complex setup with MCP servers

**Ideas for Voice Terminal:** Wake word detection, persistent memory, and MCP tool integration are all features we should consider. The approach of "say Jarvis anywhere in your sentence" for natural trigger is very user-friendly.

---

### 2.5 OpenClaw

- **GitHub:** https://github.com/openclaw/openclaw
- **Stars:** ~60,000+ (viral growth)
- **Last Activity:** Active (2026)

**Core Capabilities:** Personal AI assistant with multi-platform presence (macOS menu bar, iOS, Android, messaging apps). Voice Wake + Talk Mode on macOS/iOS.

**Tech Stack:** TypeScript/Node.js, multi-channel architecture, ElevenLabs TTS, system TTS fallback

**Strengths:**
- Massive community and rapid growth
- macOS menu bar companion app
- Voice wake word support
- Multi-agent routing
- 20+ channel integrations (WhatsApp, Slack, Discord, iMessage, etc.)
- VoxClaw extension for network-wide voice

**Weaknesses:**
- Broad scope may mean shallow macOS integration
- Not focused on system automation
- Complex multi-channel architecture

**Ideas for Voice Terminal:** The menu bar companion app UX is excellent for macOS. Voice wake word routing to different channels is innovative. The massive plugin/channel ecosystem shows the power of open extensibility.

---

### 2.6 Pipecat Local Voice Agents (kwindla/macos-local-voice-agents)

- **GitHub:** https://github.com/kwindla/macos-local-voice-agents
- **Stars:** ~300+
- **Last Activity:** 2025

**Core Capabilities:** Pipecat voice AI agents running locally on macOS. Full local pipeline: MLX Whisper STT -> local LLM (OpenAI-compatible) -> MLX-Audio TTS.

**Tech Stack:** Python, Pipecat framework, MLX Whisper, mlx-audio, local OpenAI-compatible LLM server

**Strengths:**
- Full local voice pipeline on Apple Silicon
- Uses Pipecat (mature, vendor-neutral framework)
- MLX Whisper for fast local STT
- Multiple Whisper model sizes available (tiny to large-v3-turbo)

**Weaknesses:**
- Requires separate local LLM server (Ollama, etc.)
- No system automation -- conversational only
- Reference implementation, not a full product

**Ideas for Voice Terminal:** The MLX Whisper + Pipecat pipeline is a proven pattern for local voice on macOS. The WhisperSTTServiceMLX class could be integrated into our project for on-device STT.

---

### 2.7 RightHand (tmc/righthand)

- **GitHub:** https://github.com/tmc/righthand
- **Stars:** ~200+
- **Last Activity:** 2024

**Core Capabilities:** Voice controlled assistant for macOS built in Go. Control apps with voice commands.

**Tech Stack:** Go, GPT-4, macOS native integration

**Strengths:**
- Native Go implementation (fast, low overhead)
- macOS-focused design

**Weaknesses:**
- Small project, limited community
- GPT-4 dependent

**Ideas for Voice Terminal:** Go as an alternative language for low-latency macOS voice control.

---

## 3. Accessibility API Automation Libraries

### 3.1 AXorcist (steipete/AXorcist)

- **GitHub:** https://github.com/steipete/AXorcist
- **Stars:** ~1,500+
- **Last Activity:** Active (2025-2026)
- **License:** MIT

**Core Capabilities:** Swift wrapper for macOS Accessibility APIs. Chainable, fuzzy-matched queries that read, click, and inspect any UI element.

**Tech Stack:** Swift 6.2+, macOS 14+, async/await, structured concurrency

**Strengths:**
- **Best-in-class Swift Accessibility API wrapper**
- Fuzzy-matched element queries (no exact string matching needed)
- Chainable query API
- Type-safe attributes with compile-time safety
- Modern Swift patterns (async/await)
- Used by Ghost OS and Peekaboo as dependency

**Weaknesses:**
- Requires macOS 14+
- Swift-only (no Python/JS bindings)

**Ideas for Voice Terminal:** AXorcist is the most polished Accessibility API wrapper available. We should strongly consider using it as a dependency for UI automation -- its fuzzy matching is perfect for voice-driven commands where the user might say "click the save button" without knowing the exact label.

---

### 3.2 AXSwift (tmandry/AXSwift)

- **GitHub:** https://github.com/tmandry/AXSwift
- **Stars:** ~500+
- **Last Activity:** 2024

**Core Capabilities:** Swift wrapper for macOS C-based accessibility client APIs. Simplifies error-prone low-level AX APIs.

**Tech Stack:** Swift, macOS Accessibility API

**Strengths:**
- Simpler, lighter wrapper than AXorcist
- More established (longer history)

**Weaknesses:**
- Less modern Swift patterns
- No fuzzy matching
- Less actively maintained than AXorcist

---

### 3.3 SwiftAutoGUI (NakaokaRei/SwiftAutoGUI)

- **GitHub:** https://github.com/NakaokaRei/SwiftAutoGUI
- **Stars:** ~400+
- **Last Activity:** Active (2026)

**Core Capabilities:** Library for executing keyboard, mouse, and screenshot events on macOS with Swift. Inspired by PyAutoGUI.

**Tech Stack:** Swift 6.0+, macOS 26.0+, ScreenCaptureKit, AppleScript bridge

**Strengths:**
- Action pattern for building automation sequences
- Mouse operations (move, click, scroll)
- Screenshot via ScreenCaptureKit
- AppleScript execution capability
- Has companion MCP server (swift-mcp-gui)

**Weaknesses:**
- Newer project, smaller community
- macOS 26+ requirement limits compatibility

**Ideas for Voice Terminal:** The Action pattern for chaining automation steps is clean. The companion MCP server shows how to expose automation as MCP tools.

---

### 3.4 Hammerspoon + hs._asm.axuielement

- **GitHub:** https://github.com/Hammerspoon/hammerspoon | https://github.com/asmagill/hs._asm.axuielement
- **Stars:** ~12,000+ (Hammerspoon)
- **Last Activity:** Active (2025-2026)

**Core Capabilities:** "Staggeringly powerful" macOS desktop automation with Lua scripting. The axuielement module adds deep Accessibility API access.

**Tech Stack:** Lua, Objective-C bridge, macOS APIs

**Strengths:**
- Most mature macOS automation framework
- Massive Lua API surface (windows, apps, audio, screens, keyboard, mouse, wifi, etc.)
- Spoon plugin system for community extensions
- Very active community
- AI integration being explored (2025 articles)

**Weaknesses:**
- Lua scripting language (niche)
- No built-in LLM/voice integration
- Requires user configuration

**Ideas for Voice Terminal:** Hammerspoon's comprehensive API coverage shows what's possible with macOS automation. Could potentially use Hammerspoon as a backend execution engine, sending Lua scripts generated by the LLM. Their window management and app control APIs are reference implementations.

---

## 4. MCP-Based macOS Automation Servers

### 4.1 Ghost OS (ghostwright/ghost-os)

- **GitHub:** https://github.com/ghostwright/ghost-os
- **Stars:** ~1,000+
- **Last Activity:** Active (2026)

**Core Capabilities:** Full computer-use for AI agents via MCP. Self-learning workflows. Uses accessibility tree (not screenshots) for structured data. 20 MCP tools.

**Tech Stack:** Swift 6.2+, macOS 14+, AXorcist (dependency), MCP protocol

**Strengths:**
- **Accessibility tree first, screenshots as supplement** -- structured > pixels
- Self-learning workflow recipes
- 20 tools: perception (see screen), action (click/type/scroll), recipes
- Works with any MCP client (Claude Code, Cursor, VS Code)
- Data stays local

**Weaknesses:**
- Requires Swift 6.2+ build
- Still early stage
- No voice interface

**Ideas for Voice Terminal:** Ghost OS's approach of accessibility tree + screenshots is the most robust pattern. Their "recipes" for self-learning workflows could enable our Voice Terminal to learn user patterns over time. Strong candidate for integration or inspiration.

---

### 4.2 macOS Automator MCP (steipete/macos-automator-mcp)

- **GitHub:** https://github.com/steipete/macos-automator-mcp
- **Stars:** ~2,000+
- **Last Activity:** Active (2026)

**Core Capabilities:** MCP server for executing AppleScript and JXA (JavaScript for Automation) on macOS. 200+ pre-built automation scripts in knowledge base.

**Tech Stack:** Node.js (18+), AppleScript, JXA, MCP protocol

**Strengths:**
- **200+ pre-built automation scripts** -- massive knowledge base
- Fuzzy search for automation tips
- Supports inline scripts, file scripts, argument passing
- Category-based browsing
- Lazy-loaded knowledge base for fast startup

**Weaknesses:**
- Node.js dependency (not native Swift)
- AppleScript/JXA limitations
- Knowledge base is static (predefined scripts)

**Ideas for Voice Terminal:** The 200+ pre-built AppleScript/JXA automation scripts are a goldmine. We could use this knowledge base as a foundation for our action library. The fuzzy search pattern for finding relevant automations from natural language is directly applicable.

---

### 4.3 Peekaboo (steipete/Peekaboo)

- **GitHub:** https://github.com/steipete/Peekaboo
- **Stars:** ~1,500+
- **Last Activity:** Active (2026)

**Core Capabilities:** macOS CLI & MCP server for AI agents to capture screenshots with optional visual Q&A. Full GUI automation: see, click, type, press, scroll, hotkey, swipe.

**Tech Stack:** Swift 6.2+, macOS 15+, AXorcist dependency, multiple AI providers

**Strengths:**
- Pixel-accurate captures (windows, screens, menu bar)
- Natural-language agent flows (describe tasks in prose)
- Multi-AI provider support (GPT-5.1, Claude 4.x, Grok 4, Gemini 2.5, Ollama)
- Full GUI automation command set
- Both CLI and MCP server modes

**Weaknesses:**
- macOS 15+ requirement
- Complex feature set

**Ideas for Voice Terminal:** The natural-language agent that chains native tools (see, click, type, scroll) is very close to what Voice Terminal needs. Multi-AI provider support shows how to design for flexibility.

---

### 4.4 mcp-server-macos-use (mediar-ai)

- **GitHub:** https://github.com/mediar-ai/mcp-server-macos-use
- **Stars:** ~500+
- **Last Activity:** 2025

**Core Capabilities:** MCP server in Swift that controls macOS apps via Accessibility APIs. Opens apps, clicks at coordinates, types text, traverses accessibility tree.

**Tech Stack:** Swift, macOS Accessibility APIs, MCP (stdio transport)

**Strengths:**
- Native Swift MCP server
- Accessibility tree traversal after each action (feedback loop)
- Clean, focused API

**Weaknesses:**
- Limited tool set
- Coordinate-based clicking (less reliable than element-based)

---

### 4.5 mac-use-mcp (antbotlab)

- **GitHub:** https://github.com/antbotlab/mac-use-mcp
- **Stars:** ~300+
- **Last Activity:** 2025-2026

**Core Capabilities:** Zero-dependency macOS desktop automation MCP server. 18 tools for screenshots, clicks, keystrokes, window management, accessibility inspection, clipboard.

**Tech Stack:** Node.js (zero native deps), macOS 13+, MCP protocol

**Strengths:**
- **Zero native dependencies** -- `npx mac-use-mcp` and go
- 18 comprehensive tools
- macOS 13+ compatibility (wide support)
- No Xcode tools needed

**Weaknesses:**
- Node.js (not native)
- May be slower than native Swift implementations

---

## 5. macOS Automation Frameworks

### 5.1 SwiftAutomation (hhas/SwiftAutomation)

- **GitHub:** https://github.com/hhas/SwiftAutomation
- **Stars:** ~300+
- **Last Activity:** 2024

**Core Capabilities:** High-level Apple event framework for Swift. Allows controlling "AppleScriptable" macOS applications directly from Swift code.

**Tech Stack:** Swift, Apple Events, Scripting Bridge

**Strengths:**
- True Swift alternative to AppleScript
- High-level API for app control
- Type-safe Apple event interface

**Weaknesses:**
- Apple Events/Scripting Bridge limitations
- Not all apps are scriptable

---

### 5.2 SwiftScripting (tingraldi/SwiftScripting)

- **GitHub:** https://github.com/tingraldi/SwiftScripting
- **Stars:** ~200+
- **Last Activity:** 2024

**Core Capabilities:** Utilities and samples for using Swift with Scripting Bridge. Alternative to AppleScript for Mac automation.

---

### 5.3 macOS Automation Resources (SKaplanOfficial)

- **GitHub:** https://github.com/SKaplanOfficial/macOS-Automation-Resources
- **Stars:** ~200+

**Core Capabilities:** Comprehensive collection of resources for macOS automation languages including AppleScript, JXA, Shell, Shortcuts, and more.

---

## 6. Local LLM on Apple Silicon

### 6.1 MLX (ml-explore/mlx)

- **GitHub:** https://github.com/ml-explore/mlx
- **Stars:** ~20,000+
- **Last Activity:** Active (2026)

**Core Capabilities:** Apple's array framework for machine learning on Apple Silicon. Foundation for running LLMs locally on Mac.

**Relevance to Voice Terminal:** Core dependency for local inference. MLX Whisper for STT, mlx-lm for LLM inference, mlx-audio for TTS.

---

### 6.2 LLMFarm (guinmoon/LLMFarm)

- **GitHub:** https://github.com/guinmoon/LLMFarm
- **Stars:** ~1,000+
- **Last Activity:** Active (2025)

**Core Capabilities:** iOS/macOS app for running LLMs locally using GGML/llama.cpp. Swift library available (llmfarm_core.swift).

**Tech Stack:** Swift, GGML, llama.cpp

**Strengths:**
- Native Swift library for LLM inference
- iOS + macOS support
- Wide model format support
- Swift Package Manager integration

**Ideas for Voice Terminal:** llmfarm_core.swift could be used as a Swift-native alternative to MLX for local LLM inference if we want to avoid Python dependencies.

---

## 7. Key Takeaways for Voice Terminal

### Architecture Patterns Emerging in the Ecosystem

1. **Accessibility Tree > Screenshots** -- Projects like Ghost OS and macOS-use show that using the accessibility tree for structured app state is more reliable than screenshot-based approaches. Best practice: use accessibility tree as primary, screenshots as supplement for visual context.

2. **MCP as Standard Interface** -- The MCP protocol is becoming the standard way to expose macOS automation capabilities to AI agents. Ghost OS, Peekaboo, macOS-automator-mcp, mac-use-mcp all use MCP.

3. **Local-First Voice Pipeline** -- MacEcho and Pipecat local voice agents prove that fully local STT (MLX Whisper) + LLM (MLX/Ollama) + TTS (MLX-Audio) is viable on Apple Silicon.

4. **Dual-Mode Operation** -- Computer-Agent's Background Mode vs Computer Use Mode is a great UX pattern. Voice commands should work in the background when possible, only taking over the screen when needed.

5. **Pre-Built Action Libraries** -- macOS-automator-mcp's 200+ AppleScript/JXA scripts show the value of a curated action library. Voice Terminal should build a similar library of common actions.

6. **Fuzzy Matching** -- AXorcist's fuzzy-matched queries are essential for voice-driven UI automation where users describe elements imprecisely.

### Competitive Landscape Summary

| Category | Leaders | Our Differentiator |
|----------|---------|-------------------|
| Desktop Agents | Agent-S, UI-TARS, CUA | Voice-first, macOS-native |
| Voice + Action | GPT-Automator, macOSpilot | Local-first, deeper integration |
| Accessibility Automation | AXorcist, Ghost OS | Voice trigger, LLM intelligence |
| MCP Automation | macOS-automator-mcp, Peekaboo | Unified voice interface |
| Local Voice | MacEcho, Pipecat | System automation (not just chat) |

**Our unique position:** No existing project combines all of: (1) voice-first input, (2) local-first processing on Apple Silicon, (3) deep macOS Accessibility API integration, (4) LLM-powered action routing, and (5) native Swift implementation. This is our gap to fill.

---

## 8. Recommended Ideas to Adopt

### High Priority (Direct Integration Candidates)

| Idea | Source Project | Implementation |
|------|---------------|----------------|
| AXorcist for UI automation | steipete/AXorcist | Add as Swift Package dependency |
| MLX Whisper for local STT | ml-explore/mlx + WhisperKit | Use WhisperSTTServiceMLX pattern |
| Pre-built AppleScript library | steipete/macos-automator-mcp | Port top 50 scripts as action handlers |
| Accessibility tree + screenshot combo | ghostwright/ghost-os | Primary: AX tree, Fallback: screenshot |
| MCP server exposure | Multiple projects | Expose Voice Terminal actions as MCP tools |

### Medium Priority (Architectural Patterns to Adopt)

| Pattern | Source | Benefit |
|---------|--------|---------|
| Dual-mode (background/foreground) | suitedaces/computer-agent | Non-intrusive automation |
| Wake word detection | isair/jarvis, openclaw | Always-on activation |
| Fuzzy UI element matching | steipete/AXorcist | Robust voice-to-action mapping |
| Self-learning workflows/recipes | ghostwright/ghost-os | User personalization |
| Active window context (screenshot) | elfvingralf/macOSpilot | Contextual understanding |
| Persistent memory | isair/jarvis | Cross-session learning |

### Low Priority (Future Exploration)

| Idea | Source | Notes |
|------|--------|-------|
| Sandboxed execution (VM) | trycua/cua | For risky automation commands |
| Multi-channel presence | openclaw/openclaw | Menu bar + voice + messaging |
| Agent-specialist routing | simular-ai/Agent-S | Domain-specific sub-agents |
| Browser DevTools Protocol | suitedaces/computer-agent | Reliable web automation |

---

## Appendix: Full Project Index

| Project | GitHub URL | Stars | Stack | Focus |
|---------|-----------|-------|-------|-------|
| Agent-S | github.com/simular-ai/Agent-S | ~8.5k | Python | Computer Use Agent |
| CUA | github.com/trycua/cua | ~5k | Python/Swift | CUA Infrastructure |
| macOS-use | github.com/browser-use/macOS-use | ~4k | Python | macOS AI Agent |
| Open-Interface | github.com/AmberSahdev/Open-Interface | ~3.5k | Python | LLM Computer Control |
| Self-Operating Computer | github.com/OthersideAI/self-operating-computer | ~8k | Python | Multimodal Computer Use |
| UI-TARS Desktop | github.com/bytedance/UI-TARS-desktop | ~10k | TypeScript | Multimodal Agent Stack |
| Computer-Agent | github.com/suitedaces/computer-agent | ~2k | Rust/React | Desktop AI Agent |
| GPT-Automator | github.com/chidiwilliams/GPT-Automator | ~900 | Python | Voice Mac Control |
| macOSpilot | github.com/elfvingralf/macOSpilot-ai-assistant | ~1.2k | Node.js | Voice+Vision Assistant |
| MacEcho | github.com/realtime-ai/mac-echo | ~500 | Python/MLX | Local Voice Assistant |
| Jarvis | github.com/isair/jarvis | ~2k | Python | Private Voice + MCP |
| OpenClaw | github.com/openclaw/openclaw | ~60k | TypeScript | Multi-Platform AI Assistant |
| Pipecat Local | github.com/kwindla/macos-local-voice-agents | ~300 | Python | Local Voice Pipeline |
| AXorcist | github.com/steipete/AXorcist | ~1.5k | Swift | Accessibility API Wrapper |
| Ghost OS | github.com/ghostwright/ghost-os | ~1k | Swift | MCP + Accessibility Agent |
| macOS-automator-mcp | github.com/steipete/macos-automator-mcp | ~2k | Node.js | AppleScript/JXA MCP |
| Peekaboo | github.com/steipete/Peekaboo | ~1.5k | Swift | Screenshot + GUI MCP |
| mcp-server-macos-use | github.com/mediar-ai/mcp-server-macos-use | ~500 | Swift | Accessibility MCP |
| mac-use-mcp | github.com/antbotlab/mac-use-mcp | ~300 | Node.js | Zero-Dep macOS MCP |
| Hammerspoon | github.com/Hammerspoon/hammerspoon | ~12k | Lua/ObjC | macOS Automation |
| SwiftAutoGUI | github.com/NakaokaRei/SwiftAutoGUI | ~400 | Swift | Keyboard/Mouse Automation |
| SwiftAutomation | github.com/hhas/SwiftAutomation | ~300 | Swift | Apple Events Framework |
| MLX | github.com/ml-explore/mlx | ~20k | C++/Python | Apple Silicon ML Framework |
| LLMFarm | github.com/guinmoon/LLMFarm | ~1k | Swift | Local LLM iOS/macOS |
| Open Interpreter | github.com/openinterpreter/open-interpreter | ~55k | Python | LLM Code Execution |

---

*Report generated: 2026-03-04*
