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
  final uri = Uri.parse(
    '${NetlifyConfig.baseUrl}/.netlify/functions/$functionName',
  );
  final res = await client
      .post(
        uri,
        // The functions' checkOrigin() (WEB_BASE netlify/functions/lib/http-utils.js)
        // rejects any request without an Origin/Referer matching the deployed
        // site — a browser sends Origin automatically, but package:http never
        // does, so every native call was silently getting a bare 403 until
        // this was set explicitly.
        headers: {
          'Content-Type': 'application/json',
          'Origin': NetlifyConfig.baseUrl,
        },
        body: jsonEncode(body),
      )
      // Netlify functions themselves cap out at ~10-12s server-side; give
      // this a comfortable margin above that instead of hanging forever
      // on a stalled connection.
      .timeout(const Duration(seconds: 20));
  if (res.statusCode != 200) {
    throw Exception('$errorLabel failed (${res.statusCode}): ${res.body}');
  }
  return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
}
