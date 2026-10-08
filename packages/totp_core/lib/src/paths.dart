import 'dart:io';

import 'package:path/path.dart' as p;

/// 数据目录解析：vault、密钥、审计日志都放在这里。
class TotpPaths {
  const TotpPaths(this.home);

  /// 数据目录绝对路径
  final String home;

  /// 解析优先级：显式传入 > `LZY_TOTP_HOME` > `XDG_CONFIG_HOME/lzy_totp`
  /// > `~/.config/lzy_totp`
  factory TotpPaths.resolve({String? homeOverride, Map<String, String>? env}) {
    if (homeOverride != null && homeOverride.trim().isNotEmpty) {
      return TotpPaths(homeOverride.trim());
    }
    final e = env ?? Platform.environment;
    final explicit = e['LZY_TOTP_HOME'];
    if (explicit != null && explicit.trim().isNotEmpty) {
      return TotpPaths(explicit.trim());
    }
    final xdg = e['XDG_CONFIG_HOME'];
    if (xdg != null && xdg.trim().isNotEmpty) {
      return TotpPaths(p.join(xdg.trim(), 'lzy_totp'));
    }
    final home = e['HOME'] ?? Directory.systemTemp.path;
    return TotpPaths(p.join(home, '.config', 'lzy_totp'));
  }

  /// 加密 vault 文件（密钥密文 + 元数据）
  String get vaultFile => p.join(home, 'vault.json');

  /// vault 的 AES-256-GCM 密钥文件（32 字节 base64，权限 600）
  String get keyFile => p.join(home, 'vault.key');

  /// 审计日志（JSONL）
  String get auditFile => p.join(home, 'audit.jsonl');
}
