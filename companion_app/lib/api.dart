import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'config.dart';

Future<Map<String, String>> _headers() async {
  // getIdToken() auto-refreshes when the token is near expiry
  final token = await FirebaseAuth.instance.currentUser?.getIdToken();
  return {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };
}

Future<http.Response> apiGet(String path) async =>
    http.get(Uri.parse('$apiBaseUrl$path'), headers: await _headers());

Future<http.Response> apiPost(String path, Map<String, dynamic> body) async =>
    http.post(Uri.parse('$apiBaseUrl$path'),
        headers: await _headers(), body: jsonEncode(body));

Future<http.Response> apiPut(String path, Map<String, dynamic> body) async =>
    http.put(Uri.parse('$apiBaseUrl$path'),
        headers: await _headers(), body: jsonEncode(body));

Future<http.Response> apiDelete(String path, Map<String, dynamic> body) async =>
    http.delete(Uri.parse('$apiBaseUrl$path'),
        headers: await _headers(), body: jsonEncode(body));
