# Public, fixed experimental signing key

`hma-oss-experimental.p12` is intentionally committed to GitHub and is used
**only for experimental Debug APKs**. Its private key and password are public.
Anyone can sign an APK with this identity. Do not treat this signature as an
authenticity guarantee or use the key for trusted releases.

PKCS#12 store and key password: `hma-experimental-public`
Alias: `hma-experimental`
Certificate SHA-256: `BB:E9:D7:63:B8:14:2B:D8:67:6C:73:AF:9E:D7:AC:20:41:DB:1C:D7:06:CE:97:BE:52:99:EB:56:9B:8F:73:0E`

`./gradlew :app:assembleDebug` uses this file automatically unless
`local.properties` explicitly supplies a private signing configuration.
The SukiSU `manager.apk` is copied from that exact APK build.

A **release** requires an independently secured private keystore specified in
`local.properties`, e.g.:

```properties
fileDir=/absolute/path/to/private-release.jks
storePassword=...
keyAlias=...
keyPassword=...
```

This repository intentionally never includes any trusted release key.

For previously installed manager APKs with a different signing certificate,
Android cannot do an in-place update. Back up app-specific settings, uninstall
the older manager, and install this experimental build once. Subsequent builds
using this same public test certificate can update in place.
