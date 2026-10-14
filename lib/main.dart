import 'dart:async';

import 'package:flutter/material.dart';

import 'pages/account_list_page.dart';
import 'services/mcp_service.dart';
import 'services/storage_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final mcpService = McpService();
  // 按设置决定是否拉起本机 MCP 服务；不阻塞首帧
  unawaited(mcpService.applyFromSettings());
  runApp(TotpApp(mcpService: mcpService));
}

class TotpApp extends StatelessWidget {
  const TotpApp({super.key, this.mcpService});

  /// MCP 服务宿主（测试可注入替身；为空则页面自行创建）
  final McpService? mcpService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TOTP 验证器',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
      ),
      home: AccountListPage(
        storage: StorageService(),
        mcpService: mcpService,
      ),
    );
  }
}
