# Suppress unresolved optional dependency warnings
-ignorewarnings
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**
-dontwarn io.flutter.embedding.android.FlutterPlayStoreSplitApplication
-dontwarn org.bouncycastle.**
-dontwarn javax.annotation.**
-dontwarn okhttp3.**
-dontwarn okio.**

# DocuBox App Package & Native Method Channels
-keep class com.docubox.app.** { *; }

# Flutter Wrapper & Engine
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.**  { *; }

# Essential Flutter Plugin Keep Rules
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-keep class com.crazecoder.openfile.** { *; }
-keep class dev.fluttercommunity.plus.share.** { *; }
-keep class dev.fluttercommunity.plus.packageinfo.** { *; }
-keep class io.flutter.plugins.urllauncher.** { *; }
-keep class io.flutter.plugins.camera.** { *; }
-keep class com.google_mlkit_commons.** { *; }

# Google Play In-App Update Engine
-keep class com.google.android.play.core.** { *; }
-keep class com.google.android.play.core.appupdate.** { *; }
-keep class com.google.android.play.core.tasks.** { *; }
-keep class com.google.android.play.core.install.** { *; }

# Google ML Kit Document Scanner & Vision
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.vision.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_** { *; }
-keep class com.google.android.gms.tasks.** { *; }
-keep class com.google.android.gms.common.** { *; }
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# Native Archives, Compression & I/O
-keep class org.apache.commons.compress.** { *; }
-keep class com.github.junrar.** { *; }

# AndroidX Window & Display Calibration
-keep class androidx.window.** { *; }
-keep class androidx.core.view.** { *; }

# OkHttp & Retrofit Networking (Update Service & GitHub Releases)
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }

# PDF Rendering Native Engine (pdfview)
-keep class com.github.barteksc.pdfviewer.** { *; }
-keep class com.shockwave.pdfium.** { *; }

# General optimization settings
-dontusemixedcaseclassnames
-dontskipnonpubliclibraryclasses
-verbose
