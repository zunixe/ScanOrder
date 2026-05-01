## Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

## Google Play Core (for split install)
-keep class com.google.android.play.core.** { *; }
-keep class com.google.android.play.core.common.** { *; }
-keep class com.google.android.play.core.tasks.** { *; }
-dontwarn com.google.android.play.core.**

## Supabase / GoTrue
-keep class io.supabase.** { *; }

## Google Sign-In
-keep class com.google.android.gms.** { *; }

## In-App Purchase
-keep class com.android.vending.billing.** { *; }

## ML Kit / Barcode Scanner
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
