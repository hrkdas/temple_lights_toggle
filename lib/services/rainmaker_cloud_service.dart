import 'dart:convert';
import 'dart:io';
import 'dart:math';
import '../core/log.dart';

final _log = AppLog.tag('rainmaker_cloud');

/// Represents the result of an ESP RainMaker authentication request.
class RainmakerLoginResponse {
  const RainmakerLoginResponse({
    required this.isSuccess,
    this.accessToken,
    this.refreshToken,
    this.userId,
    this.email,
    this.errorMessage,
  });

  final bool isSuccess;
  final String? accessToken;
  final String? refreshToken;
  final String? userId;
  final String? email;
  final String? errorMessage;
}

/// Service providing direct interaction with Espressif's public RainMaker REST APIs.
/// Uses Dart standard library HttpClient without adding third-party network dependencies.
class RainmakerCloudService {
  const RainmakerCloudService({HttpClient? client}) : _client = client;

  final HttpClient? _client;

  static const String baseUrl = 'https://api.rainmaker.espressif.com/v1';
  static const String authBaseUrl = 'https://3pauth.rainmaker.espressif.com';
  static const String clientId = '1h7ujqjs8140n17v0ahb4n51m2';
  static const String redirectUri = 'rainmaker://com.espressif.novahome/success';

  /// Generates the direct Google OAuth authorize URL for Espressif RainMaker.
  static Uri getGoogleOAuthUrl() {
    return Uri.parse(
      '$authBaseUrl/oauth2/authorize?'
      'identity_provider=Google'
      '&redirect_uri=$redirectUri'
      '&response_type=CODE'
      '&client_id=$clientId'
      '&scope=aws.cognito.signin.user.admin%20com.espressif.rainmaker.oauth/node.read%20com.espressif.rainmaker.oauth/node.write%20email%20openid%20phone%20profile',
    );
  }

  /// Extracts the OAuth authorization code from either a raw code string,
  /// a callback URL (e.g. rainmaker://com.espressif.novahome/success?code=...),
  /// or a query string.
  static String extractOAuthCode(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.contains('?')) {
      try {
        final uri = Uri.parse(trimmed);
        final codeParam = uri.queryParameters['code'];
        if (codeParam != null && codeParam.isNotEmpty) {
          return codeParam.trim();
        }
      } catch (_) {}
      final match = RegExp(r'[?&]code=([^&#\s]+)').firstMatch(trimmed);
      if (match != null) {
        return Uri.decodeQueryComponent(match.group(1)!).trim();
      }
    }
    return trimmed;
  }

  HttpClient _getClient() => _client ?? HttpClient();

  /// Exchanges a Google OAuth authorization code for Espressif RainMaker access tokens.
  Future<RainmakerLoginResponse> exchangeOAuthCode(String code) async {
    final client = _getClient();
    try {
      final request = await client.postUrl(Uri.parse('$authBaseUrl/oauth2/token'));
      request.headers.set('Content-Type', 'application/x-www-form-urlencoded');

      final bodyParams = {
        'grant_type': 'authorization_code',
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'code': code.trim(),
      };
      final encoded = bodyParams.entries
          .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      final bytes = utf8.encode(encoded);
      request.contentLength = bytes.length;
      request.add(bytes);

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        final token = data['access_token'] as String?;
        final refresh = data['refresh_token'] as String?;
        final idToken = data['id_token'] as String?;

        String? email;
        String? uid;
        if (idToken != null) {
          final jwtInfo = _parseJwt(idToken);
          email = jwtInfo['email'] as String?;
          uid = jwtInfo['sub'] as String?;
        }

        if (token != null && token.isNotEmpty) {
          _log.i('RainMaker OAuth token exchange successful for ${email ?? uid}');
          return RainmakerLoginResponse(
            isSuccess: true,
            accessToken: token,
            refreshToken: refresh,
            userId: uid,
            email: email,
          );
        }
      }

      _log.w('OAuth token exchange failed with status ${response.statusCode}: $body');
      try {
        final errorMap = jsonDecode(body) as Map<String, dynamic>;
        final desc = errorMap['error_description'] as String? ?? errorMap['error'] as String?;
        if (desc != null && desc.isNotEmpty) {
          return RainmakerLoginResponse(
            isSuccess: false,
            errorMessage: 'Auth error: $desc',
          );
        }
      } catch (_) {}

      return RainmakerLoginResponse(
        isSuccess: false,
        errorMessage: 'Failed to exchange Google OAuth code (code ${response.statusCode})',
      );
    } catch (e) {
      _log.e('OAuth token exchange network error: $e');
      return RainmakerLoginResponse(
        isSuccess: false,
        errorMessage: 'Network error connecting to auth server: $e',
      );
    } finally {
      if (_client == null) {
        client.close();
      }
    }
  }

  /// Silently refreshes an expired access token using the stored refresh token.
  Future<RainmakerLoginResponse> refreshAccessToken(String refreshToken) async {
    final client = _getClient();
    try {
      final request = await client.postUrl(Uri.parse('$authBaseUrl/oauth2/token'));
      request.headers.set('Content-Type', 'application/x-www-form-urlencoded');

      final bodyParams = {
        'grant_type': 'refresh_token',
        'client_id': clientId,
        'refresh_token': refreshToken.trim(),
      };
      final encoded = bodyParams.entries
          .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      final bytes = utf8.encode(encoded);
      request.contentLength = bytes.length;
      request.add(bytes);

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        final token = data['access_token'] as String?;
        final idToken = data['id_token'] as String?;

        String? email;
        String? uid;
        if (idToken != null) {
          final jwtInfo = _parseJwt(idToken);
          email = jwtInfo['email'] as String?;
          uid = jwtInfo['sub'] as String?;
        }

        if (token != null && token.isNotEmpty) {
          _log.i('RainMaker access token refreshed successfully');
          return RainmakerLoginResponse(
            isSuccess: true,
            accessToken: token,
            refreshToken: refreshToken,
            userId: uid,
            email: email,
          );
        }
      }

      return const RainmakerLoginResponse(isSuccess: false, errorMessage: 'Token refresh failed');
    } catch (e) {
      return RainmakerLoginResponse(isSuccess: false, errorMessage: 'Network error: $e');
    } finally {
      if (_client == null) {
        client.close();
      }
    }
  }

  static Map<String, dynamic> _parseJwt(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return const {};
    try {
      final normalized = base64Url.normalize(parts[1]);
      final payloadStr = utf8.decode(base64Url.decode(normalized));
      return jsonDecode(payloadStr) as Map<String, dynamic>;
    } catch (_) {
      return const {};
    }
  }

  /// Authenticates with an Espressif ESP RainMaker account.
  Future<RainmakerLoginResponse> login({
    required String email,
    required String password,
  }) async {
    final client = _getClient();
    try {
      final request = await client.postUrl(Uri.parse('$baseUrl/login'));
      request.headers.set('Content-Type', 'application/json');
      request.add(utf8.encode(jsonEncode({
        'user_name': email.trim(),
        'password': password,
      })));

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        final token = data['accesstoken'] as String?;
        final refresh = data['refreshtoken'] as String?;
        final uid = data['user_id'] as String?;

        if (token != null && token.isNotEmpty) {
          _log.i('RainMaker login successful for $email');
          return RainmakerLoginResponse(
            isSuccess: true,
            accessToken: token,
            refreshToken: refresh,
            userId: uid,
            email: email.trim(),
          );
        }
      }

      // Handle failure payload
      try {
        final errorData = jsonDecode(body) as Map<String, dynamic>;
        final desc = errorData['description'] as String? ?? 'Invalid email or password';
        _log.w('RainMaker login failed: $desc (code ${response.statusCode})');
        return RainmakerLoginResponse(isSuccess: false, errorMessage: desc);
      } catch (_) {
        return RainmakerLoginResponse(
          isSuccess: false,
          errorMessage: 'Login failed with status ${response.statusCode}',
        );
      }
    } catch (e) {
      _log.e('RainMaker login network error: $e');
      return RainmakerLoginResponse(
        isSuccess: false,
        errorMessage: 'Network error connecting to Espressif Cloud: $e',
      );
    } finally {
      if (_client == null) {
        client.close();
      }
    }
  }

  /// Retrieves the list of device Node IDs associated with the authenticated user account.
  Future<List<String>> getUserNodes({required String accessToken}) async {
    final client = _getClient();
    try {
      final request = await client.getUrl(Uri.parse('$baseUrl/user/nodes'));
      request.headers.set('Authorization', accessToken);

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        final rawNodes = data['nodes'];
        if (rawNodes is List) {
          return rawNodes.map((e) => e.toString()).toList();
        }
      }
      _log.w('Querying user nodes returned status ${response.statusCode}');
      return const [];
    } catch (e) {
      _log.e('Failed to fetch user nodes: $e');
      return const [];
    } finally {
      if (_client == null) {
        client.close();
      }
    }
  }

  /// Generates a cryptographically secure 16-character alphanumeric secret key for node mapping.
  static String generateSecretKey() {
    const chars = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final rand = Random.secure();
    return List.generate(16, (i) => chars[rand.nextInt(chars.length)]).join();
  }

  /// Maps an ESP32 node to the user account in Espressif Cloud.
  Future<bool> mapNodeToUser({
    required String accessToken,
    required String nodeId,
    String? secretKey,
  }) async {
    final client = _getClient();
    final key = (secretKey != null && secretKey.trim().isNotEmpty)
        ? secretKey.trim()
        : generateSecretKey();
    try {
      final request = await client.putUrl(Uri.parse('$baseUrl/user/nodes/mapping'));
      request.headers.set('Authorization', accessToken);
      request.headers.set('Content-Type', 'application/json');
      request.add(utf8.encode(jsonEncode({
        'node_id': nodeId,
        'secret_key': key,
        'operation': 'add',
      })));

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _log.i('Node $nodeId successfully mapped to user account');
        return true;
      }
      _log.w('Node mapping failed with status ${response.statusCode}: $body');
      return false;
    } catch (e) {
      _log.e('Error mapping node $nodeId: $e');
      return false;
    } finally {
      if (_client == null) {
        client.close();
      }
    }
  }
}
