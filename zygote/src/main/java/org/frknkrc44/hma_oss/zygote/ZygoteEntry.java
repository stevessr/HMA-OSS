package org.frknkrc44.hma_oss.zygote;

import static org.frknkrc44.hma_oss.zygote.util.Logcat.logELegacy;
import static org.frknkrc44.hma_oss.zygote.util.Logcat.logILegacy;

import android.os.Build;

import com.v7878.r8.annotations.DoNotObfuscateType;
import com.v7878.r8.annotations.DoNotShrinkType;

import de.robv.android.xposed.IXposedHookLoadPackage;
import de.robv.android.xposed.callbacks.XC_LoadPackage;

import org.frknkrc44.hma_oss.common.BuildConfig;
import org.frknkrc44.hma_oss.zygote.service.SystemServerHook;

import java.util.Locale;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Legacy Xposed API entrypoint for the system framework scope.
 * The same manager APK holds both the UI and the service/hook backend.
 * No ZygiskLoader/Zygisk native module is loaded.
 */
@DoNotObfuscateType
@DoNotShrinkType
public final class ZygoteEntry implements IXposedHookLoadPackage {
    public static final String TAG = "HMA-Xposed";
    private static final AtomicBoolean STARTED = new AtomicBoolean();

    @Override
    public void handleLoadPackage(XC_LoadPackage.LoadPackageParam lpparam) {
        if (lpparam == null || !isSystemServer(lpparam)) {
            return;
        }
        if (!STARTED.compareAndSet(false, true)) {
            return;
        }

        try {
            ClassLoader loader = lpparam.classLoader;
            if (loader == null) {
                loader = Class.forName("com.android.server.SystemServer").getClassLoader();
            }
            if (loader == null) {
                throw new IllegalStateException("Cannot resolve system_server class loader");
            }

            int sdkLevel = Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA
                    ? Build.VERSION.SDK_INT_FULL : Build.VERSION.SDK_INT;
            logILegacy(TAG, String.format(Locale.US,
                    "Initializing framework hooks - SDK %d - %s",
                    sdkLevel, BuildConfig.APP_VERSION_NAME));
            SystemServerHook.INSTANCE.onSystemServer(loader);
        } catch (Throwable error) {
            STARTED.set(false);
            logELegacy(TAG, "Could not initialize system_server hooks", error);
        }
    }

    private static boolean isSystemServer(XC_LoadPackage.LoadPackageParam param) {
        // Legacy Xposed commonly reports "android" for system_server;
        // other compatible frameworks may report "system"/"system_server".
        boolean systemPackage = "android".equals(param.packageName)
                || "system".equals(param.packageName);
        boolean systemProcess = "android".equals(param.processName)
                || "system".equals(param.processName)
                || "system_server".equals(param.processName);
        return systemPackage && systemProcess;
    }
}
