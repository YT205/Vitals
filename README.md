# Vitals

Personal health, lifting, recovery and hydration tracker: iPhone app, Apple
Watch companion, and interactive home screen widgets.

- **Health** — vitals dashboard fed by Apple Health, personal usual-range
  badges, sleep breakdown, body composition logging (weight, Navy-method
  body fat), 30/90-day history charts.
- **Fitness** — per-set workout plans with alternate exercises, live workout
  with set/rest/overtime dial, chained number pad entry, progress charts,
  training calendar. Workouts write to Apple Health with effort scores.
- **Recovery** — guided stretch/massage-gun routines, suggestions based on
  recently trained muscle groups, on-device AI routine generation
  (Apple Intelligence / FoundationModels).
- **Water** — quick logging, goal ring, daily reminders, widget quick-add.
- **Watch** — live heart rate workouts (HKWorkoutSession), synced workout
  plans via WatchConnectivity, finished workouts flow back to the phone.

Working on the code? Read **HANDOFF.md** — architecture, data model,
sync design, and the accumulated gotchas live there.

## Setup on a new Mac

### 1. Prerequisites

- macOS Tahoe 26.2+, Apple Silicon recommended
- **Xcode 26.x** from the Mac App Store (~20 GB), then:
  ```bash
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  sudo xcodebuild -license accept
  xcodebuild -downloadPlatform iOS
  xcodebuild -downloadPlatform watchOS
  ```
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (the `.xcodeproj` is
  generated, never committed):
  ```bash
  brew install xcodegen
  ```

### 2. Clone and generate

```bash
git clone https://github.com/YT205/Vitals.git
cd Vitals
xcodegen generate
open Vitals.xcodeproj
```

Re-run `xcodegen generate` any time `project.yml` changes or files are
added. Never edit the `.xcodeproj` directly — it's disposable output.

### 3. Signing

`project.yml` pins `DEVELOPMENT_TEAM` at the top of the file.

- **Same owner, new Mac:** sign into Xcode with the same Apple ID
  (Xcode → Settings → Accounts → +). The pinned team resolves automatically
  and you're done.
- **Different Apple ID:** replace `DEVELOPMENT_TEAM` with your own 10-char
  Team ID and change the identifiers, which are registered per-team:
  - `bundleIdPrefix` and each `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`
  - the App Group (`group.com.yashst.vitals`) in `project.yml`
    (both entitlements blocks) **and** in
    `Vitals/Core/Widgets/WidgetShared.swift` (`WidgetStore.appGroupID`)
  - `WKCompanionAppBundleIdentifier` in the watch target's info block

  Then `xcodegen generate` again.

### 4. Run in the simulator (no account needed beyond sign-in)

Select the **Vitals** scheme → any iPhone simulator → Run. For the watch,
select **VitalsWatch** → a watch simulator. Sync works between *paired*
phone+watch simulators; run the phone app once first so it pushes the
workout library.

Headless build check:
```bash
xcodebuild -project Vitals.xcodeproj -scheme Vitals \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build
```

### 5. Run on real devices

1. iPhone: Settings → Privacy & Security → **Developer Mode** → on → reboot.
   Same on the watch (its own Settings app).
2. Connect the iPhone, select it as the destination for the **Vitals**
   scheme, Run.
3. First launch is blocked: on the phone, Settings → General →
   VPN & Device Management → trust your developer certificate, launch again.
4. The watch app installs to the paired watch automatically (~1 min), or
   manage it from the iPhone's Watch app.
5. Approve the Health permission prompts on both devices; widgets appear in
   the home screen gallery after the app has been opened once.

**Free Apple ID:** installs expire after 7 days (re-run from Xcode to
re-sign; all data survives) and iOS caps you at 3 sideloaded apps. A paid
Apple Developer Program membership extends signatures to 1 year. App Groups
(the widgets) can be temperamental on free personal teams — if the widget
target blocks signing, build just the phone+watch first and revisit.

### 6. Data notes

- Workouts, water, and body metrics live in **Apple Health** — they survive
  reinstalls, re-signs, and even deleting the app.
- Plans, routines, and set-by-set history live in the app's local database
  and survive re-signing (same bundle ID + team), but not app deletion.
- Nothing leaves the devices: no server, no accounts, AI generation runs
  on-device.
