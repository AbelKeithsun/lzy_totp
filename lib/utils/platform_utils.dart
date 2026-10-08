import 'package:flutter/foundation.dart';

/// 平台判断工具：统一用 defaultTargetPlatform（可在测试中覆写），
/// 避免直接依赖 dart:io 的 Platform。
class AppPlatform {
  AppPlatform._();

  /// 是否为桌面端（macOS / Windows / Linux）
  static bool get isDesktop =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  /// 是否支持扫码（mobile_scanner 仅支持 Android / iOS）
  static bool get supportsScan =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}
