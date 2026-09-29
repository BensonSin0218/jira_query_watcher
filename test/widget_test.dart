import 'package:flutter_test/flutter_test.dart';

import 'package:jira_query_watcher/models.dart';

void main() {
  test(
    'calculates added and removed issues by key when count is unchanged',
    () {
      const previous = [
        JiraIssue(key: 'ABC-1', summary: 'Existing'),
        JiraIssue(key: 'ABC-2', summary: 'Removed'),
      ];
      const current = [
        JiraIssue(key: 'ABC-1', summary: 'Existing with new summary'),
        JiraIssue(key: 'ABC-3', summary: 'Added'),
      ];

      final diff = compareIssues(previous, current);

      expect(diff.added.map((issue) => issue.key), ['ABC-3']);
      expect(diff.removed.map((issue) => issue.key), ['ABC-2']);
      expect(diff.hasChanges, isTrue);
    },
  );

  test('detects issue status changes', () {
    const previous = [
      JiraIssue(key: 'ABC-1', summary: 'Existing', status: 'To Do'),
    ];
    const current = [
      JiraIssue(key: 'ABC-1', summary: 'Existing', status: 'In Progress'),
    ];

    final diff = compareIssues(previous, current);

    expect(diff.added, isEmpty);
    expect(diff.removed, isEmpty);
    expect(diff.statusChanges, hasLength(1));
    expect(diff.statusChanges.single.previous.status, 'To Do');
    expect(diff.statusChanges.single.current.status, 'In Progress');
    expect(diff.hasChanges, isTrue);
  });

  test('does not report changes for an unchanged result set', () {
    const previous = [
      JiraIssue(key: 'ABC-2', summary: 'Second', status: 'Done'),
      JiraIssue(key: 'ABC-1', summary: 'First', status: 'To Do'),
    ];
    const current = [
      JiraIssue(key: 'ABC-1', summary: 'First', status: 'To Do'),
      JiraIssue(key: 'ABC-2', summary: 'Second', status: 'Done'),
    ];

    expect(compareIssues(previous, current).hasChanges, isFalse);
  });

  test('reads and stores the Jira issue status', () {
    final issue = JiraIssue.fromJson({
      'key': 'ABC-1',
      'fields': {
        'summary': 'Existing',
        'status': {'name': 'In Progress'},
      },
    });

    final restored = JiraIssue.fromStoredJson(issue.toStoredJson());

    expect(restored.status, 'In Progress');
  });
}
