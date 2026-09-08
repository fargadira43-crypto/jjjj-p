import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Small client for the Netlify Sites and Deploys APIs.
///
/// Do not put a real token in this source file. For local development, pass
/// it through --dart-define=NETLIFY_AUTH_TOKEN=... . A production mobile app
/// should call a private backend instead, because a token shipped in a mobile
/// binary can be extracted.
class NetlifyService {
  NetlifyService({
    required this.token,
    http.Client? client,
    this.baseUrl = 'https://api.netlify.com/api/v1',
  }) : _client = client ?? http.Client();

  final String token;
  final String baseUrl;
  final http.Client _client;

  Map<String, String> get _jsonHeaders => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  Map<String, String> get _zipHeaders => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/zip',
        'Accept': 'application/json',
      };

  /// Creates a new Netlify site and deploys the supplied ZIP bytes to it.
  ///
  /// The returned value is the public HTTPS URL. A later version can persist
  /// the returned site ID and deploy to that same site on subsequent clicks.
  Future<String> deployZip({
    required List<int> zipBytes,
    required String siteName,
  }) async {
    final trimmedToken = token.trim();
    if (trimmedToken.isEmpty) {
      throw const NetlifyException(
        'Netlify is not configured. Provide NETLIFY_AUTH_TOKEN securely.',
      );
    }
    if (zipBytes.isEmpty) {
      throw const NetlifyException('The project ZIP is empty.');
    }

    final siteResponse = await _client.post(
      Uri.parse('$baseUrl/sites'),
      headers: _jsonHeaders,
      body: jsonEncode({'name': _safeSiteName(siteName)}),
    );
    _throwForFailure(siteResponse, 'create the Netlify site');

    final site = _decodeObject(siteResponse.body);
    final siteId = (site['id'] ?? site['site_id'])?.toString();
    if (siteId == null || siteId.isEmpty) {
      throw const NetlifyException(
        'Netlify created the site but did not return a site ID.',
      );
    }

    final deployResponse = await _client.post(
      Uri.parse('$baseUrl/sites/$siteId/deploys'),
      headers: _zipHeaders,
      body: Uint8List.fromList(zipBytes),
    );
    _throwForFailure(deployResponse, 'deploy the project');

    final deploy = _decodeObject(deployResponse.body);
    final url = _firstNonEmpty([
      deploy['ssl_url'],
      deploy['url'],
      deploy['deploy_ssl_url'],
      site['ssl_url'],
      site['url'],
    ]);
    if (url == null) {
      throw const NetlifyException(
        'Netlify completed the request but returned no public URL.',
      );
    }
    return url;
  }

  String _safeSiteName(String value) {
    final normalized = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final suffix = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final prefix = normalized.isEmpty ? 'sumer-site' : normalized;
    return '${prefix.substring(0, prefix.length > 45 ? 45 : prefix.length)}-$suffix';
  }

  Map<String, dynamic> _decodeObject(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // The caller receives a useful API error below when the response is not
      // valid JSON.
    }
    throw const NetlifyException('Netlify returned an invalid response.');
  }

  String? _firstNonEmpty(Iterable<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  void _throwForFailure(http.Response response, String action) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;

    var detail = response.body.trim();
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        detail = (decoded['message'] ??
                decoded['error_description'] ??
                decoded['error'] ??
                detail)
            .toString();
      }
    } catch (_) {
      // Keep the plain response body when it is not JSON.
    }
    if (detail.length > 240) detail = detail.substring(0, 240);
    throw NetlifyException(
      'Unable to $action (${response.statusCode}). $detail',
    );
  }

  void close() => _client.close();
}

class NetlifyException implements Exception {
  const NetlifyException(this.message);

  final String message;

  @override
  String toString() => message;
}