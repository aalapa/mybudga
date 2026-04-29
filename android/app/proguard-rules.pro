# Fix R8 NullPointerException on kotlinx-coroutines 1.8.1 ChannelResult$Failed
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**

# Flutter — keep platform channel / plugin classes
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# Supabase / Ktor / OkHttp
-keep class io.github.jan.supabase.** { *; }
-dontwarn io.github.jan.supabase.**
-dontwarn okhttp3.**
-dontwarn okio.**
