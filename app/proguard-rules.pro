# Enum class
-keepclassmembers,allowoptimization enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

-keep,allowoptimization class * extends androidx.preference.PreferenceFragmentCompat
-keepclassmembers class org.frknkrc44.hma_oss.databinding.**  {
    public <methods>;
}

# Standalone SukiSU JNI loader looks up this class by name. Keep all
# internal ART hook method/field names used by the framework backend.
-keep class org.frknkrc44.hma_oss.zygote.** { *; }
-keep class com.v7878.** { *; }
-dontwarn com.v7878.r8.annotations.KeepCodeAttribute
