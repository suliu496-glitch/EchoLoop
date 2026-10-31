# EchoLoop ProGuard 规则
# release 构建默认未开启代码压缩（isMinifyEnabled = false），
# 此处规则用于后续开启压缩时保持 Flutter / 原生桥接类不被裁剪。

-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class com.echoloop.player.** { *; }

# media_kit / libmpv 的 JNI 回调依赖方法名，禁止混淆
-keepclasseswithmembernames class * {
    native <methods>;
}
