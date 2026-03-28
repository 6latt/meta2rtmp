# Oakley Meta Compatibility Report

> **Generated:** 2026-03-28  
> **Branch:** copilot/prepare-oakley-meta-compatibility  
> **Scope:** SpecBridge iOS app — static audit of hardcoded assumptions, entitlements, and blockers.

---

## 1. Visible App-Level "Ray-Ban" Assumptions Found

### Swift source files
| File | Line | Finding |
|------|------|---------|
| `ContentView.swift` | Button label | Was `"Connect to Meta Glasses"` — now updated to `"Connect to Meta AI Glasses"` |
| `StreamManager.swift` | (none) | No product-specific filter; uses generic `AutoDeviceSelector` |
| `SpecBridgeApp.swift` | (none) | No product-specific check |

### Documentation / non-compiled files
| File | Finding |
|------|---------|
| `README.md` | Several `"Ray-Ban Meta"` strings in user-facing text — updated to `"Meta AI Glasses"` (trademark disclaimer line preserved) |
| `SpecsBridge_Gemini_Convo.txt` | Historical chat log containing many `"Ray-Ban"` references — **not renamed** (not compiled or user-facing UI) |

### SDK-level strings visible in the project
| Source | Finding |
|--------|---------|
| `Info.plist` — `LSApplicationQueriesSchemes` | `fb-viewapp` — this is the Meta View app URL scheme used to open the companion app during registration |
| `Info.plist` — `UISupportedExternalAccessoryProtocols` | `com.meta.ar.wearable` — protocol string used by the EAAccessory framework to enumerate MFi accessories |
| `Info.plist` — `MWDAT.AppLinkURLScheme` | `specbridge://` — the callback URL scheme registered in Meta's developer portal; **this must be registered under the developer portal entry tied to `MetaAppID`** |
| `Info.plist` — `MWDAT.MetaAppID` | `0` — **PLACEHOLDER**. This must be a real App ID obtained from the Meta for Developers portal. A value of `0` will cause registration to fail silently or with an auth error |

---

## 2. Likely SDK-Level or Entitlement-Level Blockers

### 2a. `MetaAppID = 0` (Critical)
The `MWDAT` dictionary in `Info.plist` has `MetaAppID = 0`.  
`Wearables.configure()` and `startRegistration()` pass this ID to Meta's servers to verify the pairing request.  
An ID of `0` is invalid and will cause registration to fail immediately (likely a silent `try?` failure in the original code — now surfaced as a log entry via the new instrumentation).

**Fix:** Register the app at [developers.facebook.com](https://developers.facebook.com), create a Meta App, enable the Wearables SDK product, and paste the resulting numeric App ID here.

### 2b. URL Scheme not registered in Meta Developer Portal
`specbridge://` must be registered in the Meta developer portal as the deep-link callback URL for the pairing flow.  
If a different scheme was registered (e.g., one tied to the original developer's account), the `onOpenURL` handler will never fire after the user accepts pairing in Meta View.

**Symptom:** Registration appears to launch Meta View, user taps "Allow", but the app is never called back → `handleUrl` is never executed → `registrationState` stays `"In Progress"` forever.

### 2c. MFi Protocol — `com.meta.ar.wearable`
The `UISupportedExternalAccessoryProtocols` entry (`com.meta.ar.wearable`) declares that this app can communicate with MFi accessories that advertise that protocol.  
**Apple requires an explicit MFi entitlement** for any app using `EAAccessory` with a vendor-specific protocol string. Without this entitlement the OS will silently refuse to hand the accessory connection to the app.

For **development/TestFlight builds** signed with a provisioning profile that includes `com.apple.developer.networking.multipath` or the relevant MFi entitlement this is handled automatically by Xcode if the team has the entitlement.  
For **ad-hoc/App Store** distribution, the entitlement must be explicitly requested from Apple.

**Oakley note:** Oakley glasses use the same Meta Wearables platform and therefore advertise the same `com.meta.ar.wearable` protocol. If the original registration was tied to a Ray-Ban-specific device filter in the SDK (rather than just the protocol string), that filter is inside the closed-source `MWDATCore.xcframework` binary and cannot be patched at the app level.

### 2d. `AutoDeviceSelector` device scope
`AutoDeviceSelector` is a black-box class from `MWDATCore`. It is not known whether it filters by product line (Ray-Ban vs Oakley) or accepts any device advertising `com.meta.ar.wearable`.  
The new instrumentation logs `AutoDeviceSelector`'s description string at creation time — check the Xcode console or the Debug Panel for any "Ray-Ban" or product-model string in that output when testing with an Oakley device.

### 2e. `BackgroundModes` — `external-accessory`
The `external-accessory` background mode is required for EAAccessory communication to survive backgrounding.  
This is already correctly declared in `Info.plist`. No change needed.

---

## 3. Exact Files and Lines to Patch First for Oakley Testing

| Priority | File | Key | Current Value | Required Action |
|----------|------|-----|---------------|-----------------|
| 🔴 **P0** | `SpecBridge/Info.plist` | `MWDAT > MetaAppID` | `0` | Replace with a valid Meta App ID from the developer portal |
| 🔴 **P0** | Meta Developer Portal | App Link URL Scheme | _(unknown)_ | Register `specbridge://` as the OAuth/deep-link callback URL for the App ID |
| 🟠 **P1** | `SpecBridge/Info.plist` | `CFBundleURLSchemes` | `SpecBridge` | Verify this matches what is registered in the portal exactly (case-sensitive) |
| 🟠 **P1** | Xcode project | Signing & Capabilities | _(team-specific)_ | Confirm the provisioning profile includes the MFi/EAAccessory entitlement for `com.meta.ar.wearable` |
| 🟡 **P2** | `SpecBridge/StreamManager.swift` | `AutoDeviceSelector` | created at line ~61 | After `session.start()` returns, check Debug Panel `Device` field to see what model string the SDK reports for an Oakley device |
| 🟡 **P2** | `SpecBridge/StreamManager.swift` | `selectedPreset` | `.high24fps` | If first-frame delivery fails with Oakley at High/24, switch to `medium15fps` via the in-app Picker to reduce bandwidth demand |
| 🟢 **P3** | `SpecBridge/ContentView.swift` | button label | `"Connect to Meta AI Glasses"` | ✅ Already updated |
| 🟢 **P3** | `README.md` | product name | `"Meta AI Glasses"` | ✅ Already updated |

---

## 4. New Instrumentation Added (What to Look For in Logs)

When running with Oakley glasses, the following log lines will appear in both the Xcode console (prefixed `[SpecBridge]`) and the in-app Debug Panel (tap the 🐛 button in the top-right corner):

```
[Startup] SpecBridgeApp.init — calling Wearables.configure()
[Startup] Wearables.configure() succeeded            ← or FAILED: ...
[Registration] startRegistration() called
[Registration] startRegistration() launched (awaiting Meta View callback)
[URL] onOpenURL received: specbridge://...
[URL] handleUrl(url) completed successfully          ← or FAILED: ...
[Permission] Calling checkPermissionStatus(.camera)
[Permission] Current camera permission status: ...
[Permission] requestPermission(.camera) result: ...
[Session] Creating AutoDeviceSelector
[Session] AutoDeviceSelector created: <description>  ← check for product filter
[Session] Selected quality preset: High/24
[Session] StreamSessionConfig — codec: raw, resolution: high, fps: 24
[Session] Creating StreamSession
[Session] session.start() returned
[Frame] First video frame arrived — stream is delivering data
[Session] Stream fully stopped and cleaned up
```

The **Debug Panel** additionally shows a live counter of frames received, making it immediately visible whether Oakley glasses are delivering frames at all.

---

## 5. Summary

- **No Ray-Ban product strings exist in the compiled Swift source** beyond what was in the original button label (now updated).
- **All product gating is in the closed-source `MWDATCore` binary.** Whether Oakley devices are accepted is determined there, not in app-level code.
- **The single most likely blocker is `MetaAppID = 0`** — replace this first.
- **The second most likely blocker** is the `specbridge://` URL scheme not being registered in the correct Meta developer account's portal.
- Once those two items are fixed and the app receives the `onOpenURL` callback, the new instrumentation will surface exactly where in the flow (permission, session create, session start, first frame) Oakley differs from Ray-Ban.
