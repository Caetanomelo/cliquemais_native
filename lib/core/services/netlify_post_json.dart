import 'dart:convert';
import 'package:http/http.dart' as http;

import '../netlify_config.dart';

/// Shared POST+decode+error helper for the Netlify-function-backed services
/// ([AiTutorService], [PronunciationAssessmentService], [CloudTtsService]):
/// POSTs JSON to `<NetlifyConfig.baseUrl>/.netlify/functions/<functionName>`
/// and decodes the JSON response body, throwing on any non-200 status.
Future<Map<String, dynamic>> postJson(
  http.Client client,
  String functionName,
  Map<String, dynamic> body, {
  required String errorLabel,
}) async {
  final uri = Uri.parse('${NetlifyConfig.baseUrl}/.netlify/functions/$functionName');
  final res = await client.post(
    uri,
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode(body),
  );
  if (res.statusCode != 200) {
    throw Exception('$errorLabel failed (${res.statusCode}): ${res.body}');
  }
  return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
}
