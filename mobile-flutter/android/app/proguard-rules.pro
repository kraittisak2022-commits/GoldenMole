# App-specific ProGuard / R8 rules (release minification).
# See: https://developer.android.com/topic/performance/app-optimization/enable-app-optimization

# --- Flutter engine & plugins ---
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# Keep JNI methods used by the engine.
-keepclasseswithmembernames class * {
    native <methods>;
}

# --- Kotlin (metadata for reflection used by some libraries) ---
-keepattributes *Annotation*, InnerClasses, EnclosingMethod, Signature, Exceptions, *AnnotationDefault
-dontwarn org.jetbrains.annotations.**

# --- Common transitive noise (plugins / Play Core) ---
-dontwarn com.google.android.play.core.**
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**
