import 'package:flutter/gestures.dart';
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

class ChangesTable extends StatefulWidget {
  const ChangesTable({
    super.key,
    required this.diff,
    required this.onOpenIssue,
    required this.onCopyText,
    required this.onCopyIssueLink,
    required this.onClear,
  });

  final QueryDiff diff;
  final Future<void> Function(String issueKey) onOpenIssue;
  final Future<void> Function(String text) onCopyText;
  final Future<void> Function(String issueKey) onCopyIssueLink;
  final VoidCallback onClear;

  @override
  State<ChangesTable> createState() => _ChangesTableState();
}

class _ChangesTableState extends State<ChangesTable> {
  int? _sortColumnIndex;
  bool _sortAscending = true;

  void _sortRows(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
    });
  }

  List<_ChangeTableRow> _rows() {
    final rows = [
      ...widget.diff.added.map(
        (issue) => _ChangeTableRow(
          type: '新增',
          color: Colors.green,
          issue: issue,
          status: issue.status ?? '未知',
        ),
      ),
      ...widget.diff.removed.map(
        (issue) => _ChangeTableRow(
          type: '移除',
          color: Colors.red,
          issue: issue,
          status: issue.status ?? '未知',
        ),
      ),
      ...widget.diff.statusChanges.map(
        (change) => _ChangeTableRow(
          type: '狀態變更',
          color: Colors.orange,
          issue: change.current,
          status:
              '${change.previous.status ?? '未知'} → ${change.current.status ?? '未知'}',
        ),
      ),
    ];

    final sortColumnIndex = _sortColumnIndex;
    if (sortColumnIndex == null) return _limitRows(rows);

    final indexedRows = rows.asMap().entries.toList();
    indexedRows.sort((a, b) {
      final comparison = _compareRows(
        a.value,
        b.value,
        columnIndex: sortColumnIndex,
      );
      if (comparison != 0) {
        return _sortAscending ? comparison : -comparison;
      }
      return a.key.compareTo(b.key);
    });
    return _limitRows(indexedRows.map((entry) => entry.value).toList());
  }

  List<_ChangeTableRow> _limitRows(List<_ChangeTableRow> rows) {
    final countsByType = <String, int>{};
    final visibleRows = <_ChangeTableRow>[];
    for (final row in rows) {
      final count = countsByType[row.type] ?? 0;
      if (count >= 10) continue;
      countsByType[row.type] = count + 1;
      visibleRows.add(row);
    }
    return visibleRows;
  }

  int _compareRows(
    _ChangeTableRow first,
    _ChangeTableRow second, {
    required int columnIndex,
  }) {
    final firstValue = switch (columnIndex) {
      0 => first.type,
      1 => first.issue.key,
      2 => first.issue.summary,
      3 => first.status,
      _ => '',
    };
    final secondValue = switch (columnIndex) {
      0 => second.type,
      1 => second.issue.key,
      2 => second.issue.summary,
      3 => second.status,
      _ => '',
    };
    return firstValue.toLowerCase().compareTo(secondValue.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows();
    final totalChanges =
        widget.diff.added.length +
        widget.diff.removed.length +
        widget.diff.statusChanges.length;

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
              onPressed: widget.onClear,
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
              sortColumnIndex: _sortColumnIndex,
              sortAscending: _sortAscending,
              columns: [
                DataColumn(label: const Text('類型'), onSort: _sortRows),
                DataColumn(label: const Text('Jira Key'), onSort: _sortRows),
                DataColumn(label: const Text('摘要'), onSort: _sortRows),
                DataColumn(label: const Text('狀態'), onSort: _sortRows),
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
                        row.type,
                      ),
                      _issueMenuCell(
                        SelectableText(row.issue.key),
                        row.issue.key,
                        row.issue.key,
                      ),
                      _issueMenuCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 360),
                          child: SelectableText(row.issue.summary, maxLines: 2),
                        ),
                        row.issue.key,
                        row.issue.summary,
                      ),
                      _issueMenuCell(
                        Text(
                          row.status,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        row.issue.key,
                        row.status,
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

  DataCell _issueMenuCell(Widget child, String issueKey, String copyText) {
    return DataCell(
      _IssueContextMenuCell(
        issueKey: issueKey,
        onOpenIssue: widget.onOpenIssue,
        onCopyText: widget.onCopyText,
        onCopyIssueLink: widget.onCopyIssueLink,
        copyText: copyText,
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

enum _IssueMenuAction { copy, open, copyLink }

class _IssueContextMenuCell extends StatelessWidget {
  const _IssueContextMenuCell({
    required this.issueKey,
    required this.onOpenIssue,
    required this.onCopyText,
    required this.onCopyIssueLink,
    required this.copyText,
    required this.child,
  });

  final String issueKey;
  final Future<void> Function(String issueKey) onOpenIssue;
  final Future<void> Function(String text) onCopyText;
  final Future<void> Function(String issueKey) onCopyIssueLink;
  final String copyText;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          if (event.buttons & kSecondaryMouseButton != 0) {
            _showMenu(context, event.position);
          }
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
          value: _IssueMenuAction.copy,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.copy_outlined, size: 18),
              SizedBox(width: 8),
              Text('複製'),
            ],
          ),
        ),
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
    if (action == _IssueMenuAction.copy) {
      await onCopyText(copyText);
    } else if (action == _IssueMenuAction.open) {
      await onOpenIssue(issueKey);
    } else if (action == _IssueMenuAction.copyLink) {
      await onCopyIssueLink(issueKey);
    }
  }
}
