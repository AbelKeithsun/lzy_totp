import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lzy_totp/pages/account_list_page.dart';

import 'support/fake_ai_settings.dart';
import 'support/fake_ai_vault.dart';
import 'support/fake_storage.dart';

/// 回归：删除 / 同步后的「撤销」提示条不能挡住表单页的「保存」按钮。
///
/// 起因：SnackBar 由根 ScaffoldMessenger 统一派发，会同时画在**所有**已注册的
/// Scaffold 上——列表页和推入的表单页各有一块，于是列表页的「撤销」提示会浮到
/// 表单页底部，正好压住「保存」按钮。
void main() {
  Future<void> pumpList(WidgetTester tester, FakeStorage storage) async {
    tester.view.physicalSize = const Size(700, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: AccountListPage(
        storage: storage,
        aiVault: FakeAiVaultService(),
        aiSettings: FakeAiSettingsService(),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  /// 删除一个账号，让带「撤销」的提示条出现
  Future<void> deleteFirst(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除账户'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
  }

  /// 打开「手动添加」页
  Future<void> openAddPage(WidgetTester tester) async {
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('手动输入密钥'));
    await tester.pumpAndSettle();
  }

  testWidgets('「撤销」提示不跑到添加页去', (tester) async {
    final storage = FakeStorage([testAccount('1', 'GitHub', 'me@github.com')]);
    await pumpList(tester, storage);

    await deleteFirst(tester);
    expect(find.text('撤销'), findsOneWidget, reason: '列表页上应有撤销入口');

    await openAddPage(tester);

    expect(find.text('撤销'), findsNothing,
        reason: '撤销提示属于列表页，不该浮到添加页上');
  });

  testWidgets('添加页的「保存」按钮不会被任何浮层挡住', (tester) async {
    final storage = FakeStorage([testAccount('1', 'GitHub', 'me@github.com')]);
    await pumpList(tester, storage);

    await deleteFirst(tester);
    await openAddPage(tester);

    final save = find.widgetWithText(FilledButton, '保存');
    expect(save, findsOneWidget, reason: '「保存」固定在底部，不用滚动就能看到');

    // 提示条（若还在）不能和「保存」按钮重叠
    if (find.byType(SnackBar).evaluate().isNotEmpty) {
      final snackRect = tester.getRect(find.byType(SnackBar).first);
      final saveRect = tester.getRect(save);
      expect(snackRect.overlaps(saveRect), isFalse,
          reason: '提示条压住了「保存」按钮');
    }

    // 点「保存」要真的点到按钮，而不是被上层浮层吃掉
    await tester.enterText(
        find.widgetWithText(TextFormField, '账户名 *'), '新账号');
    await tester.enterText(
        find.widgetWithText(TextFormField, '密钥 *'), 'JBSWY3DPEHPK3PXP');
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('手动添加'), findsNothing, reason: '保存后应回到列表页');
    expect(storage.accounts.single.label, '新账号');
  });

  testWidgets('从添加页回到列表页后，删除仍可撤销', (tester) async {
    final storage = FakeStorage([testAccount('1', 'GitHub', 'me@github.com')]);
    await pumpList(tester, storage);

    await deleteFirst(tester);
    await openAddPage(tester);

    // 回到列表页（直接 pop）
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('撤销'), findsOneWidget, reason: '撤销入口应重新出现');
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    expect(storage.accounts.map((a) => a.id).toList(), ['1']);
  });
}
