import 'dart:convert';
import 'dart:io';

import '../models.dart';

class JiraApiException implements Exception {
  JiraApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

class JiraClient {
  Future<List<JiraIssue>> search(WatchConfig config, [JqlWatch? watch]) async {
    final baseUrl = config.baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final jql = (watch?.jql ?? config.jql).trim();
    final client = HttpClient();

    try {
      if (config.authMode == JiraAuthMode.cloud) {
        return await _searchCloud(client, baseUrl, config, jql);
      }
      return await _searchServer(client, baseUrl, config, jql);
    } finally {
      client.close(force: true);
    }
  }

  Future<List<JiraIssue>> _searchCloud(
    HttpClient client,
    String baseUrl,
    WatchConfig config,
    String jql,
  ) async {
    final issues = <JiraIssue>[];
    String? nextPageToken;
    String? previousPageToken;

    while (true) {
      final requestBody = <String, dynamic>{
        'jql': jql,
        'maxResults': 100,
        'fields': ['summary'],
      };
      if (nextPageToken != null) {
        requestBody['nextPageToken'] = nextPageToken;
      }

      final decoded = await _sendRequest(
        client,
        Uri.parse('$baseUrl/rest/api/3/search/jql'),
        config,
        body: requestBody,
      );
      final page = _parseIssues(decoded);
      issues.addAll(page);

      final returnedToken = decoded['nextPageToken'] as String?;
      if (decoded['isLast'] == true ||
          returnedToken == null ||
          returnedToken.isEmpty ||
          returnedToken == previousPageToken) {
        break;
      }
      previousPageToken = nextPageToken;
      nextPageToken = returnedToken;
    }

    return issues;
  }

  Future<List<JiraIssue>> _searchServer(
    HttpClient client,
    String baseUrl,
    WatchConfig config,
    String jql,
  ) async {
    final issues = <JiraIssue>[];
    var startAt = 0;
    const pageSize = 100;

    while (true) {
      final uri = Uri.parse('$baseUrl/rest/api/2/search').replace(
        queryParameters: {
          'jql': jql,
          'startAt': '$startAt',
          'maxResults': '$pageSize',
          'fields': 'summary',
        },
      );
      final decoded = await _sendRequest(client, uri, config);
      final page = _parseIssues(decoded);
      issues.addAll(page);

      final total = (decoded['total'] as num?)?.toInt();
      startAt += page.length;
      if (page.isEmpty || (total != null && startAt >= total)) {
        break;
      }
      if (page.length < pageSize) {
        break;
      }
    }

    return issues;
  }

  Future<Map<String, dynamic>> _sendRequest(
    HttpClient client,
    Uri uri,
    WatchConfig config, {
    Map<String, dynamic>? body,
  }) async {
    final request = body == null
        ? await client.getUrl(uri).timeout(const Duration(seconds: 30))
        : await client.postUrl(uri).timeout(const Duration(seconds: 30));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(
      HttpHeaders.authorizationHeader,
      _authorizationHeader(config),
    );
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }

    final response = await request.close().timeout(const Duration(seconds: 30));
    final responseBody = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw JiraApiException(
        response.statusCode,
        _errorMessage(response.statusCode, responseBody),
      );
    }

    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is! Map) {
        throw const FormatException();
      }
      return Map<String, dynamic>.from(decoded);
    } on FormatException {
      throw JiraApiException(0, 'Jira 回傳了無法解析的資料。');
    }
  }

  List<JiraIssue> _parseIssues(Map<String, dynamic> decoded) {
    final rawIssues = decoded['issues'] as List<dynamic>? ?? const [];
    return rawIssues
        .whereType<Map>()
        .map((issue) => JiraIssue.fromJson(Map<String, dynamic>.from(issue)))
        .where((issue) => issue.key.isNotEmpty)
        .toList();
  }

  String _authorizationHeader(WatchConfig config) {
    if (config.authMode == JiraAuthMode.cloud) {
      final credentials = base64Encode(
        utf8.encode('${config.username.trim()}:${config.token}'),
      );
      return 'Basic $credentials';
    }
    return 'Bearer ${config.token}';
  }

  String _errorMessage(int statusCode, String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final messages = decoded['errorMessages'];
        if (messages is List && messages.isNotEmpty) {
          return 'Jira HTTP $statusCode：${messages.first}';
        }
        final errors = decoded['errors'];
        if (errors is Map && errors.isNotEmpty) {
          return 'Jira HTTP $statusCode：${errors.values.first}';
        }
      }
    } on FormatException {
      // Fall through to the status-only message.
    }
    return 'Jira HTTP $statusCode：請檢查 Jira URL、認證資訊與 JQL。';
  }
}
