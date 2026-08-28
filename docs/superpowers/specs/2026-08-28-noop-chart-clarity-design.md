# NOOP chart clarity design specification

Date: 2026-08-28
Status: Approved 2026-08-28
Scope: Phase 0 design contract and phased implementation requirements
Related inventory: `docs/superpowers/specs/2026-08-28-noop-chart-inventory.md`
Reference mockup: `docs/superpowers/specs/assets/2026-08-28-chart-clarity-reference.svg`

## Goal

Make NOOP charts answer five questions without requiring users to interpret chart mechanics:

1. What is the current or selected value?
2. Is it normal for this person?
3. What period is shown?
4. How much data exists in that period?
5. Where is more detail available?

The design uses ideas from the sampled reference in `docs/superpowers/specs/2026-06-22-whoop-design-language.md`, but retains NOOP terminology, components, tokens, and clean-room implementation.

## Scope boundaries

- Presentation only. Do not alter metric formulas, persisted values, migrations, protocol decoding, or source precedence.
- Keep `Charge`, `Rest`, and `Effort` as the user-facing names.
- Maintain feature-level Apple/Android parity.
- Use only `StrandPalette`, `StrandFont`, `NoopMetrics`, `Palette`, `NoopType`, and `Metrics` tokens.
- Do not market an observed range, population range, or independently folded presentation band as the scoring baseline.
- Do not promise a typical band when its source cannot be identified and reproduced on both platforms.

## Approved-by-default decisions

These defaults were approved for Phase 1 on 2026-08-28.

1. **D1 — Trends hierarchy:** one selectable hero metric followed by compact metric rows.
2. **D2 — Default hero:** Charge, preserving today's primary Trends emphasis.
3. **D3 — Terminology:** retain Charge, Rest, and Effort.
4. **D4 — Chart choice:** summary geometry is fixed by metric semantics. The global line/bar preference does not control migrated summary charts. Preserve its stored key until the later compatibility phase.
5. **D5 — Typical-range source:** HRV and resting-HR reference cards use the existing `VitalBands` definition of personal normality, not a new interpretation of scoring state.
6. **D6 — Calendar geometry:** Android daily charts use calendar-day X positions. Dates determine spacing; list indices do not.
7. **D7 — Daily gaps:** a daily line breaks when consecutive valid samples are more than one calendar day apart. A missing day therefore remains visible as empty horizontal space.
8. **D8 — Period honesty:** every summary card honors the selected global period. It never silently widens.
9. **D9 — Summary axes:** summary charts have at most three X labels and no persistent Y-axis.
10. **D10 — Selection:** selection updates the card's primary value and date. It does not cover the plot with a floating tooltip.

## Semantic chart matrix

| Metric family | Summary geometry | Required context | Color meaning | Domain rule |
|---|---|---|---|---|
| Charge | Daily dots or short columns | Established Charge zones and period average | Red/yellow/green status only | Fixed 0–100 |
| Effort | Daily bars | Goal or personal load context when already available | Blue metric identity only | Zero-based; labels honor selected 0–100 or 0–21 display scale |
| HRV | Line | Trusted personal typical band or explicit population fallback | Purple metric identity; status is text/icon, not line gradient | Includes visible band and samples with restrained padding |
| Resting HR | Line | Trusted personal typical band or explicit population fallback | Rose metric identity; status is text/icon | Includes visible band and samples with restrained padding |
| Rest duration | Nightly bars | Existing sleep need/goal when available | Slate-blue Rest identity | Zero-based |
| Sleep stages | Timestamped categorical timeline | Stage duration and percentage | Existing stage palette only | True onset-to-wake time |
| Skin-temperature deviation | Line around zero | Zero reference and compatible typical-deviation band | Temperature accent only | Symmetric around zero where practical |
| Stress | Stepped/filled series | Fixed calm/steady/elevated zones | Existing stress zones | Fixed 0–3 |
| Steps | Daily bars | Existing goal or personal average | One accent plus muted reference | Zero-based |
| Training load | Two lines | CTL/ATL labels and form explanation | Categorical series identity | Shared zero-based load domain |
| Heatmaps | Calendar cells | Explicit no-data cell and legend | Intensity/status appropriate to metric | Fixed calendar geometry |
| Diagnostic plots | Existing specialized geometry | Method-specific labels | Non-alarm unless diagnostic meaning requires it | Method-defined fixed domain when comparability matters |

## Summary-card contract

A migrated summary card contains, in reading order:

1. Metric label.
2. One primary value.
3. A muted selected/latest date when selection is active.
4. One context sentence:
   - `Within your typical range`,
   - `Above your typical range`,
   - `Below your typical range`,
   - or an explicitly named population fallback.
5. Coverage text.
6. The plot.
7. A clear detail-navigation affordance.

The default card does not repeat the primary value in a footer. Mean, minimum, maximum, distribution details, and methodology remain in metric detail.

### HRV reference card

The checked-in SVG contains the visual phone and wide-layout reference. The text schematic below documents its information order.

Static phone-width reference:

```text
┌──────────────────────────────────────┐
│ HRV                              ›   │
│ 58 ms                                │
│ Within your typical range            │
│ 24 of 30 nights                      │
│                                      │
│        ┌─ muted typical band ─┐      │
│   ╱╲  ╱╲__    ╱╲      ╱╲__           │
│ _╱  ╲╱    ╲__╱  ╲____╱    ●          │
│ 30 Jul          13 Aug         28 Aug│
└──────────────────────────────────────┘
```

Wide reference: retain the same hierarchy. Give the plot additional width, not extra axes or duplicated statistics. The primary value/context column may occupy the leading quarter while the plot occupies the remainder.

### Resting-HR reference card

```text
┌──────────────────────────────────────┐
│ RESTING HR                       ›   │
│ 52 bpm                               │
│ 3 bpm below your baseline            │
│ 27 of 30 nights                      │
│                                      │
│        ┌─ muted typical band ─┐      │
│ __    ╱╲       __                     │
│   ╲__╱  ╲_____╱  ╲________●           │
│ 30 Jul          13 Aug         28 Aug│
└──────────────────────────────────────┘
```

For resting HR, lower is not automatically rendered green. The text explains direction; status color is used only when the established physiological classification supports it.

## Baseline and typical-range contract

### Existing sources

NOOP has two related but distinct baseline uses:

1. Recovery scoring state in `Baselines` / `IntelligenceEngine`.
2. Health presentation classification in `VitalBands`.

Scoring history merges imported daily values with baseline-independent computed nights, applies active-device day ownership to raw data, and honors separate recalibration epochs for HRV and recovery-wide metrics. Device-era truncation exists but is not currently applied to HRV/RHR scoring. This trace explains why the presentation work must not claim to expose or modify the scoring baseline.

`VitalBands` independently folds calendar-padded history excluding the displayed day. When the state is trusted and not stale, it classifies against personal `baseline ± 2 × 1.253 × spread`, subject to physiological guards. Otherwise it uses an explicitly named population range:

- HRV: 40–120 ms.
- Resting HR: 40–60 bpm.

Relevant implementation:

- `Packages/StrandAnalytics/Sources/StrandAnalytics/VitalBands.swift:3`
- `android/app/src/main/java/com/noop/analytics/VitalBands.kt:6`
- `Strand/Screens/VitalSignsSummary.swift:360`
- `android/app/src/main/java/com/noop/ui/HealthVitalsLogic.kt:323`

### Approved display decision

Use `VitalBands` as the source of display context because it already defines the user-facing personal/population distinction and stale behavior on both platforms. This is an explicitly approved presentation range, not the recovery-scoring baseline. The UI must never label it as scoring state or feed it back into scoring.

A pure presentation result should expose:

- basis: personal or population;
- center when personal;
- lower and upper display bounds;
- valid-night count;
- baseline status;
- classification of the selected/latest value.

For a trusted personal state:

```text
sigma = 1.253 × spread
lower = max(cfg.minVal, baseline - 2 × sigma)
upper = min(cfg.maxVal, baseline + 2 × sigma)
```

For calibrating, provisional, or stale state, use the metric's named population range and label it as a general range. Do not call it `your typical range`.

The Swift output over fixed fixtures is the parity oracle for Kotlin. Required fixtures include cold start, provisional, trusted, stale, duplicates after existing source resolution, malformed day keys, missing calendar days, and physiological guards. Recalibration epochs are not part of `VitalBands` and must not be added as an accidental scoring dependency.

## Period and coverage contract

### Window definition

- `W`, `M`, `3M`, `6M`, and `1Y` are trailing inclusive calendar-day windows ending on the device's current local day.
- Expected days equal the selected range's day count: 7, 30, 90, 180, or 365.
- `ALL` starts at the earliest valid row in the resolved series and ends on the current local day. Its expected count is that inclusive calendar span.
- A future-dated row is excluded.
- Invalid day keys and non-finite values are not observations.
- Duplicate readings for one metric/day count once after the existing source-resolution rule chooses the value.
- HRV, RHR, Charge, Effort, Rest, and sleep-duration coverage is expressed as nights or days according to how the metric is produced.

### Coverage wording

- `24 of 30 nights`
- `6 of 7 days`
- For ALL: `412 nights across 3 years` or the localized equivalent, avoiding an unwieldy expected-day denominator in the visible card. Accessibility may include the exact inclusive span.
- One valid point is still coverage. It does not become a line.
- Zero valid points shows an empty state and an explicit `Show all available history` action when older data exists.

## Calendar positioning and gap contract

For daily/nightly charts:

1. Parse canonical `yyyy-MM-dd` keys as calendar dates, independent of wall-clock time and DST.
2. Compute X from integer calendar-day distance from the selected window start.
3. Use the full selected window as the X domain, not first-to-last observed point. This aligns neighboring cards and exposes stale starts/ends.
4. Break a line whenever the next valid sample is more than one calendar day after the prior valid sample.
5. Retain both boundary samples. A one-point segment renders a dot.
6. Downsample within each segment. Never downsample across a segment boundary.
7. Selection searches full-resolution valid samples and snaps to the nearest X position.

Intraday charts require a cadence-specific threshold defined by their producer. Phase 1 changes only the shared daily Trends reference path; it must not impose a daily threshold on live HR or sleep streams.

## Axes and domain

Summary mode:

- Maximum three X labels: selected-window start, midpoint, and end.
- No persistent Y-axis labels or grid.
- The X labels represent window boundaries, even when those dates have no observation.
- Line domains include all visible samples and the context band.
- Add restrained padding without implying a zero baseline for line metrics.
- Bars always include zero.
- Flat line series remain centered within a useful domain derived from the context band or metric fallback.

Detail mode may retain denser axes, gridlines, full statistics, and richer selection.

## Selection behavior

- No selection: primary reading is the latest valid sample in the selected window.
- Pointer hover, tap, or horizontal drag: snap to nearest valid full-resolution sample.
- While selected, replace the card's primary value and muted date. Do not draw a floating tooltip over the data.
- Draw one selected point and a subtle vertical rule.
- On pointer exit or touch release, return to latest. Accessibility actions may step previous/next without automatic reset.
- Bar summary cards may select bars using the same contract; fixed semantic geometry must not remove inspection.

## Accessibility contract

Treat the card as one coherent accessible group. Its value must include:

- metric name;
- selected or latest value and date;
- personal/population context;
- selected period;
- observed coverage;
- whether gaps exist;
- navigation hint for details.

Do not expose one accessibility node per point, bar, band, or axis mark. Decorative range bands, grids, and endpoint effects are hidden. Android must verify that the card-level semantics are not replaced by a nested chart's `clearAndSetSemantics`.

Example:

```text
HRV. 58 milliseconds on 28 August. Within your typical range of 46 to 71 milliseconds. Trailing 30 days, 24 nights recorded, 2 gaps. Open metric details.
```

## Color and chrome

- HRV line: existing purple metric token.
- RHR line: existing rose metric token.
- Typical band: same metric color at a low-opacity design token; it is context, not status.
- Primary values: primary text color.
- Context and coverage: secondary or tertiary text colors.
- Positive/warning/critical colors appear only for established status semantics.
- No decorative value gradient on HRV or RHR summary lines.
- No persistent area fill on HRV or RHR summary lines.
- Only the latest or selected point is visible.

## Phase 1 implementation boundaries

Phase 1 should extend existing primitives rather than introduce an all-purpose parallel chart framework.

Apple:

- Extend `TrendPoint` / `TrendChart` with summary/detail chrome and range-band input.
- Preserve explicit segments through `ChartDownsample`; downsample each segment independently.
- Keep existing callers on compatibility defaults.

Android:

- Extend `LineChart` with index-aligned calendar positions or epoch days.
- Reuse `segmentIds` and `lineChartSegmentRanges`.
- Add summary/detail chrome and range-band input.
- Keep existing index-spaced callers unchanged unless they opt in.

Both:

- Phase 1 adds mirrored pure geometry helpers for normalized calendar X positions and date-derived segments.
- Phase 2 adds the approved inclusive-window and coverage helpers at the HRV/RHR caller layer, plus the read-only `VitalBands` presentation result.
- Phase 3 applies those proven caller policies to the remaining Trends metrics; it does not reimplement the geometry helpers.
- Verify mirrored helpers using standalone Swift output copied verbatim into Kotlin expected fixtures.
- Add no scoring formula, storage, migration, or BLE changes.

## Phase 1 acceptance criteria

- Existing callers preserve current behavior unless explicitly migrated.
- Summary mode renders no persistent Y axis, no area fill, and no point markers except latest/selected.
- The shared primitive can render a caller-supplied contextual range without assigning it analytics meaning; Phase 2 supplies the documented `VitalBands` basis and labels.
- Daily Android X spacing matches elapsed calendar days and selected-window boundaries.
- Missing daily intervals produce visible width and separate line segments on both platforms.
- Downsampling cannot reconnect segments or remove a singleton segment.
- Selection and accessibility use full-resolution samples.
- Summary X labels never exceed three.
- One- and zero-point states remain honest.

## Verification plan

Automated:

```bash
# macOS
cd Packages/StrandDesign && swift test
cd ../StrandAnalytics && swift test
cd ../..
xcodegen generate
xcodebuild -project Strand.xcodeproj -scheme Strand \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
xcodebuild -project Strand.xcodeproj -scheme NOOPiOS \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build

# Android
cd android
./gradlew testFullDebugUnitTest --tests 'com.noop.ui.*Chart*' --tests 'com.noop.analytics.*VitalBands*'
./gradlew compileFullDebugKotlin
```

Rendered validation requires:

- phone width and wide desktop/tablet width;
- dense, sparse, gapped, one-point, no-data, flat, and outlier fixtures;
- light/dark appearances if both are enabled;
- Dynamic Type / Android font scaling;
- VoiceOver and TalkBack;
- pointer hover, touch drag, and keyboard/accessibility navigation.

## Phase 0 evidence and limitations

Completed:

- Source inventory and semantic classification.
- Cross-platform gap/domain/period/accessibility comparison.
- Baseline source trace and explicit separation between scoring state and `VitalBands` presentation context.
- HRV/RHR static SVG and text mockups.
- Phase 1 contract and acceptance criteria.

Unavailable on this host:

- Apple screenshots and app rendering: `xcodebuild` is unavailable.
- Android screenshots and TalkBack checks: neither `adb` nor an emulator is available.
- The SVG was parsed successfully and loaded by Chromium at its native 1440 × 980 viewport. Automated visual interpretation was unavailable because no vision provider is configured.

These are recorded as verification gaps, not silently treated as complete evidence.
