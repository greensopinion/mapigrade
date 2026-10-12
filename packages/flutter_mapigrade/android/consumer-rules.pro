# Native code creates MapSurface and calls these methods through JNI, which R8
# can't see.
-keep class com.greensopinion.flutter_mapigrade.MapSurface {
    <init>(io.flutter.view.TextureRegistry, long);
    long id();
    android.view.Surface resize(int, int);
    void release();
}
-keepclassmembers class com.greensopinion.flutter_mapigrade.MapigradePlugin {
    public static void trimSurfacesForTesting(boolean);
}
-keepclasseswithmembernames class com.greensopinion.flutter_mapigrade.** {
    native <methods>;
}
