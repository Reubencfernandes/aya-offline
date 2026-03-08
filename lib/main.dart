import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'chat/chat_screen.dart';

/// Default model path per platform.
String get defaultModelPath {
  if (kIsWeb) return '';
  if (defaultTargetPlatform == TargetPlatform.android) {
    return '/sdcard/Download/tiny-aya-global-q4_k_m.gguf';
  }
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return '/var/mobile/Documents/tiny-aya-global-q4_k_m.gguf';
  }
  // Desktop (Windows/Linux/macOS) — place model in project root or CWD
  return 'tiny-aya-global-q4_k_m.gguf';
}

void main() {
  runApp(const AyaApp());
}

class AyaApp extends StatelessWidget {
  const AyaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aya',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6750A4),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF6750A4),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: ChatScreen(
        modelPath: defaultModelPath,
      ),
    );
  }
}
