# Vitals

Personal health, lifting, recovery and hydration tracker for iPhone. Apple Watch
app comes next.

## Status

Not yet compiled. Xcode wasn't installed when this was written, so the code has
been syntax-checked only (`swiftc -parse` passes on all 36 files) and never
type-checked or run. Expect a handful of compiler fixes on the first build.

## Getting it running

1. Install **Xcode 26.6** from the Mac App Store.
2. Point the toolchain at it:
   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -license accept
   xcodebuild -downloadPlatform iOS
   ```
3. Generate and open the project:
   ```bash
   cd ~/Documents/Vitals
   xcodegen generate
   open Vitals.xcodeproj
   ```
4. Set your signing team: select the `Vitals` target, Signing & Capabilities, pick
   your team. Or paste your Team ID into `DEVELOPMENT_TEAM` in `project.yml` and
   re-run `xcodegen generate`.
5. Build to a real iPhone. HealthKit returns nothing useful in the simulator.

After first launch, open **Health → Sharing → Apps & Services → Vitals** and turn
on the categories you want. iOS never tells an app whether read access was
granted, so an empty dashboard almost always means permissions, not a bug.

## The project is generated

`Vitals.xcodeproj` is produced by [XcodeGen](https://github.com/yonaskolb/XcodeGen)
from `project.yml`. Don't hand-edit the project file — change `project.yml` and
re-run `xcodegen generate`. New source files under `Vitals/` are picked up
automatically; you only touch `project.yml` for build settings, capabilities and
new targets.

```bash
brew install xcodegen   # already installed
```

## Architecture

```
Vitals/
├── App/           VitalsApp, RootTabView (the bottom bar)
├── Core/
│   ├── Health/    HealthKitService, VitalKind, VitalReading
│   ├── Persistence/  SwiftData container + seeding
│   ├── Settings/  AppSettings (units, goal, reminders)
│   ├── Notifications/  water reminder scheduling
│   └── DesignSystem/   Card, ProgressRing, StatBlock, ...
└── Features/
    ├── Health/    dashboard tab
    ├── Fitness/   templates, live logging, history
    ├── Recovery/  stretching + massage gun routines
    ├── Water/     logging, goal ring, reminders
    └── Settings/  units and rest timer
```

### Where data lives

Two stores, on purpose.

**HealthKit** owns anything that should outlive the app: vitals and sleep are read
from it, and finished workouts plus every water log are written back to it. Delete
the app, reinstall it a year later, and that history is still in Health.

**SwiftData** owns what HealthKit can't model: the exercise library, workout
templates, individual set logs (weight × reps), and recovery routines. HealthKit
has no concept of "3×8 at 185 lb", so that has to live locally.

Weights are always stored in **kilograms** and volumes in **millilitres**.
Conversion to lb / fl oz happens only at the display layer via `AppSettings`.
Never store a display value.

### Adding things

**A new vital on the Health tab** — add a case to `VitalKind` and fill in the
switches (title, icon, tint, section, HealthKit identifier, unit, aggregation).
The dashboard picks it up automatically; no view changes.

**A new tab** — add a `Tab` in `RootTabView` and a folder under `Features/`.

**A new SwiftData model** — create the `@Model` type and register it in
`VitalsModelContainer.schema`. Adding a property with a default value migrates
automatically; anything more needs a `VersionedSchema`.

**A new exercise or starter routine** — `ExerciseLibrary` and `RecoveryLibrary`
only run when their tables are empty, so editing them won't affect an install that
already has data. Add through the app UI instead once you're using it.

## Notable implementation details

- **Set logging** writes straight to SwiftData on every keystroke, so backgrounding
  or force-quitting mid-workout loses nothing. An unfinished session is detected on
  launch and offered as "In Progress".
- **Finishing a workout** deletes any sets you never checked off, writes the
  heaviest weight per exercise back onto the template so next session is prefilled,
  then mirrors the session to HealthKit as `traditionalStrengthTraining`. If the
  HealthKit write fails the workout is still saved locally and the row shows a
  warning icon.
- **Per-side recovery steps** are flattened into two timer stages (Left, then
  Right) by `RoutinePlayerViewModel`, so the view has no special cases. The screen
  stays awake while a routine is running.
- **Water reminders** are one repeating daily `UNCalendarNotificationTrigger` per
  slot, capped at 32 to stay under the iOS pending-notification limit. They fire
  whether or not the app is running.

## Known gaps

- Swift language mode is pinned to **5.0** with `SWIFT_STRICT_CONCURRENCY: minimal`
  in `project.yml`. This was a deliberate call: strict Swift 6 concurrency
  correctness can't be verified without compiling. Flip `SWIFT_VERSION` to `6.0`
  once the app builds and fix the diagnostics then.
- No app icon. `AppIcon.appiconset` is an empty 1024×1024 slot.
- No tests. Worth adding around `AppSettings` conversions,
  `NotificationService.reminderSlots`, and `SetEntry.estimatedOneRepMaxKg` — all
  pure functions and easy to cover.
- Deleting a water entry removes the local record but leaves the HealthKit sample
  in place. Deleting from HealthKit needs the sample UUID stored on `WaterEntry`.
- The Health dashboard reads a single latest value per vital. No charts or trends
  yet; `Swift Charts` plus a `HKStatisticsCollectionQuery` is the natural next step.
