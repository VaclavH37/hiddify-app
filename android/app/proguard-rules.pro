# Rayn VPN — R8 keep rules
#
# R8 runs on every Android release build (minifyEnabled true in
# android/app/build.gradle). Play scores the DEX code for obfuscation,
# shrinking and optimization and wants at least 25% in each, so:
#   - keep only what something finds by name (JNI, reflection, stored names);
#   - never add a broad -keep for a library nothing calls: a
#     `-keep class X.** { *; }` blocks all three scores for every class it
#     matches;
#   - never -ignorewarnings, -dontobfuscate, -dontshrink or -dontoptimize
#     (DESIGN-INVARIANTS.md#android-release-r8; the design test fails on them).
#
# R8 never touches the Dart code (libapp.so) or the Go core (librayn-core.so).
# A build that strips the bridge below still builds and signs, then fails at
# connect: after any change here, run the device pass in CORE_BUILD.md.

# ---------------------------------------------------------------------------
# gomobile / gobind runtime — the JNI bridge to the Go core.
# go.Seq does reflective, reference-counted dispatch across the boundary, and
# Go finds the bound classes by name. com.raynlabs.core.** also holds the
# Wire-generated protos, and Wire's GrpcClient.create loads GrpcCoreClient by
# name. The core AAR's own proguard.txt keeps the same two packages.
# ---------------------------------------------------------------------------
-keep class go.** { *; }
-keep class com.raynlabs.core.** { *; }
-dontwarn go.**
-dontwarn com.raynlabs.core.**

# Any native method must keep its name (JNI resolves by exact signature).
-keepclasseswithmembernames class * {
    native <methods>;
}

# ---------------------------------------------------------------------------
# The Kotlin shell. Go calls back into the classes that implement libbox
# interfaces: PlatformInterfaceWrapper (VPNService, ProxyService),
# LocalResolver, the InterfaceArray/StringArray iterators and the libbox.Func
# lambdas in .bg. The Status and Alert enum names go to Dart as strings.
# Keeping the whole shell (~200 classes) is the safe choice; narrow it only if
# a Play score falls short.
# ---------------------------------------------------------------------------
-keep class com.raynlabs.app.** { *; }

# ---------------------------------------------------------------------------
# Wire runtime (the generated messages are under com.raynlabs.core.**).
# ---------------------------------------------------------------------------
-keep class com.squareup.wire.** { *; }
-dontwarn com.squareup.wire.**
-keepclassmembers class * extends com.squareup.wire.Message { *; }

# gRPC (io.grpc), protobuf-lite (com.google.protobuf) and gson have no keeps on
# purpose: nothing live calls them (unused imports and commented-out code
# only), so R8 removes them. Wire reaches the core over OkHttp, not grpc-java.

# ---------------------------------------------------------------------------
# flutter_secure_storage saves its cipher algorithm names in SharedPreferences
# and reads them back with valueOf (StorageCipherFactory). The plugin ships no
# rules, so keep the enums whole: an upgraded install must still read what an
# older one wrote.
# ---------------------------------------------------------------------------
-keep enum com.it_nomads.fluttersecurestorage.ciphers.** { *; }

# ---------------------------------------------------------------------------
# Kotlin metadata + coroutines.
# ---------------------------------------------------------------------------
-keepattributes Signature, *Annotation*, EnclosingMethod, InnerClasses
-keep class kotlin.Metadata { *; }
-keepclassmembers class kotlinx.coroutines.** { volatile <fields>; }
-dontwarn kotlinx.coroutines.**

# ---------------------------------------------------------------------------
# OkHttp / Okio (Wire's transport) — known-safe dontwarns.
# ---------------------------------------------------------------------------
-dontwarn okhttp3.**
-dontwarn okio.**

# ---------------------------------------------------------------------------
# Flutter embedding (the Flutter Gradle plugin also injects its own rules).
# ---------------------------------------------------------------------------
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**
