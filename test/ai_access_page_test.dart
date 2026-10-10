import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lzy_totp/pages/ai_access_page.dart';

void main() {
  Future<void> pumpPage(WidgetTester tester) async {
    // 说明页较长，放大测试视口让 ListView 一次性构建全部内容（默认 800x600 会裁掉后半段）
    tester.view.physicalSize = const Size(1000, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: AiAccessPage()));
    await tester.pump();
  }

  testWidgets('AI 接入页介绍 CLI / MCP 两种接入方式', (tester) async {
    await pumpPage(tester);

    expect(find.text('AI 接入'), findsOneWidget);
    expect(find.textContaining('让 AI agent 帮你取验证码'), findsOneWidget);
    expect(find.textContaining('MCP server（推荐）', findRichText: true), findsOneWidget);
    expect(find.textContaining('App 内一键同步', findRichText: true), findsOneWidget);
    expect(find.textContaining('命令行 CLI', findRichText: true), findsOneWidget);

    // 三步接入
    expect(find.text('编译命令行工具'), findsOneWidget);
    expect(find.text('录入账号'), findsOneWidget);
    expect(find.text('配置 MCP 客户端'), findsOneWidget);
  });

  testWidgets('AI 接入页给出可直接复制的 MCP 配置与 CLI 命令', (tester) async {
    await pumpPage(tester);

    expect(find.textContaining('"mcpServers"'), findsOneWidget);
    expect(find.textContaining('"args": ["mcp"]'), findsOneWidget);
    expect(find.textContaining('lzy-totp code github --json'), findsWidgets);
    expect(find.textContaining('--block-ai'), findsWidgets);
    expect(find.textContaining('dart compile exe'), findsOneWidget);
  });

  testWidgets('AI 接入页列出全部 7 个 MCP 工具', (tester) async {
    await pumpPage(tester);

    expect(find.text('MCP 工具清单（7 个）'), findsOneWidget);
    for (final tool in [
      'list_accounts',
      'get_account_info',
      'generate_totp',
      'add_account',
      'add_from_uri',
      'remove_account',
      'set_ai_allowed',
    ]) {
      expect(find.text(tool), findsOneWidget, reason: '缺少工具 $tool');
    }
  });

  testWidgets('AI 接入页说明默认放行策略与安全边界', (tester) async {
    await pumpPage(tester);

    expect(find.text('安全边界（务必了解）'), findsOneWidget);
    expect(find.textContaining('默认放行 + 黑名单'), findsOneWidget);
    expect(find.textContaining('提示注入'), findsOneWidget);
    expect(find.textContaining('审计'), findsOneWidget);
  });

  testWidgets('代码块可一键复制', (tester) async {
    await pumpPage(tester);

    // 三个步骤卡片各有一个复制按钮
    expect(find.byIcon(Icons.copy), findsNWidgets(3));

    await tester.tap(find.byIcon(Icons.copy).first);
    await tester.pumpAndSettle();

    expect(find.text('安装命令已复制'), findsOneWidget);
  });
}
