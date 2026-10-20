import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:spotube/services/kv_store/kv_store.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:uuid/uuid.dart';
import 'package:spotube/utils/platform.dart';

abstract class EncryptedKvStoreService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  static FlutterSecureStorage get storage => _storage;

  static String? _encryptionKeySync;

  static Future<void> initialize() async {
    _encryptionKeySync = await encryptionKey;
  }

  static String get encryptionKeySync => _encryptionKeySync!;

  static bool get isUnsupportedPlatform =>
      kIsMacOS || kIsIOS || (kIsLinux && !kIsFlatpak);

  static Future<String> get encryptionKey async {
    if (isUnsupportedPlatform) {
      return KVStoreService.encryptionKey;
    }
    try {
      final value = await _storage.read(key: 'encryption');
      final key = const Uuid().v4();

      if (value == null) {
        await setEncryptionKey(key);
        return key;
      }

      return value;
    } catch (e, stack) {
      // The fallback behavior is deliberate (the legacy key keeps the store
      // readable), but a secure-storage failure must leave a trail: data
      // written under the secure key can no longer be decrypted after it.
      AppLogger.reportError(e, stack, "EncryptedKvStoreService.encryptionKey");
      return KVStoreService.encryptionKey;
    }
  }

  static Future<void> setEncryptionKey(String key) async {
    if (isUnsupportedPlatform) {
      await KVStoreService.setEncryptionKey(key);
      return;
    }

    try {
      await _storage.write(key: 'encryption', value: key);
    } catch (e, stack) {
      AppLogger.reportError(
          e, stack, "EncryptedKvStoreService.setEncryptionKey");
      await KVStoreService.setEncryptionKey(key);
    } finally {
      _encryptionKeySync = key;
    }
  }
}
