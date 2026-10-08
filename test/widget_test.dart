import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lzy_totp/main.dart';

void main() {
  testWidgets('应用启动后显示标题与空账户提示', (WidgetTester tester) async {
    await tester.pumpWidget(const TotpApp());
    await tester.pump();

    expect(find.text('TOTP 验证器'), findsOneWidget);
    expect(find.textContaining('还没有账户'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);

    // 卸载组件树，取消列表页的每秒刷新定时器
    await tester.pumpWidget(const SizedBox());
  });
}
