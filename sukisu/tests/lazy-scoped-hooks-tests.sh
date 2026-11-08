#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SERVICE="$ROOT/zygote/src/main/java/org/frknkrc44/hma_oss/zygote/service/HMAService.kt"
ENTRY="$ROOT/zygote/src/main/java/org/frknkrc44/hma_oss/zygote/SukiStandaloneEntry.java"
# Structural regression gates; the Android SDK build validates Kotlin syntax.
grep -Fq 'private fun installHooksWhenConfigured()' "$SERVICE"
grep -Fq '(config.scope.isEmpty() && config.defaultConfig == null)' "$SERVICE"
grep -Fq 'private val installedHookGroups = mutableSetOf<String>()' "$SERVICE"
grep -Fq 'synchronized(lazyHookLock)' "$SERVICE"
grep -Fq 'installOnce("package-manager")' "$SERVICE"
grep -Fq 'installOnce("broadcast")' "$SERVICE"
grep -Fq 'if (!config.disableActivityLaunchProtection)' "$SERVICE"
grep -Fq 'installHooksWhenConfigured()' "$SERVICE"
grep -Fq 'if (appUid <= 0' "$SERVICE"
grep -Fq 'SukiStandaloneEntry' "$ENTRY"
grep -Fq 'if (service.config.scope.isEmpty()) return' "$ROOT/zygote/src/main/java/org/frknkrc44/hma_oss/zygote/hook/PmsHookTargetBase.kt"
grep -Fq 'hma_system_server_start' "$ROOT/sukisu/module/customize.sh"
! grep -Fq '[ -f "$MODDIR/injection_failed" ] && exit 0' "$ROOT/sukisu/module/service.sh"
echo 'Lazy scoped ART-hook activation and boot identity static gates passed'
