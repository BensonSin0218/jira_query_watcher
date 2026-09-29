import 'dart:io';

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/material.dart';

import 'models.dart';
import 'services/watch_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isMacOS) {
    await autoUpdater.setFeedURL('https://github.com/BensonSin0218/jira_query_watcher/releases/latest/download/appcast.xml');

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
      builder: (_) => const _WatchEditorDialog(),
    );
    if (watch != null) await controller.addWatch(watch);
  }

  Future<void> _editWatch(WatchRuntime state) async {
    final watch = await showDialog<JqlWatch>(
      context: context,
      builder: (_) => _WatchEditorDialog(watch: state.config),
    );
    if (watch != null) await controller.updateWatch(watch);
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
            child: _StatusBadge(label: controller.statusLabel),
          ),
        ],
      ),
      body: Row(
        children: [
          _buildNavigationRail(),
          const VerticalDivider(width: 1),
          Expanded(
            child: _selectedPage == 0
                ? _buildWatchContent(context)
                : _buildSettingsPage(context),
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

  Widget _buildWatchContent(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildIntro(context),
              const SizedBox(height: 20),
              _buildWatchesCard(context),
              const SizedBox(height: 16),
              _buildOverviewCard(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsPage(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '設定',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text('管理 Jira 連線資訊與執行方式；監聽頁中的每個 JQL 可個別設定檢查間隔。'),
              const SizedBox(height: 20),
              _buildConnectionCard(context),
              const SizedBox(height: 16),
              _buildActionsCard(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIntro(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 25,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            Icons.notifications_active_outlined,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '監聽多個 Jira JQL 查詢',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 4),
              Text('每個監聽都有自己的檢查間隔與基準；issue 有新增或移除時會發送 macOS 通知。'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionCard(BuildContext context) {
    return _SectionCard(
      title: 'Jira 連線',
      icon: Icons.cloud_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<JiraAuthMode>(
            initialValue: _authMode,
            decoration: const InputDecoration(labelText: 'Jira 類型'),
            items: JiraAuthMode.values
                .map(
                  (mode) =>
                      DropdownMenuItem(value: mode, child: Text(mode.label)),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _authMode = value);
            },
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _baseUrlController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Jira Base URL',
              hintText: 'https://your-company.atlassian.net',
              helperText: '不要包含 /rest/api/... 路徑',
            ),
          ),
          if (_authMode == JiraAuthMode.cloud) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _usernameController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Jira Email',
                hintText: 'name@example.com',
              ),
            ),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _tokenController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: _authMode == JiraAuthMode.cloud
                  ? 'API Token'
                  : 'Personal Access Token',
              hintText: controller.config.hasToken
                  ? '已儲存 token；留白表示沿用'
                  : '輸入 token',
              helperText: 'Token 只會存放在 macOS Keychain，不會寫入一般設定檔。',
            ),
          ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _saveConnection,
              icon: const Icon(Icons.save_outlined),
              label: const Text('儲存連線設定'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWatchesCard(BuildContext context) {
    final watches = controller.watches;
    return _SectionCard(
      title: 'JQL 監聽',
      icon: Icons.manage_search_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              const Text('可新增不同查詢，每個查詢獨立執行與保存歷史基準。'),
              FilledButton.icon(
                onPressed: _addWatch,
                icon: const Icon(Icons.add),
                label: const Text('新增監聽'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (watches.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                children: [
                  Icon(Icons.notifications_none_outlined, size: 32),
                  SizedBox(height: 8),
                  Text('尚未新增 JQL 監聽'),
                  SizedBox(height: 4),
                  Text('按下「新增監聽」開始設定第一個查詢。'),
                ],
              ),
            )
          else
            ...List.generate(
              watches.length,
              (index) => Padding(
                padding: EdgeInsets.only(top: index == 0 ? 0 : 12),
                child: _buildWatchCard(context, watches[index]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWatchCard(BuildContext context, WatchRuntime state) {
    final watch = state.config;
    final diff = state.lastDiff;
    final canPoll = controller.isReady && watch.isValid && !state.isPolling;
    final cardColor = Theme.of(context).colorScheme.surfaceContainerHighest;

    return Card(
      margin: EdgeInsets.zero,
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20,
                  child: Icon(
                    watch.enabled
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_off_outlined,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        watch.displayName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        state.isPolling
                            ? '正在檢查'
                            : state.isRunning
                            ? '監聽中'
                            : watch.enabled
                            ? '等待設定完成'
                            : '已停用',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: watch.enabled,
                  onChanged: (value) =>
                      controller.setWatchEnabled(watch.id, value),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                watch.jql,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _Metric(label: '檢查間隔', value: '${watch.intervalMinutes} 分鐘'),
                _Metric(label: '目前結果', value: '${state.currentItems.length} 項'),
                _Metric(
                  label: '上次檢查',
                  value: _formatDateTime(state.lastCheckedAt),
                ),
                _Metric(label: '上次新增', value: '${diff.added.length} 項'),
                _Metric(label: '上次移除', value: '${diff.removed.length} 項'),
              ],
            ),
            if (!watch.isValid) ...[
              const SizedBox(height: 14),
              const _InfoBanner(
                icon: Icons.error_outline,
                message: '請填寫 JQL 後才能開始檢查。',
                error: true,
              ),
            ],
            if (state.message != null) ...[
              const SizedBox(height: 14),
              _InfoBanner(icon: Icons.info_outline, message: state.message!),
            ],
            if (state.error != null) ...[
              const SizedBox(height: 12),
              _InfoBanner(
                icon: Icons.error_outline,
                message: state.error!,
                error: true,
              ),
            ],
            if (diff.hasChanges) ...[
              const SizedBox(height: 14),
              _ChangeLists(diff: diff),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: canPoll
                      ? () => controller.pollNow(watch.id)
                      : null,
                  icon: const Icon(Icons.refresh),
                  label: const Text('立即檢查'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _editWatch(state),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('編輯'),
                ),
                TextButton.icon(
                  onPressed: () => _removeWatch(state),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('刪除'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsCard(BuildContext context) {
    return _SectionCard(
      title: '執行控制',
      icon: Icons.tune_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('登入 macOS 後自動啟動'),
            subtitle: const Text('需要 macOS 13 或以上；應用程式會在背景常駐。'),
            value: _launchAtLogin,
            onChanged: _toggleLaunchAtLogin,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () async {
                await autoUpdater.checkForUpdates();
              },
              icon: const Icon(Icons.system_update_outlined),
              label: const Text('檢查更新'),
            ),
          ),
          if (controller.message != null || controller.error != null) ...[
            const Divider(height: 20),
            if (controller.message != null)
              _InfoBanner(
                icon: Icons.info_outline,
                message: controller.message!,
              ),
            if (controller.error != null) ...[
              if (controller.message != null) const SizedBox(height: 12),
              _InfoBanner(
                icon: Icons.error_outline,
                message: controller.error!,
                error: true,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildOverviewCard(BuildContext context) {
    final watches = controller.watches;
    return _SectionCard(
      title: '目前狀態',
      icon: Icons.monitor_heart_outlined,
      child: Wrap(
        spacing: 24,
        runSpacing: 12,
        children: [
          _Metric(label: '監聽數量', value: '${watches.length} 個'),
          _Metric(
            label: '執行中',
            value: '${watches.where((watch) => watch.isRunning).length} 個',
          ),
          _Metric(
            label: '檢查中',
            value: '${watches.where((watch) => watch.isPolling).length} 個',
          ),
          _Metric(label: '連線狀態', value: controller.isReady ? '已設定' : '未完成'),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) return '尚未檢查';
    final local = value.toLocal();
    final date =
        '${local.year}/${local.month.toString().padLeft(2, '0')}/'
        '${local.day.toString().padLeft(2, '0')}';
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}'
        ':${local.second.toString().padLeft(2, '0')}';
    return '$date $time';
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

class _WatchEditorDialog extends StatefulWidget {
  const _WatchEditorDialog({this.watch});

  final JqlWatch? watch;

  @override
  State<_WatchEditorDialog> createState() => _WatchEditorDialogState();
}

class _WatchEditorDialogState extends State<_WatchEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _jqlController;
  late double _intervalMinutes;
  late bool _enabled;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.watch?.name ?? '');
    _jqlController = TextEditingController(text: widget.watch?.jql ?? '');
    _intervalMinutes = (widget.watch?.intervalMinutes ?? 5).toDouble();
    _enabled = widget.watch?.enabled ?? true;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final watch = widget.watch?.copyWith(
      name: _nameController.text.trim(),
      jql: _jqlController.text.trim(),
      intervalMinutes: _intervalMinutes.round(),
      enabled: _enabled,
    );
    Navigator.of(context).pop(
      watch ??
          JqlWatch(
            name: _nameController.text.trim(),
            jql: _jqlController.text.trim(),
            intervalMinutes: _intervalMinutes.round(),
            enabled: _enabled,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.watch != null;
    return AlertDialog(
      title: Text(isEditing ? '編輯 JQL 監聽' : '新增 JQL 監聽'),
      content: SizedBox(
        width: 540,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: '名稱（選填）',
                    hintText: '例如：待處理缺陷',
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _jqlController,
                  minLines: 4,
                  maxLines: 8,
                  autofocus: !isEditing,
                  decoration: const InputDecoration(
                    labelText: 'JQL',
                    hintText:
                        'project = ABC AND status != Done ORDER BY updated DESC',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '請輸入 JQL。';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Text(
                      '檢查間隔',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 12),
                    Text('${_intervalMinutes.round()} 分鐘'),
                    Expanded(
                      child: Slider(
                        value: _intervalMinutes,
                        min: 1,
                        max: 30,
                        divisions: 29,
                        label: '${_intervalMinutes.round()} 分鐘',
                        onChanged: (value) {
                          setState(() => _intervalMinutes = value);
                        },
                      ),
                    ),
                  ],
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('啟用此監聽'),
                  value: _enabled,
                  onChanged: (value) => setState(() => _enabled = value),
                ),
                Text(
                  '可設定範圍：1–30 分鐘。第一次成功查詢只建立基準，不會立即發送變化通知。',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('儲存')),
      ],
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _jqlController.dispose();
    super.dispose();
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(
        Icons.circle,
        size: 10,
        color: Theme.of(context).colorScheme.primary,
      ),
      label: Text(label),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        const SizedBox(height: 3),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.message,
    this.error = false,
  });

  final IconData icon;
  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error
        ? Theme.of(context).colorScheme.errorContainer
        : Theme.of(context).colorScheme.secondaryContainer;
    final foreground = error
        ? Theme.of(context).colorScheme.onErrorContainer
        : Theme.of(context).colorScheme.onSecondaryContainer;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(color: foreground)),
          ),
        ],
      ),
    );
  }
}

class _ChangeLists extends StatelessWidget {
  const _ChangeLists({required this.diff});

  final QueryDiff diff;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 20,
      runSpacing: 16,
      children: [
        if (diff.added.isNotEmpty)
          _IssueGroup(title: '新增', color: Colors.green, issues: diff.added),
        if (diff.removed.isNotEmpty)
          _IssueGroup(title: '移除', color: Colors.red, issues: diff.removed),
      ],
    );
  }
}

class _IssueGroup extends StatelessWidget {
  const _IssueGroup({
    required this.title,
    required this.color,
    required this.issues,
  });

  final String title;
  final Color color;
  final List<JiraIssue> issues;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 410,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title (${issues.length})',
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          ...issues
              .take(10)
              .map(
                (issue) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${issue.key}  ${issue.summary}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          if (issues.length > 10) Text('還有 ${issues.length - 10} 項…'),
        ],
      ),
    );
  }
}
