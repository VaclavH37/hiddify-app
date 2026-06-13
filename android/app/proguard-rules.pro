# Rayn VPN — R8/ProGuard keep rules
#
# STATUS: dormant safety net. Release builds ship with `minifyEnabled false`
# (see android/app/build.gradle), so R8 does NOT run today and these rules have
# no effect. They exist so that IF minification is ever enabled, the
# JNI/gRPC/reflection surface below survives shrinking/obfuscation instead of
# crashing at runtime on a build that otherwise compiles and signs cleanly.
#
# Why minification is off: the app's logic lives in Dart (AOT-compiled into
# libapp.so) and the Go core (libhiddify-core.so) — neither is touched by R8.
# R8 would only process the thin Kotlin shell + Java deps, where the obfuscation
# benefit is low but the breakage risk (gomobile callbacks, gRPC, gson) is high.
#
# If full minification is ever pursued: enable minifyEnabled/shrinkResources,
# then validate an on-device release build (the rules below are necessary but
# must be re-verified against a real minified run — see CORE_BUILD.md).

# ---------------------------------------------------------------------------
# gomobile / gobind runtime — the JNI bridge to the Go core.
# go.Seq does reflective, reference-counted dispatch across the boundary, and
# Go invokes the bound Java/Kotlin types by name. Stripping or renaming any of
# this breaks the native bridge.
# ---------------------------------------------------------------------------
-keep class go.** { *; }
-keep class com.hiddify.core.** { *; }
-dontwarn go.**
-dontwarn com.hiddify.core.**

# Any native method must keep its name (JNI resolves by exact signature).
-keepclasseswithmembernames class * {
    native <methods>;
}

# ---------------------------------------------------------------------------
# The Kotlin shell classes that IMPLEMENT gomobile callback interfaces
# (PlatformInterface, LocalDNSTransport, InterfaceUpdateListener,
# CommandClientHandler, CommandServerHandler, ...). Go calls these back by
# name via JNI, so their methods must not be renamed/removed.
# Blanket-keeping the small app shell is the safe choice; tighten to the
# callback-implementing classes only if real minification is ever pursued.
# ---------------------------------------------------------------------------
-keep class com.raynlabs.app.** { *; }

# ---------------------------------------------------------------------------
# Wire gRPC + protobuf-lite (generated from src/main/protos/**.proto).
# ---------------------------------------------------------------------------
-keep class com.squareup.wire.** { *; }
-dontwarn com.squareup.wire.**
-keepclassmembers class * extends com.squareup.wire.Message { *; }
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**

# ---------------------------------------------------------------------------
# gRPC (okhttp transport).
# ---------------------------------------------------------------------------
-keep class io.grpc.** { *; }
-dontwarn io.grpc.**

# ---------------------------------------------------------------------------
# gson — reflects over @SerializedName model classes (e.g. OutboundMapper).
# Keep generic signatures + annotations and the annotated fields themselves.
# ---------------------------------------------------------------------------
-keepattributes Signature, *Annotation*, EnclosingMethod, InnerClasses
-keep class com.google.gson.** { *; }
-dontwarn com.google.gson.**
-keepclassmembers,allowobfuscation class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# ---------------------------------------------------------------------------
# Kotlin metadata + coroutines.
# ---------------------------------------------------------------------------
-keep class kotlin.Metadata { *; }
-keepclassmembers class kotlinx.coroutines.** { volatile <fields>; }
-dontwarn kotlinx.coroutines.**

# ---------------------------------------------------------------------------
# OkHttp / Okio (transitive via grpc-okhttp) — known-safe dontwarns.
# ---------------------------------------------------------------------------
-dontwarn okhttp3.**
-dontwarn okio.**

# ---------------------------------------------------------------------------
# Flutter embedding (the Flutter gradle plugin also injects its own rules).
# ---------------------------------------------------------------------------
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**
