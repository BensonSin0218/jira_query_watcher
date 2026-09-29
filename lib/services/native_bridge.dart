import 'dart:convert';

import 'package:flutter/services.dart';

import '../models.dart';

class StoredState {
  const StoredState({required this.config, required this.snapshots});

  final WatchConfig config;
  final Map<String, WatchSnapshot> snapshots;

  factory StoredState.fromMap(Map<Object?, Object?> map) {
    final watchesJson = map['watchesJson'] as String?;
    final hasNewWatchStorage = watchesJson != null && watchesJson.isNotEmpty;
    final watches = hasNewWatchStorage
        ? _decodeWatches(watchesJson)
        : _legacyWatches(map);
    final snapshotsJson = map['watchStatesJson'] as String?;
    final snapshots = snapshotsJson != null && snapshotsJson.isNotEmpty
        ? _decodeSnapshots(snapshotsJson)
        : _legacySnapshots(map, watches);

    return StoredState(
      config: WatchConfig(
        baseUrl: map['baseUrl'] as String? ?? '',
        username: map['username'] as String? ?? '',
        token: map['token'] as String? ?? '',
        authMode: JiraAuthModeX.fromStorage(map['authMode']),
        launchAtLogin: map['launchAtLogin'] == true,
        watches: watches,
      ),
      snapshots: snapshots,
    );
  }

  static List<JqlWatch> _decodeWatches(String? value) {
    if (value == null || value.isEmpty) return const [];
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => JqlWatch.fromMap(Map<String, dynamic>.from(item)))
          .toList();
    } on FormatException {
      return const [];
    }
  }

  static List<JqlWatch> _legacyWatches(Map<Object?, Object?> map) {
    final jql = map['jql'] as String? ?? '';
    if (jql.trim().isEmpty) return const [];

    final interval = ((map['intervalMinutes'] as num?)?.toInt() ?? 5)
        .clamp(1, 30)
        .toInt();
    return [
      JqlWatch(
        id: 'legacy',
        name: 'JQL 監聽',
        jql: jql,
        intervalMinutes: interval,
        enabled: map['enabled'] == true,
      ),
    ];
  }

  static Map<String, WatchSnapshot> _decodeSnapshots(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) return {};
      final snapshots = <String, WatchSnapshot>{};
      for (final item in decoded) {
        if (item is! Map) continue;
        final snapshot = WatchSnapshot.fromMap(Map<String, dynamic>.from(item));
        if (snapshot.watchId.isNotEmpty) {
          snapshots[snapshot.watchId] = snapshot;
        }
      }
      return snapshots;
    } on FormatException {
      return {};
    }
  }

  static Map<String, WatchSnapshot> _legacySnapshots(
    Map<Object?, Object?> map,
    List<JqlWatch> watches,
  ) {
    if (watches.isEmpty) return {};
    final snapshotJson = map['snapshotJson'] as String?;
    final snapshot = <JiraIssue>[];
    if (snapshotJson != null && snapshotJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(snapshotJson);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              snapshot.add(
                JiraIssue.fromStoredJson(Map<String, dynamic>.from(item)),
              );
            }
          }
        }
      } on FormatException {
        return {};
      }
    }

    final checkedAtMilliseconds = (map['lastCheckedAt'] as num?)?.toInt();
    return {
      watches.first.id: WatchSnapshot(
        watchId: watches.first.id,
        snapshot: snapshot,
        hasSnapshot: map['hasSnapshot'] == true,
        lastCheckedAt:
            checkedAtMilliseconds == null || checkedAtMilliseconds <= 0
            ? null
            : DateTime.fromMillisecondsSinceEpoch(checkedAtMilliseconds),
      ),
    };
  }
}

class NativeBridge {
  static const MethodChannel _channel = MethodChannel(
    'jira_query_watcher/native',
  );

  Future<StoredState> loadState() async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'loadSettings',
    );
    return StoredState.fromMap(result ?? <Object?, Object?>{});
  }

  Future<void> saveSettings(
    WatchConfig config, [
    Iterable<WatchSnapshot> snapshots = const [],
  ]) {
    return _channel.invokeMethod<void>('saveSettings', {
      'baseUrl': config.baseUrl.trim(),
      'username': config.username.trim(),
      'token': config.token,
      'authMode': config.authMode.storageValue,
      'launchAtLogin': config.launchAtLogin,
      'watchesJson': jsonEncode(
        config.watches.map((watch) => watch.toMap()).toList(),
      ),
      'watchStatesJson': jsonEncode(
        snapshots.map((snapshot) => snapshot.toMap()).toList(),
      ),
    });
  }

  Future<void> saveSnapshot(List<JiraIssue> issues, DateTime checkedAt) {
    return _channel.invokeMethod<void>('saveSnapshot', {
      'snapshotJson': jsonEncode(
        issues.map((issue) => issue.toStoredJson()).toList(),
      ),
      'lastCheckedAt': checkedAt.millisecondsSinceEpoch,
    });
  }

  Future<void> clearSnapshot() {
    return _channel.invokeMethod<void>('clearSnapshot');
  }

  Future<void> requestNotificationPermission() {
    return _channel.invokeMethod<void>('requestNotificationPermission');
  }

  Future<void> showNotification({required String title, required String body}) {
    return _channel.invokeMethod<void>('showNotification', {
      'title': title,
      'body': body,
    });
  }

  Future<void> setLaunchAtLogin(bool enabled) {
    return _channel.invokeMethod<void>('setLaunchAtLogin', {
      'enabled': enabled,
    });
  }
}
