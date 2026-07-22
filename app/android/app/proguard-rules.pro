# ----------------------------------------------------------------------------
# Release 打包时避免 Pigeon 通道被 R8/ProGuard 裁剪导致 channel-error
# 参见: https://github.com/flutter/flutter/issues/153075
# 错误示例: SharedPreferencesApi.getAll / GoogleSignInApi.getCredential
# ----------------------------------------------------------------------------

# 保留所有实现 FlutterPlugin 的插件类，避免方法通道无法建立连接
-if class * implements io.flutter.embedding.engine.plugins.FlutterPlugin
-keep,allowshrinking,allowobfuscation class <1>

# 保留 Pigeon 生成的 API 实现类（shared_preferences_android、google_sign_in_android 等）
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class io.flutter.plugins.googlesignin.** { *; }

# 保留 GeneratedPluginRegistrant，确保插件被正确注册
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# Sentry (sentry_flutter) — 反射读 SDK / event 字段
# https://docs.sentry.io/platforms/android/configuration/proguard/
-keep class io.sentry.** { *; }
-keep class io.sentry.android.** { *; }
-dontwarn io.sentry.**
