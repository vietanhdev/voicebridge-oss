import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'controller.dart';
import 'glossary.dart';
import 'history.dart';
import 'i18n.dart';
import 'pronunciation.dart';
import 'settings.dart';
import 'screens/interpreter_screen.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The dual-facing interpreter (top panel rotated 180° for the person across a
  // vertically-held phone) is a portrait-native UX; lock to portrait so rotating
  // the device can't squeeze the panels into a RenderFlex overflow.
  await SystemChrome.setPreferredOrientations(
    const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
  );
  final settings = AppSettings();
  await settings.load();
  final history = History();
  await history.load();
  final glossary = Glossary(settings.domain);
  await glossary.load();
  settings.addListener(() { if (glossary.domain != settings.domain) glossary.setDomain(settings.domain); });
  final pron = Pronunciation();
  final controller = InterpreterController(glossary, pron, settings, history)..init();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UiLang>(create: (_) => UiLang()),
        ChangeNotifierProvider<AppSettings>.value(value: settings),
        ChangeNotifierProvider<History>.value(value: history),
        ChangeNotifierProvider<Glossary>.value(value: glossary),
        ChangeNotifierProvider<Pronunciation>.value(value: pron),
        ChangeNotifierProvider<InterpreterController>.value(value: controller),
      ],
      child: const VoiceBridgeApp(),
    ),
  );
}

class VoiceBridgeApp extends StatelessWidget {
  const VoiceBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VoiceBridge',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const InterpreterScreen(),
    );
  }
}
