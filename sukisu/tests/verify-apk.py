#!/usr/bin/env python3
"""Verify the standalone backend is actually bundled in the built manager APK."""
import re
import sys
import zipfile
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit("usage: verify-apk.py <manager.apk>")
apk = Path(sys.argv[1])
required = (
    b"Lorg/frknkrc44/hma_oss/zygote/SukiStandaloneEntry;",
    b"Lorg/frknkrc44/hma_oss/zygote/service/SystemServerHook;",
    b"Lorg/frknkrc44/hma_oss/zygote/service/HMAService;",
    b"Lorg/frknkrc44/hma_oss/zygote/Magic;",
    b"Lcom/v7878/vmtools/Hooks;",
)
with zipfile.ZipFile(apk) as zf:
    names = zf.namelist()
    if "AndroidManifest.xml" not in names:
        raise SystemExit("APK missing AndroidManifest.xml")
    dex_names = [
        name for name in names
        if re.fullmatch(r"classes(?:[0-9]+)?\.dex", name)
    ]
    if not dex_names:
        raise SystemExit("APK has no classes.dex")
    print("APK DEX entries:", ", ".join(dex_names))
    dex = b"".join(zf.read(name) for name in dex_names)
for descriptor in required:
    if descriptor not in dex:
        raise SystemExit(f"Standalone backend missing from APK DEX: {descriptor.decode()}")
print(f"APK backend classes verified across {len(dex_names)} DEX file(s)")
