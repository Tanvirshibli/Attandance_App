import 'package:http/http.dart' as http;

/// POST multipart/form-data fields (Postman form-data style).
Future<http.Response> postFormData({
  required Uri uri,
  required Map<String, String> fields,
  Map<String, String>? headers,
  Duration timeout = const Duration(seconds: 45),
}) async {
  final request = http.MultipartRequest('POST', uri);
  request.headers.addAll({
    'Accept': 'application/json',
    'User-Agent': 'PPHLAttendance/2.2 (Android; Flutter)',
    ...?headers,
  });
  for (final entry in fields.entries) {
    request.fields[entry.key] = entry.value;
  }
  final streamed = await request.send().timeout(timeout);
  return http.Response.fromStream(streamed);
}
