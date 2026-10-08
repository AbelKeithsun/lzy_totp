# Flutter 引擎与插件通道需要保留的符号
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class dev.luziyang.lzy_totp.** { *; }

# ML Kit 条形码识别（mobile_scanner 依赖）防止被 R8 误删
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.mlkit.**

# Flutter Play Store 延迟组件引用了未引入的 play core 类（可选依赖，用不到）
-dontwarn com.google.android.play.core.**
