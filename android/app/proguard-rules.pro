
## Play Core — optional, not bundled outside Play Store
-dontwarn com.google.android.play.core.**

## Audio service / media session
-keep class com.ryanheise.audioservice.** { *; }
-keep class androidx.media.** { *; }

## Keep Dart entry points
-keep class de.ueen.antpod.** { *; }
