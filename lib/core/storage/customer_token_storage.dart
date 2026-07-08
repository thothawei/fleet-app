import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/models.dart';

/// 持久化乘客 JWT，重開 App 免重新登入。
class CustomerTokenStorage {
  CustomerTokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _keyToken = 'customer_token';
  static const _keyCustomerId = 'customer_id';
  static const _keyName = 'customer_name';

  final FlutterSecureStorage _storage;

  Future<CustomerSession?> read() async {
    final token = await _storage.read(key: _keyToken);
    final idStr = await _storage.read(key: _keyCustomerId);
    if (token == null || idStr == null) return null;
    return CustomerSession(
      customerId: int.parse(idStr),
      token: token,
      name: await _storage.read(key: _keyName),
    );
  }

  Future<void> save(CustomerSession session) async {
    await _storage.write(key: _keyToken, value: session.token);
    await _storage.write(key: _keyCustomerId, value: '${session.customerId}');
    if (session.name != null) {
      await _storage.write(key: _keyName, value: session.name);
    }
  }

  Future<void> clear() async {
    await _storage.delete(key: _keyToken);
    await _storage.delete(key: _keyCustomerId);
    await _storage.delete(key: _keyName);
  }
}
