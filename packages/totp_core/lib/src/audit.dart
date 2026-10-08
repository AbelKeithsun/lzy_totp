import 'dart:convert';
import 'dart:io';

import 'fs_utils.dart';

/// 一条审计记录：谁、什么时候、对哪个账户做了什么、结果如何。
class AuditEntry {
  AuditEntry({
    required this.action,
    required this.result,
    this.account,
    this.actor = 'cli',
    this.note,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().toUtc();

  final DateTime timestamp;
  final String action;
  final String? account;

  /// ok / denied / error
  final String result;

  /// 调用来源，如 cli / mcp
  final String actor;
  final String? note;

  Map<String, dynamic> toJson() => {
        'ts': timestamp.toIso8601String(),
        'action': action,
        if (account != null) 'account': account,
        'result': result,
        'actor': actor,
        if (note != null) 'note': note,
      };

  factory AuditEntry.fromJson(Map<String, dynamic> json) => AuditEntry(
        timestamp: DateTime.tryParse(json['ts'] as String? ?? '')?.toUtc(),
        action: json['action'] as String? ?? 'unknown',
        account: json['account'] as String?,
        result: json['result'] as String? ?? 'unknown',
        actor: json['actor'] as String? ?? 'unknown',
        note: json['note'] as String?,
      );

  String toJsonLine() => jsonEncode(toJson());

  @override
  String toString() {
    final acc = account == null ? '' : ' account=$account';
    final noteText = note == null ? '' : ' note=$note';
    return '${timestamp.toIso8601String()} [$result] $action$acc actor=$actor$noteText';
  }
}

/// 审计日志（JSONL，追加写，权限 600）
class AuditLog {
  AuditLog(this.path);

  final String path;

  Future<void> append(AuditEntry entry) async {
    final file = File(path);
    await ensurePrivateDir(file.parent.path);
    if (!await file.exists()) {
      await file.create(recursive: true);
      await restrictFilePermissions(path);
    }
    await file.writeAsString('${entry.toJsonLine()}\n',
        mode: FileMode.append, flush: true);
  }

  /// 读取最近 [n] 条记录（新的在后）
  Future<List<AuditEntry>> tail(int n) async {
    final file = File(path);
    if (!await file.exists()) return [];
    final lines = (await file.readAsLines())
        .where((l) => l.trim().isNotEmpty)
        .toList();
    final slice = lines.length <= n ? lines : lines.sublist(lines.length - n);
    return slice
        .map((l) => AuditEntry.fromJson(jsonDecode(l) as Map<String, dynamic>))
        .toList();
  }
}
