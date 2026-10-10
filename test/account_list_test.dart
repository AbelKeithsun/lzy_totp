import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lzy_totp/pages/account_list_page.dart';
import 'package:totp_core/totp_core.dart';

import 'support/fake_ai_vault.dart';
import 'support/fake_storage.dart';

void main() {
  /// 首页带每秒刷新的 Timer，测试结束前必须卸载组件树把它取消掉
  Future<void> pumpList(
    WidgetTester tester,
    FakeStorage storage, {
    FakeAiVaultService? aiVault,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: AccountListPage(storage: storage, aiVault: aiVault),
    ));
    await tester.pump();
  }

  /// 以 macOS（桌面端）跑一段测试：App→vault 同步只在桌面端出现。
  /// debug 变量必须在测试体内复位，框架会在 tearDown 之前校验。
  Future<void> asMacOs(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
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
    await asMacOs(() async {
      final storage = FakeStorage([testAccount('1', 'GitHub', 'me@github.com')]);
      await pumpList(tester, storage, aiVault: FakeAiVaultService());

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
    });
  });

  testWidgets('点一下同步图标：账号写入 AI vault 并提示', (tester) async {
    await asMacOs(() async {
      final storage = FakeStorage([testAccount('1', 'GitHub', 'me@github.com')]);
      final vault = FakeAiVaultService();
      await pumpList(tester, storage, aiVault: vault);

      expect(vault.accounts, isEmpty);
      expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.cloud_upload_outlined));
      await tester.pumpAndSettle();

      expect(vault.accounts.length, 1);
      expect(vault.accounts.single.displayTitle, 'GitHub (me@github.com)');
      expect(vault.accounts.single.aiAllowed, isTrue);
      expect(find.textContaining('已同步给 AI'), findsOneWidget);
      // 图标变成「AI 可读取」
      expect(find.byIcon(Icons.cloud_done), findsOneWidget);

      await unmount(tester);
    });
  });

  testWidgets('已同步时点一下：从 vault 移除但 App 内保留', (tester) async {
    await asMacOs(() async {
      final account = testAccount('1', 'GitHub', 'me@github.com');
      final storage = FakeStorage([account]);
      final vault = FakeAiVaultService([account]);
      await pumpList(tester, storage, aiVault: vault);

      expect(find.byIcon(Icons.cloud_done), findsOneWidget);

      await tester.tap(find.byIcon(Icons.cloud_done));
      await tester.pumpAndSettle();

      expect(vault.accounts, isEmpty);
      expect(find.textContaining('已取消 AI 读取'), findsOneWidget);
      // App 内的账号还在
      expect(storage.accounts.length, 1);
      expect(find.text('GitHub (me@github.com)'), findsOneWidget);

      await unmount(tester);
    });
  });

  testWidgets('被 lzy-totp deny 的账号：显示禁止状态，点一下只给说明不改数据', (tester) async {
    await asMacOs(() async {
      final account = testAccount('1', 'Bank', 'me@bank.com');
      final storage = FakeStorage([account]);
      final vault = FakeAiVaultService([account.copyWith(aiAllowed: false)]);
      await pumpList(tester, storage, aiVault: vault);

      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
      expect(find.byIcon(Icons.cloud_done), findsNothing);

      await tester.tap(find.byIcon(Icons.cloud_off));
      await tester.pumpAndSettle();

      expect(find.textContaining('已被 lzy-totp deny 禁止'), findsOneWidget);
      expect(vault.unlinkCount, 0);
      expect(vault.accounts.length, 1);

      await unmount(tester);
    });
  });

  testWidgets('同步后可撤销（撤销即从 vault 撤回）', (tester) async {
    await asMacOs(() async {
      final storage = FakeStorage([testAccount('1', 'GitHub', 'me@github.com')]);
      final vault = FakeAiVaultService();
      await pumpList(tester, storage, aiVault: vault);

      await tester.tap(find.byIcon(Icons.cloud_upload_outlined));
      await tester.pumpAndSettle();
      expect(vault.accounts.length, 1);

      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();

      expect(vault.accounts, isEmpty);
      expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);

      await unmount(tester);
    });
  });

  testWidgets('⋮ 菜单里也有同步给 AI', (tester) async {
    await asMacOs(() async {
      final storage = FakeStorage([testAccount('1', 'GitHub', 'me@github.com')]);
      final vault = FakeAiVaultService();
      await pumpList(tester, storage, aiVault: vault);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('同步给 AI'));
      await tester.pumpAndSettle();

      expect(vault.accounts.length, 1);

      await unmount(tester);
    });
  });

  testWidgets('vault 写入失败时给出错误提示而不是崩溃', (tester) async {
    await asMacOs(() async {
      final storage = FakeStorage([testAccount('1', 'GitHub', 'me@github.com')]);
      final vault = FakeAiVaultService()
        ..failWith = VaultError('密钥文件缺失：vault.key');
      await pumpList(tester, storage, aiVault: vault);

      await tester.tap(find.byIcon(Icons.cloud_upload_outlined));
      await tester.pumpAndSettle();

      expect(find.textContaining('同步失败'), findsOneWidget);
      expect(find.textContaining('密钥文件缺失'), findsOneWidget);

      await unmount(tester);
    });
  });

  testWidgets('Android 上不出现同步入口（vault 在沙盒内，AI 读不到）', (tester) async {
    final storage = FakeStorage([testAccount('1', 'GitHub', 'me@github.com')]);
    await pumpList(tester, storage, aiVault: FakeAiVaultService());

    expect(find.byIcon(Icons.cloud_upload_outlined), findsNothing);
    expect(find.byIcon(Icons.cloud_done), findsNothing);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('同步给 AI'), findsNothing);
    expect(find.text('复制验证码'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('⋮ 菜单可编辑账户：补上账户名后列表与存储都更新', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 模拟历史遗留：没有账户名的账号
    final storage = FakeStorage([
      TotpAccount(id: '1', issuer: '', label: '', secret: 'JBSWY3DPEHPK3PXP'),
    ]);
    await pumpList(tester, storage, aiVault: FakeAiVaultService());

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑账户'));
    await tester.pumpAndSettle();

    expect(find.text('保存修改'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextFormField, '账户名 *'), '生产环境 Jenkins');
    await tester.enterText(
        find.widgetWithText(TextFormField, '发行方（可选）'), 'Jenkins');
    await tester.enterText(
        find.widgetWithText(TextFormField, '备注（可选）'), '生产环境');
    await tester.tap(find.widgetWithText(FilledButton, '保存修改'));
    await tester.pumpAndSettle();

    expect(find.text('Jenkins (生产环境 Jenkins)'), findsOneWidget);
    expect(find.text('# 生产环境'), findsOneWidget);
    expect(storage.accounts.single.label, '生产环境 Jenkins');
    expect(storage.accounts.single.issuer, 'Jenkins');
    expect(storage.accounts.single.note, '生产环境');

    await unmount(tester);
  });

  testWidgets('已同步给 AI 的账号改名后，vault 里的条目同步更新', (tester) async {
    await asMacOs(() async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final account = testAccount('1', 'GitHub', 'me@github.com');
      final storage = FakeStorage([account]);
      final vault = FakeAiVaultService([account]);
      await pumpList(tester, storage, aiVault: vault);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑账户'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, '账户名 *'), 'work@github.com');
      await tester.enterText(
          find.widgetWithText(TextFormField, '备注（可选）'), '工作账号');
      await tester.tap(find.widgetWithText(FilledButton, '保存修改'));
      await tester.pumpAndSettle();

      expect(vault.accounts.single.label, 'work@github.com');
      expect(vault.accounts.single.note, '工作账号');
      expect(find.textContaining('更新了 vault'), findsOneWidget);

      await unmount(tester);
    });
  });

  testWidgets('编辑已被 deny 的已同步账号，不会把它改回可读', (tester) async {
    await asMacOs(() async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final account = testAccount('1', 'Bank', 'me@bank.com');
      final storage = FakeStorage([account]);
      final vault = FakeAiVaultService([account.copyWith(aiAllowed: false)]);
      await pumpList(tester, storage, aiVault: vault);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑账户'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, '备注（可选）'), '银行卡');
      await tester.tap(find.widgetWithText(FilledButton, '保存修改'));
      await tester.pumpAndSettle();

      expect(vault.accounts.single.aiAllowed, isFalse);
      expect(vault.accounts.single.note, '银行卡');
      // 行内图标仍是「已被 deny」状态
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);

      await unmount(tester);
    });
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
