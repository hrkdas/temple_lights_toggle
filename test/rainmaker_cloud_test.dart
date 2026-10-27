import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:temple_lights_toggle/contract/light_contract.dart';
import 'package:temple_lights_toggle/core/kv_store.dart';
import 'package:temple_lights_toggle/domain/models.dart';
import 'package:temple_lights_toggle/domain/providers.dart';
import 'package:temple_lights_toggle/services/rainmaker_cloud_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ESP RainMaker Packet Contract Tests', () {
    test('encodeGetRmakerInfo serializes correct JSON command', () {
      final bytes = LightPacketEncoder.encodeGetRmakerInfo();
      final str = utf8.decode(bytes);
      final json = jsonDecode(str) as Map<String, dynamic>;

      expect(json['cmd'], 'get_rmaker_info');
    });

    test('encodeRmakerMapUser serializes correct user_id and secret_key', () {
      final bytes = LightPacketEncoder.encodeRmakerMapUser(
        userId: 'cognito_sub_999',
        secretKey: 'key_1234567890ab',
      );
      final str = utf8.decode(bytes);
      final json = jsonDecode(str) as Map<String, dynamic>;

      expect(json['cmd'], 'rmaker_map_user');
      expect(json['user_id'], 'cognito_sub_999');
      expect(json['secret_key'], 'key_1234567890ab');
    });
  });

  group('ESP RainMaker Cloud Service Model Tests', () {
    test('getGoogleOAuthUrl produces compliant Cognito authorize URL for Google Sign-In', () {
      final uri = RainmakerCloudService.getGoogleOAuthUrl();

      expect(uri.scheme, 'https');
      expect(uri.host, '3pauth.rainmaker.espressif.com');
      expect(uri.path, '/oauth2/authorize');
      expect(uri.queryParameters['identity_provider'], 'Google');
      expect(uri.queryParameters['client_id'], '1h7ujqjs8140n17v0ahb4n51m2');
      expect(uri.queryParameters['redirect_uri'], 'rainmaker://com.espressif.novahome/success');
      expect(uri.queryParameters['response_type'], 'CODE');
      expect(uri.queryParameters['scope'], contains('email openid'));
    });

    test('RainmakerLoginResponse correctly handles successful auth payload', () {
      const response = RainmakerLoginResponse(
        isSuccess: true,
        accessToken: 'mock_token_abc',
        refreshToken: 'mock_refresh_xyz',
        userId: 'user_123',
        email: 'dev@templelights.org',
      );

      expect(response.isSuccess, true);
      expect(response.accessToken, 'mock_token_abc');
      expect(response.refreshToken, 'mock_refresh_xyz');
      expect(response.userId, 'user_123');
      expect(response.email, 'dev@templelights.org');
      expect(response.errorMessage, isNull);
    });

    test('RainmakerLoginResponse correctly handles failure payload', () {
      const response = RainmakerLoginResponse(
        isSuccess: false,
        errorMessage: 'Invalid credentials',
      );

      expect(response.isSuccess, false);
      expect(response.accessToken, isNull);
      expect(response.errorMessage, 'Invalid credentials');
    });

    test('generateSecretKey produces 16-character alphanumeric key', () {
      final key1 = RainmakerCloudService.generateSecretKey();
      final key2 = RainmakerCloudService.generateSecretKey();

      expect(key1.length, 16);
      expect(key2.length, 16);
      expect(key1, isNot(equals(key2)));
      expect(RegExp(r'^[a-zA-Z0-9]{16}$').hasMatch(key1), isTrue);
    });

    test('extractOAuthCode extracts code correctly across all URL variants and raw codes', () {
      expect(RainmakerCloudService.extractOAuthCode('raw_code_123'), 'raw_code_123');
      expect(
        RainmakerCloudService.extractOAuthCode('rainmaker://com.espressif.novahome/success?code=abc-xyz'),
        'abc-xyz',
      );
      expect(
        RainmakerCloudService.extractOAuthCode('  https://custom.callback.com/success?state=123&code=my_code_456&scope=all  '),
        'my_code_456',
      );
      expect(RainmakerCloudService.extractOAuthCode(''), '');
      expect(RainmakerCloudService.extractOAuthCode('   '), '');
    });
  });

  group('LightState Rainmaker Properties Tests', () {
    test('LightState stores and updates rainmakerNodeId', () {
      const initial = LightState();
      expect(initial.rainmakerNodeId, isNull);

      final updated = initial.copyWith(rainmakerNodeId: 'node_esp32_mandir_01');
      expect(updated.rainmakerNodeId, 'node_esp32_mandir_01');

      final preserved = updated.copyWith(brightness: 200);
      expect(preserved.rainmakerNodeId, 'node_esp32_mandir_01');
      expect(preserved.brightness, 200);
    });
  });

  group('RainmakerAuthNotifier State & KV Persistence Tests', () {
    late KvStore kv;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      kv = await KvStore.instance();
    });

    test('RainmakerAuthNotifier initializes empty when no credentials in KV', () {
      final container = ProviderContainer(
        overrides: [
          kvStoreProvider.overrideWithValue(kv),
        ],
      );

      final state = container.read(rainmakerAuthProvider);
      expect(state.isLoggedIn, false);
      expect(state.email, isNull);
      expect(state.accessToken, isNull);
    });

    test('RainmakerAuthNotifier auto-loads credentials from KV on startup', () async {
      await kv.putString(KvKeys.rainmakerEmail, 'user@templelights.org');
      await kv.putString(KvKeys.rainmakerAccessToken, 'saved_token_123');
      await kv.putString(KvKeys.rainmakerUserId, 'uid_456');

      final container = ProviderContainer(
        overrides: [
          kvStoreProvider.overrideWithValue(kv),
        ],
      );

      final state = container.read(rainmakerAuthProvider);
      expect(state.isLoggedIn, true);
      expect(state.email, 'user@templelights.org');
      expect(state.accessToken, 'saved_token_123');
      expect(state.userId, 'uid_456');
    });

    test('RainmakerAuthNotifier logout cleans KV and resets state', () async {
      await kv.putString(KvKeys.rainmakerEmail, 'user@templelights.org');
      await kv.putString(KvKeys.rainmakerAccessToken, 'saved_token_123');
      await kv.putString(KvKeys.rainmakerRefreshToken, 'saved_refresh_789');

      final container = ProviderContainer(
        overrides: [
          kvStoreProvider.overrideWithValue(kv),
        ],
      );

      expect(container.read(rainmakerAuthProvider).isLoggedIn, true);

      await container.read(rainmakerAuthProvider.notifier).logout();

      final state = container.read(rainmakerAuthProvider);
      expect(state.isLoggedIn, false);
      expect(state.email, isNull);
      expect(state.accessToken, isNull);
      expect(state.refreshToken, isNull);
      expect(kv.getString(KvKeys.rainmakerEmail), isNull);
      expect(kv.getString(KvKeys.rainmakerAccessToken), isNull);
      expect(kv.getString(KvKeys.rainmakerRefreshToken), isNull);
    });

    test('loginWithOAuthCode validates empty code and reports error', () async {
      final container = ProviderContainer(
        overrides: [
          kvStoreProvider.overrideWithValue(kv),
        ],
      );

      final ok = await container.read(rainmakerAuthProvider.notifier).loginWithOAuthCode('');
      expect(ok, false);
      expect(container.read(rainmakerAuthProvider).errorMessage, contains('Invalid or empty code'));
    });

    test('loginWithOAuthCode succeeds and stores credentials in KV', () async {
      final fakeService = FakeRainmakerCloudService();
      final container = ProviderContainer(
        overrides: [
          kvStoreProvider.overrideWithValue(kv),
          rainmakerCloudServiceProvider.overrideWithValue(fakeService),
        ],
      );

      final ok = await container.read(rainmakerAuthProvider.notifier).loginWithOAuthCode(
            'rainmaker://com.espressif.novahome/success?code=valid_code',
          );
      expect(ok, true);

      final state = container.read(rainmakerAuthProvider);
      expect(state.isLoggedIn, true);
      expect(state.email, 'test@gmail.com');
      expect(state.accessToken, 'test_access');
      expect(state.refreshToken, 'test_refresh');
      expect(state.userId, 'uid_1');
      expect(state.nodes, contains('node_test_123'));

      expect(kv.getString(KvKeys.rainmakerAccessToken), 'test_access');
      expect(kv.getString(KvKeys.rainmakerRefreshToken), 'test_refresh');
      expect(kv.getString(KvKeys.rainmakerEmail), 'test@gmail.com');
      expect(kv.getString(KvKeys.rainmakerUserId), 'uid_1');
    });
  });
}

class FakeRainmakerCloudService extends RainmakerCloudService {
  FakeRainmakerCloudService({
    this.exchangeResult = const RainmakerLoginResponse(
      isSuccess: true,
      accessToken: 'test_access',
      refreshToken: 'test_refresh',
      email: 'test@gmail.com',
      userId: 'uid_1',
    ),
  });

  final RainmakerLoginResponse exchangeResult;

  @override
  Future<RainmakerLoginResponse> exchangeOAuthCode(String code) async {
    if (code == 'valid_code') return exchangeResult;
    return const RainmakerLoginResponse(isSuccess: false, errorMessage: 'Invalid code');
  }

  @override
  Future<List<String>> getUserNodes({required String accessToken}) async {
    return ['node_test_123'];
  }
}
