# Native code creates MapSurface and calls these methods through JNI, which R8
# can't see.
-keep class com.greensopinion.flutter_mapigrade.MapSurface {
    <init>(io.flutter.view.TextureRegistry, long);
    long id();
    android.view.Surface resize(int, int);
    void push(android.media.Image);
    void closeImage(android.media.Image);
    void releaseReaders();
    void release();
}
-keepclasseswithmembernames class com.greensopinion.flutter_mapigrade.** {
    native <methods>;
}
