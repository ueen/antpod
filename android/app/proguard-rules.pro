## Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

## Play Core — optional, not bundled outside Play Store
-dontwarn com.google.android.play.core.**

## Audio service / media session
-keep class com.ryanheise.audioservice.** { *; }
-keep class androidx.media.** { *; }

## Keep Dart entry points
-keep class de.ueen.antpod.** { *; }
