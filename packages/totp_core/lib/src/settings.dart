import 'dart:convert';
import 'dart:io';

import 'fs_utils.dart';
import 'paths.dart';

/// 本地设置（App、CLI、MCP 共用同一份文件）。
///
/// 目前只有一项：AI / MCP 取码总开关。放在数据目录而不是系统钥匙串里，
/// 是为了让 CLI 与 MCP（无 GUI、可能是 AI 子进程）也能读到它。
class TotpSettings {
  const TotpSettings({this.aiAccessEnabled = true});

  /// AI / MCP 取码总开关。
  ///
  /// `false` = 关闭：CLI 的读取/取码与 MCP 的所有工具都会被拒绝（fail closed），
  /// 但不会删除 vault 里的任何账号。默认 `true`（保持既有行为）。
  final bool aiAccessEnabled;

  static const TotpSettings enabled = TotpSettings();

  Map<String, dynamic> toJson() => {
        'version': 1,
        'aiAccessEnabled': aiAccessEnabled,
      };

  factory TotpSettings.fromJson(Map<String, dynamic> json) => TotpSettings(
        aiAccessEnabled: json['aiAccessEnabled'] as bool? ?? true,
      );

  TotpSettings copyWith({bool? aiAccessEnabled}) => TotpSettings(
        aiAccessEnabled: aiAccessEnabled ?? this.aiAccessEnabled,
      );
}

/// 设置读写：文件不存在或损坏时回退到默认值（总开关=开），
/// 绝不因为读不到设置就把用户锁在外面（读不到设置时按既有默认行为走）。
class SettingsStore {
  SettingsStore({required this.paths});

  final TotpPaths paths;

  Future<TotpSettings> load() async {
    final file = File(paths.settingsFile);
    if (!await file.exists()) return TotpSettings.enabled;
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map<String, dynamic>) return TotpSettings.enabled;
      return TotpSettings.fromJson(raw);
    } catch (_) {
      return TotpSettings.enabled;
    }
  }

  /// 原子写入并保持 600 权限
  Future<void> save(TotpSettings settings) async {
    await ensurePrivateDir(paths.home);
    await writeFileAtomic(
      paths.settingsFile,
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
    );
    await restrictFilePermissions(paths.settingsFile);
  }

  /// 只改总开关（读改写，避免覆盖将来新增的字段）
  Future<TotpSettings> setAiAccessEnabled(bool enabled) async {
    final next = (await load()).copyWith(aiAccessEnabled: enabled);
    await save(next);
    return next;
  }
}
