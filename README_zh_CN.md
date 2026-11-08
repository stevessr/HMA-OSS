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

- [English](README.md)
- **中文（简体）**
- [Türkçe](README_tr.md)
- [日本語](README_ja.md)
- [Indonesia](README_id.md)
- [Português](README_pt.md)
- [Français](README_fr.md)

## 关于该模块
虽然“检测安装的应用”是不正确的做法，但是并不是所有的与 root 相关联的插件类应用都提供了随机包名支持。这就意味着检测到安装了此类应用（如 Fake Location 、存储空间隔离）与检测到了 root 本身区别不大。（会使用检测手段的 app 可不会认为你是在“我就蹭蹭不进去”）  
与此同时，部分“不安分”的应用会使用各种漏洞绕过系统权限来获取你的应用列表，从而对你建立用户画像。（如陈叔叔将安装了 V2Ray 的用户分为一类），或是类似于某某校园某某乐跑的软件会要求你卸载作弊软件。  
该模块提供了一些检测方式用于测试您是否成功地隐藏了某些特定的包名，如 Magisk Manager；现在可作为 Xposed 兼容模块隐藏应用列表或特定应用，保护隐私；管理界面与系统 Hook 后端集成在同一个 APK 内，无须 Zygisk。  

## 更新日志
[参考发布页面](https://github.com/frknkrc44/HMA-OSS/commits)  

## 安装方法（无 Zygisk）

1. 安装本分支编译的 HMA-OSS APK；它同时包含管理界面和系统服务 Hook。
2. 在**兼容 Xposed API 的框架**中启用 HMA-OSS，将作用域设为 **系统框架（System Framework）**。例如使用基于 Riru 的 Xposed/LSPosed 实现，而不是 Zygisk。仍需要框架提供 `system_server` 注入能力，普通 APK 无法独立注入系统进程。
3. 重启设备（或重启框架和系统进程），打开 HMA-OSS，检查首页是否显示系统服务运行。
4. 原有配置、模板及 `/data/misc/hide_my_applist_*/` 数据目录继续复用。

已经移除了原先的 Magisk/Zygisk 模块 ZIP 构建、ZygoteLoader Gradle 插件和 Zygisk 安装检查脚本。现在运行 `./gradlew :app:assembleDebug` 或 `./gradlew :app:assembleRelease` 生成 APK 即可。

**迁移注意：**先停用并卸载旧版 `hma_oss_zygisk` 模块，避免两个后端同时 Hook `system_server`。更换框架前建议备份配置。

**兼容性：**底层 ART Hook 仍由 AndroidVMTools 实现，兼容范围取决于 Android 版本、SELinux 策略和所选 Xposed 框架是否支持注入系统服务。此修改不会让所有 Android 版本自动获得兼容性。
