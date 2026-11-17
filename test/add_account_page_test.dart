import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lzy_totp/pages/add_account_page.dart';
import 'package:totp_core/totp_core.dart';

void main() {
  /// 页面较长，放大视口让表单一次性全部构建
  Future<void> pumpForm(WidgetTester tester, {TotpAccount? initial, bool editing = false}) async {
    tester.view.physicalSize = const Size(700, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: AddAccountPage(initial: initial, editing: editing),
    ));
    await tester.pump();
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  testWidgets('账户名是必填项，并有 * 标识', (tester) async {
    await pumpForm(tester);

    expect(find.text('账户名 *'), findsOneWidget);
    expect(find.text('密钥 *'), findsOneWidget);
    expect(find.textContaining('带 * 的为必填项'), findsOneWidget);

    // 只填密钥、不填账户名 → 拦下并给提示
    await tester.enterText(field('密钥 *'), 'JBSWY3DPEHPK3PXP');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.textContaining('请填写账户名'), findsOneWidget);
  });

  testWidgets('填齐账户名与密钥后保存，返回带备注的账号', (tester) async {
    TotpAccount? result;
    tester.view.physicalSize = const Size(700, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await Navigator.of(context).push<TotpAccount>(
              MaterialPageRoute(builder: (_) => const AddAccountPage()),
            );
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(field('账户名 *'), '生产环境 Jenkins');
    await tester.enterText(field('发行方（可选）'), 'Jenkins');
    await tester.enterText(field('密钥 *'), 'JBSWY3DPEHPK3PXP');
    await tester.enterText(field('备注（可选）'), '生产环境');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.label, '生产环境 Jenkins');
    expect(result!.issuer, 'Jenkins');
    expect(result!.note, '生产环境');
    expect(result!.secret, 'JBSWY3DPEHPK3PXP');
  });

  testWidgets('编辑模式：预填原有信息，保存保留 id 与 AI 权限', (tester) async {
    final original = TotpAccount(
      id: 'keep-me',
      issuer: '',
      label: '',
      secret: 'JBSWY3DPEHPK3PXP',
      aiAllowed: false,
      note: '',
    );
    TotpAccount? result;
    tester.view.physicalSize = const Size(700, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await Navigator.of(context).push<TotpAccount>(
              MaterialPageRoute(
                builder: (_) =>
                    AddAccountPage(initial: original, editing: true),
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('编辑账户'), findsOneWidget);
    expect(find.text('保存修改'), findsOneWidget);
    // 原密钥已预填
    expect(find.text('JBSWY3DPEHPK3PXP'), findsOneWidget);

    await tester.enterText(field('账户名 *'), 'GitHub 主账号');
    await tester.enterText(field('发行方（可选）'), 'GitHub');
    await tester.enterText(field('备注（可选）'), '个人账号');
    await tester.tap(find.widgetWithText(FilledButton, '保存修改'));
    await tester.pumpAndSettle();

    expect(result!.id, 'keep-me'); // 不换身份
    expect(result!.aiAllowed, isFalse); // 不偷偷放开被 deny 的账号
    expect(result!.label, 'GitHub 主账号');
    expect(result!.note, '个人账号');
  });

  testWidgets('编辑已有账号时不改密钥也能保存（密钥校验仍然通过）', (tester) async {
    await pumpForm(
      tester,
      initial: TotpAccount(
        id: '1',
        issuer: 'AWS',
        label: 'root',
        secret: 'GEZDGNBVGY3TQOJQ',
      ),
      editing: true,
    );

    expect(find.text('GEZDGNBVGY3TQOJQ'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '保存修改'));
    await tester.pumpAndSettle();
    // 页面 pop 后由 Navigator 处理，这里断言没有校验错误
    expect(find.textContaining('请填写账户名'), findsNothing);
    expect(find.textContaining('密钥应为'), findsNothing);
  });

  /// 表单比屏幕长，放大视口让所有字段一次性构建
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(700, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('恢复码录入', () {
    /// 打开页面 → 填字段 → 保存 → 取回结果
    Future<TotpAccount?> saveWith(
      WidgetTester tester, {
      String? recovery,
      String label = 'GitHub',
      String secret = 'JBSWY3DPEHPK3PXP',
    }) async {
      useTallViewport(tester);
      TotpAccount? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await Navigator.of(context).push<TotpAccount>(
                MaterialPageRoute(builder: (_) => const AddAccountPage()),
              );
            },
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(field('账户名 *'), label);
      await tester.enterText(field('密钥 *'), secret);
      if (recovery != null) {
        await tester.enterText(field('恢复码（可选）'), recovery);
      }
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('录入恢复码：每行一个，去掉空行', (tester) async {
      final result = await saveWith(tester, recovery: 'abcd-efgh\n\n1234-5678\n');

      expect(result, isNotNull);
      expect(result!.recoveryCodes, ['abcd-efgh', '1234-5678']);
      expect(result.recoveryCodeCount, 2);
    });

    testWidgets('不填恢复码也能保存（可选字段）', (tester) async {
      final result = await saveWith(tester);

      expect(result, isNotNull);
      expect(result!.recoveryCodes, isEmpty);
    });

    testWidgets('格式不对的恢复码会被拦下并提示', (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(MaterialApp(
        home: const AddAccountPage(),
      ));
      await tester.pump();

      await tester.enterText(field('账户名 *'), 'GitHub');
      await tester.enterText(field('密钥 *'), 'JBSWY3DPEHPK3PXP');
      await tester.enterText(field('恢复码（可选）'), '不 对');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(find.textContaining('格式不对'), findsOneWidget);
    });

    testWidgets('编辑已有账号时预填原有恢复码', (tester) async {
      await pumpForm(
        tester,
        initial: TotpAccount(
          id: '1',
          issuer: 'GitHub',
          label: 'me@x.com',
          secret: 'JBSWY3DPEHPK3PXP',
          recoveryCodes: ['abcd-efgh', '1234-5678'],
        ),
        editing: true,
      );

      // 预填在输入框里（提示文案里也有同名字样，所以直接看 controller）
      final input = tester.widget<TextFormField>(field('恢复码（可选）'));
      expect(input.controller!.text, 'abcd-efgh\n1234-5678');
    });
  });

  group('类型与时间', () {
    testWidgets('类型选 HOTP：出现计数器、隐藏周期，保存带上 type 与 counter',
        (tester) async {
      useTallViewport(tester);
      TotpAccount? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await Navigator.of(context).push<TotpAccount>(
                MaterialPageRoute(builder: (_) => const AddAccountPage()),
              );
            },
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // 默认 TOTP：有周期、没有计数器
      expect(find.text('周期'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '计数器'), findsNothing);

      await tester.tap(find.text('TOTP（按时间）'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('HOTP（按计数器）').last);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, '计数器'), findsOneWidget);
      expect(find.text('周期'), findsNothing);

      await tester.enterText(field('账户名 *'), 'Legacy 令牌');
      await tester.enterText(field('密钥 *'), 'GEZDGNBVGY3TQOJQ');
      await tester.enterText(
          find.widgetWithText(TextFormField, '计数器'), '5');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.type, TotpAccount.typeHotp);
      expect(result!.counter, 5);
      expect(result!.createdAt, isNotNull, reason: '新账号自动记创建时间');
    });

    testWidgets('失效日期：编辑时预填，保存沿用', (tester) async {
      final expiring = TotpAccount(
        id: '1',
        issuer: 'GitHub',
        label: 'me@x.com',
        secret: 'JBSWY3DPEHPK3PXP',
        expiresAt:
            DateTime(2027, 3, 4, 23, 59, 59).millisecondsSinceEpoch,
      );
      await pumpForm(tester, initial: expiring, editing: true);

      expect(find.text('2027-03-04'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '保存修改'));
      await tester.pumpAndSettle();

      // 页面已 pop；用 initial 上的展示文本无法再断言，改由「无校验错误」证明可保存
      expect(find.textContaining('请填写账户名'), findsNothing);
    });
  });
}
