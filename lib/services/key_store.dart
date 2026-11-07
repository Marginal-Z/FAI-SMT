/// API keys in the operating system's secure store (Windows credential
/// storage, Android Keystore, libsecret on Linux). Where no secure store
/// works, keys are kept for this session only and [secure] says so; they
/// are never written to the plain settings file.
library;

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class KeyStore {
  /// Keys survive a restart only when true.
  bool get secure;

  Future<String?> read(String id);
  Future<void> write(String id, String key);
  Future<void> delete(String id);
}

/// For tests, and the fallback when no secure store works.
class MemoryKeyStore implements KeyStore {
  final _keys = <String, String>{};

  @override
  bool get secure => false;

  @override
  Future<String?> read(String id) async => _keys[id];

  @override
  Future<void> write(String id, String key) async => _keys[id] = key;

  @override
  Future<void> delete(String id) async => _keys.remove(id);
}

class SecureKeyStore implements KeyStore {
  final _storage = const FlutterSecureStorage();
  final _memory = MemoryKeyStore();
  var _secure = true;

  @override
  bool get secure => _secure;

  String _name(String id) => 'smt_fai_api_key_$id';

  Future<T> _guard<T>(Future<T> Function() secure, Future<T> Function() memory) async {
    if (!_secure) return memory();
    try {
      return await secure();
    } on PlatformException {
      // No keyring (e.g. a Linux desktop without one): session only.
      _secure = false;
      return memory();
    } on MissingPluginException {
      _secure = false;
      return memory();
    }
  }

  @override
  Future<String?> read(String id) => _guard(() => _storage.read(key: _name(id)), () => _memory.read(id));

  @override
  Future<void> write(String id, String key) => _guard(() => _storage.write(key: _name(id), value: key), () => _memory.write(id, key));

  @override
  Future<void> delete(String id) => _guard(() => _storage.delete(key: _name(id)), () => _memory.delete(id));
}
