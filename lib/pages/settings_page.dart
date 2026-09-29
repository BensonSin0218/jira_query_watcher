import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/watch_controller.dart';
import '../widgets/common_widgets.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    required this.baseUrlController,
    required this.usernameController,
    required this.tokenController,
    required this.authMode,
    required this.onAuthModeChanged,
    required this.onSaveConnection,
    required this.launchAtLogin,
    required this.onLaunchAtLoginChanged,
  });

  final WatchController controller;
  final TextEditingController baseUrlController;
  final TextEditingController usernameController;
  final TextEditingController tokenController;
  final JiraAuthMode authMode;
  final ValueChanged<JiraAuthMode> onAuthModeChanged;
  final Future<void> Function() onSaveConnection;
  final bool launchAtLogin;
  final Future<void> Function(bool value) onLaunchAtLoginChanged;

  @override
  Widget build(BuildContext context) {
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

  Widget _buildConnectionCard(BuildContext context) {
    return SectionCard(
      title: 'Jira 連線',
      icon: Icons.cloud_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<JiraAuthMode>(
            initialValue: authMode,
            decoration: const InputDecoration(labelText: 'Jira 類型'),
            items: JiraAuthMode.values
                .map(
                  (mode) =>
                      DropdownMenuItem(value: mode, child: Text(mode.label)),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) onAuthModeChanged(value);
            },
          ),
          const SizedBox(height: 14),
          TextField(
            controller: baseUrlController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Jira Base URL',
              hintText: 'https://your-company.atlassian.net',
              helperText: '不要包含 /rest/api/... 路徑',
            ),
          ),
          if (authMode == JiraAuthMode.cloud) ...[
            const SizedBox(height: 14),
            TextField(
              controller: usernameController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Jira Email',
                hintText: 'name@example.com',
              ),
            ),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: tokenController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: authMode == JiraAuthMode.cloud
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
              onPressed: () => onSaveConnection(),
              icon: const Icon(Icons.save_outlined),
              label: const Text('儲存連線設定'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsCard(BuildContext context) {
    return SectionCard(
      title: '執行控制',
      icon: Icons.tune_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('登入 macOS 後自動啟動'),
            subtitle: const Text('需要 macOS 13 或以上；應用程式會在背景常駐。'),
            value: launchAtLogin,
            onChanged: (value) {
              onLaunchAtLoginChanged(value);
            },
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
              InfoBanner(
                icon: Icons.info_outline,
                message: controller.message!,
              ),
            if (controller.error != null) ...[
              if (controller.message != null) const SizedBox(height: 12),
              InfoBanner(
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
}
