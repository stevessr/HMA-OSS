package de.robv.android.xposed.callbacks;

/** Compile-only signature: never include this stub in the installed APK. */
public abstract class XC_LoadPackage {
    public static final class LoadPackageParam {
        public String packageName;
        public String processName;
        public ClassLoader classLoader;
    }
}
