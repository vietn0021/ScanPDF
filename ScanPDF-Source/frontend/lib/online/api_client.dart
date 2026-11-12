import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class ApiFailure implements Exception {
  const ApiFailure(this.status, this.message);
  final int status;
  final String message;
}

class ScanApi {
  ScanApi(this.base, {http.Client? client}) : client = client ?? http.Client();
  final Uri base;
  final http.Client client;
  static const maxPdf = 20 * 1024 * 1024;

  static ScanApi? configured() {
    const value = String.fromEnvironment('SCANPDF_API_BASE_URL');
    if (value.isEmpty ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.scheme != 'https' &&
            !(kDebugMode &&
                uri.scheme == 'http' &&
                const [
                  '10.0.2.2',
                  '127.0.0.1',
                  'localhost',
                ].contains(uri.host)))) {
      throw const ApiFailure(
        0,
        'SCANPDF_API_BASE_URL không hợp lệ. Bản phát hành cần HTTPS.',
      );
    }
    return ScanApi(uri);
  }

  Uri uri(String path, [Map<String, String>? query]) => base.replace(
    path: '${base.path.replaceFirst(RegExp(r'/+$'), '')}/$path',
    queryParameters: query,
  );

  Future<http.Response> _send(
    http.BaseRequest request, {
    int limit = 128 * 1024,
  }) async {
    try {
      return await (() async {
        final response = await client.send(request);
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > limit) {
            throw const ApiFailure(0, 'Phản hồi vượt giới hạn.');
          }
          bytes.add(chunk);
        }
        return http.Response.bytes(
          bytes.takeBytes(),
          response.statusCode,
          headers: response.headers,
        );
      })().timeout(const Duration(seconds: 45));
    } on TimeoutException {
      throw const ApiFailure(0, 'Kết nối quá lâu. Vui lòng thử lại.');
    } on http.ClientException {
      throw const ApiFailure(0, 'Không thể kết nối máy chủ.');
    }
  }

  Map<String, dynamic> _json(http.Response response) {
    if (response.statusCode == 204) return {};
    try {
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (response.statusCode >= 200 && response.statusCode < 300) return data;
      final error = data['error'] as Map<String, dynamic>?;
      throw ApiFailure(
        response.statusCode,
        error?['message'] as String? ?? 'Không thể xử lý yêu cầu.',
      );
    } on FormatException {
      throw ApiFailure(response.statusCode, 'Phản hồi máy chủ không hợp lệ.');
    } on TypeError {
      throw ApiFailure(response.statusCode, 'Phản hồi máy chủ không hợp lệ.');
    }
  }

  Future<Map<String, dynamic>> json(
    String method,
    String path, {
    String? token,
    Map<String, Object>? body,
    Map<String, String>? query,
  }) async {
    final request = http.Request(method, uri(path, query));
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    return _json(await _send(request));
  }

  Future<Map<String, dynamic>> upload(
    String token,
    String uploadId,
    String filename,
    Uint8List bytes,
  ) async {
    if (bytes.length > maxPdf) {
      throw const ApiFailure(413, 'PDF tối đa 20 MiB.');
    }
    final request = http.MultipartRequest('POST', uri('documents'))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Idempotency-Key'] = uploadId
      ..fields['filename'] = filename
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: 'scan.pdf',
          contentType: MediaType('application', 'pdf'),
        ),
      );
    return _json(await _send(request));
  }

  Future<Uint8List> download(String token, String id) async {
    final request = http.Request('GET', uri('documents/$id/content'))
      ..headers['Authorization'] = 'Bearer $token';
    final result = await _send(request, limit: maxPdf);
    if (result.statusCode != 200) _json(result);
    if (result.statusCode != 200 ||
        !(result.headers['content-type'] ?? '').startsWith('application/pdf')) {
      throw const ApiFailure(0, 'Máy chủ không trả về tệp PDF.');
    }
    return result.bodyBytes;
  }
}
