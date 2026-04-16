# Aya Offline - Architecture & Developer Guide

Offline AI translation and chat app powered by on-device LLM inference. Built with Flutter + llama.cpp.

---

## File Map

### App Layer (`lib/`)

| File | Purpose |
|------|---------|
| `lib/main.dart` | App entry point, theme, tab shell, download/error banners, status pill |
| `lib/engine/engine.dart` | Prompt templates, generation config, model loading wrapper |
| `lib/chat/chat_screen.dart` | Chat UI: message bubbles, input field, streaming display |
| `lib/translate/translate_screen.dart` | Translation UI: language pickers, speech input, TTS output |
| `lib/translate/language_option.dart` | Supported languages list (10 languages) |
| `lib/models/model_info.dart` | Model definitions: families, quantizations, download URLs, sizes |
| `lib/models/model_picker.dart` | Model selection screen: browse, download, delete, use |
| `lib/models/model_manager.dart` | Download logic: resume support, storage checks, retry |
| `lib/models/storage_space_service.dart` | Platform channel to query available disk space |
| `lib/app/aya_session_controller.dart` | Session state: current model, loading status, engine lifecycle |
| `lib/app/model_download_controller.dart` | Download state: progress, phase, error tracking |

### Plugin Layer (`flutter_llama/`)

| File | Purpose |
|------|---------|
| `flutter_llama/lib/src/flutter_llama.dart` | Dart interface to native llama.cpp (singleton, method/event channels) |
| `flutter_llama/lib/src/models/llama_config.dart` | Model load configuration (threads, GPU, context size) |
| `flutter_llama/lib/src/models/generation_params.dart` | Generation parameters (temperature, topP, topK, etc.) |
| `flutter_llama/android/.../FlutterLlamaPlugin.kt` | Android native: JNI bridge to llama.cpp C++ |
| `flutter_llama/android/.../cpp/flutter_llama_bridge.cpp` | Android C++ bridge: tokenization, sampling, streaming |
| `flutter_llama/ios/Classes/FlutterLlamaPlugin.swift` | iOS native: Swift bridge to llama.cpp |
| `flutter_llama/ios/Classes/llama_cpp_bridge.mm` | iOS C++ bridge: same role as Android bridge |

### Platform Config

| File | Purpose |
|------|---------|
| `android/app/src/main/AndroidManifest.xml` | Permissions (INTERNET, RECORD_AUDIO), largeHeap |
| `android/app/src/main/kotlin/.../MainActivity.kt` | Storage info platform channel (StatFs) |
| `android/app/build.gradle.kts` | minSdk 24, ABIs: arm64-v8a + x86_64 |
| `ios/Runner/Info.plist` | Microphone + speech recognition permission descriptions |
| `flutter_llama/ios/flutter_llama.podspec` | iOS build: Metal, Accelerate frameworks, static libs |

---

## Navigation Flow

```
AyaApp (MaterialApp)
 └── AyaHomeShell (Scaffold + bottom NavigationBar)
      ├── Tab 0: TranslateScreen
      │    ├── No model loaded  -->  _TranslationLockedState (prompts to open settings)
      │    └── Model loaded     -->  Full translation UI
      ├── Tab 1: ChatScreen
      │    ├── No model loaded  -->  _ModelRequiredState (prompts to open settings)
      │    └── Model loaded     -->  Full chat UI
      └── Settings icon (AppBar) --> ModelPickerScreen (push route)
           ├── Download a model
           ├── Delete a model
           └── Select a model   --> pops with model path, shell reloads screens
```

---

## UI Guide

### Theme & Styling (`lib/main.dart:20-40`)

| Property | Value |
|----------|-------|
| Seed color | `#0F766E` (teal) |
| Light background | `#F4F1EA` (warm cream) |
| Dark theme | Auto-generated from seed |
| Design system | Material 3 |
| Border radii | Cards: 24-28px, Buttons/inputs: 22px, Small elements: 18-20px |
| Screen padding | 16px edges |
| Card padding | 16-18px internal |

To change the app's color scheme, edit the `seed` variable and `scaffoldBackgroundColor` in `lib/main.dart:20-31`.

### Main Shell (`lib/main.dart`)

| Widget | Lines | What it does |
|--------|-------|-------------|
| `AyaHomeShell` | 46-233 | Tab controller, model auto-loading, download listener |
| `_DownloadBanner` | 235-283 | Progress bar shown during model download |
| `_DownloadErrorBanner` | 285-324 | Red error bar with dismiss button |
| `_StatusPill` | 326-361 | Colored dot + label: "Ready" (green), "Loading" (orange), "No model" (grey), "Error" (red) |
| `NavigationBar` | 199-215 | Bottom tabs: Translate (translate icon) and Chat (chat bubble icon) |

### Chat Screen (`lib/chat/chat_screen.dart`)

| Widget | Lines | What it does |
|--------|-------|-------------|
| Message list | 183-190 | `ListView` with reverse scroll, auto-scrolls to latest |
| User bubble | 381-425 | Right-aligned, primary color background, radius 20/4 |
| Assistant bubble | 381-425 | Left-aligned, surfaceContainerHigh background, radius 4/20 |
| Input field | 208-225 | `TextField` with max 5 lines, hint "Ask Aya anything...", radius 22 |
| Send button | 228-242 | Circular filled button, shows spinner while generating |
| `_ModeBanner` | 260-315 | Info card explaining "Offline chat" mode |
| `_ModelRequiredState` | 317-379 | Full-screen placeholder when no model loaded |

**Chat flow**: User sends message -> `AyaSessionController.generateChatReply()` -> tokens stream in -> assistant bubble updates live -> `<|END_OF_TURN_TOKEN|>` stripped from output.

### Translate Screen (`lib/translate/translate_screen.dart`)

| Widget | Lines | What it does |
|--------|-------|-------------|
| Language pickers | 235-280 | Two dropdowns (From/To) with swap button between them |
| Source input | 281-310 | `TextField` with 6-8 lines, label "Source text" |
| Action buttons | 311-354 | Row of 3: Translate, Mic (speech-to-text), Clear |
| Translation output | 356-408 | Read-only container, min height 170px, with TTS speaker button |
| `_LanguagePicker` | 423-454 | `DropdownButtonFormField` for language selection |
| `_TranslationLockedState` | 456-516 | Full-screen placeholder when no model loaded |

**Speech config**: Listen duration 30s, pause timeout 4s, speech rate 0.45, pitch 1.0.

**Translation flow**: User enters text + picks languages -> `AyaSessionController.translateText()` -> tokens stream in -> output updates live.

### Model Picker (`lib/models/model_picker.dart`)

| Widget | Lines | What it does |
|--------|-------|-------------|
| Family cards | 113-153 | One card per model family (Global, Earth, Fire, Water) |
| Quant row | 155-263 | Per-quantization: name, size badge, download/use/delete buttons |
| "recommended" badge | 181-197 | Shows on q4_k_m variants |
| Storage warning | 249-258 | "Need X, have Y" text when insufficient space |
| Progress bar | 199-218 | Linear progress + MB counter during download |

---

## Prompts & Generation

### Translation Prompt (`lib/engine/engine.dart:66-71`)

```
You are a precise translation assistant.
Translate the user text from {sourceLanguage} to {targetLanguage}.
Preserve meaning, names, tone, and formatting when possible.
Return only the translated text without explanations.

Text:
{user text}
```

This is sent as a single user turn wrapped in the Aya chat template.

### Chat Template (`lib/engine/engine.dart:106-124`)

```
<BOS_TOKEN>
<|START_OF_TURN_TOKEN|><|USER_TOKEN|>{user message}<|END_OF_TURN_TOKEN|>
<|START_OF_TURN_TOKEN|><|CHATBOT_TOKEN|>{assistant reply}<|END_OF_TURN_TOKEN|>
... (repeat for full history) ...
<|START_OF_TURN_TOKEN|><|CHATBOT_TOKEN|>
```

The model generates from the final `<|CHATBOT_TOKEN|>` until it emits `<|END_OF_TURN_TOKEN|>`.

### Generation Parameters (`lib/engine/engine.dart`)

| Parameter | Chat (line 44-46) | Translation (line 75-79) | Effect |
|-----------|------|-------------|--------|
| `temperature` | 0.7 | 0.2 | Higher = more creative, lower = more deterministic |
| `topP` | 0.95 | 0.9 | Nucleus sampling threshold |
| `topK` | 40 | 20 | Limits token candidates |
| `maxTokens` | 192 | 200 | Maximum output length |
| `repeatPenalty` | 1.08 | 1.08 | Penalizes repeated tokens |
| `stopSequences` | `<\|END_OF_TURN_TOKEN\|>` | `<\|END_OF_TURN_TOKEN\|>` | Stops generation |

### Output Cleaning

Both `chat_screen.dart` and `translate_screen.dart` strip the stop token from output:
```dart
value.replaceAll('<|END_OF_TURN_TOKEN|>', '').trim()
```

---

## Languages (`lib/translate/language_option.dart`)

| Language | Translation Label | STT Locale | TTS Locale |
|----------|------------------|------------|------------|
| English | English | en_US | en-US |
| Hindi | Hindi | hi_IN | hi-IN |
| Spanish | Spanish | es_ES | es-ES |
| French | French | fr_FR | fr-FR |
| German | German | de_DE | de-DE |
| Arabic | Arabic | ar_SA | ar-SA |
| Portuguese | Portuguese | pt_BR | pt-BR |
| Japanese | Japanese | ja_JP | ja-JP |
| Tamil | Tamil | ta_IN | ta-IN |
| Telugu | Telugu | te_IN | te-IN |

**To add a language**, append a new `TranslationLanguage` to the `translationLanguages` list in `language_option.dart`. You need:
- `name`: Display name in the UI dropdown
- `translationLabel`: Name sent to the model in the prompt (use the English name of the language)
- `sttLocale`: Locale code for speech-to-text (format: `xx_XX`)
- `ttsLocale`: Locale code for text-to-speech (format: `xx-XX`)

---

## Model Configuration

### Available Models (`lib/models/model_info.dart:28-156`)

4 families x 3 quantizations = 12 variants:

| Family | Coverage | q4_0 | q4_k_m | q8_0 |
|--------|----------|------|--------|------|
| Global | 70+ languages | 1940 MB | 2045 MB | 3405 MB |
| Earth | European languages | 1940 MB | 2045 MB | 3405 MB |
| Fire | South/SE Asian | 1940 MB | 2045 MB | 3405 MB |
| Water | East Asian, African, Middle Eastern | 1940 MB | 2045 MB | 3405 MB |

All hosted on Hugging Face: `https://huggingface.co/CohereLabs/tiny-aya-{family}-GGUF/`

### Engine Config (`lib/engine/engine.dart:25-33`)

| Setting | Value | Notes |
|---------|-------|-------|
| `nThreads` | `(cores - 2).clamp(2, 6)` | Leaves 2 cores for UI/OS |
| `nGpuLayers` | 99 | Offload all layers to GPU |
| `contextSize` | 1024 | Smaller than default for mobile memory |
| `batchSize` | 512 | Processing batch size |
| `useGpu` | true | Enables Vulkan (Android) / Metal (iOS) |

---

## Quick Reference: "Where do I change X?"

| I want to... | File | Lines |
|--------------|------|-------|
| Change app colors / theme | `lib/main.dart` | 20-40 |
| Edit the translation prompt | `lib/engine/engine.dart` | 66-71 |
| Edit the chat template tokens | `lib/engine/engine.dart` | 106-124 |
| Change chat generation params (temp, topK, etc.) | `lib/engine/engine.dart` | 44-46 |
| Change translation generation params | `lib/engine/engine.dart` | 75-79 |
| Change model load config (threads, GPU, context) | `lib/engine/engine.dart` | 25-33 |
| Add/remove a translation language | `lib/translate/language_option.dart` | 15-76 |
| Modify the chat bubble appearance | `lib/chat/chat_screen.dart` | 381-425 |
| Modify the chat input field | `lib/chat/chat_screen.dart` | 208-225 |
| Modify the translate input/output layout | `lib/translate/translate_screen.dart` | 235-408 |
| Change speech-to-text settings | `lib/translate/translate_screen.dart` | 24-59 |
| Add a new model variant | `lib/models/model_info.dart` | 28-156 |
| Change download storage headroom | `lib/models/model_manager.dart` | 10 |
| Change the bottom navigation tabs | `lib/main.dart` | 199-215 |
| Change the status pill labels/colors | `lib/main.dart` | 326-361 |
| Modify model picker card layout | `lib/models/model_picker.dart` | 113-263 |
| Change max chat history length | `lib/chat/chat_screen.dart` | 38-92 |
| Edit the "no model" placeholder screens | `lib/chat/chat_screen.dart` (317-379), `lib/translate/translate_screen.dart` (456-516) |

---

## State Management

```
AyaHomeShell
 ├── AyaSessionController (ChangeNotifier)
 │    ├── Owns AyaEngine instance
 │    ├── Tracks: modelPath, isChecking, isModelLoading, status
 │    ├── initialize() → finds first downloaded model → loads it
 │    └── selectModelPath() → loads new model into engine
 │
 └── ModelDownloadController (ChangeNotifier)
      ├── Delegates to ModelManager for actual download I/O
      ├── Tracks: downloaded set, progress, phase, errors, readiness
      ├── Throttles UI updates (250ms / 4MB)
      └── Single download at a time
```

Both controllers use `ChangeNotifier` + `AnimatedBuilder` for reactive UI updates. No external state management package.

---

## Download Flow

1. User taps "Download" in ModelPickerScreen
2. `ModelDownloadController.download(model)` checks storage readiness
3. `ModelManager.download(model)` starts HTTP GET to Hugging Face
4. File saves to `.part` during download (supports resume on retry)
5. On completion: `.part` renamed to `.gguf`, phase set to `completed`
6. `AyaHomeShell` listener auto-loads the model via `AyaSessionController`

Storage paths:
- **Android**: `getExternalStorageDirectory()/models/` (external app storage, more space)
- **iOS**: `getApplicationDocumentsDirectory()/models/`

---

## Platform Notes

| | Android | iOS |
|-|---------|-----|
| GPU | Vulkan / OpenCL (auto-detected) | Metal |
| Min version | API 24 (Android 7.0) | iOS 13.0 |
| Storage | External app dir (no permission needed) | Documents dir |
| Space check | `StatFs` via platform channel | `path_provider` |
| Native bridge | JNI (Kotlin -> C++) | `@_silgen_name` (Swift -> C++) |
| Libraries | Shared (.so) built by CMake | Static (.a) pre-built |
