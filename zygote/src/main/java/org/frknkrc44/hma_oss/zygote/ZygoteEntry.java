package org.frknkrc44.hma_oss.zygote;

/**
 * Legacy tag holder retained because the ART hook utilities refer to
 * ZygoteEntry.TAG. The standalone SukiSU JNI entry is SukiStandaloneEntry.
 * No Zygisk or third-party framework entrypoints are implemented.
 */
public final class ZygoteEntry {
    public static final String TAG = "HMA-SukiSU";
    private ZygoteEntry() {}
}
