import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models.dart';
import 'jira_client.dart';
import 'native_bridge.dart';

class WatchRuntime {
  WatchRuntime({
    required this.config,
    List<JiraIssue> currentItems = const [],
    this.lastDiff = const QueryDiff(),
    this.lastCheckedAt,
    this.hasBaseline = false,
  }) : currentItems = List.unmodifiable(currentItems);

  JqlWatch config;
  List<JiraIssue> currentItems;
  QueryDiff lastDiff;
  DateTime? lastCheckedAt;
  bool hasBaseline;
  bool isPolling = false;
  bool isRunning = false;
  String? error;
  String? message;
}

class WatchController extends ChangeNotifier {
  WatchController({NativeBridge? nativeBridge, JiraClient? jiraClient})
    : _nativeBridge = nativeBridge ?? NativeBridge(),
      _jiraClient = jiraClient ?? JiraClient();

  final NativeBridge _nativeBridge;
  final JiraClient _jiraClient;
  final Map<String, WatchRuntime> _watchStates = {};
  final Map<String, Timer> _timers = {};

  WatchConfig _config = WatchConfig();
  bool _isInitialized = false;
  bool _notificationPermissionRequested = false;
  String? _error;
  String? _message;

  WatchConfig get config => _config;
  List<WatchRuntime> get watches => List.unmodifiable(_watchStates.values);
  WatchRuntime? watchById(String id) => _watchStates[id];
  bool get isPolling => _watchStates.values.any((watch) => watch.isPolling);
  bool get isRunning => _watchStates.values.any((watch) => watch.isRunning);
  bool get isInitialized => _isInitialized;
  String? get error {
    if (_error != null) return _error;
    for (final watch in _watchStates.values) {
      if (watch.error != null) {
        return '${watch.config.displayName}：${watch.error}';
      }
    }
    return null;
  }

  String? get message => _message;
  bool get isReady => _config.isConnectionValid;

  List<JiraIssue> get currentItems => _watchStates.length == 1
      ? _watchStates.values.single.currentItems
      : const [];
  QueryDiff get lastDiff => _watchStates.length == 1
      ? _watchStates.values.single.lastDiff
      : const QueryDiff();
  DateTime? get lastCheckedAt => _watchStates.length == 1
      ? _watchStates.values.single.lastCheckedAt
      : null;
  bool get hasBaseline =>
      _watchStates.length == 1 && _watchStates.values.single.hasBaseline;

  String get statusLabel {
    if (isPolling) return '正在檢查';
    if (error != null) return '需要注意';
    if (isRunning) return '監聽中';
    if (!_config.isConnectionValid) return '尚未設定完成';
    if (_watchStates.isEmpty) return '尚未新增監聽';
    return '已暫停';
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final state = await _nativeBridge.loadState();
      _config = _normalizeConfig(state.config);
      for (final watch in _config.watches) {
        final snapshot = state.snapshots[watch.id];
        _watchStates[watch.id] = WatchRuntime(
          config: watch,
          currentItems: snapshot?.snapshot ?? const [],
          lastCheckedAt: snapshot?.lastCheckedAt,
          hasBaseline: snapshot?.hasSnapshot ?? false,
        );
      }
      _isInitialized = true;
      notifyListeners();

      await _syncTimers();
    } catch (error) {
      _isInitialized = true;
      _error = '無法讀取本機設定：${_friendlyError(error)}';
      notifyListeners();
    }
  }

  Future<void> save(WatchConfig config) async {
    _applyConfig(_normalizeConfig(config));
    _error = null;
    await _persist();
    await _syncTimers();
    _message = '設定已儲存';
    notifyListeners();
  }

  Future<void> addWatch(JqlWatch watch) async {
    final requestedId = watch.id.trim();
    final id = requestedId.isEmpty || _watchStates.containsKey(requestedId)
        ? _newWatchId()
        : requestedId;
    final normalized = watch.copyWith(id: id);
    _watchStates[normalized.id] = WatchRuntime(config: normalized);
    _config = _config.copyWith(
      watches: [..._watchStates.values.map((state) => state.config)],
    );
    _error = null;
    await _persist();
    if (normalized.enabled) {
      await _startWatch(normalized.id);
    }
    _message = '已新增「${normalized.displayName}」';
    notifyListeners();
  }

  Future<void> updateWatch(JqlWatch watch) async {
    final state = _watchStates[watch.id];
    if (state == null) return;

    final previous = state.config;
    final queryChanged = previous.queryFingerprint != watch.queryFingerprint;
    final needsRestart =
        queryChanged ||
        previous.intervalMinutes != watch.intervalMinutes ||
        previous.enabled != watch.enabled;
    if (needsRestart) _stopTimer(watch.id);
    if (queryChanged) _resetState(state);

    state.config = watch;
    _config = _config.copyWith(
      watches: [..._watchStates.values.map((item) => item.config)],
    );
    _error = null;
    await _persist();

    if (watch.enabled) {
      if (needsRestart || !_timers.containsKey(watch.id)) {
        await _startWatch(watch.id);
      }
    } else {
      _stopTimer(watch.id);
    }
    _message = '已更新「${watch.displayName}」';
    notifyListeners();
  }

  Future<void> removeWatch(String id) async {
    final state = _watchStates[id];
    if (state == null) return;

    _stopTimer(id);
    _watchStates.remove(id);
    _config = _config.copyWith(
      watches: [..._watchStates.values.map((item) => item.config)],
    );
    await _persist();
    _message = '已刪除「${state.config.displayName}」';
    notifyListeners();
  }

  Future<void> setWatchEnabled(String id, bool enabled) async {
    final state = _watchStates[id];
    if (state == null || state.config.enabled == enabled) return;
    await updateWatch(state.config.copyWith(enabled: enabled));
  }

  Future<void> start() async {
    if (!_config.isConnectionValid) {
      _error = '請先到設定頁填寫 Jira URL 與認證資訊。';
      notifyListeners();
      return;
    }
    if (_watchStates.isEmpty) {
      _error = '請先新增至少一個 JQL 監聽。';
      notifyListeners();
      return;
    }

    for (final state in _watchStates.values) {
      state.config = state.config.copyWith(enabled: true);
    }
    _config = _config.copyWith(
      watches: [..._watchStates.values.map((state) => state.config)],
    );
    await _persist();
    await _syncTimers();
    notifyListeners();
  }

  Future<void> stop() async {
    for (final state in _watchStates.values) {
      state.config = state.config.copyWith(enabled: false);
      _stopTimer(state.config.id);
    }
    _config = _config.copyWith(
      watches: [..._watchStates.values.map((state) => state.config)],
    );
    await _persist();
    _message = '監聽已暫停';
    notifyListeners();
  }

  Future<void> pollNow([String? watchId]) async {
    if (watchId != null) {
      await _pollWatch(watchId);
      return;
    }

    for (final id in _watchStates.keys.toList()) {
      await _pollWatch(id);
    }
  }

  Future<void> setLaunchAtLogin(bool enabled) async {
    await _nativeBridge.setLaunchAtLogin(enabled);
    _config = _config.copyWith(launchAtLogin: enabled);
    await _persist();
    notifyListeners();
  }

  Future<void> _syncTimers() async {
    for (final state in _watchStates.values.toList()) {
      final shouldRun =
          state.config.enabled &&
          _config.isConnectionValid &&
          state.config.isValid;
      if (shouldRun) {
        if (!_timers.containsKey(state.config.id)) {
          await _startWatch(state.config.id);
        }
      } else {
        _stopTimer(state.config.id);
      }
    }
  }

  Future<void> _startWatch(String id) async {
    final state = _watchStates[id];
    if (state == null) return;
    if (!_config.isConnectionValid) {
      state.isRunning = false;
      state.error = '請先到設定頁填寫 Jira URL 與認證資訊。';
      notifyListeners();
      return;
    }
    if (!state.config.isValid) {
      state.isRunning = false;
      state.error = '請填寫 JQL。';
      notifyListeners();
      return;
    }

    _stopTimer(id);
    state.error = null;
    state.message = null;
    state.isRunning = true;
    notifyListeners();

    if (!_notificationPermissionRequested) {
      await _nativeBridge.requestNotificationPermission();
      _notificationPermissionRequested = true;
    }
    await _pollWatch(id);

    final current = _watchStates[id];
    if (identical(current, state) && state.isRunning && state.config.enabled) {
      _timers[id] = Timer.periodic(
        Duration(minutes: state.config.intervalMinutes),
        (_) => unawaited(_pollWatch(id)),
      );
    }
  }

  Future<void> _pollWatch(String id) async {
    final state = _watchStates[id];
    if (state == null || state.isPolling) return;
    if (!_config.isConnectionValid || !state.config.isValid) return;

    final watch = state.config;
    final connectionFingerprint = _config.connectionFingerprint;
    state.isPolling = true;
    state.error = null;
    notifyListeners();

    try {
      final result = await _jiraClient.search(_config, watch);
      if (!_isCurrent(state, watch, connectionFingerprint)) return;

      final isInitialBaseline = !state.hasBaseline;
      final diff = isInitialBaseline
          ? const QueryDiff()
          : compareIssues(state.currentItems, result);
      final checkedAt = DateTime.now();

      state.currentItems = List.unmodifiable(result);
      state.lastDiff = diff;
      state.lastCheckedAt = checkedAt;
      state.hasBaseline = true;
      if (isInitialBaseline) {
        state.message = '已建立初始基準，共 ${result.length} 個項目。';
      } else if (diff.hasChanges) {
        state.message = _changeSummary(diff);
      } else {
        state.message = '查詢完成，沒有項目變化。';
      }
      await _persist();

      if (diff.hasChanges) {
        await _nativeBridge.showNotification(
          title: '${watch.displayName} 有變化',
          body: _notificationBody(diff),
        );
      }
    } catch (error) {
      if (_isCurrent(state, watch, connectionFingerprint)) {
        state.error = _friendlyError(error);
        state.message = null;
      }
    } finally {
      if (identical(_watchStates[id], state)) {
        state.isPolling = false;
        notifyListeners();
      }
    }
  }

  bool _isCurrent(
    WatchRuntime state,
    JqlWatch watch,
    String connectionFingerprint,
  ) {
    return identical(_watchStates[watch.id], state) &&
        state.config.queryFingerprint == watch.queryFingerprint &&
        _config.connectionFingerprint == connectionFingerprint;
  }

  void _applyConfig(WatchConfig config) {
    final connectionChanged =
        _config.connectionFingerprint != config.connectionFingerprint;
    final incomingIds = config.watches.map((watch) => watch.id).toSet();

    for (final id in _watchStates.keys.toList()) {
      if (!incomingIds.contains(id)) {
        _stopTimer(id);
        _watchStates.remove(id);
      }
    }

    for (final watch in config.watches) {
      final existing = _watchStates[watch.id];
      if (existing == null) {
        _watchStates[watch.id] = WatchRuntime(config: watch);
        continue;
      }

      final queryChanged =
          existing.config.queryFingerprint != watch.queryFingerprint;
      final needsRestart =
          connectionChanged ||
          queryChanged ||
          existing.config.intervalMinutes != watch.intervalMinutes ||
          existing.config.enabled != watch.enabled;
      if (needsRestart) _stopTimer(watch.id);
      if (connectionChanged || queryChanged) _resetState(existing);
      existing.config = watch;
    }

    final reordered = <String, WatchRuntime>{};
    for (final watch in config.watches) {
      final state = _watchStates[watch.id];
      if (state != null) reordered[watch.id] = state;
    }
    _watchStates
      ..clear()
      ..addAll(reordered);
    _config = config;
  }

  WatchConfig _normalizeConfig(WatchConfig config) {
    final usedIds = <String>{};
    final watches = <JqlWatch>[];
    for (final watch in config.watches) {
      var id = watch.id.trim();
      if (id.isEmpty || !usedIds.add(id)) {
        id = _newWatchId(usedIds);
        usedIds.add(id);
      }
      watches.add(id == watch.id ? watch : watch.copyWith(id: id));
    }
    return config.copyWith(watches: watches);
  }

  String _newWatchId([Set<String>? reservedIds]) {
    final reserved = reservedIds ?? const <String>{};
    var id = DateTime.now().microsecondsSinceEpoch.toString();
    while (_watchStates.containsKey(id) || reserved.contains(id)) {
      id = '${id}_1';
    }
    return id;
  }

  void _resetState(WatchRuntime state) {
    state.currentItems = const [];
    state.lastDiff = const QueryDiff();
    state.lastCheckedAt = null;
    state.hasBaseline = false;
    state.error = null;
    state.message = null;
  }

  void _stopTimer(String id) {
    _timers.remove(id)?.cancel();
    final state = _watchStates[id];
    if (state != null) state.isRunning = false;
  }

  Future<void> _persist() {
    return _nativeBridge.saveSettings(
      _config,
      _watchStates.values.map(
        (state) => WatchSnapshot(
          watchId: state.config.id,
          snapshot: state.currentItems,
          hasSnapshot: state.hasBaseline,
          lastCheckedAt: state.lastCheckedAt,
        ),
      ),
    );
  }

  String _changeSummary(QueryDiff diff) {
    final parts = <String>[];
    if (diff.added.isNotEmpty) parts.add('新增 ${diff.added.length} 項');
    if (diff.removed.isNotEmpty) parts.add('移除 ${diff.removed.length} 項');
    if (diff.statusChanges.isNotEmpty) {
      parts.add('狀態變更 ${diff.statusChanges.length} 項');
    }
    return parts.join('，');
  }

  String _notificationBody(QueryDiff diff) {
    final added = diff.added.take(3).map((issue) => issue.key).join(', ');
    final removed = diff.removed.take(3).map((issue) => issue.key).join(', ');
    final statusChanges = diff.statusChanges
        .take(3)
        .map((change) {
          final previous = change.previous.status ?? '未知';
          final current = change.current.status ?? '未知';
          return '${change.current.key}：$previous → $current';
        })
        .join(', ');
    final parts = <String>[];
    if (diff.added.isNotEmpty) {
      parts.add('新增 ${diff.added.length} 項${added.isEmpty ? '' : '：$added'}');
    }
    if (diff.removed.isNotEmpty) {
      parts.add(
        '移除 ${diff.removed.length} 項${removed.isEmpty ? '' : '：$removed'}',
      );
    }
    if (diff.statusChanges.isNotEmpty) {
      parts.add(
        '狀態變更 ${diff.statusChanges.length} 項'
        '${statusChanges.isEmpty ? '' : '：$statusChanges'}',
      );
    }
    return parts.join('\n');
  }

  String _friendlyError(Object error) {
    if (error is JiraApiException) return error.message;
    return error.toString().replaceFirst('Exception: ', '');
  }

  @override
  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    super.dispose();
  }
}
