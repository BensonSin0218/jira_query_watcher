import 'package:flutter_test/flutter_test.dart';

import 'package:jira_query_watcher/models.dart';

void main() {
  test('calculates added and removed issues by key', () {
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
  });

  test('does not report changes for an unchanged result set', () {
    const previous = [
      JiraIssue(key: 'ABC-2', summary: 'Second'),
      JiraIssue(key: 'ABC-1', summary: 'First'),
    ];
    const current = [
      JiraIssue(key: 'ABC-1', summary: 'First'),
      JiraIssue(key: 'ABC-2', summary: 'Second'),
    ];

    expect(compareIssues(previous, current).hasChanges, isFalse);
  });
}
