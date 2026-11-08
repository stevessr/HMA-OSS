# SukiSU Ultra standalone backend (experimental)

This branch targets SukiSU Ultra only. No Zygisk, Riru, LSPosed, Xposed or separate injection framework is used.

The experimental native AArch64 loader attaches to system_server using ptrace, creates a **target-owned memfd**, copies its JNI payload and loads it using dlopen/dlsym. The payload attaches to the existing JavaVM and loads the HMA manager APK through DexClassLoader. SukiStandaloneEntry starts the original HMAService and PackageManager hooks.

The SukiSU/KernelSU ZIP includes module.prop, a manager APK, the native injector, JNI payload and late-start scripts. On first install, **injection is disabled**; use the module Action button to attempt exactly one test. The injector does not request permissive SELinux, does not weaken Android sandboxing globally, and will report a failure if ptrace or native loading is forbidden.

The original HMA configuration files in /data/misc/hide_my_applist_* are retained. Do not enable alongside the old hma_oss_zygisk module.

## Build

Build the APK with `./gradlew :app:assembleDebug`. Use Android NDK r27+ and CMake 3.22+ for `sukisu/native` (arm64-v8a). Package with `bash sukisu/package.sh <apk> <native-build-dir> <output-zip>`.

## Test / Recovery

1. Install the ZIP in SukiSU Ultra. Install its manager.apk as a normal Android APK, then reboot.
2. In the module manager tap Action. An error keeps autostart disabled. A zero exit code means only that the JNI payload was loaded; check HMA's system service status and per-app filtering separately.
3. Tap Action again to disable next-boot attempts. Reboot to unload the active hooks. If unstable, disable the module from SukiSU's safe mode or recovery.

**Unverified and experimental.** Device tests are still required for SELinux, ptrace restrictions, Android linker namespaces, AndroidVMTools API changes, and framework class-loader resolution. Does not promise that Android 10–17 or all SukiSU kernels work. Do not ship as a stable release until those tests pass.

## Important implementation details

- Backend executes only after Android reports boot completed and **only after manual opt-in**. It never silently installs a KPM, swaps services.jar, edits the system partition or enables permissive SELinux.
- Its `injection_failed` marker is written *before* attaching. A success is accepted only after a fresh `status.json` reports HMAService work mode 1 and the target PID remains alive. Failures disable autostart.
- SukiSU's regular module scripting API is sufficient for packaging and launch; optional KPM is **not** required by this design. A kernel loader with ptrace/SELinux restrictions may still block native loading.
- A successful native/JNI load does not prove the filtering semantics of every Android or OEM PackageManager implementation; those require behavioral regression tests.
