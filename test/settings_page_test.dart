import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lzy_totp/pages/settings_page.dart';

import 'support/fake_ai_settings.dart';
import 'support/fake_mcp_service.dart';
import 'support/fake_ai_vault.dart';
import 'support/fake_storage.dart';

void main() {
  /// 设置页较长，放大视口让内容一次性构建
  Future<void> pumpSettings(
    WidgetTester tester, {
    required FakeAiSettingsService settings,
    FakeAiVaultService? vault,
    FakeMcpService? mcp,
  }) async {
    tester.view.physicalSize = const Size(700, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: SettingsPage(
        aiSettings: settings,
        aiVault: vault ?? FakeAiVaultService(),
        mcpService: mcp ?? FakeMcpService(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// 点开关：busy 时会显示不断动画的进度条，
  /// 因此不能用 pumpAndSettle，要用显式 pump 等异步完成
  Future<void> tapSwitch(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(SwitchListTile, label));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
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
      // 两个开关：MCP 服务 + 取码权限
      expect(find.byType(SwitchListTile), findsNWidgets(2));
      expect(find.text('启动 MCP 服务'), findsOneWidget);
      expect(find.text('允许 AI / MCP 取码'), findsOneWidget);
      expect(find.textContaining('开启中'), findsOneWidget);
      expect(find.textContaining('2（其中禁止取码 1）'), findsOneWidget);
    });
  });

  testWidgets('关掉开关会持久化，并提示 CLI / MCP 立即被拒绝', (tester) async {
    await asMacOs(() async {
      final settings = FakeAiSettingsService();
      await pumpSettings(tester, settings: settings);

      await tapSwitch(tester, '允许 AI / MCP 取码');

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

      await tapSwitch(tester, '允许 AI / MCP 取码');

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

  testWidgets('启动 MCP 服务后显示地址与可直接粘贴的客户端配置', (tester) async {
    await asMacOs(() async {
      final mcp = FakeMcpService();
      await pumpSettings(tester, settings: FakeAiSettingsService(), mcp: mcp);

      // 未启动：只有说明，没有地址与片段
      expect(find.text('启动 MCP 服务'), findsOneWidget);
      expect(find.textContaining('已停止：agent 无法连接'), findsOneWidget);
      expect(find.textContaining('claude mcp add'), findsNothing);

      await tapSwitch(tester, '启动 MCP 服务');

      expect(mcp.startCount, 1);
      expect(mcp.isRunning, isTrue);
      expect(find.textContaining('运行中，agent 可以用下面地址接入'), findsOneWidget);
      // 地址 + 三种粘贴片段
      expect(
        find.textContaining('http://127.0.0.1:45763/mcp/deadbeef'),
        findsWidgets,
      );
      expect(find.textContaining('claude mcp add --transport http lzy_totp'),
          findsOneWidget);
      expect(find.textContaining('"mcpServers"'), findsOneWidget);
      expect(find.textContaining('transport: streamable-http'), findsOneWidget);
      expect(find.textContaining('关掉上面的开关 = 服务停止'), findsOneWidget);
      expect(find.text('复制全部'), findsOneWidget);
    });
  });

  testWidgets('停止 MCP 服务后地址与片段消失，并提示客户端会连不上', (tester) async {
    await asMacOs(() async {
      final mcp = FakeMcpService(running: true);
      await pumpSettings(tester,
          settings: FakeAiSettingsService(mcpEnabled: true), mcp: mcp);
      expect(find.textContaining('claude mcp add'), findsOneWidget);

      await tapSwitch(tester, '启动 MCP 服务');

      expect(mcp.stopCount, 1);
      expect(find.textContaining('已粘贴的客户端配置会连不上'), findsOneWidget);
      expect(find.textContaining('claude mcp add'), findsNothing);
    });
  });

  testWidgets('启动失败时提示错误并回滚开关', (tester) async {
    await asMacOs(() async {
      final mcp = FakeMcpService()..failWith = StateError('无法在本机端口上启动 MCP 服务');
      await pumpSettings(tester, settings: FakeAiSettingsService(), mcp: mcp);

      await tapSwitch(tester, '启动 MCP 服务');

      expect(mcp.isRunning, isFalse);
      expect(find.textContaining('启动 MCP 服务失败'), findsOneWidget);
      expect(find.textContaining('已停止：agent 无法连接'), findsOneWidget);
    });
  });

  testWidgets('复制片段会写剪贴板并提示', (tester) async {
    await asMacOs(() async {
      await pumpSettings(tester,
          settings: FakeAiSettingsService(mcpEnabled: true),
          mcp: FakeMcpService(running: true));

      await tester.tap(find.byTooltip('复制「Claude Code」'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Claude Code 已复制'), findsOneWidget);

      await tester.tap(find.text('复制全部'));
      await tester.pumpAndSettle();
      expect(find.textContaining('全部接入说明 已复制'), findsOneWidget);
    });
  });
}
