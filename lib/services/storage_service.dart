import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/account.dart';

/// 账户密钥的本地加密存储
///
/// Android 上默认使用 AES-GCM 加密 + RSA 密钥包裹
/// （密钥由 Android Keystore 保管，API 23+），iOS/macOS 上使用 Keychain。
class StorageService {
  static const _key = 'totp_accounts_v1';

  /// macOS 上关闭 data-protection keychain，退回传统 Keychain：
  /// 避免 keychain-access-groups entitlement 与 provisioning profile 的
  /// 签名要求（个人本地使用不需要 Keychain Sharing）。
  final FlutterSecureStorage _storage = (!kIsWeb && Platform.isMacOS)
      ? const FlutterSecureStorage(
          mOptions: MacOsOptions(usesDataProtectionKeychain: false),
        )
      : const FlutterSecureStorage();

  Future<List<TotpAccount>> load() async {
    try {
      final jsonStr = await _storage.read(key: _key);
      if (jsonStr == null || jsonStr.isEmpty) return [];
      return TotpAccount.decodeList(jsonStr);
    } catch (_) {
      // 解密失败（如换机后 Keystore 变化）时宁可返回空，也不让 App 崩溃
      return [];
    }
  }

  Future<void> save(List<TotpAccount> accounts) {
    return _storage.write(key: _key, value: TotpAccount.encodeList(accounts));
  }
}
