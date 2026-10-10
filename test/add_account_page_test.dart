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
}
