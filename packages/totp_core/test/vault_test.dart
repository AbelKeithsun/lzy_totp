import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:totp_core/totp_core.dart';

void main() {
  late Directory tmp;
  late TotpPaths paths;
  late VaultStore vault;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('totp_core_test_');
    paths = TotpPaths(tmp.path);
    vault = VaultStore(paths: paths);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  TotpAccount account({bool aiAllowed = true, String secret = 'JBSWY3DPEHPK3PXP'}) =>
      TotpAccount(
        id: 'id-1',
        issuer: 'GitHub',
        label: 'me@x.com',
        secret: secret,
        digits: 6,
        period: 30,
        algorithm: 'SHA1',
        aiAllowed: aiAllowed,
      );

  group('加密 vault', () {
    test('vault 不存在时返回空列表，且不创建任何文件', () async {
      expect(await vault.load(), isEmpty);
      expect(await File(paths.vaultFile).exists(), isFalse);
      expect(await File(paths.keyFile).exists(), isFalse);
    });

    test('保存后往返一致', () async {
      await vault.save([account(aiAllowed: true)]);
      final loaded = (await vault.load()).single;
      expect(loaded.issuer, 'GitHub');
      expect(loaded.secret, 'JBSWY3DPEHPK3PXP');
      expect(loaded.aiAllowed, isTrue);
    });

    test('密钥在磁盘上是密文，明文不出现在文件里', () async {
      const secret = 'JBSWY3DPEHPK3PXP';
      await vault.save([account()]);
      final raw = await File(paths.vaultFile).readAsString();
      expect(raw.contains(secret), isFalse, reason: '明文密钥不得落盘');
      expect(raw.contains('enc:v1:'), isTrue, reason: '密钥字段应为密文');
      // 但元数据仍需可读，便于 list 操作
      final json = jsonDecode(raw) as Map<String, dynamic>;
      expect((json['accounts'] as List).first['issuer'], 'GitHub');
    });

    test('每次保存使用不同 nonce（相同明文密文不同）', () async {
      await vault.save([account()]);
      final first = await File(paths.vaultFile).readAsString();
      await vault.save([account()]);
      final second = await File(paths.vaultFile).readAsString();
      expect(first == second, isFalse);
    });

    test('vault 与密钥文件权限为 600', () async {
      await vault.save([account()]);
      expect(await describePermissions(paths.vaultFile), '600');
      expect(await describePermissions(paths.keyFile), '600');
    });

    test('密钥文件丢失时报 VaultError 而不是返回空/崩溃', () async {
      await vault.save([account()]);
      await File(paths.keyFile).delete();
      expect(
        () => vault.load(),
        throwsA(isA<VaultError>().having(
            (e) => e.message, 'message', contains('密钥文件缺失'))),
      );
    });

    test('密钥被换掉后解密失败报 VaultError', () async {
      await vault.save([account()]);
      await File(paths.keyFile).writeAsString(base64Encode(List.filled(32, 7)));
      expect(() => vault.load(), throwsA(isA<VaultError>()));
    });

    test('update 事务：读改写一次完成', () async {
      await vault.save([account()]);
      await vault.update((accounts) async {
        accounts.single.aiAllowed = true;
        return null;
      });
      expect((await vault.load()).single.aiAllowed, isTrue);
    });
  });

  group('AI 访问策略：默认放行 + 黑名单', () {
    test('新增账号默认允许 AI 取码', () {
      expect(TotpAccount.defaultAiAllowed, isTrue);
      expect(AiAccessPolicy.defaultAllow, TotpAccount.defaultAiAllowed);
      expect(AiAccessPolicy.allows(account()), isTrue);
      expect(AiAccessPolicy.denialReason(account()), isNull);
    });

    test('显式禁止后才拒绝，且给出恢复指引', () {
      final blocked = account(aiAllowed: false);
      expect(AiAccessPolicy.allows(blocked), isFalse);
      expect(AiAccessPolicy.denialReason(blocked), contains('已被显式禁止'));
      expect(AiAccessPolicy.denialReason(blocked), contains('lzy-totp allow'));
    });

    test('禁止标记可随 vault 持久化', () async {
      await vault.save([account(aiAllowed: false)]);
      expect((await vault.load()).single.aiAllowed, isFalse);
    });
  });

  group('审计日志', () {
    test('追加写入并可读取最近记录', () async {
      final audit = AuditLog(paths.auditFile);
      await audit.append(AuditEntry(action: 'generate_totp', result: 'ok', account: 'GitHub'));
      await audit.append(AuditEntry(
          action: 'generate_totp', result: 'denied', account: 'Bank', actor: 'mcp'));

      final tail = await audit.tail(10);
      expect(tail, hasLength(2));
      expect(tail.first.result, 'ok');
      expect(tail.last.result, 'denied');
      expect(tail.last.actor, 'mcp');
      expect(await describePermissions(paths.auditFile), '600');
    });

    test('tail 只返回最近 N 条', () async {
      final audit = AuditLog(paths.auditFile);
      for (var i = 0; i < 5; i++) {
        await audit.append(AuditEntry(action: 'a$i', result: 'ok'));
      }
      final tail = await audit.tail(2);
      expect(tail.map((e) => e.action), ['a3', 'a4']);
    });
  });
  _noteFieldTests();
}

void _noteFieldTests() {
  group('账户备注（note）', () {
    test('JSON 往返保留备注，旧数据没有该字段时回退为空串', () {
      final account = TotpAccount(
        id: '1',
        issuer: 'Jenkins',
        label: '生产环境',
        secret: 'JBSWY3DPEHPK3PXP',
        note: '生产环境 / 需要审批后才取码',
      );
      final restored =
          TotpAccount.decodeList(TotpAccount.encodeList([account])).single;
      expect(restored.note, '生产环境 / 需要审批后才取码');
      expect(restored.displayTitle, 'Jenkins (生产环境)');

      // 兼容历史数据（没有 note 字段）
      final legacy = TotpAccount.fromJson({
        'id': '2',
        'issuer': 'GitHub',
        'label': 'me@github.com',
        'secret': 'JBSWY3DPEHPK3PXP',
      });
      expect(legacy.note, '');
    });

    test('copyWith 能改任意字段且保留其余字段', () {
      final account = TotpAccount(
        id: '1',
        issuer: 'GitHub',
        label: 'me@github.com',
        secret: 'JBSWY3DPEHPK3PXP',
        note: 'x',
      );
      final renamed = account.copyWith(label: 'work@github.com', note: '工作');
      expect(renamed.id, '1');
      expect(renamed.issuer, 'GitHub');
      expect(renamed.secret, 'JBSWY3DPEHPK3PXP');
      expect(renamed.label, 'work@github.com');
      expect(renamed.note, '工作');
    });
  });
}
