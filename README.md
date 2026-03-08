# Aya Offline

Offline multilingual LLM chat app. Runs a 3.5B parameter model (Aya) entirely on-device with no internet connection required.

Built with Flutter + a custom C inference engine with SIMD optimizations (AVX2 on x86, NEON on ARM64).

## Platforms

| Platform | Status | Engine |
|----------|--------|--------|
| Android  | ✅     | Native C (NDK/CMake) |
| iOS      | ✅     | Native C (CocoaPods) |
| macOS    | ✅     | Native C (CocoaPods) |
| Windows  | ✅     | Native C (DLL) |
| Web      | ✅     | WASM + SSE fallback |

## Prerequisites

- Flutter SDK 3.11+
- Model file: `tiny-aya-global-q4_k_m.gguf` (~2 GB)

## Quick Start

```bash
git clone https://github.com/Complexity-ML/aya-offline.git
cd aya-offline
flutter pub get
```

### Android

1. Push the model to the device:
```bash
adb push tiny-aya-global-q4_k_m.gguf /sdcard/Download/
```

2. Build and install:
```bash
flutter build apk --debug
adb install build/app/outputs/flutter-apk/app-debug.apk
```

3. Launch the app and grant "All files access" when prompted.

### iOS

Requires a Mac with Xcode installed.

1. Transfer the model to the device (via Finder/iTunes shared files, or use a file manager app to place it in `/var/mobile/Documents/`).

2. Install CocoaPods dependencies and run:
```bash
cd ios && pod install && cd ..
flutter run -d <iphone-device-id>
```

### macOS

1. Place the model file in the project root directory.

2. Install CocoaPods dependencies and run:
```bash
cd macos && pod install && cd ..
flutter run -d macos
```

### Windows

1. Place the model file in the project root directory.
2. Build the C engine as DLL (requires MSYS2/MinGW or Visual Studio):
```bash
cd engine-c
gcc -shared -O2 -mavx2 -mfma -o aya_engine.dll src/gguf.c src/model.c src/aya_api.c -DAYA_BUILD_DLL -lm
```

3. Copy `aya_engine.dll` next to the Flutter executable and run:
```bash
flutter run -d windows
```

### Web

1. Start the local inference server:
```bash
cd engine-c
./aya_server.exe tiny-aya-global-q4_k_m.gguf
```

2. In another terminal:
```bash
flutter run -d chrome
```

The web version connects to the local server via SSE (Server-Sent Events).

## Architecture

```
aya-offline/
├── engine-c/          # C inference engine
│   ├── src/
│   │   ├── aya_api.c  # Public API (init, generate, free)
│   │   ├── model.c    # Transformer forward pass
│   │   ├── gguf.c     # GGUF file parser
│   │   └── quant.h    # Q4_K/Q6_K quantization + SIMD
│   └── CMakeLists.txt # Android NDK build
├── lib/
│   ├── engine/
│   │   ├── native_engine.dart  # FFI bindings (Android/iOS/desktop)
│   │   ├── sse_engine.dart     # SSE client (web)
│   │   └── engine.dart         # Platform abstraction
│   └── chat/
│       └── chat_screen.dart    # Chat UI
├── ios/Podfile         # iOS CocoaPods config
├── macos/Podfile       # macOS CocoaPods config
└── android/app/build.gradle.kts  # Android CMake/NDK config
```

## License

INL 2025
