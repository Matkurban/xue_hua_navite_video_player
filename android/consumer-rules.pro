# Preserve Pigeon JNI bridge classes, DTOs, and FlutterApi/HostApi registrars for R8.
-keep class com.kurban.xue_hua_navite_video_player.PlayerApi_gKt { *; }
-keep class com.kurban.xue_hua_navite_video_player.PlayerHostApi { *; }
-keep class com.kurban.xue_hua_navite_video_player.PlayerHostApi$** { *; }
-keep class com.kurban.xue_hua_navite_video_player.PlayerHostApiRegistrar { *; }
-keep class com.kurban.xue_hua_navite_video_player.PlayerHostApiRegistrar$** { *; }
-keep class com.kurban.xue_hua_navite_video_player.PlayerFlutterApi { *; }
-keep class com.kurban.xue_hua_navite_video_player.PlayerFlutterApiBridge { *; }
-keep class com.kurban.xue_hua_navite_video_player.PlayerFlutterApiRegistrar { *; }
-keep class com.kurban.xue_hua_navite_video_player.FlutterError { *; }
-keep @androidx.annotation.Keep class com.kurban.xue_hua_navite_video_player.** { *; }
-keepclasseswithmembers class com.kurban.xue_hua_navite_video_player.** {
    @androidx.annotation.Keep <methods>;
    @androidx.annotation.Keep <fields>;
}
