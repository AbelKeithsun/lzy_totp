// 截图生成器（不属于常规测试，放在 tool/ 下避免 `flutter test` 自动收集）。
//
// 用法：
//   cd <repo root>
//   flutter test tool/screenshots/capture_test.dart --update-goldens
//
// 产物写入 docs/images/。原理：加载系统中文字体后用真实 widget 树渲染成 PNG，
// 因此不依赖屏幕录制权限，也能在 CI/无头环境复现。
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:lzy_totp/pages/account_list_page.dart';
import 'package:lzy_totp/pages/ai_access_page.dart';

import '../../test/support/fake_storage.dart';

/// 测试环境的默认字体是 Ahem（方框），换上真实字体截图才看得清：
/// - 中文/正文：系统的 Arial Unicode（含 CJK 字形）
/// - 图标：Flutter SDK 自带的 MaterialIcons-Regular.otf
Future<void> _loadFont(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return; // 缺字体时降级为方框，不阻断截图
  final bytes = file.readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

/// 从当前 dart 可执行文件反推 Flutter SDK 根目录
String _flutterRoot() {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && env.isNotEmpty) return env;
  var dir = File(Platform.resolvedExecutable).parent.path;
  for (var i = 0; i < 4; i++) {
    dir = File(dir).parent.path; // bin -> cache -> dart-sdk -> bin -> flutter
  }
  return dir;
}

const _cjkFont = '/System/Library/Fonts/Supplemental/Arial Unicode.ttf';

ThemeData _theme() => ThemeData(
      // macOS 的 Typography 会用 SF Pro 等系统字族，测试环境没有这些字体（会渲染成方框），
      // 因此显式指定已加载的 'Roboto'（实际是 Arial Unicode，含中文与数字）
      fontFamily: 'Roboto',
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.teal,
        brightness: Brightness.dark,
      ),
    );

const _shotKey = ValueKey('shot');

Widget _frame(Widget child) => RepaintBoundary(
      key: _shotKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(),
        home: child,
      ),
    );

Future<void> _shoot(WidgetTester tester, String fileName) =>
    expectLater(find.byKey(_shotKey), matchesGoldenFile('../../docs/images/$fileName'));

/// 按 macOS 渲染（截图要体现桌面端：显式复制按钮 + ⋮ 菜单）。
/// debug 变量必须在测试体内复位，框架会在 tearDown 之前校验。
void _macOsTest(String name, Future<void> Function(WidgetTester tester) body) {
  testWidgets(name, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  setUpAll(() async {
    // 应用用默认字族显示中文，用等宽字族显示验证码，图标用 MaterialIcons
    await _loadFont('Roboto', _cjkFont);
    await _loadFont('monospace', _cjkFont);
    await _loadFont(
      'MaterialIcons',
      '${_flutterRoot()}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
  });

  _macOsTest('账户列表（含 ⋮ 删除入口）', (tester) async {
    tester.view.physicalSize = const Size(840, 1280); // 420x640 @2x
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final storage = FakeStorage([
      testAccount('1', 'GitHub', 'me@github.com',
          secret: 'JBSWY3DPEHPK3PXP'),
      testAccount('2', 'Google', 'me@gmail.com',
          secret: 'GEZDGNBVGY3TQOJQ'),
      testAccount('3', 'AWS', 'root@company.com',
          secret: 'KRSXG5CTMVRXEZLU'),
    ]);
    await tester.pumpWidget(_frame(AccountListPage(storage: storage)));
    await tester.pumpAndSettle();

    await _shoot(tester, 'app-account-list.png');
    await tester.pumpWidget(const SizedBox());
  });

  _macOsTest('行尾菜单：复制 / 删除', (tester) async {
    tester.view.physicalSize = const Size(840, 1280);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final storage = FakeStorage([
      testAccount('1', 'GitHub', 'me@github.com',
          secret: 'JBSWY3DPEHPK3PXP'),
      testAccount('2', 'Google', 'me@gmail.com',
          secret: 'GEZDGNBVGY3TQOJQ'),
      testAccount('3', 'AWS', 'root@company.com',
          secret: 'KRSXG5CTMVRXEZLU'),
    ]);
    await tester.pumpWidget(_frame(AccountListPage(storage: storage)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();

    await _shoot(tester, 'app-account-menu.png');
    await tester.pumpWidget(const SizedBox());
  });

  _macOsTest('删除二次确认', (tester) async {
    tester.view.physicalSize = const Size(840, 1280);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final storage = FakeStorage([
      testAccount('1', 'GitHub', 'me@github.com',
          secret: 'JBSWY3DPEHPK3PXP'),
      testAccount('2', 'Google', 'me@gmail.com',
          secret: 'GEZDGNBVGY3TQOJQ'),
    ]);
    await tester.pumpWidget(_frame(AccountListPage(storage: storage)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除账户'));
    await tester.pumpAndSettle();

    await _shoot(tester, 'app-delete-confirm.png');
    await tester.pumpWidget(const SizedBox());
  });

  _macOsTest('AI 接入说明页（整页）', (tester) async {
    tester.view.physicalSize = const Size(840, 3400); // 420x1700 @2x
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_frame(const AiAccessPage()));
    await tester.pumpAndSettle();

    await _shoot(tester, 'app-ai-access.png');
    await tester.pumpWidget(const SizedBox());
  });
}
