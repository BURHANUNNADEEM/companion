import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.status, this.detail);
  final int status;
  final String detail;
  bool get isOffline => status == 0;
  @override
  String toString() => 'ApiException($status, $detail)';
}

typedef TokenProvider = Future<String?> Function();

/// Thin JSON client that adds the Firebase ID token (or dev token) as a Bearer header.
class ApiClient {
  ApiClient(this.baseUrl, this.tokenProvider, {http.Client? client}) : _http = client ?? http.Client();

  final String baseUrl;
  final TokenProvider tokenProvider;
  final http.Client _http;
  static const _timeout = Duration(seconds: 12);

  Future<dynamic> get(String path, {Map<String, String>? query}) => _send('GET', path, query: query);
  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body: body);
  Future<dynamic> put(String path, [Object? body]) => _send('PUT', path, body: body);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<dynamic> _send(String method, String path, {Object? body, Map<String, String>? query}) async {
    final uri = Uri.parse('$baseUrl/api$path').replace(queryParameters: query);
    final token = await tokenProvider();
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    http.Response r;
    try {
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      r = await http.Response.fromStream(await _http.send(req).timeout(_timeout));
    } on TimeoutException {
      throw ApiException(0, 'timeout');
    } catch (e) {
      throw ApiException(0, 'offline');
    }
    final text = utf8.decode(r.bodyBytes);
    final data = text.isEmpty ? null : jsonDecode(text);
    if (r.statusCode >= 400) {
      final detail = data is Map && data['detail'] != null ? data['detail'].toString() : 'error';
      throw ApiException(r.statusCode, detail);
    }
    return data;
  }

  // ---- typed helpers ----
  Future<Map<String, dynamic>> me() async => Map<String, dynamic>.from(await get('/me'));
  Future<Map<String, dynamic>> config() async => Map<String, dynamic>.from(await get('/config'));
  Future<Map<String, dynamic>> suggestions({required int hour, String? lastTask}) async =>
      Map<String, dynamic>.from(await get('/suggestions', query: {
        'hour': '$hour',
        if (lastTask != null) 'last_task': lastTask,
      }));
  Future<Map<String, dynamic>> plan(
          {String? utterance, String? task, String? workflowId, Map<String, dynamic>? slots}) async =>
      Map<String, dynamic>.from(await post('/navigation/plan', {
        if (utterance != null) 'utterance': utterance,
        if (task != null) 'task': task,
        if (workflowId != null) 'workflow_id': workflowId,
        'slots': slots ?? {},
      }));
  Future<Map<String, dynamic>> voiceIntent(String transcript, String locale) async =>
      Map<String, dynamic>.from(await post('/voice/intent', {'transcript': transcript, 'locale': locale}));
  Future<Map<String, dynamic>> scamCheck(String text, String source) async =>
      Map<String, dynamic>.from(await post('/scam/check', {'text': text, 'source': source}));
}
