import 'package:flutter/material.dart';

import 'chat/chat_screen.dart';
import 'models/model_manager.dart';
import 'models/model_picker.dart';

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
      home: const _HomeRouter(),
    );
  }
}

/// Checks for a downloaded model on startup.
/// If found, goes straight to chat. Otherwise shows the model picker.
class _HomeRouter extends StatefulWidget {
  const _HomeRouter();

  @override
  State<_HomeRouter> createState() => _HomeRouterState();
}

class _HomeRouterState extends State<_HomeRouter> {
  String? _modelPath;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkForModel();
  }

  Future<void> _checkForModel() async {
    final model = await ModelManager.firstDownloaded();
    if (model != null) {
      final path = await ModelManager.modelPath(model);
      setState(() {
        _modelPath = path;
        _checking = false;
      });
    } else {
      setState(() => _checking = false);
    }
  }

  Future<void> _openModelPicker() async {
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ModelPickerScreen()),
    );
    if (path != null && mounted) {
      setState(() => _modelPath = path);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_modelPath != null) {
      return ChatScreen(
        modelPath: _modelPath!,
        onChangeModel: _openModelPicker,
      );
    }

    // No model downloaded — show picker immediately.
    return ModelPickerScreen();
  }
}
