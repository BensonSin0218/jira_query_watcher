import 'dart:io';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/watch_controller.dart';
import '../widgets/common_widgets.dart';
import '../widgets/watch_editor_dialog.dart';
import 'monitor_page.dart';
import 'settings_page.dart';

class WatchPage extends StatefulWidget {
  const WatchPage({super.key, required this.controller});

  final WatchController controller;

  @override
  State<WatchPage> createState() => _WatchPageState();
}

class _WatchPageState extends State<WatchPage> {
  late final TextEditingController _baseUrlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _tokenController;
  JiraAuthMode _authMode = JiraAuthMode.cloud;
  bool _launchAtLogin = false;
  bool _loading = true;
  int _selectedPage = 0;

  WatchController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController();
    _usernameController = TextEditingController();
    _tokenController = TextEditingController();
    controller.addListener(_onControllerChanged);
    _initialize();
  }

  Future<void> _initialize() async {
    await controller.initialize();
    if (!mounted) return;
    _syncFields(controller.config);
    setState(() => _loading = false);
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _syncFields(WatchConfig config) {
    _baseUrlController.text = config.baseUrl;
    _usernameController.text = config.username;
    _authMode = config.authMode;
    _launchAtLogin = config.launchAtLogin;
  }

  WatchConfig _configFromFields() {
    final enteredToken = _tokenController.text.trim();
    return controller.config.copyWith(
      baseUrl: _baseUrlController.text.trim(),
      username: _usernameController.text.trim(),
      token: enteredToken.isEmpty ? controller.config.token : enteredToken,
      authMode: _authMode,
      launchAtLogin: _launchAtLogin,
    );
  }

  Future<void> _saveConnection() async {
    await controller.save(_configFromFields());
    if (!mounted) return;
    if (controller.error == null) {
      _tokenController.clear();
    }
  }

  Future<void> _toggleLaunchAtLogin(bool value) async {
    setState(() => _launchAtLogin = value);
    try {
      await controller.setLaunchAtLogin(value);
    } catch (error) {
      if (!mounted) return;
      setState(() => _launchAtLogin = !value);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _addWatch() async {
    final watch = await showDialog<JqlWatch>(
      context: context,
      builder: (_) => const WatchEditorDialog(),
    );
    if (watch != null) await controller.addWatch(watch);
  }

  Future<void> _editWatch(WatchRuntime state) async {
    final watch = await showDialog<JqlWatch>(
      context: context,
      builder: (_) => WatchEditorDialog(watch: state.config),
    );
    if (watch != null) await controller.updateWatch(watch);
  }

  Future<void> _showJqlDialog(JqlWatch watch) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${watch.displayName} 的 JQL'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540, maxHeight: 400),
          child: SingleChildScrollView(
            child: SelectableText(
              watch.jql,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('關閉'),
          ),
        ],
      ),
    );
  }

  Future<void> _openIssueInBrowser(String issueKey) async {
    final baseUrl = controller.config.baseUrl.trim().replaceFirst(
      RegExp(r'/+$'),
      '',
    );
    final uri = Uri.tryParse(
      '$baseUrl/browse/${Uri.encodeComponent(issueKey)}',
    );
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('請先設定有效的 Jira Base URL。')));
      }
      return;
    }

    try {
      final result = await Process.run('open', [uri.toString()]);
      if (result.exitCode != 0 && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('無法開啟 Jira 網頁。')));
      }
    } on ProcessException {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('無法開啟 Jira 網頁。')));
    }
  }

  Future<void> _removeWatch(WatchRuntime state) async {
    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除監聽？'),
        content: Text('確定要刪除「${state.config.displayName}」嗎？歷史基準也會一併移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (shouldRemove == true) await controller.removeWatch(state.config.id);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Jira Query Watcher'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: StatusBadge(label: controller.statusLabel),
          ),
        ],
      ),
      body: Row(
        children: [
          _buildNavigationRail(),
          const VerticalDivider(width: 1),
          Expanded(
            child: _selectedPage == 0
                ? MonitorPage(
                    controller: controller,
                    onAddWatch: _addWatch,
                    onEditWatch: _editWatch,
                    onShowJql: _showJqlDialog,
                    onOpenIssue: _openIssueInBrowser,
                    onRemoveWatch: _removeWatch,
                  )
                : SettingsPage(
                    controller: controller,
                    baseUrlController: _baseUrlController,
                    usernameController: _usernameController,
                    tokenController: _tokenController,
                    authMode: _authMode,
                    onAuthModeChanged: (value) {
                      setState(() => _authMode = value);
                    },
                    onSaveConnection: _saveConnection,
                    launchAtLogin: _launchAtLogin,
                    onLaunchAtLoginChanged: _toggleLaunchAtLogin,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationRail() {
    return NavigationRail(
      selectedIndex: _selectedPage,
      onDestinationSelected: (index) {
        setState(() => _selectedPage = index);
      },
      labelType: NavigationRailLabelType.all,
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.monitor_heart_outlined),
          selectedIcon: Icon(Icons.monitor_heart),
          label: Text('監聽'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: Text('設定'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChanged);
    controller.dispose();
    _baseUrlController.dispose();
    _usernameController.dispose();
    _tokenController.dispose();
    super.dispose();
  }
}
