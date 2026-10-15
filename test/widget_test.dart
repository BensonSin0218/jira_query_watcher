import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jira_query_watcher/models.dart';
import 'package:jira_query_watcher/services/jira_client.dart';
import 'package:jira_query_watcher/services/native_bridge.dart';
import 'package:jira_query_watcher/services/watch_controller.dart';
import 'package:jira_query_watcher/widgets/common_widgets.dart';
import 'package:jira_query_watcher/widgets/watch_editor_dialog.dart';

void main() {
  group('notification periods', () {
    test('defaults to weekdays and the entire day', () {
      const period = NotificationPeriod();

      expect(period.weekdays, [1, 2, 3, 4, 5]);
      expect(period.startMinute, 0);
      expect(period.endMinute, 1439);
      expect(period.timeLabel, '00:00–23:59');
      expect(period.validationError, isNull);
    });

    test('includes both boundary minutes on the selected weekdays', () {
      const period = NotificationPeriod(
        startMinute: 9 * 60,
        endMinute: 12 * 60,
        weekdays: [DateTime.monday],
      );

      expect(period.contains(DateTime(2026, 10, 12, 8, 59, 59)), isFalse);
      expect(period.contains(DateTime(2026, 10, 12, 9)), isTrue);
      expect(period.contains(DateTime(2026, 10, 12, 12, 0, 59)), isTrue);
      expect(period.contains(DateTime(2026, 10, 12, 12, 1)), isFalse);
      expect(period.contains(DateTime(2026, 10, 13, 10)), isFalse);
      expect(
        const NotificationPeriod().contains(DateTime(2026, 10, 16, 23, 59, 59)),
        isTrue,
      );
      expect(
        const NotificationPeriod().contains(DateTime(2026, 10, 17)),
        isFalse,
      );
    });

    test('only overlaps when a weekday and a minute are shared', () {
      const period = NotificationPeriod(
        startMinute: 9 * 60,
        endMinute: 12 * 60,
        weekdays: [DateTime.monday, DateTime.tuesday],
      );

      for (final other in const [
        NotificationPeriod(startMinute: 9 * 60, endMinute: 12 * 60),
        NotificationPeriod(startMinute: 10 * 60, endMinute: 11 * 60),
        NotificationPeriod(startMinute: 8 * 60, endMinute: 13 * 60),
        NotificationPeriod(startMinute: 12 * 60, endMinute: 13 * 60),
      ]) {
        expect(period.overlaps(other), isTrue);
        expect(other.overlaps(period), isTrue);
      }
      expect(
        period.overlaps(
          const NotificationPeriod(
            startMinute: 12 * 60 + 1,
            endMinute: 13 * 60,
          ),
        ),
        isFalse,
      );
      expect(
        period.overlaps(
          const NotificationPeriod(
            startMinute: 9 * 60,
            endMinute: 12 * 60,
            weekdays: [DateTime.saturday, DateTime.sunday],
          ),
        ),
        isFalse,
      );
    });

    test(
      'rejects invalid times and weekdays without allowing overnight ranges',
      () {
        for (final period in const [
          NotificationPeriod(startMinute: -1),
          NotificationPeriod(endMinute: 1440),
          NotificationPeriod(startMinute: 23 * 60, endMinute: 60),
          NotificationPeriod(weekdays: []),
          NotificationPeriod(weekdays: [0, 8]),
        ]) {
          expect(period.validationError, isNotNull);
        }
        expect(
          const NotificationPeriod(startMinute: 1439).validationError,
          isNull,
        );
      },
    );
  });

  group('watch notification schedules', () {
    test('validates all periods within a watch', () {
      const watch = JqlWatch(jql: 'project = ABC');

      expect(watch.isValid, isTrue);
      expect(watch.notificationPeriods.single.weekdays, [1, 2, 3, 4, 5]);
      expect(watch.copyWith(notificationPeriods: []).isValid, isFalse);
      expect(
        watch
            .copyWith(
              notificationPeriods: const [
                NotificationPeriod(),
                NotificationPeriod(startMinute: 9 * 60, endMinute: 10 * 60),
              ],
            )
            .notificationScheduleError,
        contains('重疊'),
      );
      expect(
        watch
            .copyWith(
              notificationPeriods: const [
                NotificationPeriod(),
                NotificationPeriod(weekdays: [6, 7]),
              ],
            )
            .isValid,
        isTrue,
      );
    });

    test(
      'round trips independent schedules and preserves them when copied',
      () {
        const first = JqlWatch(
          id: 'first',
          jql: 'project = ABC',
          notificationPeriods: [
            NotificationPeriod(startMinute: 9 * 60, endMinute: 12 * 60),
            NotificationPeriod(
              startMinute: 14 * 60,
              endMinute: 18 * 60,
              weekdays: [DateTime.saturday],
            ),
          ],
        );
        const second = JqlWatch(
          id: 'second',
          jql: 'project = DEF',
          notificationPeriods: [
            NotificationPeriod(weekdays: [DateTime.sunday]),
          ],
        );
        final stored = StoredState.fromMap({
          'watchesJson': jsonEncode([first.toMap(), second.toMap()]),
        });

        expect(stored.config.watches.first.toMap(), first.toMap());
        expect(stored.config.watches.last.toMap(), second.toMap());
        expect(
          first
              .copyWith(name: 'Renamed', enabled: false)
              .notificationFingerprint,
          first.notificationFingerprint,
        );
        expect(
          first
              .copyWith(notificationPeriods: second.notificationPeriods)
              .queryFingerprint,
          first.queryFingerprint,
        );
      },
    );

    test('keeps existing and legacy watches active every day', () {
      final existing = JqlWatch.fromMap({
        'id': 'existing',
        'jql': 'project = ABC',
      });
      final legacy = StoredState.fromMap({'jql': 'project = ABC'});

      for (final watch in [existing, legacy.config.watches.single]) {
        expect(watch.notificationPeriods.single.weekdays, [
          1,
          2,
          3,
          4,
          5,
          6,
          7,
        ]);
        expect(
          watch.isWithinNotificationPeriod(DateTime(2026, 10, 18, 23, 59, 59)),
          isTrue,
        );
      }
    });

    test(
      'does not turn an empty or invalid stored schedule into all-day access',
      () {
        for (final periods in [
          <Object?>[],
          [null],
          [
            {
              'startMinute': 0,
              'endMinute': 1440,
              'weekdays': [1],
            },
          ],
        ]) {
          final watch = JqlWatch.fromMap({
            'jql': 'project = ABC',
            'notificationPeriods': periods,
          });

          expect(watch.isValid, isFalse);
          expect(
            watch.isWithinNotificationPeriod(DateTime(2026, 10, 12, 10)),
            isFalse,
          );
        }
      },
    );

    test(
      'finds the next opening or closing boundary including weekly rollover',
      () {
        const watch = JqlWatch(
          jql: 'project = ABC',
          notificationPeriods: [
            NotificationPeriod(startMinute: 9 * 60, endMinute: 12 * 60),
            NotificationPeriod(startMinute: 14 * 60, endMinute: 18 * 60),
          ],
        );

        expect(
          watch.nextNotificationBoundaryAfter(DateTime(2026, 10, 12, 8)),
          DateTime(2026, 10, 12, 9),
        );
        expect(
          watch.nextNotificationBoundaryAfter(DateTime(2026, 10, 12, 9)),
          DateTime(2026, 10, 12, 12, 1),
        );
        expect(
          watch.nextNotificationBoundaryAfter(DateTime(2026, 10, 12, 12, 1)),
          DateTime(2026, 10, 12, 14),
        );
        expect(
          watch.nextNotificationBoundaryAfter(DateTime(2026, 10, 16, 18, 1)),
          DateTime(2026, 10, 19, 9),
        );
        expect(
          const JqlWatch(
            jql: 'project = ABC',
          ).nextNotificationBoundaryAfter(DateTime(2026, 10, 16, 23, 59, 59)),
          DateTime(2026, 10, 17),
        );
        expect(
          const JqlWatch(
            notificationPeriods: [
              NotificationPeriod(weekdays: [DateTime.monday]),
            ],
          ).nextNotificationBoundaryAfter(DateTime(2026, 10, 13)),
          DateTime(2026, 10, 19),
        );
      },
    );
  });

  group('scheduled polling', () {
    testWidgets(
      'pauses outside periods and resumes immediately with the previous baseline',
      (tester) async {
        var now = DateTime(2026, 10, 12, 8, 59);
        final native = _FakeNativeBridge(
          watches: const [
            JqlWatch(
              id: 'work',
              jql: 'project = ABC',
              intervalMinutes: 30,
              notificationPeriods: [
                NotificationPeriod(startMinute: 9 * 60, endMinute: 9 * 60 + 1),
                NotificationPeriod(
                  startMinute: 9 * 60 + 3,
                  endMinute: 9 * 60 + 4,
                ),
              ],
            ),
          ],
        );
        final jira = _FakeJiraClient();
        final controller = WatchController(
          nativeBridge: native,
          jiraClient: jira,
          now: () => now,
        );
        await controller.initialize();
        await controller.pollNow('work');

        expect(jira.requestedWatchIds, isEmpty);
        expect(controller.statusLabel, '等待通知時段');
        expect(controller.hasBaseline, isFalse);

        now = DateTime(2026, 10, 12, 9);
        await tester.pump(const Duration(minutes: 1));
        expect(jira.requestedWatchIds, ['work']);
        expect(controller.hasBaseline, isTrue);
        expect(native.notificationBodies, isEmpty);

        jira.result = const [
          JiraIssue(key: 'ABC-1', summary: 'First'),
          JiraIssue(key: 'ABC-2', summary: 'Added outside the period'),
        ];
        now = DateTime(2026, 10, 12, 9, 2);
        await tester.pump(const Duration(minutes: 2));
        await controller.pollNow('work');
        expect(jira.requestedWatchIds, ['work']);
        expect(controller.statusLabel, '等待通知時段');
        expect(controller.lastCheckedAt, DateTime(2026, 10, 12, 9));

        now = DateTime(2026, 10, 12, 9, 3);
        await tester.pump(const Duration(minutes: 1));
        expect(jira.requestedWatchIds, ['work', 'work']);
        expect(controller.lastDiff.added.single.key, 'ABC-2');
        expect(native.notificationBodies.single, contains('ABC-2'));
        expect(native.state.snapshots['work']?.snapshot, hasLength(2));
        controller.dispose();
      },
    );

    testWidgets('keeps the polling interval within an active period', (
      tester,
    ) async {
      var now = DateTime(2026, 10, 12, 10);
      final native = _FakeNativeBridge(
        watches: const [
          JqlWatch(
            id: 'work',
            jql: 'project = ABC',
            intervalMinutes: 5,
            notificationPeriods: [
              NotificationPeriod(startMinute: 9 * 60, endMinute: 10 * 60 + 9),
            ],
          ),
        ],
      );
      final jira = _FakeJiraClient();
      final controller = WatchController(
        nativeBridge: native,
        jiraClient: jira,
        now: () => now,
      );
      await controller.initialize();

      now = DateTime(2026, 10, 12, 10, 5);
      await tester.pump(const Duration(minutes: 5));
      expect(jira.requestedWatchIds, ['work', 'work']);
      now = DateTime(2026, 10, 12, 10, 10);
      await tester.pump(const Duration(minutes: 5));
      expect(jira.requestedWatchIds, ['work', 'work']);
      expect(controller.statusLabel, '等待通知時段');
      controller.dispose();
    });

    testWidgets('schedules the next weekday after a weekend', (tester) async {
      var now = DateTime(2026, 10, 16, 18, 1);
      final native = _FakeNativeBridge(
        watches: const [
          JqlWatch(
            id: 'work',
            jql: 'project = ABC',
            notificationPeriods: [
              NotificationPeriod(startMinute: 9 * 60, endMinute: 18 * 60),
            ],
          ),
        ],
      );
      final jira = _FakeJiraClient();
      final controller = WatchController(
        nativeBridge: native,
        jiraClient: jira,
        now: () => now,
      );
      await controller.initialize();
      expect(jira.requestedWatchIds, isEmpty);

      final monday = DateTime(2026, 10, 19, 9);
      final delay = monday.difference(now);
      now = monday;
      await tester.pump(delay);
      expect(jira.requestedWatchIds, ['work']);
      expect(controller.statusLabel, '監聽中');
      controller.dispose();
    });

    testWidgets(
      'updates one watch schedule without resetting its baseline or affecting another',
      (tester) async {
        final now = DateTime(2026, 10, 17, 10);
        const weekdayWatch = JqlWatch(
          id: 'weekday',
          name: 'Weekday',
          jql: 'project = ABC',
        );
        const weekendWatch = JqlWatch(
          id: 'weekend',
          jql: 'project = DEF',
          notificationPeriods: [
            NotificationPeriod(weekdays: [6, 7]),
          ],
        );
        final native = _FakeNativeBridge(
          watches: const [weekdayWatch, weekendWatch],
          snapshots: const {
            'weekday': WatchSnapshot(watchId: 'weekday', hasSnapshot: true),
          },
        );
        final jira = _FakeJiraClient();
        final controller = WatchController(
          nativeBridge: native,
          jiraClient: jira,
          now: () => now,
        );
        await controller.initialize();
        expect(jira.requestedWatchIds, ['weekend']);
        expect(controller.watchById('weekday')?.hasBaseline, isTrue);

        final updated = weekdayWatch.copyWith(
          notificationPeriods: weekendWatch.notificationPeriods,
        );
        await controller.updateWatch(updated);
        expect(jira.requestedWatchIds, ['weekend', 'weekday']);
        expect(native.notificationTitles, ['Weekday 有變化']);
        expect(
          controller.watchById('weekday')?.lastDiff.added.single.key,
          'ABC-1',
        );
        expect(
          controller.watchById('weekend')?.config.notificationFingerprint,
          weekendWatch.notificationFingerprint,
        );
        expect(
          native.state.config.watches.first.notificationFingerprint,
          updated.notificationFingerprint,
        );

        await controller.updateWatch(
          weekendWatch.copyWith(
            notificationPeriods: weekdayWatch.notificationPeriods,
          ),
        );
        await controller.pollNow('weekend');
        expect(jira.requestedWatchIds, ['weekend', 'weekday']);
        controller.dispose();
      },
    );

    testWidgets('reschedules when saving the whole configuration', (
      tester,
    ) async {
      final native = _FakeNativeBridge(
        watches: const [JqlWatch(id: 'work', jql: 'project = ABC')],
      );
      final jira = _FakeJiraClient();
      final controller = WatchController(
        nativeBridge: native,
        jiraClient: jira,
        now: () => DateTime(2026, 10, 17, 10),
      );
      await controller.initialize();
      expect(jira.requestedWatchIds, isEmpty);

      final watch = controller.config.watches.single.copyWith(
        notificationPeriods: const [
          NotificationPeriod(weekdays: [6, 7]),
        ],
      );
      await controller.save(controller.config.copyWith(watches: [watch]));
      expect(jira.requestedWatchIds, ['work']);
      expect(controller.hasBaseline, isTrue);
      controller.dispose();
    });

    testWidgets('discards responses that arrive after the period closes', (
      tester,
    ) async {
      var now = DateTime(2026, 10, 12, 11, 59, 30);
      final native = _FakeNativeBridge(
        watches: const [
          JqlWatch(
            id: 'work',
            jql: 'project = ABC',
            notificationPeriods: [
              NotificationPeriod(startMinute: 9 * 60, endMinute: 11 * 60 + 59),
              NotificationPeriod(startMinute: 13 * 60, endMinute: 18 * 60),
            ],
          ),
        ],
      );
      final jira = _FakeJiraClient();
      final controller = WatchController(
        nativeBridge: native,
        jiraClient: jira,
        now: () => now,
      );
      await controller.initialize();
      final previousCheck = controller.lastCheckedAt;
      final response = Completer<List<JiraIssue>>();
      jira.onSearch = () => response.future;
      final polling = controller.pollNow('work');
      now = DateTime(2026, 10, 12, 12);
      jira.result = const [
        JiraIssue(key: 'ABC-1', summary: 'First'),
        JiraIssue(key: 'ABC-2', summary: 'Second'),
      ];
      response.complete(jira.result);
      await polling;

      expect(controller.currentItems, hasLength(1));
      expect(controller.lastCheckedAt, previousCheck);
      expect(native.notificationBodies, isEmpty);

      now = DateTime(2026, 10, 12, 13);
      jira.onSearch = null;
      await controller.pollNow('work');
      expect(controller.lastDiff.added.single.key, 'ABC-2');
      expect(native.notificationBodies.single, contains('ABC-2'));
      controller.dispose();
    });

    testWidgets(
      'rechecks the current schedule before delivering a notification',
      (tester) async {
        var now = DateTime(2026, 10, 12, 11, 59, 30);
        final native = _FakeNativeBridge(
          watches: const [
            JqlWatch(
              id: 'work',
              jql: 'project = ABC',
              notificationPeriods: [
                NotificationPeriod(
                  startMinute: 9 * 60,
                  endMinute: 11 * 60 + 59,
                ),
              ],
            ),
          ],
        );
        final jira = _FakeJiraClient();
        final controller = WatchController(
          nativeBridge: native,
          jiraClient: jira,
          now: () => now,
        );
        await controller.initialize();
        jira.result = const [];
        native.onSave = () async => now = DateTime(2026, 10, 12, 12);
        await controller.pollNow('work');

        expect(native.notificationBodies, isEmpty);
        expect(controller.lastDiff.removed, hasLength(1));
        controller.dispose();
      },
    );

    testWidgets(
      'disabled and removed watches do not resume at the next opening',
      (tester) async {
        var now = DateTime(2026, 10, 12, 8, 59);
        const watch = JqlWatch(
          id: 'work',
          jql: 'project = ABC',
          notificationPeriods: [
            NotificationPeriod(startMinute: 9 * 60, endMinute: 18 * 60),
          ],
        );
        final native = _FakeNativeBridge(
          watches: const [
            watch,
            JqlWatch(id: 'removed', jql: 'project = DEF'),
          ],
        );
        final jira = _FakeJiraClient();
        final controller = WatchController(
          nativeBridge: native,
          jiraClient: jira,
          now: () => now,
        );
        await controller.initialize();
        await controller.setWatchEnabled('work', false);
        await controller.removeWatch('removed');
        jira.requestedWatchIds.clear();

        now = DateTime(2026, 10, 12, 9);
        await tester.pump(const Duration(minutes: 1));
        expect(jira.requestedWatchIds, isEmpty);
        expect(controller.isRunning, isFalse);
        controller.dispose();
      },
    );
  });

  group('notification time editor', () {
    testWidgets('saves the default weekday schedule for a new watch', (
      tester,
    ) async {
      JqlWatch? saved;
      await _openWatchEditor(tester, onSaved: (watch) => saved = watch);

      expect(find.text('通知時間'), findsOneWidget);
      expect(find.text('時段 1 · 00:00–23:59'), findsOneWidget);
      expect(find.text('星期一、二、三、四、五'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'JQL'),
        'project = ABC',
      );
      await tester.tap(find.text('儲存'));
      await tester.pumpAndSettle();

      expect(saved?.notificationPeriods.single.weekdays, [1, 2, 3, 4, 5]);
      expect(saved?.notificationPeriods.single.timeLabel, '00:00–23:59');
    });

    testWidgets(
      'rejects overlaps when adding but allows independent weekdays',
      (tester) async {
        JqlWatch? saved;
        await _openWatchEditor(
          tester,
          watch: const JqlWatch(jql: 'project = ABC'),
          onSaved: (watch) => saved = watch,
        );
        await tester.tap(find.text('新增時段'));
        await tester.pumpAndSettle();

        for (var day = 1; day <= 7; day++) {
          final chip = tester.widget<FilterChip>(
            find.widgetWithText(
              FilterChip,
              '星期${NotificationPeriod.weekdayNames[day - 1]}',
            ),
          );
          expect(chip.selected, day <= 5);
        }
        await tester.tap(find.text('確定'));
        await tester.pumpAndSettle();
        expect(find.text('此時段與其他時段重疊，請調整時間或星期。'), findsOneWidget);

        for (final day in NotificationPeriod.weekdayNames) {
          await tester.tap(find.widgetWithText(FilterChip, '星期$day'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('確定'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('儲存'));
        await tester.pumpAndSettle();

        expect(saved?.notificationPeriods, hasLength(2));
        expect(saved?.notificationPeriods.first.weekdays, [1, 2, 3, 4, 5]);
        expect(saved?.notificationPeriods.last.weekdays, [6, 7]);
      },
    );

    testWidgets('checks edited periods against others but not themselves', (
      tester,
    ) async {
      JqlWatch? saved;
      await _openWatchEditor(
        tester,
        watch: const JqlWatch(
          jql: 'project = ABC',
          notificationPeriods: [
            NotificationPeriod(startMinute: 9 * 60, endMinute: 12 * 60),
            NotificationPeriod(startMinute: 13 * 60, endMinute: 18 * 60),
          ],
        ),
        onSaved: (watch) => saved = watch,
      );
      await tester.tap(find.byTooltip('編輯時段 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('確定'));
      await tester.pumpAndSettle();
      expect(find.text('編輯通知時段'), findsNothing);

      await tester.tap(find.byTooltip('編輯時段 1'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, '結束時間'),
        '14:00',
      );
      await tester.tap(find.text('確定'));
      await tester.pumpAndSettle();
      expect(find.text('此時段與其他時段重疊，請調整時間或星期。'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, '開始時間'),
        '08:00',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '結束時間'),
        '12:00',
      );
      await tester.tap(find.text('確定'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('刪除時段 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('儲存'));
      await tester.pumpAndSettle();

      expect(saved?.notificationPeriods, hasLength(1));
      expect(saved?.notificationPeriods.single.timeLabel, '08:00–12:00');
    });

    testWidgets('requires valid times, weekdays, and at least one period', (
      tester,
    ) async {
      await _openWatchEditor(
        tester,
        watch: const JqlWatch(jql: 'project = ABC'),
      );
      await tester.tap(find.byTooltip('編輯時段 1'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, '開始時間'),
        '24:00',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '結束時間'),
        '23:60',
      );
      await tester.tap(find.text('確定'));
      await tester.pumpAndSettle();
      expect(find.text('請輸入 00:00–23:59（HH:mm）。'), findsNWidgets(2));

      await tester.enterText(
        find.widgetWithText(TextFormField, '開始時間'),
        '23:00',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '結束時間'),
        '01:00',
      );
      await tester.tap(find.text('確定'));
      await tester.pumpAndSettle();
      expect(find.text('開始時間不可晚於結束時間；跨午夜請分成兩個時段。'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, '開始時間'),
        '00:00',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '結束時間'),
        '23:59',
      );
      for (final day in NotificationPeriod.weekdayNames.take(5)) {
        await tester.tap(find.widgetWithText(FilterChip, '星期$day'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('確定'));
      await tester.pumpAndSettle();
      expect(find.text('請至少選擇一天。'), findsOneWidget);

      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('刪除時段 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('儲存'));
      await tester.pumpAndSettle();
      expect(find.text('請新增至少一個通知時段。'), findsOneWidget);
      expect(find.byType(WatchEditorDialog), findsOneWidget);
    });

    testWidgets('cancelling does not mutate the original watch schedule', (
      tester,
    ) async {
      const original = JqlWatch(jql: 'project = ABC');
      JqlWatch? saved = original;
      await _openWatchEditor(
        tester,
        watch: original,
        onSaved: (watch) => saved = watch,
      );
      await tester.tap(find.byTooltip('編輯時段 1'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, '開始時間'),
        '09:00',
      );
      await tester.tap(find.text('確定'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(saved, isNull);
      expect(original.notificationPeriods.single.startMinute, 0);
    });
  });

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

  testWidgets('opens an issue from the row context menu', (tester) async {
    String? openedIssueKey;
    String? copiedIssueKey;
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangesTable(
            diff: const QueryDiff(
              added: [JiraIssue(key: 'ABC-1', summary: 'First issue')],
            ),
            onOpenIssue: (issueKey) async {
              openedIssueKey = issueKey;
            },
            onCopyIssueLink: (issueKey) async {
              copiedIssueKey = issueKey;
            },
            onClear: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('操作'), findsNothing);
    expect(find.byIcon(Icons.open_in_new), findsNothing);

    await tester.tap(find.text('ABC-1'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(find.text('在瀏覽器開啟'), findsOneWidget);
    expect(find.text('複製連結'), findsOneWidget);
    await tester.tap(find.text('在瀏覽器開啟'));
    await tester.pumpAndSettle();

    expect(openedIssueKey, 'ABC-1');

    await tester.tap(find.text('ABC-1'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('複製連結'));
    await tester.pumpAndSettle();

    expect(copiedIssueKey, 'ABC-1');
  });
}

Future<void> _openWatchEditor(
  WidgetTester tester, {
  JqlWatch? watch,
  ValueChanged<JqlWatch?>? onSaved,
}) async {
  tester.view.physicalSize = const Size(1000, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final result = await showDialog<JqlWatch>(
                context: context,
                builder: (_) => WatchEditorDialog(watch: watch),
              );
              onSaved?.call(result);
            },
            child: const Text('開啟編輯器'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('開啟編輯器'));
  await tester.pumpAndSettle();
}

class _FakeNativeBridge extends NativeBridge {
  _FakeNativeBridge({
    required List<JqlWatch> watches,
    Map<String, WatchSnapshot> snapshots = const {},
  }) : state = StoredState(
         config: WatchConfig(
           baseUrl: 'https://jira.example.com',
           token: 'test-token',
           authMode: JiraAuthMode.server,
           watches: watches,
         ),
         snapshots: snapshots,
       );

  StoredState state;
  final List<String> notificationTitles = [];
  final List<String> notificationBodies = [];
  Future<void> Function()? onSave;

  @override
  Future<StoredState> loadState() async => state;

  @override
  Future<void> saveSettings(
    WatchConfig config, [
    Iterable<WatchSnapshot> snapshots = const [],
  ]) async {
    state = StoredState(
      config: config,
      snapshots: {for (final snapshot in snapshots) snapshot.watchId: snapshot},
    );
    await onSave?.call();
  }

  @override
  Future<void> requestNotificationPermission() async {}

  @override
  Future<void> showNotification({
    required String title,
    required String body,
  }) async {
    notificationTitles.add(title);
    notificationBodies.add(body);
  }
}

class _FakeJiraClient extends JiraClient {
  List<JiraIssue> result = const [JiraIssue(key: 'ABC-1', summary: 'First')];
  final List<String> requestedWatchIds = [];
  Future<List<JiraIssue>> Function()? onSearch;

  @override
  Future<List<JiraIssue>> search(WatchConfig config, [JqlWatch? watch]) async {
    requestedWatchIds.add(watch!.id);
    if (onSearch != null) return onSearch!();
    return result;
  }
}
