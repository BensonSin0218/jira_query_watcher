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
    required this.onCopyIssueLink,
    required this.onClear,
  });

  final QueryDiff diff;
  final Future<void> Function(String issueKey) onOpenIssue;
  final Future<void> Function(String issueKey) onCopyIssueLink;
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
              ],
              rows: [
                for (final row in rows)
                  DataRow(
                    cells: [
                      _issueMenuCell(
                        Text(
                          row.type,
                          style: TextStyle(
                            color: row.color,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        row.issue.key,
                      ),
                      _issueMenuCell(Text(row.issue.key), row.issue.key),
                      _issueMenuCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 360),
                          child: Text(
                            row.issue.summary,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        row.issue.key,
                      ),
                      _issueMenuCell(
                        Text(
                          row.status,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        row.issue.key,
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

  DataCell _issueMenuCell(Widget child, String issueKey) {
    return DataCell(
      _IssueContextMenuCell(
        issueKey: issueKey,
        onOpenIssue: onOpenIssue,
        onCopyIssueLink: onCopyIssueLink,
        child: child,
      ),
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

enum _IssueMenuAction { open, copyLink }

class _IssueContextMenuCell extends StatelessWidget {
  const _IssueContextMenuCell({
    required this.issueKey,
    required this.onOpenIssue,
    required this.onCopyIssueLink,
    required this.child,
  });

  final String issueKey;
  final Future<void> Function(String issueKey) onOpenIssue;
  final Future<void> Function(String issueKey) onCopyIssueLink;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: (details) {
          _showMenu(context, details.globalPosition);
        },
        child: child,
      ),
    );
  }

  Future<void> _showMenu(BuildContext context, Offset globalPosition) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final localPosition = overlay.globalToLocal(globalPosition);
    final action = await showMenu<_IssueMenuAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        localPosition.dx,
        localPosition.dy,
        overlay.size.width - localPosition.dx,
        overlay.size.height - localPosition.dy,
      ),
      items: const [
        PopupMenuItem<_IssueMenuAction>(
          value: _IssueMenuAction.open,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.open_in_new, size: 18),
              SizedBox(width: 8),
              Text('在瀏覽器開啟'),
            ],
          ),
        ),
        PopupMenuItem<_IssueMenuAction>(
          value: _IssueMenuAction.copyLink,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.link, size: 18),
              SizedBox(width: 8),
              Text('複製連結'),
            ],
          ),
        ),
      ],
    );
    if (action == _IssueMenuAction.open) {
      await onOpenIssue(issueKey);
    } else if (action == _IssueMenuAction.copyLink) {
      await onCopyIssueLink(issueKey);
    }
  }
}
