# Vitals — Agent Handoff Document

Personal health/fitness tracker for one user (yashst). iPhone app + Apple
Watch companion + home screen widgets. Built iteratively across ~16 rounds of
user feedback; every round is a conventional commit on `main`. Read this
whole document before making changes.

## Toolchain and workflow — read first

- **The `.xcodeproj` is generated. Never hand-edit it.** `project.yml`
  (XcodeGen) is the source of truth. After adding files or changing targets:
  `xcodegen generate`. New Swift files under existing source dirs are picked
  up automatically; target settings, entitlements, Info.plist keys, and new
  targets go in `project.yml`.
- **Always verify with real builds**, both targets:
  ```bash
  xcodebuild -project Vitals.xcodeproj -scheme Vitals \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -configuration Debug CODE_SIGNING_ALLOWED=NO build
  xcodebuild -project Vitals.xcodeproj -scheme VitalsWatch \
    -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' \
    -configuration Debug CODE_SIGNING_ALLOWED=NO build
  ```
  Pipe output to a log file and grep for `error:` — full logs overflow context.
- **Shell quirks observed on this machine:** long `git commit -m` messages in
  chained commands hang; write the message to `/tmp/msg.txt` and use
  `git commit -F`. Long command chains mixing several `swiftc`/`git` calls
  have hung twice; keep chains short and run steps as separate commands.
- Commit early and often, conventional commits style. Never push; there is no
  remote. User's Team ID belongs in `DEVELOPMENT_TEAM` in project.yml (top
  `settings.base`) or signing breaks on every regenerate.
- Deployment targets: **iOS 26.0** (required by FoundationModels), watchOS
  11.0. Swift language mode pinned to 5 with minimal strict concurrency in
  project.yml; a Swift 6 migration is an open task nobody asked for yet.

## Targets

| Target | What | Bundle ID |
|---|---|---|
| Vitals | iPhone app (SwiftUI) | com.yashst.vitals |
| VitalsWatch | watchOS app, embedded in Vitals | com.yashst.vitals.watchkitapp |
| VitalsWidgets | WidgetKit extension, embedded | com.yashst.vitals.widgets |

Shared code is per-file: the watch target lists individual files from
`Vitals/` in project.yml (models, HealthKitService, AppSettings,
DesignSystem, RecoveryLibrary, sync models, Haptics). The widget target
shares only `Core/Widgets/WidgetShared.swift`. Check the lists before
assuming a file exists on another platform. `Haptics` is platform-branched
(`#if os(watchOS)`); `LanguageModelSession` is iOS-only per the SDK.

## Data architecture — the two-store rule

**HealthKit owns anything that should outlive the app**: vitals, sleep,
workouts (HKWorkout), water (dietaryWater), body metrics (bodyMass,
bodyFatPercentage, leanBodyMass, bodyMassIndex), workout effort
(workoutEffortScore, related via `relateWorkoutEffortSample`). History
charts query HealthKit directly; nothing is duplicated app-side.

**SwiftData owns what HealthKit can't model** (`VitalsModelContainer`,
schema list is the registry):
- `Exercise` — library (~230 seeded, versioned re-seed via
  `ExerciseLibrary.version` + UserDefaults marker; insert-missing-by-name,
  never touches user rows)
- `WorkoutTemplate` → `TemplateItem` → `TemplateSet` — plans are per-set
  (each set has own weightKg/reps). `TemplateItem.targetSets/targetReps` are
  legacy fields kept for migration + summaries; `materializedPlan(in:)`
  synthesizes plan rows from them on first touch. `TemplateItem.alternate`
  (self-relationship, cascade, one level deep) = interchangeable exercise
  with its own plan; the alternate has `template == nil` and lives only
  through the relationship.
- `WorkoutSession` → `SetEntry` — performed workouts. SetEntry denormalizes
  exerciseName/muscleGroup/restSeconds so history survives renames/deletes.
- `RecoveryRoutine` → `RecoveryStep` (+ `targetGroups: [MuscleGroup]` drives
  suggestions), `WaterEntry` (mirrored to HK, `savedToHealthKit` flag for
  retry).

**Canonical units: kilograms and millilitres, always.** Conversion to the
user's lb/fl-oz preference happens only at display time via `AppSettings`
helpers. Never store a display value.

`AppSettings` (@Observable, UserDefaults-backed, injected via environment):
units, water goal + reminder schedule, hidden dashboard vitals (stored as
the HIDDEN set so new metrics auto-appear), sleep card toggle, appearance
override, dismissed suggestion snoozes.

## Feature map (iPhone tabs)

- **Health**: vitals grid (config-driven by `VitalKind` enum — add a case,
  fill the switches, done), sleep card, tap-through detail views charting
  30/90-day HealthKit history, personal usual-range badges
  (`VitalBaseline`, mean ± 1σ of last 30 days, ≥5 samples, today excluded;
  daily-sum vitals deliberately unbadged), Edit Metrics sheet, body section
  (Log Weight derives BMI from height; Navy-method body fat calculator
  derives lean mass), Settings (units, appearance, watch sync status panel,
  water reminder config lives on Water tab).
- **Fitness**: template list (preview sheet on tap → Edit/Start), per-set
  editor with chained number pad, reorder sheet, alternates, active workout
  (persistent phase dial: idle/set/rest/overtime with date-anchored timing
  in the app-lived `ActiveWorkoutViewModel.shared`), finish sheet (effort
  1–10 → HealthKit; update-plan toggle; discard offered only under 10 min),
  history (boxed table style), progress charts (heaviest/e1RM/volume/set
  time per day), compact week calendar expanding to month.
- **Recovery**: routine library with guided player (per-side steps run
  twice), Suggested-for-You (targetGroups ∩ muscle groups trained last 3
  days, snoozable), AI assistant (below), + menu for AI/manual creation.
- **Water**: quick adds, goal ring, 7-day chart, repeating daily reminders
  (UNCalendarNotificationTrigger per slot, ≤32).

## The number pad (`Core/DesignSystem/NumberPadSheet.swift`)

Custom 4×4 keypad: digits left; right column = Done / ±step (0.5 weight,
1 rep) / copy-down (fills following sets of the same exercise, stays put) /
Next (commits, chains weight → reps → next set → next exercise via
`NumberPadTarget.next` closures built in ActiveWorkoutView and
TemplateEditorView). **Critical pattern:** the sheet reads its target from a
plain `let` (fresh per presentation) with `@State chained` only for the
Next-chain, wiped in `onAppear`/`onChange(of: target.id)`. Do not
reintroduce `@State`-initialized-from-init — SwiftUI preserves sheet state
across presentations and it caused a long-lived "always edits Set 1" bug.
`.id(target.id)` at presentation sites is kept as belt-and-suspenders.

## Watch app

Real `HKWorkoutSession` + `HKLiveWorkoutBuilder` (live HR/kcal on wrist,
survives wrist-down) in `WatchWorkoutManager` (NSObject singleton, same
date-anchored dial phases as the phone). Pages (horizontal): workout
(template picker → 3 panes: metrics / current set + crown-scrollable plan
with ±editing / system `NowPlayingView`), vitals (watch-local metric
selection), recovery (own seeded SwiftData store — **custom phone routines
do not sync**), water. No blank-workout path by design.

## Phone ↔ watch sync (`Core/Sync/`)

Wire format: plain Codable DTOs in `WorkoutSyncModels.swift` (shared).
- Phone → watch: template library + unit prefs as
  `updateApplicationContext` (latest-wins, delivered when watch is ready).
  Pushed on activation, on watch-app-install (`sessionWatchStateDidChange`),
  after template save/delete/reorder, and on demand via live message
  (`requestTemplates`). Status (paired/installed/lastPush/lastError)
  surfaced in Settings — errors are never swallowed.
- Watch → phone: finished workouts via `transferUserInfo` (queues until
  reachable). **Ingest is idempotent** (same title + startedAt skipped)
  because WCSession re-delivers unacknowledged transfers after app kills —
  this caused duplicate history once; a one-shot cleanup keyed
  `cleanup.duplicateSessions.v1` healed existing stores.
- Ingested workouts get full SetEntries, `savedToHealthKit = true` (the
  watch wrote the HKWorkout), and template write-back.

## Widgets (`VitalsWidgets/`, `Core/Widgets/`)

Widgets can't query HealthKit. The app publishes a pre-formatted
`WidgetSnapshot` (App Group `group.com.yashst.vitals`) on dashboard refresh
and water changes; widgets render it (`SnapshotProvider`, hourly timeline,
app-driven reloads). Water widget's +8oz is an `AppIntent` that queues a
`PendingWater` + bumps the snapshot optimistically; the app drains the queue
into HealthKit + SwiftData on launch/scene-active
(`SnapshotPublisher.drainPendingWater`, clears queue first for idempotency).

## AI recovery (`Features/Recovery/AI/`)

On-device FoundationModels (`LanguageModelSession`, `@Generable` structs
with `@Guide` ranges — API was verified against the SDK swiftinterface, do
the same for any new FM API). Kept on-task by four layers: prohibition +
bank-vocabulary anchoring in instructions, temperature 0.3, post-generation
rejection of exercise-like step names (`looksLikeExercise`: keyword set +
exercise-library match), and a <3-steps quality gate falling back to the
rule-based `RecoveryLibrary` generator (also the fallback when Apple
Intelligence is unavailable; `Result.fallbackNote` tells the UI why).
Output is clamped (durations 15–180s, ≤15 steps, string prefixes).
`RecoveryLibrary`'s step bank is the vocabulary source — extend it there.

## Write-back semantics (easy to get wrong)

On finish (phone) and on watch-ingest: performed sets are matched to plan
sets by **exercise name + set number**, weights >0 only. Alternates are
matched by their own names, so only the performed variant updates. The
finish sheet's "update plan" toggle can skip write-back entirely;
`lastPerformedAt` updates regardless. Sets with data but no checkmark are
auto-completed at finish; empty rows are dropped.

## Hard-won gotchas (do not relearn these)

1. `deinit` is nonisolated — it cannot touch @MainActor state. Timer loops
   use `[weak self]` + early return instead.
2. Never put a lazy container (LazyVGrid/LazyVStack) inside a self-sizing
   List row → fatal recursive layout loop. The calendar uses non-lazy `Grid`.
3. Never delete a SwiftData object a visible view is bound to — dismiss
   first, delete after the transition (`discardAfterDismiss`, the
   FinishAction-in-onDismiss pattern). This froze the app once.
4. Sheet `@State` survives re-presentation (see number pad section).
5. `.sheet(item:)` + presenting-view state changes mid-dismissal → run
   follow-up actions in `onDismiss`, never in the sheet's buttons.
6. Timers must be wall-clock anchored (store start/deadline Dates, re-derive
   on tick) or they freeze when views unmount or the app backgrounds.
7. ForEach IDs: weekday letters repeat (S, T) — ID by offset. Duplicate IDs
   are undefined behavior.
8. `HierarchicalShapeStyle` (`.tertiary`) can't share a ternary with `Color`.
9. Forced `.environment(\.editMode, .constant(.active))` on a Form breaks
   swipes and text fields. EditButton toggles only; text-only lists are the
   exception (reorder sheet).
10. WCSession: see idempotent-ingest note above. App context payloads must
    differ (a `pushedAt` timestamp uniquifies) or the API throws.
11. Watch install order: `sessionWatchStateDidChange` handles
    phone-ran-before-watch-installed. Don't remove it.
12. Adding entitlements (App Group) changes provisioning and can silently
    break device installs — if the user reports old bugs "still" present,
    first verify the new build actually installed (the m:ss duration is the
    current visual marker).
13. exrx.net blocks scraping (403 + JS-rendered); the exercise library is
    hand-curated instead. Don't retry scraping without a browser-side export.
14. HealthKit never reports whether READ permission was granted — empty
    dashboard usually means Health permissions, and the UI says so.

## Known gaps / natural next steps

- Watch doesn't know about alternates (SyncTemplateItem has no alternate
  field) — sync DTO + watch swap UI is the obvious next slice.
- Custom recovery routines and template edits don't sync to the watch's
  recovery store (only workout templates sync).
- Live per-second HR on the phone during workouts requires
  `startMirroringToCompanionDevice` from the watch session — currently the
  phone polls latest samples every 15s.
- No tests. Pure functions worth covering first: AppSettings conversions,
  NotificationService.reminderSlots, SetEntry.estimatedOneRepMaxKg,
  VitalBaseline.compute, RecoveryAIService.looksLikeExercise.
- No app icon (empty 1024 slot, both platforms).
- Deleting a water entry doesn't delete its HealthKit sample (needs stored
  sample UUID).
- Swift 6 language mode migration.
- README.md's setup section predates Xcode being installed; HANDOFF.md (this
  file) supersedes it for agents.

## User preferences observed

Direct, iterates in batches, tests on real device between rounds and reports
precisely. Prefers acting over asking for trivia, wants honest notes when
something is a fallback or unverifiable, dislikes clutter (has removed
features for being "too big"), wants UI consistent with existing patterns
(boxed tables, m:ss times). When a report contradicts the code you're
reading, consider stale-build before assuming a new bug — it has happened.
