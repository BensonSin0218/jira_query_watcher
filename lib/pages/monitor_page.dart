import 'package:flutter/material.dart';

import '../models.dart';
import '../services/watch_controller.dart';
import '../widgets/common_widgets.dart';

class MonitorPage extends StatelessWidget {
  const MonitorPage({
    super.key,
    required this.controller,
    required this.onAddWatch,
    required this.onEditWatch,
    required this.onShowJql,
    required this.onOpenIssue,
    required this.onRemoveWatch,
  });

  final WatchController controller;
  final Future<void> Function() onAddWatch;
  final Future<void> Function(WatchRuntime state) onEditWatch;
  final Future<void> Function(JqlWatch watch) onShowJql;
  final Future<void> Function(String issueKey) onOpenIssue;
  final Future<void> Function(WatchRuntime state) onRemoveWatch;

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
              _buildIntro(context),
              const SizedBox(height: 20),
              _buildOverviewCard(context),
              const SizedBox(height: 16),
              _buildWatchesCard(context),
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
              Text('每個監聽都有自己的檢查間隔與基準；issue 清單或 status 有變動時會發送 macOS 通知。'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWatchesCard(BuildContext context) {
    final watches = controller.watches;
    return SectionCard(
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
                onPressed: () => onAddWatch(),
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
                      Row(
                        spacing: 8,
                        children: [
                          Flexible(
                            child: Text(
                              watch.displayName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => onShowJql(watch),
                            icon: const Icon(Icons.info_outline),
                            tooltip: '查看 JQL',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                          ),
                        ],
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
                  onChanged: (value) {
                    controller.setWatchEnabled(watch.id, value);
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                Metric(label: '檢查間隔', value: '${watch.intervalMinutes} 分鐘'),
                Metric(label: '目前結果', value: '${state.currentItems.length} 項'),
                Metric(
                  label: '上次檢查',
                  value: _formatDateTime(state.lastCheckedAt),
                ),
                Metric(label: '上次新增', value: '${diff.added.length} 項'),
                Metric(label: '上次移除', value: '${diff.removed.length} 項'),
                Metric(
                  label: '上次狀態變更',
                  value: '${diff.statusChanges.length} 項',
                ),
              ],
            ),
            if (diff.hasChanges) ...[
              const SizedBox(height: 14),
              ChangesTable(diff: diff, onOpenIssue: onOpenIssue),
            ],
            if (!watch.isValid) ...[
              const SizedBox(height: 14),
              const InfoBanner(
                icon: Icons.error_outline,
                message: '請填寫 JQL 後才能開始檢查。',
                error: true,
              ),
            ],
            if (state.message != null) ...[
              const SizedBox(height: 14),
              InfoBanner(icon: Icons.info_outline, message: state.message!),
            ],
            if (state.error != null) ...[
              const SizedBox(height: 12),
              InfoBanner(
                icon: Icons.error_outline,
                message: state.error!,
                error: true,
              ),
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
                  onPressed: () => onEditWatch(state),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('編輯'),
                ),
                TextButton.icon(
                  onPressed: () => onRemoveWatch(state),
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

  Widget _buildOverviewCard(BuildContext context) {
    final watches = controller.watches;
    return SectionCard(
      title: '目前狀態',
      icon: Icons.monitor_heart_outlined,
      child: Wrap(
        spacing: 24,
        runSpacing: 12,
        children: [
          Metric(label: '監聽數量', value: '${watches.length} 個'),
          Metric(
            label: '執行中',
            value: '${watches.where((watch) => watch.isRunning).length} 個',
          ),
          Metric(
            label: '檢查中',
            value: '${watches.where((watch) => watch.isPolling).length} 個',
          ),
          Metric(label: '連線狀態', value: controller.isReady ? '已設定' : '未完成'),
        ],
      ),
    );
  }
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
