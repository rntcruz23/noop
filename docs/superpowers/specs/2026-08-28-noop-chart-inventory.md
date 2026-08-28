# NOOP chart inventory

Date: 2026-08-28

Status: Phase 0 inventory complete from source inspection. Rendered screenshots remain pending because the current host has neither Xcode nor an Android device/emulator.

This inventory classifies production data visualizations. Decorative canvases, score rings, and simple progress indicators are excluded. Line references describe the source as reviewed on 2026-08-28 and may move.

## Shared primitives

| Platform | Primitive | Geometry and domain | Interaction | Gap and accessibility behavior |
|---|---|---|---|---|
| Apple | `TrendChart` (`Packages/StrandDesign/Sources/StrandDesign/TrendChart.swift:15`) | Date-positioned line/area or zero-based bars; caller supplies value/color range and optional Y domain | Pointer hover with nearest full-resolution point | Supports explicit segment IDs. Missing dates without new segment IDs connect. One collapsed VoiceOver summary. Dense drawing is min/max downsampled. |
| Apple | `OverviewHRChart` (`Packages/StrandDesign/Sources/StrandDesign/OverviewHRChart.swift:19`) | Timestamped line/area with sleep and event overlays | Hover; optional touch scrub, zoom, and pan | Internal acquisition gaps can connect. Its fixed HR accessibility label is inaccurate when reused for other Deep Timeline metrics. |
| Apple | `Sparkline` (`Packages/StrandDesign/Sources/StrandDesign/Sparkline.swift:12`) | Index-spaced, auto-fit line with optional fill | Pointer hover | Cannot represent missing dates or irregular spacing. Collapsed summary. |
| Apple | `Hypnogram` (`Packages/StrandDesign/Sources/StrandDesign/Hypnogram.swift:17`) | Time-proportional categorical bands/ribbon | Hover and selected-stage highlight | Uncovered time remains visible. Collapsed per-stage duration summary. |
| Apple | `MotionTrace` (`Packages/StrandDesign/Sources/StrandDesign/MotionTrace.swift:15`) | Index-spaced nightly movement trace, normalized to that night's peak | None | Requires two epochs; collapsed movement summary. |
| Apple | `YearHeatStrip` (`Packages/StrandDesign/Sources/StrandDesign/YearHeatStrip.swift:13`) | Monday-first daily calendar cells | Hover | Nil-score days are muted outlined cells. Collapsed annual summary. |
| Android | `LineChart` (`android/app/src/main/java/com/noop/ui/Charts.kt:226`) | Index-spaced min/max line with optional fill | Optional tap and drag | Explicit `segmentIds` break lines, but removed/non-finite samples otherwise collapse. One `clearAndSetSemantics` summary. |
| Android | `BarChart` (`android/app/src/main/java/com/noop/ui/Charts.kt:538`) | Zero-based rounded bars | Optional tap | Missing/non-finite and negative values become zero. One collapsed summary. |
| Android | `Sparkline` (`android/app/src/main/java/com/noop/ui/Charts.kt:162`) | Index-spaced min/max line | None | Cannot represent missing time. One collapsed summary. |
| Android | `TimelineChart` (`android/app/src/main/java/com/noop/ui/Charts.kt:959`) | Timestamp-positioned line/area over a visible interval | Pinch zoom and pan | Preserves elapsed-time width but connects across gaps. One visible-window summary. |
| Android | sleep chart implementations (`android/app/src/main/java/com/noop/ui/SleepStageBreakdownUi.kt:117`) | Proportional strip or timestamped filled/ribbon hypnogram | Mostly none | Timestamped form preserves empty width; transition risers may imply continuity across gaps. |

## Trends and metric-history charts

| Surface | Metrics | Current semantics | Main clarity risk |
|---|---|---|---|
| Apple Trends (`Strand/Screens/TrendsView.swift:15`) | Charge, HRV, RHR, Effort, Rest, training load | W/M/3M/6M/1Y/ALL, default 3M. Each metric auto-widens independently. Full Y axis, area, endpoint, mean/min/max/trend. Global line/bar switch. | Duplicate average, inconsistent effective periods, absent dates connect, bars and lines use materially different baselines. |
| Android Trends (`android/app/src/main/java/com/noop/ui/TrendsScreen.kt:95`) | Same feature set | Mirrors Apple period widening and footer. `LineChart` is index-spaced; first/middle/last date labels do not change point geometry. | Missing dates are compressed; line/bar choice changes apparent scale and removes selection in bar mode. |
| Apple metric explorer (`Strand/Screens/MetricExplorerView.swift:1049`) | Catalog metrics | Date-positioned `TrendChart`, fitted domain, sparse widening | Most missing dates connect; generic accessibility label for some metrics. |
| Android Trends Explore (`android/app/src/main/java/com/noop/ui/TrendsExploreScreen.kt:620`) | Catalog metrics | Index-spaced `LineChart`, fitted domain, sparse widening | Missing dates compress; generic accessibility summary. |
| Apple Health import (`Strand/Screens/AppleHealthView.swift:567`) | RHR, HRV, SpO2, respiration, steps, energy, body composition, sleep | W/M/3M/6M/1Y/ALL with per-series widening | Missing dates connect and effective periods differ. |
| Android Health import (`android/app/src/main/java/com/noop/ui/AppleHealthScreen.kt:356`) | Same family | Same period set and widening; no chart selection | Missing dates compress; metric/unit context is absent from shared spoken summary. |
| Apple/Android vital detail (`Strand/Screens/MetricExplorerView.swift:1049`; `android/app/src/main/java/com/noop/ui/HealthScreen.kt:2020`) | Health vital selected by user | Fitted line; Android supports date/value scrub; VO2max method changes use segments | Missing days remain unsegmented except method changes. |
| Apple stress history (`Strand/Screens/StressView.swift:532`) | Daily stress 0–3 | Fitted display domain with fixed stress color range | Missing days connect; short ranges can widen. |
| Android stress history (`android/app/src/main/java/com/noop/ui/StressScreen.kt:1021`) | Daily stress 0–3 | Fitted line, W/M/3M/6M/1Y/ALL; fewer than two points falls back to all history | A fixed-scale metric is drawn with local min/max and missing days compress. |
| Compare (`Strand/Screens/CompareView.swift:722`; `android/app/src/main/java/com/noop/ui/CompareScreen.kt:800`) | Multiple heterogeneous metrics | Each series independently normalizes to 0–1 over union dates | Missing dates have horizontal width but surviving points connect; sparse series may widen independently. |

## Intraday and session charts

| Surface | Geometry/period | Gap behavior | Accessibility concern |
|---|---|---|---|
| Today HR (`Strand/Screens/TodayView.swift:3283`; `android/app/src/main/java/com/noop/ui/TodayScreen.kt:5894`) | One-day HR with sleep/workout/Charge/Effort overlays | Timestamp labels exist, but gaps can be bridged; Android line itself remains index-spaced | Android parent/child semantics merge needs rendered TalkBack verification. |
| Deep Timeline (`Strand/Screens/FullDayChartView.swift:241`; `android/app/src/main/java/com/noop/ui/FullDayChartScreen.kt:277`) | HR, HRV, temperature, SpO2, respiration; selected day within three-day pan bounds | Time width is preserved, but gaps connect | Apple shared chart announces heart rate even for non-HR metrics. |
| Live Health HR (`Strand/Screens/HealthView.swift:393`; `android/app/src/main/java/com/noop/ui/HealthScreen.kt:1343`) | Rolling live HR | Elapsed-time gap width is preserved only in local implementations; no break | Custom chart summaries are absent or weak. |
| Workout HR (`Strand/Screens/WorkoutDetailView.swift:377`; `android/app/src/main/java/com/noop/ui/WorkoutsScreen.kt:1611`) | One workout | Missing samples connect | Generic summary on Android. |
| Workout HR recovery (`Strand/Screens/WorkoutsView.swift:1816`; `android/app/src/main/java/com/noop/ui/WorkoutsScreen.kt:1749`) | 1/2/5-minute recovery series across workouts | Missing interval results are omitted and surviving values connect | Apple is label-only; period can be coerced to 90 days despite broader workout selection. |
| Intraday stress (`Strand/Screens/StressView.swift:953`; `android/app/src/main/java/com/noop/ui/StressScreen.kt:639`) | Hourly 0–3 series for today | Android explicitly breaks null runs and draws isolated dots. Apple connects remaining scored hours. | Apple and Android gap semantics differ. |

## Sleep visualizations

| Visualization | Paths | Semantics |
|---|---|---|
| Stage hypnogram/timeline | `Strand/Screens/SleepView.swift:760`; `Strand/Screens/StagesCard.swift:160`; `android/app/src/main/java/com/noop/ui/SleepStageBreakdownUi.kt:117` | Categorical stage time, not a conventional trend line. Timestamped variants preserve duration and gaps; proportional variants may compress unrepresented time. |
| Sleeping HR | `Strand/Screens/SleepView.swift:1537`; `android/app/src/main/java/com/noop/ui/SleepScreen.kt:1284` | Apple breaks gaps over five minutes. Android compacts missing buckets and connects. |
| Motion trace | `Strand/Screens/SleepView.swift:883`; `android/app/src/main/java/com/noop/ui/SleepScreen.kt:2124` | Night-relative diagnostic shape. Not suitable for cross-night magnitude comparison. |
| Asleep duration | `Strand/Screens/AsleepDurationCard.swift:13`; `android/app/src/main/java/com/noop/ui/SleepMetricCardsUi.kt:473` | Zero-based nightly bars. Apple uses trailing 30 days; Android card uses trailing 14 days, so period parity needs an explicit product decision. |
| Sleep debt | `Strand/Screens/SleepDebtLedgerCard.swift:16`; `android/app/src/main/java/com/noop/ui/SleepMetricCardsUi.kt:515` | Signed deficit/surplus around zero on Apple; Android currently uses a zero-based debt bar treatment. Semantics require parity review before visual rollout. |
| Stages versus typical | `Strand/Screens/StagesVsTypicalCard.swift:14`; Android stage breakdown components | Range/marker comparison, not a time series. Keep separate from the trend-chart contract. |

## Other quantitative visualizations

- Training load: `Strand/Screens/TrainingLoadCard.swift:8`, `android/app/src/main/java/com/noop/ui/TrainingLoadCard.kt:67`. Two continuous CTL/ATL lines over engine-defined contiguous history; custom charts have weak semantics.
- Active-calorie heatmap: `Strand/Screens/WorkoutsView.swift:829`, `android/app/src/main/java/com/noop/ui/WorkoutsScreen.kt:830`. Fixed 13-week calendar; no-data cells are explicit.
- Hydration history: `android/app/src/main/java/com/noop/ui/HydrationScreen.kt:473`. Fixed seven-day bars; missing versus recorded zero is not explicit.
- Insights dose response: `Strand/Screens/InsightsHubView.swift:412`, `android/app/src/main/java/com/noop/ui/InsightsHubScreen.kt:430`. Symmetric outcome-delta domain around zero; not a time series.
- Rhythm Poincare: `Strand/Screens/RhythmView.swift:182`, `android/app/src/main/java/com/noop/ui/RhythmScreen.kt:415`. Fixed 300–1500 ms square scatter; surrounding text carries accessibility.
- Lab Book sparklines: `Strand/Screens/LabBookView.swift:366`, `android/app/src/main/java/com/noop/ui/LabBookScreen.kt:355`. Index-spaced decorative history.
- Route polyline: `android/app/src/main/java/com/noop/ui/RouteCanvas.kt:16` and Apple map surfaces. This is spatial geometry, outside the trend contract.
- Exported report sparklines: `Strand/Screens/TrendsReportView.swift:286`, `android/app/src/main/java/com/noop/ui/TrendsReport.kt:384`. Noninteractive image content.

## Cross-platform conclusions

1. Daily chart X semantics are not equivalent. Swift Charts uses dates; the shared Android line uses indices.
2. Missing-data behavior is inconsistent. Most daily charts bridge or compress gaps; Android intraday stress and Apple sleeping HR are useful honest-gap references.
3. The global Trends line/bar preference changes both geometry and scale. It cannot remain authoritative for semantically fixed summary charts.
4. Accessibility is strongest in shared primitives but weak in several custom canvases. Metric, selected/latest value, context, period, and coverage should be supplied by the surrounding card as one semantic unit.
5. Period widening is widespread and inconsistent. Trends must stop widening cards independently before claiming a shared selected period.
6. Color currently means metric identity, physiological status, or signed direction depending on the chart. The design contract must assign only one role within each chart.
