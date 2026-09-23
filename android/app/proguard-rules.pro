-keep class com.warpvpn.app.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# usque / gomobile (MASQUE) bindings
-keep class mobile.** { *; }
-keep class go.** { *; }
-keep class go.Seq { *; }
-keep class go.Seq$* { *; }
-dontwarn mobile.**
-dontwarn go.**
-keepclasseswithmembers class * {
    @java.lang.Deprecated <methods>;
}
