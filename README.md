<div align="center">
  <h2>HMA-OSS</h2>

  <img src="HideMyAss-OSS.svg" alt="HMA-OSS Logo" style="max-width:360px;width:60%;height:auto;">

  <p>
    <a href="https://github.com/frknkrc44/HMA-OSS" style="text-decoration:none">
      <img src="https://img.shields.io/github/stars/frknkrc44/HMA-OSS?label=Stars&logo=github">
    </a>
    <a href="https://github.com/frknkrc44/HMA-OSS/actions" style="text-decoration:none">
      <img src="https://img.shields.io/github/actions/workflow/status/frknkrc44/HMA-OSS/main.yml?branch=master&logo=github">
    </a>
    <a href="https://github.com/frknkrc44/HMA-OSS/releases/latest" style="text-decoration:none">
      <img src="https://img.shields.io/github/v/release/frknkrc44/HMA-OSS?label=Release">
    </a>
    <a href="https://github.com/frknkrc44/HMA-OSS/releases/latest" style="text-decoration:none">
      <img src="https://img.shields.io/github/downloads/frknkrc44/HMA-OSS/total">
    </a>
    <a href="https://t.me/aerathfuns" style="text-decoration:none">
      <img src="https://img.shields.io/badge/Telegram-Channel-blue.svg?logo=telegram">
    </a>
    <a href="https://choosealicense.com/licenses/gpl-3.0/" style="text-decoration:none">
      <img src="https://img.shields.io/github/license/frknkrc44/HMA-OSS?label=License">
    </a>
  </p>
</div>

---

- **English**
- [中文（简体）](README_zh_CN.md)
- [Türkçe](README_tr.md)
- [日本語](README_ja.md)
- [Indonesia](README_id.md)
- [Português](README_pt.md)
- [Français](README_fr.md)

## About this module

Although it's bad practice to detect the installation of specific apps, not every app using root provides random package name support. In this case, if apps related to root (such as Fake Location and Storage Isolation) are detected, it is tantamount to detecting that the device is rooted.

Additionally, some apps use various loopholes to acquire your app list, in order to use it as fingerprinting data or for other nefarious purposes.

The APK now acts as an Xposed-compatible module. Its manager and system-server hook backend are packaged together, with **no Zygisk dependency**.

## About HMA-OSS

https://github.com/frknkrc44/HMA-OSS/wiki

## I want to contribute translation
You can contribute translation [here](https://crowdin.com/project/frknkrc44-hma-oss).

## Update log
[Reference to the commits page](https://github.com/frknkrc44/HMA-OSS/commits)

## Installation (non-Zygisk)

1. Install the HMA-OSS APK built from this branch; it includes both the settings UI and the framework hook code.
2. In an **Xposed-compatible hooking framework**, enable HMA-OSS and set its scope to **System Framework**. A Riru-based Xposed/LSPosed setup is one possible option without Zygisk. A compatible framework is still required; a regular Android APK cannot hook `system_server` by itself.
3. Reboot the device (or restart the framework/system process) and open HMA-OSS to check that the system service is running.
4. Reuse your existing app list, templates, and configuration. The backend keeps its `/data/misc/hide_my_applist_*/` state directory.

The old Magisk/Zygisk module ZIP, ZygoteLoader Gradle plugin and Zygisk installation scripts were removed from the build. Compile the APK using `./gradlew :app:assembleDebug` or `./gradlew :app:assembleRelease`.

**Migration:** Disable and remove the old `hma_oss_zygisk` module before enabling the Xposed-based APK to avoid hooking `system_server` twice. Keep a config backup before changing frameworks. If your previous manager APK used a different signing certificate, uninstall it before installing the new build; Android will not accept an in-place update signed with a different key.

**Limitations:** The in-process ART hooks still use AndroidVMTools and depend on Android version, SELinux policy, and the framework's system-server injection support. Android versions beyond those supported by your chosen Xposed implementation are not automatically covered by this conversion.
