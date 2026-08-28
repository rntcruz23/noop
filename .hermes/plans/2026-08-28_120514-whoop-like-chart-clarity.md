# WHOOP-Like Chart Clarity Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Make NOOP's plots easier to interpret and more consistent with a restrained WHOOP-like visual language, without copying proprietary assets or changing metric calculations.

**Architecture:** Define a shared semantic chart contract first, then implement one reference pattern for HRV and resting heart rate on Apple and Android. Roll the proven pattern out by metric family, simplify the Trends screen hierarchy, and verify parity, accessibility, localization, and real rendered behavior at each phase. Keep all work presentation-only unless a phase explicitly identifies a required read-model change.

**Tech Stack:** SwiftUI + Swift Charts (`StrandDesign`, `Strand`), Kotlin + Jetpack Compose Canvas (`android`), XCTest/Swift Testing, JUnit, XcodeGen, Gradle.

---

## Status and operating rules

**Overall status:** Phase 0 completed with recorded platform-verification gaps; Phase 1 not started

**Last updated:** 2026-08-28

### Non-negotiable constraints

- Do not alter analytics formulas, stored metric values, migrations, or protocol decoding as part of this effort.
- Maintain feature-level UI parity between Apple and Android.
- Use existing design tokens only: `StrandPalette` / `StrandFont` / `NoopMetrics` and Android `Palette` / `Metrics`.
- Preserve the app's offline model and accessibility summaries.
- Do not silently widen one metric to a different period from neighboring charts.
- Do not connect lines across known missing-data intervals.
- Color must have one clear role per chart. Status colors are not decorative gradients.
- Keep detailed statistics available, but move secondary statistics out of the default summary card where possible.
- App-target Swift changes require local `xcodebuild` validation on macOS; package CI alone is insufficient.
- BLE or physiological calculations are out of scope.
- Do not label a presentation range as the scoring baseline. HRV/RHR cards use the approved `VitalBands` presentation contract: calendar-padded history before the displayed day, trusted personal bounds when available, and an explicitly labeled population fallback otherwise.
- Pure date-window, coverage, segmentation, normalized-position, and `VitalBands` display-range helpers must be mirrored in Swift and Kotlin and pinned with the repository's Swift-oracle-to-Kotlin-literal workflow.

### Product principles

1. **Answer first, evidence second.** One primary number and one comparison lead each card; the plot supports them.
2. **Context beats decoration.** Typical range, baseline, goal, or zone gives the line meaning.
3. **One visual grammar per metric family.** Do not offer arbitrary line/bar switching when the chart type carries semantic meaning.
4. **Selected period means one period.** Every visible card honors the same chosen window.
5. **Missing data remains visible.** Gaps and coverage are represented honestly.
6. **Details on demand.** Min/max/mean and deeper analysis live in metric detail, not every summary card.

---

## Current context

The repository already contains a sampled WHOOP design reference at:

- `docs/superpowers/specs/2026-06-22-whoop-design-language.md`

Relevant implementation seams:

- Apple shared trend primitive: `Packages/StrandDesign/Sources/StrandDesign/TrendChart.swift`
- Apple hover/selection support: `Packages/StrandDesign/Sources/StrandDesign/ChartHover.swift`
- Apple Trends screen: `Strand/Screens/TrendsView.swift`
- Apple metric detail: `Strand/Screens/MetricExplorerView.swift`
- Android shared charts: `android/app/src/main/java/com/noop/ui/Charts.kt`
- Android Trends screen: `android/app/src/main/java/com/noop/ui/TrendsScreen.kt`
- Android metric detail screens: `android/app/src/main/java/com/noop/ui/TrendsExploreScreen.kt`, `HealthScreen.kt`, `SleepScreen.kt`, `StressScreen.kt`
- Existing chart tests: `Packages/StrandDesign/Tests/StrandDesignTests/`, `StrandTests/`, and `android/app/src/test/java/com/noop/ui/`

Observed clarity issues:

- Trends cards duplicate the average in the header and footer.
- Summary cards permanently expose mean/min/max/trend plus full axes, grid, gradient, area, dots, and selection.
- Data-fitted Y domains can visually exaggerate small changes without a typical-range reference.
- Each metric can silently widen to a different time period.
- Color alternates between metric identity, value ramp, and status meaning.
- The global line/bar preference allows semantically unsuitable chart types.

### Review findings against the current implementation

- Apple currently plots real `Date` values through Swift Charts, while Android `LineChart` spaces values uniformly by list index. Supplying date labels alone does not make Android's geometry calendar-time-aware. Honest visual gaps and cross-card X alignment therefore require a timestamp-aware Android geometry seam, not only segment IDs.
- Android already supports segmented lines through `LineChart(..., segmentIds:)` and `lineChartSegmentRanges`; Phase 1 should generalize and reuse that seam rather than create a parallel chart model.
- Apple already carries explicit segment identity through `TrendPoint.segment` and renders it through the `LineMark` / `AreaMark` series key. The missing guarantee is downsampling: `ChartDownsample.minMaxBucketed` currently receives the combined series, so Phase 1 must preserve segment boundaries and singleton segments before or during downsampling.
- Existing Trends code does not expose HRV/RHR presentation bounds. Phase 0 approved the existing cross-platform `VitalBands` model for this purpose; Phase 2 must expose its basis, bounds, valid-night count, status, and classification without changing recovery scoring.
- Apple package-local chart strings belong in `Packages/StrandDesign/Sources/StrandDesign/Resources/Localizable.xcstrings`; screen copy belongs in `Strand/Resources/Localizable.xcstrings`.
- Existing focused tests should be extended where possible: `Packages/StrandDesign/Tests/StrandDesignTests/PlaceholderTests.swift`, `android/app/src/test/java/com/noop/ui/TrendsAxisLabelsTest.kt`, and `android/app/src/test/java/com/noop/ui/Vo2MaxTrendProvenanceTest.kt`.

---

## Approved implementation decisions

Phase 0 resolved these decisions as D1–D10 in `docs/superpowers/specs/2026-08-28-noop-chart-clarity-design.md`:

- [x] Keep the NOOP names `Charge`, `Rest`, and `Effort`.
- [x] Use one selectable hero metric followed by compact metric rows; Charge is the default hero.
- [x] Fix summary geometry by metric semantics. Ignore the global line/bar preference on migrated summaries while preserving its stored key until compatibility cleanup.
- [x] Use `VitalBands` for HRV/RHR display context. Call trusted bounds `your typical range`; label calibrating, provisional, or stale population fallbacks as general ranges, never as the scoring baseline.
- [x] Make Android daily geometry calendar-time-aware by passing normalized day positions or epoch days into the existing `LineChart` seam.
- [x] Define coverage from the selected inclusive local-day window, one resolved finite observation per day/night, with future/invalid rows excluded and explicit `ALL` wording.
- [x] Break daily lines across every absent calendar day while preserving elapsed horizontal width.
- [x] Honor one global selected period without per-metric widening.
- [x] Limit summary charts to three X labels and no persistent Y-axis.
- [x] Make selection replace the card's primary value/date rather than obscure the plot with a tooltip.

---

# Phase 0: Baseline, inventory, and visual contract

**Priority:** P0  
**Status:** Completed with recorded platform-verification gaps

**Objective:** Establish a measurable current-state baseline and approve a shared chart specification before changing production UI.

**Files:**

- Read: `docs/superpowers/specs/2026-06-22-whoop-design-language.md`
- Read: `Packages/StrandDesign/Sources/StrandDesign/TrendChart.swift`
- Read: `android/app/src/main/java/com/noop/ui/Charts.kt`
- Read: `Strand/Screens/TrendsView.swift`
- Read: `android/app/src/main/java/com/noop/ui/TrendsScreen.kt`
- Created: `docs/superpowers/specs/2026-08-28-noop-chart-clarity-design.md`
- Created: `docs/superpowers/specs/2026-08-28-noop-chart-inventory.md`
- Created: `docs/superpowers/specs/assets/2026-08-28-chart-clarity-reference.svg`
- Production code remains unchanged.

### Tasks

- [x] Inventory every chart use by screen and classify it as trend line, accumulated bar, stage timeline, range/goal bar, heat strip, route, or diagnostic plot.
- [x] Trace the exact scoring-baseline construction on both platforms, including recalibration epochs and active-device/history resolution; record whether a reusable read model exists or must be added.
- [x] Record current chart semantics: primary value, comparison, chart type, domain, color meaning, axis density, selection behavior, gap handling, and coverage display.
- [ ] Deferred validation evidence: capture representative current screenshots on Apple and Android when those platforms are available for:
  - Trends
  - HRV detail
  - Resting HR detail
  - Sleep duration/stages
  - Effort/strain
  - Skin temperature
  - Stress
- [x] Write the semantic chart matrix for each metric family.
- [x] Produce static reference mockups for HRV and resting HR at phone width and desktop/tablet width.
- [x] Specify exact chart chrome:
  - one primary reading
  - one baseline comparison
  - compact coverage
  - typical-range band
  - one line
  - latest/selected point only
  - maximum three X-axis labels
  - no persistent Y-axis on summary cards
- [x] Specify selection behavior and accessibility behavior.
- [x] Specify calendar-time X positioning and a concrete gap threshold for daily/nightly metrics. Intraday thresholds remain metric-specific and outside Phase 1.
- [x] Product approved decisions D1–D10 on 2026-08-28.

### Proposed semantic chart matrix

| Metric family | Default geometry | Context | Color rule |
|---|---|---|---|
| Charge/recovery | Daily dots or short columns | Recovery zones and selected-period average | Red/yellow/green only by established zone |
| Effort/strain | Zero-based bars | Personal typical load or target when available | Blue only |
| HRV | Line | Personal typical-range band | Purple or restrained white/purple; status in text |
| Resting HR | Line | Personal typical-range band | Rose or restrained white/rose; status in text |
| Sleep duration | Bars | Sleep need/goal reference | Rest slate-blue |
| Sleep stages | Proportional timeline | Stage durations and percentages | Existing stage palette only |
| Skin temperature deviation | Zero-centered line | Zero baseline and typical deviation band | Neutral/temperature accent; absolute value outside plot |
| Stress | Stepped/filled time series | Calm/elevated zones | Existing stress ramp by zone |
| Steps | Bars | Goal or personal average | Single accent plus muted reference |

### Acceptance criteria

- [x] The written design spec and phone/wide-layout mockups are approved.
- [x] Every existing chart is assigned a semantic chart family.
- [x] Color and chart-type meanings are unambiguous in the proposed contract.
- [x] No production code has changed.
- [x] The typical-range source and its parity contract are documented. The proposal uses `VitalBands` and explicitly distinguishes personal from population context.

### Completion evidence

- Spec path: `docs/superpowers/specs/2026-08-28-noop-chart-clarity-design.md`
- Inventory path: `docs/superpowers/specs/2026-08-28-noop-chart-inventory.md`
- Static mockup: `docs/superpowers/specs/assets/2026-08-28-chart-clarity-reference.svg`
- Rendered screenshots: blocked on this Linux host (`xcodebuild`, `adb`, and Android emulator unavailable)
- Source review: completed 2026-08-28; no production files changed
- Approval decision: approved D1–D10 on 2026-08-28
- Deferred evidence does not block Phase 1 implementation, but native before/after screenshots and VoiceOver/TalkBack checks are mandatory before release in Phase 7.

---

# Phase 1: Shared chart contract and gap-safe data model

**Priority:** P0  
**Status:** In progress
**Depends on:** Phase 0 approval

**Objective:** Add the smallest shared chart-geometry seams for range bands, calendar-time positioning, gaps, sparse axes, and latest/selected state without changing screen hierarchy or metric-window policy yet.

**Likely files:**

- Modify: `Packages/StrandDesign/Sources/StrandDesign/TrendChart.swift`
- Modify: `Packages/StrandDesign/Sources/StrandDesign/ChartHover.swift`
- Create or modify: `Packages/StrandDesign/Tests/StrandDesignTests/TrendChartTests.swift`
- Modify: `android/app/src/main/java/com/noop/ui/Charts.kt`
- Modify existing tests first: `Packages/StrandDesign/Tests/StrandDesignTests/PlaceholderTests.swift`, `android/app/src/test/java/com/noop/ui/TrendsAxisLabelsTest.kt`, and `android/app/src/test/java/com/noop/ui/Vo2MaxTrendProvenanceTest.kt`.
- Create a focused helper/test file only when the existing files become incoherent.

### Tasks

- [ ] Extend the existing `TrendChart` and `LineChart` seams instead of introducing a second all-purpose chart model. Reuse Apple `TrendPoint.segment` and Android `segmentIds`; add only optional range-band bounds, summary/detail chrome, and Android calendar positions.
- [ ] Extract mirrored pure helpers for date-derived segment IDs and normalized calendar X positions. Window and coverage policy belongs to Phase 2 callers, then migrates across Trends in Phase 3.
- [ ] Produce a standalone Swift oracle over geometry boundary cases (DST-independent local day keys, leap day, one/two points, multi-day gaps, and non-finite values), then paste its stdout verbatim as the expected Kotlin fixture.
- [ ] Write failing tests for gap segmentation: known gaps produce separate contiguous ranges.
- [ ] Write failing tests proving Android X coordinates reflect elapsed calendar days rather than list indices.
- [ ] Write failing tests proving segment boundaries and first/last points survive downsampling on Apple; downsample each segment independently if necessary.
- [ ] Write failing tests for typical-band geometry and clipping.
- [ ] Write failing tests for summary mode suppressing persistent Y-axis and point markers.
- [ ] Write failing tests for a maximum of three X-axis labels in summary mode.
- [ ] Write failing tests for selection fallback: no active selection means latest point.
- [ ] Implement the minimal Apple shared-chart changes.
- [ ] Implement the matching Android Canvas behavior by reusing `segmentIds` / `lineChartSegmentRanges` and adding timestamp-aware X geometry.
- [ ] Preserve one collapsed accessibility node per chart on Android.
- [ ] Preserve full-resolution values for accessibility/selection while retaining current downsampling for drawing.
- [ ] Add snapshots or deterministic geometry tests where the frameworks permit them.

### Acceptance criteria

- [ ] Summary charts can render a muted typical band.
- [ ] Known missing intervals break the line on both platforms.
- [ ] Summary mode renders no persistent Y-axis, no area fill by default, and no dots except latest/selected.
- [ ] Selection snaps to the nearest valid sample and exposes date plus formatted value.
- [ ] Accessibility reports metric, selected/latest value, range context, and coverage without per-point nodes.
- [ ] Existing callers retain old behavior until explicitly migrated.
- [ ] Android points with dates one and ten days apart are farther apart than points one day apart; Apple and Android use the same normalized day positions.
- [ ] Downsampling cannot join two segments or drop a singleton segment.

### Verification

```bash
(cd Packages/StrandDesign && swift test)
(cd android && ./gradlew testFullDebugUnitTest --tests 'com.noop.ui.*Chart*')
```

App compile on macOS after any shared SwiftUI change:

```bash
xcodegen generate
xcodebuild -project Strand.xcodeproj -scheme Strand \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Strand.xcodeproj -scheme Strand \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
xcodebuild -project Strand.xcodeproj -scheme NOOPiOS \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

### Completion evidence

- Apple tests: _pending_
- Android tests: _pending_
- macOS build: _pending_
- iOS build: _pending_
- StrandTests: _pending_

---

# Phase 2: HRV and resting-HR reference implementation

**Priority:** P0  
**Status:** Not started  
**Depends on:** Phase 1

**Objective:** Prove the new visual grammar on two physiological metrics before changing every chart.

**Likely files:**

- Modify: `Strand/Screens/TrendsView.swift`
- Modify: `Strand/Screens/MetricExplorerView.swift`
- Modify: `android/app/src/main/java/com/noop/ui/TrendsScreen.kt`
- Modify: `android/app/src/main/java/com/noop/ui/TrendsExploreScreen.kt`
- Modify `VitalBands` only to expose the already-computed presentation basis/bounds/status needed by the cards; do not change its classification formulas or recovery scoring.
- Add: focused Apple tests under `StrandTests/`
- Add: focused Android tests under `android/app/src/test/java/com/noop/ui/`

### Target card contract

For each metric:

- Primary: latest valid value in the selected window; selection temporarily replaces it with the selected value and date.
- Secondary: comparison against the approved `VitalBands` personal range, or an explicitly named population fallback.
- Plot: one crisp line, typical band, latest/selected point, sparse X labels.
- Coverage: `24 of 30 nights`, or equivalent localized phrasing.
- The context sentence may include compact bounds such as `48–74 ms`; no persistent four-column footer.
- On selection: replace the primary value and date with the selected reading; do not obscure the plot with a floating tooltip.

### Tasks

- [ ] Write failing pure tests for `VitalBands` display bounds, basis/status copy, and HRV/RHR direction semantics.
- [ ] Add a read-only `VitalBands` presentation result that exposes personal center/bounds when trusted and population bounds otherwise. Feed it calendar-padded history strictly before the displayed day, matching `VitalSignsSummary.swift` and `HealthVitalsLogic.kt`; do not copy fold logic into either screen and do not route it into scoring.
- [ ] Pin that result with a Swift oracle and matching Kotlin fixture covering cold start, provisional, trusted, stale, missing calendar days, duplicates after source resolution, malformed day keys, and physiological guards.
- [ ] Write failing tests proving HRV/RHR use the selected global window without invoking per-metric widening.
- [ ] Write failing tests for the approved inclusive-window coverage rules, including future dates, invalid/non-finite values, duplicates, one point, no data, and `ALL`.
- [ ] Implement HRV summary card on Apple.
- [ ] Implement matching HRV summary card on Android.
- [ ] Implement resting-HR summary card on Apple.
- [ ] Implement matching resting-HR summary card on Android.
- [ ] Move detailed min/max/mean into the metric detail view if not already present.
- [ ] Ensure the same input samples, period, units, and comparison rules are used across platforms.
- [ ] If `VitalBands` bounds cannot be exposed without changing classification behavior, ship the reference cards without a typical band and record that deferral; never substitute selected-window mean/min/max or scoring state as “typical.”
- [ ] Add all new strings to Apple String Catalog and Android resources, including focus locales.
- [ ] Capture before/after screenshots at phone and wide widths.

### Acceptance criteria

- [ ] A user can answer “what is it now?” and “is that normal for me?” without reading the axes.
- [ ] Header and footer do not duplicate the same statistic.
- [ ] HRV and RHR use the exact selected period on both platforms.
- [ ] Missing days are visible as gaps.
- [ ] Dynamic domains cannot imply context without the visible typical band.
- [ ] Selection behavior is identical at feature level on Apple and Android.

### Verification

```bash
(cd android && ./gradlew testFullDebugUnitTest \
  --tests 'com.noop.ui.*Hrv*' \
  --tests 'com.noop.ui.*Resting*' \
  --tests 'com.noop.ui.*Trend*' \
  --tests 'com.noop.analytics.*VitalBands*')
python3 Tools/i18n_audit.py --ci origin/main
python3 Tools/doc_comment_lint.py
```

Plus both Apple app builds from Phase 1.

### Completion evidence

- Screenshots: _pending_
- Tests/builds: _pending_
- Cross-platform visual review: _pending_

---

# Phase 3: Period honesty, coverage, and missing data across Trends

**Priority:** P0  
**Status:** Not started  
**Depends on:** Phase 2

**Objective:** Migrate every remaining Trends card to the window, coverage, and gap behavior proven by HRV/RHR in Phase 2.

**Likely files:**

- Modify: `Strand/Screens/TrendsView.swift`
- Modify: `android/app/src/main/java/com/noop/ui/TrendsScreen.kt`
- Add or modify: `StrandTests/Trends*Tests.swift`
- Add or modify: `android/app/src/test/java/com/noop/ui/Trends*Test.kt`

### Tasks

- [ ] Replace Apple `Range.widening` / `resolve(_:)` and Android `resolveMetric` auto-widening with one global selected window.
- [ ] Preserve sparse points in that window instead of substituting data from another period.
- [ ] Add an explicit “Show all available history” action when the selected window has no usable samples.
- [ ] Apply the Phase 2 coverage helper to each metric: observed days/nights versus expected days.
- [ ] Apply the approved daily gap rule and Phase 1 date-derived segment IDs without modifying stored data. Cadence-specific intraday rules remain with their producers.
- [ ] Pass the Phase 1 calendar positions through every migrated Android daily chart so missing days retain their elapsed width.
- [ ] Keep x-axis boundaries aligned across cards in the same selected period.
- [ ] Add tests for stale imports, one-point windows, no-data windows, and multi-day gaps.

### Acceptance criteria

- [ ] Selecting `M` means the same date interval on every chart.
- [ ] Sparse metrics say how sparse they are.
- [ ] No card silently substitutes `3M`, `1Y`, or all-history data.
- [ ] Lines do not bridge missing intervals.
- [ ] Explicit all-history navigation remains available.

### Completion evidence

- Apple tests: _pending_
- Android tests: _pending_
- Screenshot comparison: _pending_

---

# Phase 4: Simplify the Trends information hierarchy

**Priority:** P1  
**Status:** Not started  
**Depends on:** Phases 2–3 and approved Phase 0 hierarchy

**Objective:** Replace the equal-weight wall of chart cards with one clear primary chart and compact secondary metrics.

**Likely files:**

- Modify: `Strand/Screens/TrendsView.swift`
- Modify: `android/app/src/main/java/com/noop/ui/TrendsScreen.kt`
- Modify or create shared compact trend row components in `Packages/StrandDesign/` and Android `ui/`.
- Add corresponding component and screen tests.

### Recommended structure

1. Global period selector.
2. One large selected metric chart.
3. Compact metric rows for HRV, RHR, Rest, Effort, and other approved metrics.
4. Weekly/monthly narrative insight.
5. Calendar heat strip at the bottom or behind an explicit “History calendar” action.

### Tasks

- [ ] Build a compact metric row with label, primary value, comparison, coverage, and sparkline.
- [ ] Make each row select the hero chart and retain tap-through to full metric detail.
- [ ] Preserve keyboard, VoiceOver, TalkBack, and large-text navigation semantics.
- [ ] Remove duplicate mean/min/max/trend summaries from the main Trends screen.
- [ ] Keep deeper statistics in the existing metric detail screen.
- [ ] Decide and implement the year heat-strip placement.
- [ ] Test metric switching, selected state, navigation, empty state, and dynamic type/font scaling.

### Acceptance criteria

- [ ] There is one obvious primary visualization.
- [ ] Secondary metrics are scannable without scrolling through several full-size charts.
- [ ] Every compact row has one primary label and muted secondary context.
- [ ] No metric identifier, period label, or average is repeated unnecessarily.
- [ ] Metric detail remains one tap away.

### Completion evidence

- Phone screenshots: _pending_
- Tablet/desktop screenshots: _pending_
- Accessibility review: _pending_
- Tests/builds: _pending_

---

# Phase 5: Roll out semantic charts by metric family

**Priority:** P1  
**Status:** Not started  
**Depends on:** Phase 4

**Objective:** Apply the approved grammar to remaining charts without turning the effort into a broad visual rewrite.

## Phase 5A: Charge and Effort

**Likely files:**

- `Strand/Screens/TrendsView.swift`
- `Strand/Screens/MetricExplorerView.swift`
- `android/app/src/main/java/com/noop/ui/TrendsScreen.kt`
- `android/app/src/main/java/com/noop/ui/TrendsExploreScreen.kt`
- Shared chart primitives and tests

**Tasks:**

- [ ] Render Charge as daily zone-colored dots or short columns.
- [ ] Render Effort as zero-based blue bars.
- [ ] Remove arbitrary line/bar switching for these summary charts.
- [ ] Preserve the user's Effort display scale in labels and selection.
- [ ] Test zone thresholds and zero-baseline truthfulness.

## Phase 5B: Sleep duration and stages

**Likely files:**

- `Strand/Screens/SleepView.swift`
- `Strand/Screens/AsleepDurationCard.swift`
- `Strand/Screens/StagesCard.swift`
- `android/app/src/main/java/com/noop/ui/SleepScreen.kt`
- `android/app/src/main/java/com/noop/ui/SleepMetricCardsUi.kt`
- `android/app/src/main/java/com/noop/ui/SleepStageBreakdownUi.kt`

**Tasks:**

- [ ] Use bars for nightly duration with a sleep-need/goal reference when already available.
- [ ] Keep stages as a proportional timeline/hypnogram.
- [ ] Avoid conventional lines for categorical stage transitions.
- [ ] Ensure durations and percentages remain visible without redundant legends.

## Phase 5C: Skin temperature

**Likely files:**

- `Strand/Screens/HealthView.swift`
- `Strand/Screens/VitalSignsSummary.swift`
- `Strand/Screens/FusedRecordView.swift`
- `android/app/src/main/java/com/noop/ui/HealthScreen.kt`
- `android/app/src/main/java/com/noop/ui/HealthVitalsLogic.kt`

**Tasks:**

- [ ] Plot deviation around a visible zero line.
- [ ] Show absolute nightly temperature as the primary reading outside the plot.
- [ ] Respect Celsius/Fahrenheit everywhere.
- [ ] Add typical deviation band only from existing baseline data.

## Phase 5D: Stress and steps

**Likely files:**

- `Strand/Screens/StressView.swift`
- `android/app/src/main/java/com/noop/ui/StressScreen.kt`
- `Strand/Screens/SettingsView.swift` or current Apple calibration screen location
- `android/app/src/main/java/com/noop/ui/StepsCalibrationScreen.kt`

**Tasks:**

- [ ] Use stepped/filled stress plots against calm/elevated zones.
- [ ] Use bars for steps with goal or personal-average reference.
- [ ] Ensure calibration charts use the active-device union already established by recent upstream changes.

### Phase 5 acceptance criteria

- [ ] Every metric family has a semantically appropriate fixed default chart type.
- [ ] Color meaning is consistent across screens and platforms.
- [ ] No presentation change alters metric values or storage.
- [ ] All migrated charts retain accessibility summaries and selection.

### Completion evidence

- Per-family tests and screenshots: _pending_
- Cross-platform parity matrix: _pending_

---

# Phase 6: Retire conflicting options and clean up legacy paths

**Priority:** P2  
**Status:** Not started  
**Depends on:** Phase 5

**Objective:** Remove or constrain old presentation options that conflict with the semantic chart contract.

**Likely files:**

- `Strand/Data/Units.swift`
- `Strand/Screens/SettingsView.swift`
- `android/app/src/main/java/com/noop/ui/Units.kt`
- `android/app/src/main/java/com/noop/ui/SettingsScreen.kt`
- `android/app/src/main/java/com/noop/ui/SettingsLogic.kt`
- Any tests referencing `TrendChartStyle` or the chart-style preference

### Tasks

- [ ] Audit every use of the line/bar preference.
- [ ] Decide whether to remove it, migrate it to an advanced detail-only preference, or ignore it on semantically fixed summary charts.
- [ ] Preserve backward compatibility for stored preference keys where removal could affect backups.
- [ ] Remove dead chart branches only after all callers migrate.
- [ ] Update settings copy and release notes.
- [ ] Run source hygiene and localization audits.

### Acceptance criteria

- [ ] Users cannot select a misleading geometry for summary charts.
- [ ] Existing backup/settings decoding remains compatible.
- [ ] No dead chart-style code remains in migrated paths.

### Completion evidence

- Preference migration decision: _pending_
- Tests: _pending_

---

# Phase 7: Final rendered QA and release gate

**Priority:** P0 before release  
**Status:** Not started  
**Depends on:** All implementation phases selected for the release

**Objective:** Verify that the new charts are clearer, truthful, accessible, responsive, and cross-platform consistent with real rendered output.

### Required datasets

- [ ] Dense 30-day data
- [ ] Sparse 30-day data
- [ ] Multi-day gaps
- [ ] One-point window
- [ ] No-data window
- [ ] Flat series
- [ ] Outlier series
- [ ] Very long history requiring downsampling
- [ ] Celsius and Fahrenheit
- [ ] Effort 0–100 and 0–21 display modes
- [ ] Multiple devices / re-paired active-device union

### Automated verification

```bash
# Swift packages (macOS; StrandDesign requires SwiftUI and StrandAnalytics links through WhoopStore/GRDB)
cd Packages/StrandDesign && swift test
cd ../StrandAnalytics && swift test

# Android
cd ../../android
./gradlew testFullDebugUnitTest
./gradlew compileFullDebugKotlin

# Repository hygiene
cd ..
python3 Tools/doc_comment_lint.py
python3 Tools/i18n_audit.py --ci origin/main
python3 -m unittest discover -s Tools -p 'test_*.py'
```

On macOS:

```bash
xcodegen generate
xcodebuild -project Strand.xcodeproj -scheme Strand \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Strand.xcodeproj -scheme Strand \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
xcodebuild -project Strand.xcodeproj -scheme NOOPiOS \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

### Manual rendered checks

- [ ] Phone portrait and landscape
- [ ] Tablet/desktop width
- [ ] Dark and light themes if both remain supported
- [ ] Dynamic Type / large Android font scale
- [ ] VoiceOver and TalkBack summaries
- [ ] Touch drag, tap, mouse hover, keyboard focus, and selection reset
- [ ] No chart clipping, overflow, label collision, or tooltip occlusion
- [ ] Selected period and coverage are understandable without inspecting source data
- [ ] Typical bands remain visible but subordinate
- [ ] Status colors are not used decoratively
- [ ] Compare Apple and Android screenshots side by side for feature parity

### User-validation prompt

Ask representative users to answer, without explanation:

1. What is the current or selected value?
2. Is it normal for this person?
3. What period is shown?
4. How much data exists in that period?
5. Where would they tap for more detail?

The design passes only if those answers are immediate and consistent.

### Acceptance criteria

- [ ] All feasible automated tests and builds pass.
- [ ] Any hardware-only or unavailable-platform verification gap is explicitly recorded.
- [ ] The five user questions are answered correctly in a brief usability review.
- [ ] Before/after screenshots demonstrate reduced chrome and a clearer primary reading.
- [ ] No analytics, protocol, or persisted values changed.

### Completion evidence

- Test/build output: _pending_
- Screenshot set: _pending_
- Accessibility notes: _pending_
- Usability notes: _pending_
- Known gaps: _pending_

---

## Files likely to change

### Shared Apple chart system

- `Packages/StrandDesign/Sources/StrandDesign/TrendChart.swift`
- `Packages/StrandDesign/Sources/StrandDesign/ChartHover.swift`
- `Packages/StrandDesign/Sources/StrandDesign/Resources/Localizable.xcstrings`
- `Packages/StrandDesign/Tests/StrandDesignTests/`

### Apple screens

- `Strand/Screens/TrendsView.swift`
- `Strand/Screens/MetricExplorerView.swift`
- `Strand/Screens/HealthView.swift`
- `Strand/Screens/SleepView.swift`
- `Strand/Screens/AsleepDurationCard.swift`
- `Strand/Screens/StagesCard.swift`
- `Strand/Screens/StressView.swift`
- `Strand/Screens/VitalSignsSummary.swift`
- `Strand/Screens/FusedRecordView.swift`
- `Strand/Screens/SettingsView.swift`
- `Strand/Resources/Localizable.xcstrings`
- `StrandTests/`

### Android shared chart system and screens

- `android/app/src/main/java/com/noop/ui/Charts.kt`
- `android/app/src/main/java/com/noop/ui/TrendsScreen.kt`
- `android/app/src/main/java/com/noop/ui/TrendsExploreScreen.kt`
- `android/app/src/main/java/com/noop/ui/HealthScreen.kt`
- `android/app/src/main/java/com/noop/ui/SleepScreen.kt`
- `android/app/src/main/java/com/noop/ui/SleepMetricCardsUi.kt`
- `android/app/src/main/java/com/noop/ui/SleepStageBreakdownUi.kt`
- `android/app/src/main/java/com/noop/ui/StressScreen.kt`
- `android/app/src/main/java/com/noop/ui/StepsCalibrationScreen.kt`
- `android/app/src/main/java/com/noop/ui/SettingsScreen.kt`
- `android/app/src/main/res/values/strings.xml`
- Focus-locale resource files
- `android/app/src/test/java/com/noop/ui/`

### Documentation

- `docs/superpowers/specs/YYYY-MM-DD-noop-chart-clarity-design.md`
- Relevant release notes after implementation

---

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| “WHOOP-like” becomes literal copying | Use the existing clean-room design principles and metric semantics, not proprietary assets or exact layouts. |
| Typical bands disagree between platforms | Consume existing baseline outputs and pin input/output fixtures on both platforms. |
| “Typical” silently becomes a UI-local statistic | Reuse the scoring fold, config, active-device history, and recalibration epochs through one read-only adapter; otherwise defer the band. |
| Android labels dates but still spaces samples uniformly | Add and test timestamp-aware X geometry before claiming calendar gaps or aligned windows. |
| Downsampling reconnects a known gap | Segment before downsampling and preserve first/last plus singleton segments in deterministic tests. |
| Dynamic Y domains mislead users | Show a visible baseline/typical band and use explicit domains by metric family. |
| Simplification removes useful detail | Move detail to metric explorer rather than deleting it. |
| Global period causes sparse cards | Show honest coverage and explicit all-history action instead of silent widening. |
| Gap thresholds create false breaks | Define thresholds from metric cadence and test edge cases. |
| Large chart refactor causes regressions | Migrate HRV/RHR first, retain compatibility defaults, then roll out family by family. |
| Swift package tests pass while app fails | Build both macOS and iOS app targets after every app-layer phase. |
| Android Canvas and Swift Charts diverge visually | Maintain a shared semantic contract and side-by-side screenshot review, not pixel equality. |
| Existing line/bar setting conflicts with new grammar | Defer removal until migrated charts are verified; preserve stored-key compatibility. |

---

## Summary dashboard

| Phase | Priority | Status | Dependency | Completion evidence |
|---|---:|---|---|---|
| 0. Baseline and visual contract | P0 | Completed with platform-verification gaps | None | Spec, inventory, static mockup, source validation, and product approval complete; native screenshots/accessibility checks unavailable on host |
| 1. Shared chart contract | P0 | Not started | Phase 0 | Pending |
| 2. HRV/RHR reference | P0 | Not started | Phase 1 | Pending |
| 3. Period honesty and gaps | P0 | Not started | Phase 2 | Pending |
| 4. Trends hierarchy | P1 | Not started | Phases 2–3 | Pending |
| 5. Metric-family rollout | P1 | Not started | Phase 4 | Pending |
| 6. Legacy option cleanup | P2 | Not started | Phase 5 | Pending |
| 7. Rendered QA and release gate | P0 | Not started | Selected implementation phases | Pending |

## Recommended first implementation slice

Implement only Phases 0–2 initially. HRV and resting HR provide the best test of whether the new grammar works because they need personal context, honest gaps, restrained scaling, units, selection, and cross-platform parity. Do not roll the system out to Charge, sleep, stress, or steps until that reference implementation passes visual and usability review.
