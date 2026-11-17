import 'package:test/test.dart';
import 'package:totp_core/totp_core.dart';

void main() {
  group('otpauth URI 解析', () {
    test('完整 URI', () {
      final acc = TotpAccount.fromOtpAuthUri(
        'otpauth://totp/GitHub:user@example.com?secret=JBSWY3DPEHPK3PXP&issuer=GitHub&digits=6&period=30',
      );
      expect(acc, isNotNull);
      expect(acc!.issuer, 'GitHub');
      expect(acc.label, 'user@example.com');
      expect(acc.secret, 'JBSWY3DPEHPK3PXP');
      expect(acc.digits, 6);
      expect(acc.period, 30);
      expect(acc.algorithm, 'SHA1');
      expect(acc.aiAllowed, isTrue, reason: '默认放行 AI 访问');
    });

    test('无 issuer 参数时从 label 前缀取', () {
      final acc = TotpAccount.fromOtpAuthUri(
        'otpauth://totp/Google:bob@gmail.com?secret=JBSWY3DPEHPK3PXP',
      );
      expect(acc!.issuer, 'Google');
      expect(acc.label, 'bob@gmail.com');
    });

    test('secret 容忍空格与小写', () {
      final acc = TotpAccount.fromOtpAuthUri(
        'otpauth://totp/a:b?secret=jbsw y3dp ehpk 3pxp',
      );
      expect(acc!.secret, 'JBSWY3DPEHPK3PXP');
    });

    test('非 otpauth / 未知类型 / 缺 secret 均拒绝', () {
      expect(TotpAccount.fromOtpAuthUri('https://example.com'), isNull);
      expect(
        TotpAccount.fromOtpAuthUri('otpauth://motp/a:b?secret=JBSWY3DPEHPK3PXP'),
        isNull,
      );
      expect(TotpAccount.fromOtpAuthUri('otpauth://totp/a:b'), isNull);
      // hotp 现在是支持的（旧版本会拒绝）
      final hotp = TotpAccount.fromOtpAuthUri(
        'otpauth://hotp/a:b?secret=JBSWY3DPEHPK3PXP',
      );
      expect(hotp, isNotNull);
      expect(hotp!.isHotp, isTrue);
      expect(hotp.counter, 0);
    });
  });

  group('TOTP 计算（RFC 6238 附录 B 测试向量，8 位）', () {
    TotpAccount acc(String seedBase32, String algo) => TotpAccount(
          id: 't',
          issuer: '',
          label: '',
          secret: seedBase32,
          digits: 8,
          algorithm: algo,
        );

    final at59 = DateTime.fromMillisecondsSinceEpoch(59 * 1000, isUtc: true);

    test('SHA1, T=59s → 94287082', () {
      expect(
        TotpService.codeFor(
          acc('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ', 'SHA1'),
          now: at59,
        ),
        '94287082',
      );
    });

    test('SHA256, T=59s → 46119246', () {
      expect(
        TotpService.codeFor(
          acc('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA', 'SHA256'),
          now: at59,
        ),
        '46119246',
      );
    });

    test('SHA512, T=59s → 90693936', () {
      expect(
        TotpService.codeFor(
          acc(
              'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNA',
              'SHA512'),
          now: at59,
        ),
        '90693936',
      );
    });

    test('剩余秒数与进度', () {
      final at10 = DateTime.fromMillisecondsSinceEpoch(10 * 1000, isUtc: true);
      expect(TotpService.remainingSeconds(period: 30, now: at10), 20);
      expect(TotpService.progress(period: 30, now: at10), closeTo(1 / 3, 1e-9));
    });
  });

  group('HOTP 计算（RFC 4226 附录 D 测试向量）', () {
    // 密钥是 ASCII "12345678901234567890" 的 base32
    const secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
    const vectors = {
      0: '755224',
      1: '287082',
      2: '359152',
      3: '969429',
      4: '338314',
      5: '254676',
      6: '287922',
      7: '162583',
      8: '399871',
      9: '520489',
    };

    test('计数器 0..9 的码与 RFC 向量一致', () {
      for (final entry in vectors.entries) {
        final account = TotpAccount(
          id: 'h',
          issuer: 'Legacy',
          label: 'token',
          secret: secret,
          type: TotpAccount.typeHotp,
          counter: entry.key,
        );
        expect(TotpService.codeFor(account), entry.value,
            reason: 'counter=${entry.key}');
      }
    });

    test('HOTP 不受当前时间影响（同一计数器两次取码相同）', () {
      final account = TotpAccount(
        id: 'h',
        issuer: '',
        label: 'token',
        secret: secret,
        type: TotpAccount.typeHotp,
        counter: 3,
      );
      final a = TotpService.codeFor(account, now: DateTime(2020, 1, 1));
      final b = TotpService.codeFor(account, now: DateTime(2030, 1, 1));
      expect(a, b);
      expect(a, '969429');
    });

    test('计数器 +1 后换成下一个码', () {
      final account = TotpAccount(
        id: 'h',
        issuer: '',
        label: 'token',
        secret: secret,
        type: TotpAccount.typeHotp,
      );
      expect(TotpService.codeFor(account), '755224');
      expect(TotpService.codeFor(account.advanceCounter()), '287082');
    });
  });

  group('otpauth://hotp 解析', () {
    test('hotp URI 带 counter 参数', () {
      final acc = TotpAccount.fromOtpAuthUri(
        'otpauth://hotp/Legacy:token?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&counter=5',
      );
      expect(acc, isNotNull);
      expect(acc!.type, TotpAccount.typeHotp);
      expect(acc.isHotp, isTrue);
      expect(acc.counter, 5);
      expect(acc.issuer, 'Legacy');
      expect(acc.label, 'token');
    });

    test('totp URI 仍是 totp 且 counter 为 0', () {
      final acc = TotpAccount.fromOtpAuthUri(
        'otpauth://totp/GitHub:me@x.com?secret=JBSWY3DPEHPK3PXP',
      );
      expect(acc!.type, TotpAccount.typeTotp);
      expect(acc.counter, 0);
    });
  });

  group('账户 JSON 序列化', () {
    test('往返一致（含 aiAllowed）', () {
      final original = TotpAccount(
        id: '1',
        issuer: 'GitHub',
        label: 'me@x.com',
        secret: 'JBSWY3DPEHPK3PXP',
        digits: 8,
        period: 60,
        algorithm: 'SHA256',
        aiAllowed: true,
      );
      final decoded =
          TotpAccount.decodeList(TotpAccount.encodeList([original])).single;
      expect(decoded.issuer, 'GitHub');
      expect(decoded.digits, 8);
      expect(decoded.algorithm, 'SHA256');
      expect(decoded.aiAllowed, isTrue);
    });

    test('旧数据无 aiAllowed 字段时按默认（放行）处理', () {
      final decoded = TotpAccount.decodeList(
        '[{"id":"1","issuer":"G","label":"a","secret":"JBSWY3DPEHPK3PXP"}]',
      ).single;
      expect(decoded.aiAllowed, TotpAccount.defaultAiAllowed);
      expect(decoded.digits, 6);
    });
  });

  group('恢复码', () {
    test('JSON 往返保留恢复码与已用恢复码', () {
      final original = TotpAccount(
        id: '1',
        issuer: 'GitHub',
        label: 'me@x.com',
        secret: 'JBSWY3DPEHPK3PXP',
        recoveryCodes: ['abcd-efgh', '1234-5678'],
        usedRecoveryCodes: ['zzzz-9999'],
      );
      final decoded =
          TotpAccount.decodeList(TotpAccount.encodeList([original])).single;
      expect(decoded.recoveryCodes, ['abcd-efgh', '1234-5678']);
      expect(decoded.usedRecoveryCodes, ['zzzz-9999']);
      expect(decoded.recoveryCodeCount, 2);
      expect(decoded.hasRecoveryCodes, isTrue);
    });

    test('旧数据没有恢复码字段时按空处理', () {
      final decoded = TotpAccount.decodeList(
        '[{"id":"1","issuer":"G","label":"a","secret":"JBSWY3DPEHPK3PXP"}]',
      ).single;
      expect(decoded.recoveryCodes, isEmpty);
      expect(decoded.usedRecoveryCodes, isEmpty);
      expect(decoded.hasRecoveryCodes, isFalse);
    });

    test('归一化：去空白、丢空行、去重、保留原文大小写', () {
      final codes = TotpAccount.normalizeRecoveryCodes([
        ' abcd-efgh ',
        '',
        '   ',
        'ABCD-EFGH',
        '1234-5678',
      ]);
      expect(codes, ['abcd-efgh', 'ABCD-EFGH', '1234-5678']);
    });

    test('形状校验：字母数字与 - _，至少 4 位', () {
      expect(TotpAccount.isValidRecoveryCode('abcd-efgh'), isTrue);
      expect(TotpAccount.isValidRecoveryCode('12345678'), isTrue);
      expect(TotpAccount.isValidRecoveryCode('ab_12'), isTrue);
      expect(TotpAccount.isValidRecoveryCode('abc'), isFalse, reason: '太短');
      expect(TotpAccount.isValidRecoveryCode('ab cd'), isFalse, reason: '含空格');
      expect(TotpAccount.isValidRecoveryCode('密码'), isFalse, reason: '非 ASCII');
    });

    test('标记已用：从未使用列表移到已用列表，原对象不变', () {
      final account = TotpAccount(
        id: '1',
        issuer: '',
        label: 'a',
        secret: 'JBSWY3DPEHPK3PXP',
        recoveryCodes: ['abcd-efgh', '1234-5678'],
      );
      final used = account.markRecoveryCodeUsed('abcd-efgh');
      expect(used.recoveryCodes, ['1234-5678']);
      expect(used.usedRecoveryCodes, ['abcd-efgh']);
      expect(account.recoveryCodes, hasLength(2), reason: '原对象不应被修改');
    });

    test('删除恢复码：从未用与已用两侧都能删', () {
      final account = TotpAccount(
        id: '1',
        issuer: '',
        label: 'a',
        secret: 'JBSWY3DPEHPK3PXP',
        recoveryCodes: ['abcd-efgh'],
        usedRecoveryCodes: ['zzzz-9999'],
      );
      final removed = account.removeRecoveryCode('zzzz-9999');
      expect(removed.usedRecoveryCodes, isEmpty);
      expect(removed.recoveryCodes, ['abcd-efgh']);
    });
  });

  group('类型与时间字段', () {
    test('JSON 往返保留 type / counter / 三个时间', () {
      final created = DateTime(2026, 1, 2, 3, 4).millisecondsSinceEpoch;
      final used = DateTime(2026, 2, 3, 4, 5).millisecondsSinceEpoch;
      final expires = DateTime(2027, 3, 4, 23, 59, 59).millisecondsSinceEpoch;
      final original = TotpAccount(
        id: '1',
        issuer: 'Legacy',
        label: 'token',
        secret: 'GEZDGNBVGY3TQOJQ',
        type: TotpAccount.typeHotp,
        counter: 7,
        createdAt: created,
        lastUsedAt: used,
        expiresAt: expires,
      );
      final decoded =
          TotpAccount.decodeList(TotpAccount.encodeList([original])).single;
      expect(decoded.type, TotpAccount.typeHotp);
      expect(decoded.isHotp, isTrue);
      expect(decoded.counter, 7);
      expect(decoded.createdAt, created);
      expect(decoded.lastUsedAt, used);
      expect(decoded.expiresAt, expires);
      expect(decoded.createdAtTime!.year, 2026);
    });

    test('旧数据没有新字段时按 totp / 0 / 未知时间处理', () {
      final decoded = TotpAccount.decodeList(
        '[{"id":"1","issuer":"G","label":"a","secret":"JBSWY3DPEHPK3PXP"}]',
      ).single;
      expect(decoded.type, TotpAccount.typeTotp);
      expect(decoded.isHotp, isFalse);
      expect(decoded.counter, 0);
      expect(decoded.createdAt, isNull);
      expect(decoded.lastUsedAt, isNull);
      expect(decoded.expiresAt, isNull);
      expect(decoded.isExpired, isFalse);
    });

    test('type 值非法时回退为 totp', () {
      final decoded = TotpAccount.fromJson({
        'id': '1',
        'issuer': 'G',
        'label': 'a',
        'secret': 'JBSWY3DPEHPK3PXP',
        'type': 'whatever',
      });
      expect(decoded.type, TotpAccount.typeTotp);
    });

    test('有效期：过去为已过期，未来为未过期', () {
      final past = TotpAccount(
        id: '1',
        issuer: '',
        label: 'a',
        secret: 'JBSWY3DPEHPK3PXP',
        expiresAt: DateTime.now()
            .subtract(const Duration(days: 1))
            .millisecondsSinceEpoch,
      );
      final future = TotpAccount(
        id: '2',
        issuer: '',
        label: 'b',
        secret: 'JBSWY3DPEHPK3PXP',
        expiresAt:
            DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
      );
      expect(past.isExpired, isTrue);
      expect(future.isExpired, isFalse);
    });

    test('touch 记录取码时间且不动计数器；advanceCounter 只动 HOTP', () {
      final totp = TotpAccount(
        id: '1',
        issuer: '',
        label: 'a',
        secret: 'JBSWY3DPEHPK3PXP',
      );
      final t = DateTime(2026, 5, 6, 7, 8);
      final touched = totp.touch(now: t);
      expect(touched.lastUsedAt, t.millisecondsSinceEpoch);
      expect(touched.counter, 0);
      expect(totp.advanceCounter().counter, 0, reason: 'TOTP 不推进计数');

      final hotp = totp.copyWith(type: TotpAccount.typeHotp, counter: 3);
      expect(hotp.advanceCounter().counter, 4);
      expect(hotp.touch(now: t).counter, 3, reason: 'touch 不改计数');
    });
  });

  group('账户名匹配', () {
    test('支持 id / issuer / label / 组合标题，大小写不敏感', () {
      final a = TotpAccount(
        id: 'abc123',
        issuer: 'GitHub',
        label: 'me@x.com',
        secret: 'JBSWY3DPEHPK3PXP',
      );
      expect(a.matches('abc123'), isTrue);
      expect(a.matches('github'), isTrue);
      expect(a.matches('ME@X.COM'), isTrue);
      expect(a.matches('GitHub (me@x.com)'), isTrue);
      expect(a.matches('gitlab'), isFalse);
    });
  });
}
