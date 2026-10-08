import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:totp_core/totp_core.dart';

import 'mcp_server.dart';

/// 交互确认回调（仅在 stdin 是终端时使用）
typedef Confirm = Future<bool> Function(String prompt);

/// CLI 运行上下文（依赖注入，便于测试）
class CliContext {
  CliContext({
    required this.vault,
    required this.audit,
    required this.paths,
    required this.out,
    required this.err,
    this.stdinIsTerminal = false,
    Confirm? confirm,
    this.stdinStream,
  }) : confirm = confirm ?? _defaultConfirm;

  final VaultStore vault;
  final AuditLog audit;
  final TotpPaths paths;
  final IOSink out;
  final IOSink err;

  /// stdin 是否为终端。AI 调用（管道/非交互）时为 false——
  /// 这是「人工放行」与「AI 调用」的区分依据。
  final bool stdinIsTerminal;
  final Confirm confirm;
  final Stream<List<int>>? stdinStream;

  static Future<bool> _defaultConfirm(String prompt) async {
    stdout.write(prompt);
    final line = stdin.readLineSync()?.trim().toLowerCase();
    return line == 'y' || line == 'yes';
  }
}

/// 退出码约定：0 成功 / 1 用法或内部错误 / 2 被策略拒绝 / 3 未找到账户
class ExitCode {
  static const ok = 0;
  static const usage = 1;
  static const denied = 2;
  static const notFound = 3;
}

Future<int> runCli(List<String> argv, CliContext ctx) async {
  final parser = _buildParser();

  ArgResults results;
  try {
    results = parser.parse(argv);
  } on FormatException catch (e) {
    ctx.err.writeln('参数错误：${e.message}');
    ctx.err.writeln(_usage(parser));
    return ExitCode.usage;
  }

  if (results['help'] == true) {
    ctx.out.writeln(_usage(parser));
    return ExitCode.ok;
  }

  final command = results.command;
  if (command == null) {
    ctx.out.writeln(_usage(parser));
    return ExitCode.usage;
  }

  try {
    switch (command.name) {
      case 'list':
        return _list(ctx, command);
      case 'info':
        return _info(ctx, command);
      case 'code':
        return _code(ctx, command);
      case 'add':
        return _add(ctx, command);
      case 'remove':
        return _remove(ctx, command);
      case 'allow':
        return _setAllowed(ctx, command, true);
      case 'deny':
        return _setAllowed(ctx, command, false);
      case 'audit':
        return _audit(ctx, command);
      case 'doctor':
        return _doctor(ctx);
      case 'mcp':
        return _mcp(ctx);
      default:
        ctx.err.writeln('未知命令：${command.name}');
        return ExitCode.usage;
    }
  } on VaultError catch (e) {
    ctx.err.writeln(e.message);
    return ExitCode.usage;
  } on FileSystemException catch (e) {
    ctx.err.writeln('文件操作失败：${e.message}');
    return ExitCode.usage;
  }
}

ArgParser _buildParser() {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: '显示帮助');

  parser.addCommand('list').addFlag('json', negatable: false, help: '以 JSON 输出');

  parser.addCommand('info').addFlag('json', negatable: false, help: '以 JSON 输出');

  parser
      .addCommand('code')
      .addFlag('json', negatable: false, help: '以 JSON 输出（含剩余秒数）');
  parser.commands['code']!
      .addFlag('quiet', abbr: 'q', negatable: false, help: '只输出验证码本身');

  parser
      .addCommand('add')
      .addOption('secret', help: 'Base32 密钥');
  parser.commands['add']!
    ..addOption('uri', help: 'otpauth:// URI（与 --secret 二选一）')
    ..addOption('issuer', help: '发行方')
    ..addOption('label', help: '账户名')
    ..addOption('digits', allowed: ['6', '8'], defaultsTo: '6')
    ..addOption('period', allowed: ['30', '60'], defaultsTo: '30')
    ..addOption('algorithm',
        allowed: ['SHA1', 'SHA256', 'SHA512'], defaultsTo: 'SHA1')
    ..addFlag('allow-ai', negatable: false, help: '同时放行给 AI（默认不放行）');

  parser.addCommand('remove');
  parser.addCommand('allow');
  parser.addCommand('deny');

  parser
      .addCommand('audit')
      .addOption('tail', defaultsTo: '20', help: '显示最近 N 条');

  parser.addCommand('doctor');
  parser.addCommand('mcp');

  return parser;
}

String _usage(ArgParser parser) => '''
lzy_totp —— 一次性验证码（TOTP）命令行 / MCP 入口

用法：lzy_totp <命令> [参数]

命令：
  list                 列出账号（含是否允许 AI 取码）
  info <名称>          查看账号元数据（绝不返回密钥）
  code <名称>          输出当前验证码
  add <名称>           添加账号（--secret <Base32> 或 --uri <otpauth://...>）
  remove <名称>        删除账号
  allow <名称>         放行给 AI（默认全部拒绝）
  deny <名称>          撤销放行
  audit               查看审计日志（--tail N）
  doctor              自检
  mcp                 启动 MCP stdio server

示例：
  lzy_totp add github --secret JBSWY3DPEHPK3PXP --issuer GitHub --allow-ai
  lzy_totp code github --json
  lzy_totp allow "Bank (me@x.com)"

全局选项：
${parser.usage}''';

// --------------------------------------------------------------------- 命令

Future<int> _list(CliContext ctx, ArgResults cmd) async {
  final accounts = await ctx.vault.load();
  if (cmd['json'] as bool) {
    ctx.out.writeln(_encode({
      'vault': ctx.paths.vaultFile,
      'accounts': accounts
          .map((a) => {
                'account': a.displayTitle,
                'id': a.id,
                'issuer': a.issuer,
                'label': a.label,
                'digits': a.digits,
                'period': a.period,
                'algorithm': a.algorithm,
                'ai_allowed': a.aiAllowed,
              })
          .toList(),
    }));
    return ExitCode.ok;
  }

  if (accounts.isEmpty) {
    ctx.out.writeln('vault 为空：${ctx.paths.vaultFile}');
    ctx.out.writeln('用 lzy_totp add <名称> --secret <Base32> 录入账号。');
    return ExitCode.ok;
  }
  for (final a in accounts) {
    final flag = a.aiAllowed ? 'AI 允许' : 'AI 拒绝';
    ctx.out.writeln('${a.displayTitle}  [$flag]  ${a.digits}位/${a.period}s/${a.algorithm}');
  }
  return ExitCode.ok;
}

Future<int> _info(CliContext ctx, ArgResults cmd) async {
  final query = _firstArg(cmd);
  if (query == null) {
    ctx.err.writeln('用法：lzy_totp info <名称>');
    return ExitCode.usage;
  }
  final result = await _resolve(ctx, query);
  if (result.exitCode != null) return result.exitCode!;
  final a = result.account!;

  if (cmd['json'] as bool) {
    ctx.out.writeln(_encode(_metadata(a)));
  } else {
    ctx.out.writeln('账号：${a.displayTitle}');
    ctx.out.writeln('id：${a.id}');
    ctx.out.writeln('参数：${a.digits} 位 / ${a.period} 秒 / ${a.algorithm}');
    ctx.out.writeln('AI 取码：${a.aiAllowed ? '允许' : '拒绝（默认）'}');
  }
  return ExitCode.ok;
}

Future<int> _code(CliContext ctx, ArgResults cmd) async {
  final query = _firstArg(cmd);
  if (query == null) {
    ctx.err.writeln('用法：lzy_totp code <名称>');
    return ExitCode.usage;
  }
  final result = await _resolve(ctx, query);
  if (result.exitCode != null) return result.exitCode!;
  final account = result.account!;

  var allowed = AiAccessPolicy.allows(account);
  String? overrideNote;

  if (!allowed && ctx.stdinIsTerminal) {
    // 交互终端下的人工通道：AI 非交互调用拿不到这条路径
    final ok = await ctx.confirm(
        '账号「${account.displayTitle}」未放行给 AI。确认以人工身份查看验证码？[y/N] ');
    if (ok) {
      allowed = true;
      overrideNote = 'human-tty-override';
    }
  }

  if (!allowed) {
    await ctx.audit.append(AuditEntry(
      action: 'generate_totp',
      account: account.displayTitle,
      result: 'denied',
      actor: 'cli',
      note: 'ai_allowed=false',
    ));
    ctx.err.writeln('拒绝取码：${AiAccessPolicy.denialReason(account)}');
    return ExitCode.denied;
  }

  final now = DateTime.now();
  final code = TotpService.codeFor(account, now: now);
  final remaining =
      TotpService.remainingSeconds(period: account.period, now: now);

  await ctx.audit.append(AuditEntry(
    action: 'generate_totp',
    account: account.displayTitle,
    result: 'ok',
    actor: 'cli',
    note: overrideNote,
  ));

  if (cmd['json'] as bool) {
    ctx.out.writeln(_encode({
      'account': account.displayTitle,
      'code': code,
      'remaining_seconds': remaining,
      'period': account.period,
      'expires_at':
          now.add(Duration(seconds: remaining)).toUtc().toIso8601String(),
    }));
  } else {
    ctx.out.writeln(code);
  }
  return ExitCode.ok;
}

Future<int> _add(CliContext ctx, ArgResults cmd) async {
  final name = _firstArg(cmd);
  if (name == null) {
    ctx.err.writeln('用法：lzy_totp add <名称> --secret <Base32> [--issuer X] [--allow-ai]');
    return ExitCode.usage;
  }
  final secret = cmd['secret'] as String?;
  final uri = cmd['uri'] as String?;
  if ((secret == null) == (uri == null)) {
    ctx.err.writeln('必须且只能提供 --secret 或 --uri 之一。');
    return ExitCode.usage;
  }

  final allowAi = cmd['allow-ai'] as bool;
  late final TotpAccount account;

  if (uri != null) {
    final parsed = TotpAccount.fromOtpAuthUri(uri, aiAllowed: allowAi);
    if (parsed == null) {
      ctx.err.writeln('otpauth URI 解析失败（仅支持 otpauth://totp/... 且需含 secret）。');
      return ExitCode.usage;
    }
    account = TotpAccount(
      id: parsed.id,
      issuer: (cmd['issuer'] as String?) ?? parsed.issuer,
      label: (cmd['label'] as String?) ?? parsed.label,
      secret: parsed.secret,
      digits: parsed.digits,
      period: parsed.period,
      algorithm: parsed.algorithm,
      aiAllowed: allowAi,
    );
  } else {
    final normalized = secret!.toUpperCase().replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^[A-Z2-7]+=*$').hasMatch(normalized)) {
      ctx.err.writeln('密钥格式不正确：应为 Base32（字母 A-Z 与数字 2-7）。');
      return ExitCode.usage;
    }
    account = TotpAccount(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      issuer: (cmd['issuer'] as String?) ?? name,
      label: (cmd['label'] as String?) ?? '',
      secret: normalized,
      digits: int.parse(cmd['digits'] as String),
      period: int.parse(cmd['period'] as String),
      algorithm: cmd['algorithm'] as String,
      aiAllowed: allowAi,
    );
    try {
      TotpService.codeFor(account);
    } catch (_) {
      ctx.err.writeln('密钥无法解码，请检查是否完整。');
      return ExitCode.usage;
    }
  }

  final accounts = await ctx.vault.load();
  final conflict = accounts.where((a) => a.matches(name)).toList();
  if (conflict.isNotEmpty) {
    ctx.err.writeln('已存在同名账户「${conflict.first.displayTitle}」，请先 remove。');
    return ExitCode.usage;
  }
  accounts.add(account);
  await ctx.vault.save(accounts);
  await ctx.audit.append(AuditEntry(
    action: 'add_account',
    account: account.displayTitle,
    result: 'ok',
    actor: 'cli',
    note: 'ai_allowed=${account.aiAllowed}',
  ));

  ctx.out.writeln('已添加：${account.displayTitle}'
      '（AI 取码：${account.aiAllowed ? '允许' : '拒绝'}）');
  return ExitCode.ok;
}

Future<int> _remove(CliContext ctx, ArgResults cmd) async {
  final query = _firstArg(cmd);
  if (query == null) {
    ctx.err.writeln('用法：lzy_totp remove <名称>');
    return ExitCode.usage;
  }
  final result = await _resolve(ctx, query);
  if (result.exitCode != null) return result.exitCode!;
  final account = result.account!;

  await ctx.vault.update((accounts) async {
    accounts.removeWhere((a) => a.id == account.id);
    return null;
  });
  await ctx.audit.append(AuditEntry(
    action: 'remove_account',
    account: account.displayTitle,
    result: 'ok',
    actor: 'cli',
  ));
  ctx.out.writeln('已删除：${account.displayTitle}');
  return ExitCode.ok;
}

Future<int> _setAllowed(
  CliContext ctx,
  ArgResults cmd,
  bool allowed,
) async {
  final query = _firstArg(cmd);
  if (query == null) {
    ctx.err.writeln('用法：lzy_totp ${allowed ? 'allow' : 'deny'} <名称>');
    return ExitCode.usage;
  }
  final result = await _resolve(ctx, query);
  if (result.exitCode != null) return result.exitCode!;
  final account = result.account!;

  await ctx.vault.update((accounts) async {
    accounts.firstWhere((a) => a.id == account.id).aiAllowed = allowed;
    return null;
  });
  await ctx.audit.append(AuditEntry(
    action: 'set_ai_allowed',
    account: account.displayTitle,
    result: 'ok',
    actor: 'cli',
    note: 'allowed=$allowed',
  ));
  ctx.out.writeln('${account.displayTitle} → AI 取码${allowed ? '已允许' : '已拒绝'}');
  return ExitCode.ok;
}

Future<int> _audit(CliContext ctx, ArgResults cmd) async {
  final n = int.tryParse(cmd['tail'] as String) ?? 20;
  final entries = await ctx.audit.tail(n);
  if (entries.isEmpty) {
    ctx.out.writeln('暂无审计记录：${ctx.paths.auditFile}');
    return ExitCode.ok;
  }
  for (final e in entries) {
    ctx.out.writeln(e.toString());
  }
  return ExitCode.ok;
}

Future<int> _doctor(CliContext ctx) async {
  final accounts = await ctx.vault.load();
  final allowed = accounts.where((a) => a.aiAllowed).length;

  ctx.out.writeln('数据目录：${ctx.paths.home}');
  for (final entry in {
    'vault': ctx.paths.vaultFile,
    '密钥': ctx.paths.keyFile,
    '审计': ctx.paths.auditFile,
  }.entries) {
    final file = File(entry.value);
    final exists = await file.exists();
    final perms = exists ? await describePermissions(entry.value) : null;
    ctx.out.writeln('  ${entry.key}：${exists ? '存在' : '不存在'}'
        '${perms == null ? '' : '（权限 $perms）'}  ${entry.value}');
  }
  ctx.out.writeln('账号数：${accounts.length}（其中允许 AI 取码：$allowed）');
  ctx.out.writeln('策略：默认拒绝，需逐账号 lzy_totp allow 放行');
  return ExitCode.ok;
}

Future<int> _mcp(CliContext ctx) async {
  final stream = ctx.stdinStream;
  if (stream == null) {
    ctx.err.writeln('mcp 命令需要在 stdio 模式下运行（stdin 不可用）。');
    return ExitCode.usage;
  }
  final server = McpServer(vault: ctx.vault, audit: ctx.audit);
  await server.serve(stream, ctx.out);
  return ExitCode.ok;
}

// --------------------------------------------------------------------- 辅助

class _Resolution {
  _Resolution(this.account, this.exitCode);

  final TotpAccount? account;
  final int? exitCode;
}

Future<_Resolution> _resolve(CliContext ctx, String query) async {
  final accounts = await ctx.vault.load();
  final matches = accounts.where((a) => a.matches(query)).toList();
  if (matches.isEmpty) {
    final available = accounts.map((a) => a.displayTitle).join('、');
    ctx.err.writeln('未找到账户「$query」。'
        '${available.isEmpty ? 'vault 为空。' : '可用账号：$available'}');
    return _Resolution(null, ExitCode.notFound);
  }
  if (matches.length > 1) {
    ctx.err.writeln('「$query」匹配到 ${matches.length} 个账户，请使用更精确的名称。');
    return _Resolution(null, ExitCode.usage);
  }
  return _Resolution(matches.single, null);
}

String? _firstArg(ArgResults cmd) {
  final rest = cmd.rest;
  if (rest.isEmpty) return null;
  final value = rest.first.trim();
  return value.isEmpty ? null : value;
}

Map<String, dynamic> _metadata(TotpAccount a) => {
      'account': a.displayTitle,
      'id': a.id,
      'issuer': a.issuer,
      'label': a.label,
      'digits': a.digits,
      'period': a.period,
      'algorithm': a.algorithm,
      'ai_allowed': a.aiAllowed,
    };

String _encode(Object value) => const JsonEncoder.withIndent('  ').convert(value);
