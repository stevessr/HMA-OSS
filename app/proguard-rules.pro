# Enum class
-keepclassmembers,allowoptimization enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

-keep,allowoptimization class * extends androidx.preference.PreferenceFragmentCompat
-keepclassmembers class org.frknkrc44.hma_oss.databinding.**  {
    public <methods>;
}

# This class is looked up by name by the external Xposed framework.
-keep class org.frknkrc44.hma_oss.zygote.ZygoteEntry { *; }
# The framework provides these classes; do not bundle Xposed API stubs.
-dontwarn de.robv.android.xposed.**
-dontwarn com.v7878.r8.annotations.KeepCodeAttribute
