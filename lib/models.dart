enum JiraAuthMode { cloud, server }

extension JiraAuthModeX on JiraAuthMode {
  String get storageValue => switch (this) {
    JiraAuthMode.cloud => 'cloud',
    JiraAuthMode.server => 'server',
  };

  String get label => switch (this) {
    JiraAuthMode.cloud => 'Jira Cloud (Email + API token)',
    JiraAuthMode.server => 'Jira Server / Data Center (Bearer token)',
  };

  static JiraAuthMode fromStorage(Object? value) {
    return value == JiraAuthMode.server.storageValue
        ? JiraAuthMode.server
        : JiraAuthMode.cloud;
  }
}

class JqlWatch {
  const JqlWatch({
    this.id = '',
    this.name = '',
    this.jql = '',
    this.intervalMinutes = 5,
    this.enabled = true,
  });

  final String id;
  final String name;
  final String jql;
  final int intervalMinutes;
  final bool enabled;

  String get displayName {
    final value = name.trim();
    return value.isEmpty ? 'JQL 監聽' : value;
  }

  bool get isValid {
    return jql.trim().isNotEmpty &&
        intervalMinutes >= 1 &&
        intervalMinutes <= 30;
  }

  String get queryFingerprint => jql.trim();

  factory JqlWatch.fromMap(Map<String, dynamic> map) {
    final interval = ((map['intervalMinutes'] as num?)?.toInt() ?? 5)
        .clamp(1, 30)
        .toInt();
    return JqlWatch(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      jql: map['jql'] as String? ?? '',
      intervalMinutes: interval,
      enabled: map['enabled'] != false,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name.trim(),
      'jql': jql.trim(),
      'intervalMinutes': intervalMinutes,
      'enabled': enabled,
    };
  }

  JqlWatch copyWith({
    String? id,
    String? name,
    String? jql,
    int? intervalMinutes,
    bool? enabled,
  }) {
    return JqlWatch(
      id: id ?? this.id,
      name: name ?? this.name,
      jql: jql ?? this.jql,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      enabled: enabled ?? this.enabled,
    );
  }
}

class WatchSnapshot {
  const WatchSnapshot({
    required this.watchId,
    this.snapshot = const [],
    this.hasSnapshot = false,
    this.lastCheckedAt,
  });

  final String watchId;
  final List<JiraIssue> snapshot;
  final bool hasSnapshot;
  final DateTime? lastCheckedAt;

  factory WatchSnapshot.fromMap(Map<String, dynamic> map) {
    final snapshot = <JiraIssue>[];
    final rawSnapshot = map['snapshot'];
    if (rawSnapshot is List) {
      for (final item in rawSnapshot) {
        if (item is Map) {
          snapshot.add(
            JiraIssue.fromStoredJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    final checkedAtMilliseconds = (map['lastCheckedAt'] as num?)?.toInt();
    return WatchSnapshot(
      watchId: map['watchId'] as String? ?? '',
      snapshot: snapshot,
      hasSnapshot: map['hasSnapshot'] == true,
      lastCheckedAt: checkedAtMilliseconds == null || checkedAtMilliseconds <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(checkedAtMilliseconds),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'watchId': watchId,
      'snapshot': snapshot.map((issue) => issue.toStoredJson()).toList(),
      'hasSnapshot': hasSnapshot,
      'lastCheckedAt': lastCheckedAt?.millisecondsSinceEpoch ?? 0,
    };
  }
}

class WatchConfig {
  WatchConfig({
    this.baseUrl = '',
    this.username = '',
    this.token = '',
    this.authMode = JiraAuthMode.cloud,
    this.launchAtLogin = false,
    List<JqlWatch>? watches,
    String? jql,
    int? intervalMinutes,
    bool? enabled,
  }) : watches =
           watches ??
           (jql == null
               ? const []
               : [
                   JqlWatch(
                     id: 'legacy',
                     name: 'JQL 監聽',
                     jql: jql,
                     intervalMinutes: intervalMinutes ?? 5,
                     enabled: enabled ?? false,
                   ),
                 ]);

  final String baseUrl;
  final String username;
  final String token;
  final JiraAuthMode authMode;
  final bool launchAtLogin;
  final List<JqlWatch> watches;

  String get jql => watches.length == 1 ? watches.single.jql : '';
  int get intervalMinutes =>
      watches.length == 1 ? watches.single.intervalMinutes : 5;
  bool get enabled => watches.any((watch) => watch.enabled);

  bool get hasToken => token.trim().isNotEmpty;

  bool get isConnectionValid {
    return baseUrl.trim().isNotEmpty &&
        hasToken &&
        (authMode == JiraAuthMode.server || username.trim().isNotEmpty);
  }

  bool get isValid =>
      isConnectionValid && watches.any((watch) => watch.isValid);

  String get connectionFingerprint {
    return [
      baseUrl.trim().replaceFirst(RegExp(r'/+$'), ''),
      authMode.storageValue,
      username.trim(),
    ].join('|');
  }

  String get queryFingerprint {
    return [
      connectionFingerprint,
      ...watches.map((watch) => '${watch.id}:${watch.queryFingerprint}'),
    ].join('|');
  }

  WatchConfig copyWith({
    String? baseUrl,
    String? username,
    String? token,
    JiraAuthMode? authMode,
    bool? launchAtLogin,
    List<JqlWatch>? watches,
    String? jql,
    int? intervalMinutes,
    bool? enabled,
  }) {
    var nextWatches = watches ?? this.watches;
    if (watches == null &&
        (jql != null || intervalMinutes != null || enabled != null)) {
      final current = nextWatches.isEmpty
          ? const JqlWatch(id: 'legacy', name: 'JQL 監聽')
          : nextWatches.first;
      final updated = current.copyWith(
        jql: jql,
        intervalMinutes: intervalMinutes,
        enabled: enabled,
      );
      nextWatches = nextWatches.isEmpty
          ? [updated]
          : [updated, ...nextWatches.skip(1)];
    }

    return WatchConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      username: username ?? this.username,
      token: token ?? this.token,
      authMode: authMode ?? this.authMode,
      launchAtLogin: launchAtLogin ?? this.launchAtLogin,
      watches: nextWatches,
    );
  }
}

class JiraIssue {
  const JiraIssue({required this.key, required this.summary, this.status});

  final String key;
  final String summary;
  final String? status;

  factory JiraIssue.fromJson(Map<String, dynamic> json) {
    final fields = json['fields'];
    final rawStatus = fields is Map ? fields['status'] : null;
    return JiraIssue(
      key: json['key'] as String? ?? '',
      summary: fields is Map ? fields['summary'] as String? ?? '' : '',
      status: rawStatus is Map ? rawStatus['name'] as String? : null,
    );
  }

  factory JiraIssue.fromStoredJson(Map<String, dynamic> json) {
    return JiraIssue(
      key: json['key'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      status: json['status'] as String?,
    );
  }

  Map<String, String> toStoredJson() {
    final stored = {'key': key, 'summary': summary};
    if (status != null) stored['status'] = status!;
    return stored;
  }
}

class IssueStatusChange {
  const IssueStatusChange({required this.previous, required this.current});

  final JiraIssue previous;
  final JiraIssue current;
}

class QueryDiff {
  const QueryDiff({
    this.added = const [],
    this.removed = const [],
    this.statusChanges = const [],
  });

  final List<JiraIssue> added;
  final List<JiraIssue> removed;
  final List<IssueStatusChange> statusChanges;

  bool get hasChanges =>
      added.isNotEmpty || removed.isNotEmpty || statusChanges.isNotEmpty;
}

QueryDiff compareIssues(List<JiraIssue> previous, List<JiraIssue> current) {
  final previousByKey = {for (final issue in previous) issue.key: issue};
  final currentByKey = {for (final issue in current) issue.key: issue};

  final added =
      currentByKey.entries
          .where((entry) => !previousByKey.containsKey(entry.key))
          .map((entry) => entry.value)
          .toList()
        ..sort((a, b) => a.key.compareTo(b.key));
  final removed =
      previousByKey.entries
          .where((entry) => !currentByKey.containsKey(entry.key))
          .map((entry) => entry.value)
          .toList()
        ..sort((a, b) => a.key.compareTo(b.key));
  final statusChanges =
      currentByKey.entries
          .where((entry) {
            final previousStatus = previousByKey[entry.key]?.status;
            final currentStatus = entry.value.status;
            return previousStatus != null &&
                currentStatus != null &&
                previousStatus != currentStatus;
          })
          .map(
            (entry) => IssueStatusChange(
              previous: previousByKey[entry.key]!,
              current: entry.value,
            ),
          )
          .toList()
        ..sort((a, b) => a.current.key.compareTo(b.current.key));

  return QueryDiff(
    added: added,
    removed: removed,
    statusChanges: statusChanges,
  );
}
