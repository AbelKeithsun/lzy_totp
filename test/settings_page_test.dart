import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lzy_totp/pages/settings_page.dart';

import 'support/fake_ai_settings.dart';
import 'support/fake_ai_vault.dart';
import 'support/fake_storage.dart';

void main() {
  /// 设置页较长，放大视口让内容一次性构建
  Future<void> pumpSettings(
    WidgetTester tester, {
    required FakeAiSettingsService settings,
    FakeAiVaultService? vault,
  }) async {
    tester.view.physicalSize = const Size(700, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: SettingsPage(
        aiSettings: settings,
        aiVault: vault ?? FakeAiVaultService(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// 以 macOS（桌面端）跑一段测试：只有桌面端提供 AI 开关
  Future<void> asMacOs(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('桌面端：显示 AI / MCP 总开关与 vault 状态', (tester) async {
    await asMacOs(() async {
      final vault = FakeAiVaultService([
        testAccount('1', 'GitHub', 'me@github.com'),
        testAccount('2', 'Bank', 'me@bank.com').copyWith(aiAllowed: false),
      ]);
      await pumpSettings(tester,
          settings: FakeAiSettingsService(), vault: vault);

      expect(find.text('设置'), findsOneWidget);
      expect(find.byType(SwitchListTile), findsOneWidget);
      expect(find.text('允许 AI / MCP 取码'), findsOneWidget);
      expect(find.textContaining('开启中'), findsOneWidget);
      expect(find.textContaining('2（其中禁止取码 1）'), findsOneWidget);
      expect(find.textContaining('MCP server 不是一个常驻服务'), findsOneWidget);
    });
  });

  testWidgets('关掉开关会持久化，并提示 CLI / MCP 立即被拒绝', (tester) async {
    await asMacOs(() async {
      final settings = FakeAiSettingsService();
      await pumpSettings(tester, settings: settings);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(settings.enabled, isFalse);
      expect(settings.writeCount, 1);
      expect(find.textContaining('已关闭：CLI 读取与 MCP 全部工具都会被拒绝'), findsOneWidget);
      expect(find.textContaining('已关闭 AI / MCP 取码'), findsOneWidget);
      expect(find.textContaining('2（其中禁止取码'), findsNothing); // 本次 vault 为空
    });
  });

  testWidgets('写入失败时回滚开关状态并提示', (tester) async {
    await asMacOs(() async {
      final settings = FakeAiSettingsService()..failWith = Exception('磁盘只读');
      await pumpSettings(tester, settings: settings);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(settings.enabled, isTrue, reason: '写失败不应改变真实状态');
      expect(find.textContaining('保存失败'), findsOneWidget);
      expect(find.textContaining('开启中'), findsOneWidget);
    });
  });

  testWidgets('Android 上不提供开关（vault 在沙盒内）', (tester) async {
    final settings = FakeAiSettingsService();
    await pumpSettings(tester, settings: settings);

    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.textContaining('当前平台不支持'), findsOneWidget);
  });
}
