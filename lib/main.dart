import 'dart:io';

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/material.dart';

import 'pages/watch_page.dart';
import 'services/watch_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isMacOS) {
    await autoUpdater.setFeedURL(
      'https://github.com/BensonSin0218/jira_query_watcher/releases/latest/download/appcast.xml',
    );

    // 最少 3600 秒
    await autoUpdater.setScheduledCheckInterval(86400);
  }

  runApp(MyApp(controller: WatchController()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.controller});

  final WatchController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jira Query Watcher',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1868DB),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          alignLabelWithHint: true,
        ),
      ),
      home: WatchPage(controller: controller),
    );
  }
}
