package org.frknkrc44.hma_oss.zygote;

import android.os.Build;
import android.util.Log;
import org.frknkrc44.hma_oss.zygote.service.SystemServerHook;
import java.lang.reflect.Method;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * JNI entrypoint for HMA's own SukiSU/KernelSU loader.
 * This is intentionally not an Xposed or Zygisk API implementation.
 */
public final class SukiStandaloneEntry {
    private static final String TAG = "HMA-SukiSU";
    private static final AtomicBoolean STARTED = new AtomicBoolean();

    private SukiStandaloneEntry() {}

    public static void start(ClassLoader fallback) throws Exception {
        if (!STARTED.compareAndSet(false, true)) return;
        try {
            ClassLoader framework = resolveLoader(fallback);
            if (framework == null) {
                throw new ClassNotFoundException("Cannot locate system_server services.jar loader");
            }
            Class.forName("com.android.server.SystemServer", false, framework);
            SystemServerHook.INSTANCE.onSystemServer(framework);
            Log.i(TAG, "HMA standalone system_server bootstrap scheduled");
        } catch (Throwable error) {
            STARTED.set(false);
            Log.e(TAG, "Unable to initialize standalone HMA backend", error);
            if (error instanceof Exception) throw (Exception) error;
            throw new IllegalStateException(error);
        }
    }

    private static ClassLoader resolveLoader(ClassLoader fallback) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                Class<?> zygoteInit = Class.forName("com.android.internal.os.ZygoteInit");
                Method method = zygoteInit.getDeclaredMethod("getOrCreateSystemServerClassLoader");
                method.setAccessible(true);
                Object loader = method.invoke(null);
                if (loader instanceof ClassLoader) return (ClassLoader) loader;
            } catch (ReflectiveOperationException | SecurityException error) {
                Log.w(TAG, "Android 12+ loader reflection unavailable", error);
            }
        }
        return fallback;
    }
}
