import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lzy_totp/pages/account_list_page.dart';

import 'support/fake_storage.dart';

void main() {
  /// 首页带每秒刷新的 Timer，测试结束前必须卸载组件树把它取消掉
  Future<void> pumpList(WidgetTester tester, FakeStorage storage) async {
    await tester.pumpWidget(MaterialApp(home: AccountListPage(storage: storage)));
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox());

  testWidgets('每个账户都提供显式的删除入口（⋮ 菜单）', (tester) async {
    final storage = FakeStorage([
      testAccount('1', 'GitHub', 'me@github.com'),
      testAccount('2', 'Google', 'me@gmail.com'),
    ]);
    await pumpList(tester, storage);

    expect(find.byIcon(Icons.more_vert), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    expect(find.text('复制验证码'), findsOneWidget);
    expect(find.text('删除账户'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('菜单删除：确认后从列表移除并落库', (tester) async {
    final storage = FakeStorage([
      testAccount('1', 'GitHub', 'me@github.com'),
      testAccount('2', 'Google', 'me@gmail.com'),
    ]);
    await pumpList(tester, storage);

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除账户'));
    await tester.pumpAndSettle();

    // 二次确认
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('确定删除「GitHub (me@github.com)」'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(find.text('GitHub (me@github.com)'), findsNothing);
    expect(find.text('Google (me@gmail.com)'), findsOneWidget);
    expect(storage.accounts.map((a) => a.id).toList(), ['2']);
    expect(storage.saveCount, 1);
    expect(find.textContaining('已删除「GitHub'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('菜单删除：取消则不动数据', (tester) async {
    final storage = FakeStorage([testAccount('1', 'GitHub', 'me@github.com')]);
    await pumpList(tester, storage);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除账户'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    expect(find.text('GitHub (me@github.com)'), findsOneWidget);
    expect(storage.accounts.length, 1);
    expect(storage.saveCount, 0);

    await unmount(tester);
  });

  testWidgets('删除后可「撤销」，账户回到原来的位置', (tester) async {
    final storage = FakeStorage([
      testAccount('1', 'GitHub', 'me@github.com'),
      testAccount('2', 'Google', 'me@gmail.com'),
      testAccount('3', 'AWS', 'root'),
    ]);
    await pumpList(tester, storage);

    await tester.tap(find.byIcon(Icons.more_vert).at(1)); // Google
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除账户'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(storage.accounts.map((a) => a.id).toList(), ['1', '3']);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    expect(storage.accounts.map((a) => a.id).toList(), ['1', '2', '3']);
    expect(find.text('Google (me@gmail.com)'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('长按列表项弹出操作面板，也能删除', (tester) async {
    final storage = FakeStorage([testAccount('1', 'GitHub', 'me@github.com')]);
    await pumpList(tester, storage);

    await tester.longPress(find.text('GitHub (me@github.com)'));
    await tester.pumpAndSettle();
    expect(find.text('复制验证码'), findsOneWidget);

    await tester.tap(find.text('删除账户'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(find.textContaining('还没有账户'), findsOneWidget);
    expect(storage.accounts, isEmpty);

    await unmount(tester);
  });

  testWidgets('左滑删除仍然可用（保持旧交互）', (tester) async {
    final storage = FakeStorage([testAccount('1', 'GitHub', 'me@github.com')]);
    await pumpList(tester, storage);

    await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(storage.accounts, isEmpty);
    expect(find.textContaining('还没有账户'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('倒计时圆环显示剩余比例（周期起点是满环而非空环）', (tester) async {
    final storage = FakeStorage([testAccount('1', 'GitHub', 'me@github.com')]);
    await pumpList(tester, storage);

    // 回归：曾经误用 TotpService.progress()（已过去比例），周期起点 value=0.0 直接画不出圆环
    final ring = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(ring.value, isNotNull);
    expect(ring.value!, greaterThan(0.0));
    expect(ring.value!, lessThanOrEqualTo(1.0));

    await unmount(tester);
  });

  testWidgets('桌面端（macOS）：显式复制按钮与 ⋮ 删除入口并存', (tester) async {
    // 必须在测试体内复位：框架会在 tearDown 之前校验 debug 变量是否被改动
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final storage = FakeStorage([testAccount('1', 'GitHub', 'me@github.com')]);
      await pumpList(tester, storage);

      expect(find.byIcon(Icons.copy), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除账户'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(storage.accounts, isEmpty);

      await unmount(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('顶部入口可打开 AI 接入说明页', (tester) async {
    final storage = FakeStorage();
    await pumpList(tester, storage);

    await tester.tap(find.byIcon(Icons.smart_toy_outlined).first);
    await tester.pumpAndSettle();

    expect(find.text('AI 接入'), findsOneWidget);
    expect(find.textContaining('让 AI agent 帮你取验证码'), findsOneWidget);

    await unmount(tester);
  });
}
