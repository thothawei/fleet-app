import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/models.dart';

/// 司機登入狀態持久化抽象，方便單元測試注入記憶體實作。
abstract class DriverAuthStore {
  Future<AuthSession?> read();
  Future<void> save(AuthSession session);
  Future<void> clear();
}

/// 持久化 JWT，重開 App 免重新登入。
class TokenStorage implements DriverAuthStore {
  TokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _keyToken = 'driver_token';
  static const _keyDriverId = 'driver_id';
  static const _keyName = 'driver_name';

  final FlutterSecureStorage _storage;

  @override
  Future<AuthSession?> read() async {
    final token = await _storage.read(key: _keyToken);
    final idStr = await _storage.read(key: _keyDriverId);
    if (token == null || idStr == null) return null;
    return AuthSession(
      driverId: int.parse(idStr),
      token: token,
      name: await _storage.read(key: _keyName),
    );
  }

  @override
  Future<void> save(AuthSession session) async {
    await _storage.write(key: _keyToken, value: session.token);
    await _storage.write(key: _keyDriverId, value: '${session.driverId}');
    if (session.name != null) {
      await _storage.write(key: _keyName, value: session.name);
    }
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _keyToken);
    await _storage.delete(key: _keyDriverId);
    await _storage.delete(key: _keyName);
  }
}

/// 測試用：純記憶體，不碰平台 secure storage。
class MemoryDriverAuthStore implements DriverAuthStore {
  AuthSession? _session;

  @override
  Future<AuthSession?> read() async => _session;

  @override
  Future<void> save(AuthSession session) async {
    _session = session;
  }

  @override
  Future<void> clear() async {
    _session = null;
  }
}
