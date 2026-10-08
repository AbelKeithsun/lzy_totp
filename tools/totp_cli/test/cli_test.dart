import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:totp_cli/cli.dart';
import 'package:totp_cli/mcp_server.dart';
import 'package:totp_core/totp_core.dart';

import 'mcp_server_test.dart' show CaptureSink;

void main() {
  late Directory tmp;
  late TotpPaths paths;
  late VaultStore vault;
  late AuditLog audit;
  late CaptureSink out;
  late CaptureSink err;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('totp_cli_run_');
    paths = TotpPaths(tmp.path);
    vault = VaultStore(paths: paths);
    audit = AuditLog(paths.auditFile);
    out = CaptureSink();
    err = CaptureSink();
  });

  tearDown(() async {
    await out.close();
    await err.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  CliContext context({
    bool stdinIsTerminal = false,
    Confirm? confirm,
  }) =>
      CliContext(
        paths: paths,
        vault: vault,
        audit: audit,
        out: out.sink,
        err: err.sink,
        stdinIsTerminal: stdinIsTerminal,
        confirm: confirm,
      );

  Future<int> run(List<String> args, {CliContext? ctx}) async {
    out.clear();
    err.clear();
    final code = await runCli(args, ctx ?? context());
    await out.sink.flush();
    await err.sink.flush();
    return code;
  }

  group('CLI 基础命令', () {
    test('无参数时输出帮助并以 1 退出', () async {
      expect(await run([]), ExitCode.usage);
      expect(out.text, contains('lzy_totp'));
    });

    test('add + list + info', () async {
      expect(
        await run(['add', 'github', '--secret', 'JBSWY3DPEHPK3PXP', '--issuer', 'GitHub']),
        ExitCode.ok,
      );
      expect(out.text, contains('已添加'));

      expect(await run(['list']), ExitCode.ok);
      expect(out.text, contains('GitHub'));
      expect(out.text, contains('AI 允许'));

      expect(await run(['info', 'github']), ExitCode.ok);
      expect(out.text, contains('AI 取码：允许（默认）'));
    });

    test('add --uri 解析 otpauth', () async {
      final code = await run([
        'add',
        'google',
        '--uri',
        'otpauth://totp/Google:bob@gmail.com?secret=JBSWY3DPEHPK3PXP&issuer=Google',
      ]);
      expect(code, ExitCode.ok);
      final accounts = await vault.load();
      expect(accounts.single.issuer, 'Google');
      expect(accounts.single.label, 'bob@gmail.com');
    });

    test('非法密钥 / 同时给 secret 和 uri 都报错', () async {
      expect(await run(['add', 'x', '--secret', 'BAD!']), ExitCode.usage);
      expect(
        await run([
          'add',
          'y',
          '--secret',
          'JBSWY3DPEHPK3PXP',
          '--uri',
          'otpauth://totp/a:b?secret=JBSWY3DPEHPK3PXP',
        ]),
        ExitCode.usage,
      );
    });

    test('list --json 输出可解析且不含密钥', () async {
      await run(['add', 'github', '--secret', 'JBSWY3DPEHPK3PXP', '--issuer', 'GitHub']);
      await run(['list', '--json']);
      final parsed = jsonDecode(out.text) as Map<String, dynamic>;
      expect((parsed['accounts'] as List).first['account'], 'GitHub');
      expect(out.text.contains('JBSWY3DPEHPK3PXP'), isFalse);
    });

    test('未找到账户返回 3', () async {
      expect(await run(['info', 'nope']), ExitCode.notFound);
      expect(err.text, contains('未找到账户'));
    });
  });

  group('CLI 默认放行与黑名单', () {
    setUp(() async {
      // 默认放行：不加 --block-ai 即可被 AI 取码
      await run(['add', 'github', '--secret', 'JBSWY3DPEHPK3PXP', '--issuer', 'GitHub']);
      // 黑名单：显式禁止
      await run(['add', 'bank', '--secret', 'JBSWY3DPEHPK3PXP', '--issuer', 'Bank', '--block-ai']);
    });

    test('默认放行的账号直接可取码', () async {
      expect(await run(['code', 'github']), ExitCode.ok);
      expect(out.text.trim(), matches(RegExp(r'^\d{6}$')));
    });

    test('add --block-ai 的账号被拒绝取码（退出码 2），且不输出验证码', () async {
      expect(await run(['code', 'bank']), ExitCode.denied);
      expect(err.text, contains('拒绝取码'));
      expect(out.text, isNot(matches(RegExp(r'\b\d{6}\b'))));
    });

    test('非交互（AI 调用）时不会走人工确认通道', () async {
      var asked = false;
      final ctx = context(
        stdinIsTerminal: false,
        confirm: (_) async {
          asked = true;
          return true;
        },
      );
      expect(await run(['code', 'bank'], ctx: ctx), ExitCode.denied);
      expect(asked, isFalse, reason: 'AI 非交互调用不应弹出确认');
    });

    test('交互终端下人工确认后可以取码，并记录 override', () async {
      final ctx = context(
        stdinIsTerminal: true,
        confirm: (prompt) async {
          expect(prompt, contains('确认以人工身份查看'));
          return true;
        },
      );
      expect(await run(['code', 'bank'], ctx: ctx), ExitCode.ok);
      expect(out.text.trim(), matches(RegExp(r'^\d{6}$')));

      final entries = await audit.tail(5);
      expect(entries.last.result, 'ok');
      expect(entries.last.note, 'human-tty-override');
    });

    test('人工确认被拒绝时仍然拒绝取码', () async {
      final ctx = context(stdinIsTerminal: true, confirm: (_) async => false);
      expect(await run(['code', 'bank'], ctx: ctx), ExitCode.denied);
    });

    test('allow 恢复后可以取码（退出码 0）', () async {
      expect(await run(['allow', 'bank']), ExitCode.ok);
      expect(await run(['code', 'bank']), ExitCode.ok);
      final entries = await audit.tail(5);
      expect(
        entries.any((e) => e.action == 'set_ai_allowed' && e.result == 'ok'),
        isTrue,
      );
    });

    test('deny 默认放行的账号后立即拒绝', () async {
      expect(await run(['code', 'github']), ExitCode.ok);
      expect(await run(['deny', 'github']), ExitCode.ok);
      expect(await run(['code', 'github']), ExitCode.denied);
      expect(await run(['allow', 'github']), ExitCode.ok);
      expect(await run(['code', 'github']), ExitCode.ok);
    });

    test('code --json 输出结构化结果', () async {
      await run(['code', 'github', '--json']);
      final parsed = jsonDecode(out.text) as Map<String, dynamic>;
      expect(parsed['code'], matches(RegExp(r'^\d{6}$')));
      expect(parsed['remaining_seconds'], inInclusiveRange(1, 30));
      expect(parsed['account'], contains('GitHub'));
    });
  });

  group('CLI 运维命令', () {
    test('audit 展示记录', () async {
      await run(['add', 'github', '--secret', 'JBSWY3DPEHPK3PXP', '--issuer', 'GitHub']);
      await run(['audit']);
      expect(out.text, contains('add_account'));
    });

    test('doctor 输出路径与统计', () async {
      await run(['add', 'a', '--secret', 'JBSWY3DPEHPK3PXP']);
      await run(['add', 'b', '--secret', 'JBSWY3DPEHPK3PXP', '--block-ai']);
      expect(await run(['doctor']), ExitCode.ok);
      expect(out.text, contains('账号数：2（其中禁止 AI 取码：1）'));
      expect(out.text, contains('默认放行'));
    });

    test('remove 删除账号', () async {
      await run(['add', 'a', '--secret', 'JBSWY3DPEHPK3PXP']);
      expect(await run(['remove', 'a']), ExitCode.ok);
      expect(await vault.load(), isEmpty);
    });
  });

  group('CLI 作为 MCP 启动器', () {
    test('mcp 命令把 stdin 交给 MCP server 并输出协议响应', () async {
      await run(['add', 'github', '--secret', 'JBSWY3DPEHPK3PXP', '--issuer', 'GitHub']);

      final ctx = CliContext(
        paths: paths,
        vault: vault,
        audit: audit,
        out: out.sink,
        err: err.sink,
        stdinIsTerminal: false,
        stdinStream: Stream.fromIterable([
          utf8.encode('${jsonEncode({
                'jsonrpc': '2.0',
                'id': 1,
                'method': 'tools/call',
                'params': {
                  'name': 'generate_totp',
                  'arguments': {'account': 'github'},
                },
              })}\n'),
        ]),
      );
      expect(await runCli(['mcp'], ctx), ExitCode.ok);
      await out.sink.flush();

      final line = out.text.trim().split('\n').last;
      final response = jsonDecode(line) as Map<String, dynamic>;
      final text = (((response['result'] as Map)['content'] as List).first
          as Map)['text'] as String;
      expect(jsonDecode(text)['code'], matches(RegExp(r'^\d{6}$')));
    });

    test('McpServer 输出可被逐行解析（stdio transport）', () async {
      final sink = CaptureSink();
      final server = McpServer(vault: vault, audit: audit);
      await server.serve(
        Stream.fromIterable([
          utf8.encode('${jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': 'ping'})}\n'),
          utf8.encode('不是JSON\n'),
        ]),
        sink.sink,
      );
      await sink.sink.flush();
      final lines = sink.text.trim().split('\n');
      expect(lines, hasLength(2));
      expect(jsonDecode(lines[0])['result'], isEmpty);
      expect(jsonDecode(lines[1])['error']['code'], -32700);
      await sink.close();
    });
  });
}
