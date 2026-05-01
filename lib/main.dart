import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'providers/app_state.dart';
import 'services/folder_service.dart';
import 'services/history_service.dart';
import 'services/transform_presets_service.dart';
import 'screens/home_screen.dart';
import 'screens/transcription_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appState = AppState();
  final historyService = HistoryService();
  final presetsService = TransformPresetsService();
  final folderService = FolderService();
  await Future.wait([
    appState.load(),
    historyService.load(),
    presetsService.load(),
    folderService.load(),
  ]);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider.value(value: historyService),
        ChangeNotifierProvider.value(value: presetsService),
        ChangeNotifierProvider.value(value: folderService),
      ],
      child: const VoiceApp(),
    ),
  );
}

class VoiceApp extends StatefulWidget {
  const VoiceApp({super.key});

  @override
  State<VoiceApp> createState() => _VoiceAppState();
}

class _VoiceAppState extends State<VoiceApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription? _sharingSub;

  @override
  void initState() {
    super.initState();
    _initSharing();
  }

  Future<void> _initSharing() async {
    final initial =
        await ReceiveSharingIntent.instance.getInitialMedia();
    if (initial.isNotEmpty && initial.first.path.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openTranscription(initial.first.path);
      });
    }
    await ReceiveSharingIntent.instance.reset();

    _sharingSub =
        ReceiveSharingIntent.instance.getMediaStream().listen((files) {
      if (files.isNotEmpty && files.first.path.isNotEmpty) {
        _openTranscription(files.first.path);
      }
    });
  }

  void _openTranscription(String filePath) {
    _navigatorKey.currentState?.push(MaterialPageRoute(
      builder: (_) => TranscriptionScreen(initialFilePath: filePath),
    ));
  }

  @override
  void dispose() {
    _sharingSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appTheme = context.watch<AppState>().buttonTheme;
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Voice Assistant',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: appTheme.backgroundColor,
        cardTheme: CardThemeData(
          color: appTheme.surfaceColor,
          elevation: 4,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
