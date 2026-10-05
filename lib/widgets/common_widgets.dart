import 'package:flutter/material.dart';

import '../models.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
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

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label});

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

class Metric extends StatelessWidget {
  const Metric({super.key, required this.label, required this.value});

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

class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
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

class ChangesTable extends StatelessWidget {
  const ChangesTable({
    super.key,
    required this.diff,
    required this.onOpenIssue,
    required this.onClear,
  });

  final QueryDiff diff;
  final Future<void> Function(String issueKey) onOpenIssue;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final rows = [
      ...diff.added
          .take(10)
          .map(
            (issue) => _ChangeTableRow(
              type: '新增',
              color: Colors.green,
              issue: issue,
              status: issue.status ?? '未知',
            ),
          ),
      ...diff.removed
          .take(10)
          .map(
            (issue) => _ChangeTableRow(
              type: '移除',
              color: Colors.red,
              issue: issue,
              status: issue.status ?? '未知',
            ),
          ),
      ...diff.statusChanges
          .take(10)
          .map(
            (change) => _ChangeTableRow(
              type: '狀態變更',
              color: Colors.orange,
              issue: change.current,
              status:
                  '${change.previous.status ?? '未知'} → ${change.current.status ?? '未知'}',
            ),
          ),
    ];
    final totalChanges =
        diff.added.length + diff.removed.length + diff.statusChanges.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Jira 項目變化',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.clear_all, size: 18),
              label: const Text('清除'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('類型')),
                DataColumn(label: Text('Jira Key')),
                DataColumn(label: Text('摘要')),
                DataColumn(label: Text('狀態')),
                DataColumn(label: Text('操作')),
              ],
              rows: [
                for (final row in rows)
                  DataRow(
                    cells: [
                      DataCell(
                        Text(
                          row.type,
                          style: TextStyle(
                            color: row.color,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      DataCell(Text(row.issue.key)),
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 360),
                          child: Text(
                            row.issue.summary,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          row.status,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DataCell(
                        IconButton(
                          onPressed: () => onOpenIssue(row.issue.key),
                          icon: const Icon(Icons.open_in_new, size: 18),
                          tooltip: '在瀏覽器開啟',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        if (totalChanges > rows.length)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('還有 ${totalChanges - rows.length} 項變化未顯示。'),
          ),
      ],
    );
  }
}

class _ChangeTableRow {
  const _ChangeTableRow({
    required this.type,
    required this.color,
    required this.issue,
    required this.status,
  });

  final String type;
  final Color color;
  final JiraIssue issue;
  final String status;
}
