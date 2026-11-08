# SukiSU Ultra standalone backend (experimental)

This branch targets SukiSU Ultra only. No Zygisk, Riru, LSPosed, Xposed or separate injection framework is used.

The experimental native AArch64 loader attaches to system_server using ptrace, creates a **target-owned memfd**, copies its JNI payload and loads it using dlopen/dlsym. The payload attaches to the existing JavaVM and loads the HMA manager APK through DexClassLoader. SukiStandaloneEntry starts the original HMAService and PackageManager hooks.

The SukiSU/KernelSU ZIP includes module.prop, a manager APK, the native injector, JNI payload and late-start scripts. On first install, **injection is disabled**; use the module Action button to attempt exactly one test. The injector does not request permissive SELinux, does not weaken Android sandboxing globally, and will report a failure if ptrace or native loading is forbidden.

The original HMA configuration files in /data/misc/hide_my_applist_* are retained. Do not enable alongside the old hma_oss_zygisk module.

## Build

Build the APK with `./gradlew :app:assembleDebug`. Use Android NDK r27+ and CMake 3.22+ for `sukisu/native` (arm64-v8a). Package with `bash sukisu/package.sh <apk> <native-build-dir> <output-zip>`.

## Test / Recovery

1. Install the ZIP in SukiSU Ultra. Install its manager.apk as a normal Android APK, then reboot.
2. In the module manager tap Action. The action succeeds only when a fresh HMAService status reports work mode 1, a verified positive manager UID, and a stable system_server process instance. This is a service-health check, **not** proof of correct per-app filtering.
3. Tap Action again to disable next-boot attempts. Reboot to unload the active hooks. A native injection failure locks out retries for the same boot; reboot before trying Action again. If unstable, disable the module from SukiSU's safe mode or recovery.

**Unverified and experimental.** Device tests are still required for SELinux, ptrace restrictions, Android linker namespaces, AndroidVMTools API changes, and framework class-loader resolution. Does not promise that Android 10–17 or all SukiSU kernels work. Do not ship as a stable release until those tests pass.

## Important implementation details

- Backend executes only after Android reports boot completed and **only after manual opt-in**. It never silently installs a KPM, swaps services.jar, edits the system partition or enables permissive SELinux.
- Its `injection_failed` marker is written *before* attaching. A success is accepted only after a fresh `status.json` reports HMAService work mode 1 and the target PID remains alive. Failures disable autostart.
- SukiSU's regular module scripting API is sufficient for packaging and launch; optional KPM is **not** required by this design. A kernel loader with ptrace/SELinux restrictions may still block native loading.
- A successful native/JNI load does not prove the filtering semantics of every Android or OEM PackageManager implementation; those require behavioral regression tests.

## Reliability and signing

- Only one injector can run at once. A verified injection is tagged with boot ID, system_server PID and process start ticks; duplicate loading into the same process is refused. A crashed injector's lock is only reclaimed on a later boot.
- A previously failed native attempt cannot be retried in the same boot. The manager must be installed and have the **same signing certificate as the APK bundled in the module**. An older manager signed with a different certificate cannot be updated in place; back up its configuration before changing signatures.
- CI validates the APK and arm64 binaries, package layout, shell syntax and process-state unit tests. The kernel's SELinux policy may still prohibit ptrace/dlopen; this module does not relax it.

## Package compatibility

The module targets **arm64-v8a Android API 29+** and requires a SukiSU/KernelSU-compatible module manager. `customize.sh` rejects unsupported ABI/API levels. The ZIP uses `skip_mount`: no system partition overlay or metamodule is required merely to run its scripts. Packaging validates the APK archive and both native ELF architectures before producing the ZIP.
