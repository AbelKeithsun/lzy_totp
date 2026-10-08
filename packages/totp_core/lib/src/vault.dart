import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import 'account.dart';
import 'fs_utils.dart';
import 'paths.dart';

/// vault 读写异常（密钥缺失、密文损坏等）
class VaultError implements Exception {
  VaultError(this.message);

  final String message;

  @override
  String toString() => 'VaultError: $message';
}

/// 加密 vault：账户密钥以 AES-256-GCM 加密后落盘，明文只存在于内存。
///
/// 文件格式（`~/.config/lzy_totp/vault.json`）：
/// ```json
/// {
///   "version": 1,
///   "accounts": [
///     {"id":"...","issuer":"GitHub","label":"me@x.com","digits":6,
///      "period":30,"algorithm":"SHA1","aiAllowed":false,
///      "secret":"enc:v1:<base64(nonce|mac|cipherText)>"}
///   ]
/// }
/// ```
class VaultStore {
  VaultStore({required this.paths});

  final TotpPaths paths;

  static const _cipherPrefix = 'enc:v1:';
  static final _aes = AesGcm.with256bits();

  /// 读取并解密全部账户。vault 文件不存在时返回空列表（且不创建密钥文件）。
  Future<List<TotpAccount>> load() async {
    final file = File(paths.vaultFile);
    if (!await file.exists()) return [];

    final key = await _readKey();
    if (key == null) {
      throw VaultError('密钥文件缺失：${paths.keyFile}\n'
          'vault 已存在但密钥丢失，无法解密。请从备份恢复密钥，或删除 vault 重新录入。');
    }

    final Map<String, dynamic> root;
    try {
      root = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      throw VaultError('vault 文件解析失败：$e');
    }

    final rawList = (root['accounts'] as List<dynamic>? ?? const []);
    final accounts = <TotpAccount>[];
    for (final raw in rawList) {
      final map = Map<String, dynamic>.from(raw as Map);
      final stored = map['secret'] as String? ?? '';
      map['secret'] = await _decrypt(stored, key);
      accounts.add(TotpAccount.fromJson(map));
    }
    return accounts;
  }

  /// 加密写回全部账户（原子写入 + 权限 600）。
  Future<void> save(List<TotpAccount> accounts) async {
    await ensurePrivateDir(paths.home);
    final key = await _ensureKey();

    final out = <Map<String, dynamic>>[];
    for (final account in accounts) {
      final map = account.toJson();
      map['secret'] = await _encrypt(account.secret, key);
      out.add(map);
    }

    final contents = const JsonEncoder.withIndent('  ')
        .convert({'version': 1, 'accounts': out});
    await writeFileAtomic(paths.vaultFile, contents);
  }

  /// 读改写的事务封装
  Future<T> update<T>(
    Future<T> Function(List<TotpAccount> accounts) mutate,
  ) async {
    final accounts = await load();
    final result = await mutate(accounts);
    await save(accounts);
    return result;
  }

  Future<List<int>?> _readKey() async {
    final file = File(paths.keyFile);
    if (!await file.exists()) return null;
    final raw = (await file.readAsString()).trim();
    if (raw.isEmpty) return null;
    final bytes = base64Decode(raw);
    if (bytes.length != 32) {
      throw VaultError('密钥文件长度异常（期望 32 字节，实际 ${bytes.length}）');
    }
    return bytes;
  }

  Future<List<int>> _ensureKey() async {
    final existing = await _readKey();
    if (existing != null) return existing;

    final key = randomBytes(32);
    await File(paths.keyFile).writeAsString(base64Encode(key), flush: true);
    await restrictFilePermissions(paths.keyFile);
    return key;
  }

  Future<String> _encrypt(String plain, List<int> key) async {
    final nonce = randomBytes(12);
    final box = await _aes.encrypt(
      utf8.encode(plain),
      secretKey: SecretKey(key),
      nonce: nonce,
    );
    return _cipherPrefix +
        base64Encode([...box.nonce, ...box.mac.bytes, ...box.cipherText]);
  }

  Future<String> _decrypt(String stored, List<int> key) async {
    // 兼容早期未加密的明文（迁移用）
    if (!stored.startsWith(_cipherPrefix)) return stored;

    final raw = base64Decode(stored.substring(_cipherPrefix.length));
    if (raw.length < 29) throw VaultError('密文长度异常');
    final nonce = raw.sublist(0, 12);
    final mac = raw.sublist(12, 28);
    final cipherText = raw.sublist(28);
    try {
      final clear = await _aes.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: SecretKey(key),
      );
      return utf8.decode(clear);
    } catch (_) {
      throw VaultError('密文解密失败：密钥不匹配或数据损坏');
    }
  }
}
