# R8 / ProGuard rules for Kecilin.
#
# The Flutter engine and every Flutter plugin ship their own consumer rules, so
# this file only covers the two plain-Java/native paths the app calls directly:
# the method-channel entry points (reflection-free, but kept for clarity) and
# PDFBox, which builds a few classes by name at runtime.

# ---------------------------------------------------------------------------
# Flutter plugin registration
# ---------------------------------------------------------------------------
-keep class io.flutter.** { *; }
-keep class com.maleolabs.kecilin.** { *; }

# Play Core (deferred components / split APKs) is not used by Kecilin: the app
# ships as a single module with no dynamic feature delivery. The Flutter engine
# still references those classes, so R8 must be told they are optional.
-dontwarn com.google.android.play.core.**

# ---------------------------------------------------------------------------
# PDFBox-Android
# ---------------------------------------------------------------------------
-keep class com.tom_roush.pdfbox.** { *; }
-dontwarn com.tom_roush.pdfbox.**
-dontwarn org.apache.**

# PDFBox optionally probes for these at runtime; absent is fine.
-dontwarn javax.imageio.**
-dontwarn java.awt.**
-dontwarn org.bouncycastle.**
-dontwarn org.brotli.**
-dontwarn org.apache.pdfbox.**

# ---------------------------------------------------------------------------
# Kotlin / coroutines internals pulled in transitively
# ---------------------------------------------------------------------------
-dontwarn kotlinx.coroutines.**
-dontwarn org.jetbrains.annotations.**

# Keep line numbers in crash reports without keeping the full debug info.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
