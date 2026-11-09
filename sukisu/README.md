# SukiSU Ultra standalone backend (experimental)

This branch targets SukiSU Ultra only. No Zygisk, Riru, LSPosed, Xposed or separate injection framework is used.

The experimental native AArch64 loader attaches to system_server using ptrace, creates a **target-owned memfd**, copies its JNI payload and loads it using dlopen/dlsym. The payload attaches to the existing JavaVM and loads the HMA manager APK through DexClassLoader. SukiStandaloneEntry starts the original HMAService and PackageManager hooks.

The SukiSU/KernelSU ZIP includes module.prop, a manager APK, the native injector, JNI payload and late-start scripts. On first install, **injection is disabled**; use the module Action button to attempt exactly one test. The injector does not request permissive SELinux, does not weaken Android sandboxing globally, and will report a failure if ptrace or native loading is forbidden.

The original HMA configuration files in /data/misc/hide_my_applist_* are retained. Installing this version **automatically disables and schedules removal** of the legacy `hma_oss_zygisk` module from both active and staged module directories. It also removes known original `hmaoss.sh` boot-script leftovers while leaving unrelated files untouched. **Reboot once before pressing Action**, because previously injected hooks cannot be unloaded safely until system_server restarts.

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

## CI regression gates

The GitHub Actions workflow builds on feature-branch pushes, pull requests and `master` pushes. Host-side regression coverage includes module Action enable/disable, failed-attempt lockout, lock conflicts, boot-scoped lock reclamation, shell-state parsing, APK DEX-class presence, ELF architecture, and final ZIP integrity. This is *not* a substitute for on-device system_server behavior or SELinux testing.

The native injector is additionally restricted to Android's `system_server` process (UID 1000) and rejects oversize APK paths before copying data into a remote memory mapping.

## Installation migration and safe removal

- The new module replaces the old installer failure when `/data/adb/modules/hma_oss_zygisk` still exists. It validates `module.prop`, writes KernelSU `disable` and `remove` flags, cleans positively identified old `hmaoss.sh` boot scripts, and lets KernelSU remove the legacy module on reboot.
- Installation is **not** a hot migration. Any Action or native injection attempt in the installation boot is rejected; reboot before activation to avoid double-hooking a live `system_server`.
- Uninstall cleans its own injected-state flags and old HMA boot-script remnants. Persistent HMA settings under `/data/misc/hide_my_applist_*` and Android app data are not deleted. Other modules' files and symlinks are never removed by the migration helper.
- If the bundled manager APK and an existing manager use different signing keys, Android will reject an in-place APK update. Back up user settings before manually replacing the manager APK. The installer never silently uninstalls an app or wipes its private data.
- GitHub Actions runs a fixture-based legacy migration test covering active/staged old modules, orphan boot scripts, foreign module IDs, symlinks and preservation of user configuration.

- The CI suite also sources the actual `customize.sh` with mocked KernelSU installer functions and runs a copied `uninstall.sh` against isolated fixture paths. It asserts successful migration without deleting user configurations.

## Stable experimental signing certificate

Every CI and normal local `assembleDebug` now uses the same **checked-in public test key** at `signing/hma-oss-experimental.p12`, instead of the runner-specific Android debug keystore. Both the `Main` APK and the `SukiSU` ZIP's `manager.apk` therefore carry the same certificate. The embedded `Magic.java` signature verifier is generated from that configured signing key. CI verifies its SHA-256 fingerprint after packaging.

The pinned experimental certificate SHA-256 fingerprint is:

`BB:E9:D7:63:B8:14:2B:D8:67:6C:73:AF:9E:D7:AC:20:41:DB:1C:D7:06:CE:97:BE:52:99:EB:56:9B:8F:73:0E`

**This test private key is publicly downloadable and cannot authenticate official releases.** To produce a trusted release, supply a separate private keystore via local `local.properties` (`fileDir`, `storePassword`, `keyAlias`, `keyPassword`). An unsigned release remains unsigned without that configuration.

**One-time certificate migration:** Android will still reject updating an already-installed APK signed by an older random debug/official certificate. The module installer never silently deletes app data. Back up the manager's app-specific settings (and HMA configurations if desired), uninstall the old manager APK, then install the new signed manager. All future experimental updates signed with this pinned public test key will install over one another.


## Scoped lazy ART hook activation and reboot state fix

- This SukiSU backend injects **only into `system_server`**, not every user-app process. It starts its manager Binder/control service first and **lazily installs framework ART hooks only after `config.scope` contains one or more configured app entries**. An explicit `defaultConfig` also activates hooks, because HMA applies that policy to newly installed apps.
- App configuration changes activate hooks without repeating the native loader or restarting the system. Removing a scope immediately disables that app's filtering behavior via existing caller checks; hooks cannot be safely hot-uninstalled from `system_server` after activation and remain resident until reboot.
- Installation stores both the kernel boot ID and `system_server` start ticks. A full reboot or Android framework-only restart unlocks the installer gate; older single-field markers are supported. A previous-boot `injection_failed` marker no longer disables autostart forever.
- Neither per-app ptrace attachment nor a separate app-process injection engine is implemented. Scoped filtering operates in the centralized PackageManager/framework service and unconfigured callers retain the original system behavior.

- PMS callbacks additionally bypass package lookup work when there are no scoped application entries; when the last scope is removed, resident framework trampolines no longer apply filtering and return the original responses.

- Native-injection failure lockouts are now also tied to the actual `system_server` instance, so a framework-only restart unlocks both the first-install gate and a failed prior injection without requiring a kernel reboot. An ongoing or unknown process identity remains fail-closed.

- The native backend keeps all graphics/media processes untouched. Rather than installing all system_server hooks when any app is configured, it incrementally enables only required hook groups, with package visibility as the default and installation source, app-data isolation, settings provider, accessibility, input methods, and broadcast protection gated by configuration. This reduces unrelated callbacks during media playback but cannot guarantee the absence of display glitches without device tests.

- For minimum playback interference, activity and broadcast interception now attach only when a configured scope actually has a hide rule, and the old **global USB_STATE broadcast mutation has been removed**: it previously changed broadcasts visible to apps that had no HMA policy. Package-manager hooks remain system_server-only and use a no-scope fast return.

- PackageManager hot paths now cache per-UID scoped membership. An app with no HMA configuration returns before target package inspection and filter-rule evaluation. The cache is invalidated when app installation state or HMA configuration changes.

- The fast path resolves per-UID package membership through the same OEM-specific resolver as the active hook, caches only valid results, and does not perform an additional Binder lookup. Per-app activity protection inversion remains respected when selectively enabling activity hooks.

- The hot ZygoteProcess-start hook now attaches only if a configured app requests restricted process permissions or data isolation actually requires force-mounting. A lightweight package-event listener remains for manager signature changes and config/cache correctness.


## Manager APK discovery and KernelSU / SukiSU WebUI

- The module ZIP contains `manager.apk`; `cmd package path` only reports the installed Android application, not files bundled in an SukiSU module. The injector now first resolves the installed application using `cmd package path` or `pm path`, and when missing uses `pm install -r` on the **bundled APK** before any native attach. Installation failure is reported explicitly; it never uninstalls another APK or clears data to bypass a signature mismatch.
- Open the module's **WebUI** in SukiSU/KernelSU to inspect manager installation, pending reboot, system_server identity, injected/autostart state and service log. The interface provides **Install/Update manager APK**, **Test injection / Enable next boot**, **Disable next-boot injection**, refresh and log actions. Root shell requests use only predefined, fixed shell operations, and no public network or external JavaScript dependencies.
- Web assets live in `webroot/` and are included in the top level of the installable module ZIP.

## Direct GitHub Actions download

`actions/upload-artifact@v7` uses `archive: false` for the **single already-built module ZIP**. Downloading the workflow artifact yields `HMA-OSS-SukiSU-experimental.zip` directly; no ZIP-within-a-ZIP is created. The workflow verifies the root entries before upload.


## Framework soft reboot recovery and upstream alignment

- **Upstream baseline:** checked against `frknkrc44/HMA-OSS` `master` commit `fe7a36799f040a79c666fb05b8479e69854656df` (tag/release `oss-175`, November 6, 2026). This fork already includes all upstream master commits as of November 9, 2026; there are no missing upstream master commits to merge. Standalone SukiSU backend intentionally remains independent from upstream Zygisk module packaging.
- `service.sh` stays resident as a low-rate monitor after boot and recognizes `system_server` replacement during a **framework-only soft reboot** even when the kernel boot UUID stays unchanged. It waits for framework boot completion and stable target process identity before injecting the new process. The one-time boot service hook alone cannot relaunch after every framework restart.
- Both injection operation locks and failure markers now track the specific `system_server` instance, permitting safe reclamation across a soft reboot while preventing duplicate injection in the same instance. The watcher itself uses a separately owned lock with PID/start time and clears abandoned watchers.
- To guard against a crash-restart cycle, at most **two unverified native attempts in five minutes** are permitted per kernel boot. A verified health handshake clears the attempt budget. Preflight failures due to PackageManager startup are retried later without consuming this budget. The autostart preference is not silently deleted after a transient failure.
- WebUI's Start action verifies/injects the current process even when next-boot autostart is already enabled. The logging window includes watchdog attempts and native return codes; uninstall removes the attempt budget without deleting app data.
