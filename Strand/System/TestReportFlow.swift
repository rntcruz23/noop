import Foundation
import StrandAnalytics

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Drives the in-app "Report" action (spec section 5.2): build plus save the redacted .zip, open the
/// prefilled GitHub issue, then toast the user to attach the file. The decision logic lives in `Plan`
/// (pure, unit-tested); `run` performs the side effects over the shipped share path. The bundle is
/// already redacted by TestBundleAssembler (meta.redaction="v2"); this flow never re-scrubs.
///
/// Group B owns the assembler primitives (redactEntries, capEntries) and FileExport.exportBundle;
/// Group C owns the deep-link and this flow. The caller assembles the already-redacted, already-capped
/// entries (the Group D orchestrator composes redactEntries + capEntries + meta.json) and hands them
/// here, so this file depends only on the Group A/B/C contracts and stays compilable on its own.
enum TestReportFlow {

    /// Pure decisions, no side effects, so they are testable on any actor.
    enum Plan {
        /// noop-<profile>-<platform>-v<version>-<yyMMdd-HHmm>.zip (spec section 5.1). Delegates the
        /// stamp to FileExport.bundleName so the filename matches the export layer exactly.
        static func bundleName(profile: TestDomain, platform: String, version: String,
                               date: Date = Date()) -> String {
            FileExport.bundleName(profile: profile.id, platform: platform, version: version, date: date)
        }

        /// The toast shown after the issue page opens, naming the exact saved file to attach.
        static func attachToast(savedName: String) -> String {
            "Saved as \(savedName). On the next screen tap the paperclip and pick it."
        }

        /// GitHub's mobile composer can't reliably attach a .zip, so iOS also offers "Copy report.txt".
        /// macOS Finder drag-drop works, so the fallback is mobile-only.
        static func offersCopyFallback(platform: String) -> Bool {
            platform.lowercased() == "ios"
        }
    }

    /// The review gate is mandatory and not skippable (spec section 12): the flow only proceeds once
    /// the user has explicitly confirmed the review.
    static func shouldProceed(gate: ReportReviewGate) -> Bool { gate.isCleared }

    /// Save/share the already-redacted bundle, open the prefilled issue, and toast. `entries` is the
    /// redacted, capped bundle the caller assembled (the Group D orchestrator builds it from
    /// TestBundleAssembler.redactEntries + capEntries + meta.json). `showToast` and `copyToPasteboard`
    /// are injected so the call site supplies the platform presenters. Review-before-share is mandatory:
    /// nothing is shared, no URL opened and no toast shown until the gate is cleared (spec section 12).
    @MainActor
    static func run(profile: TestDomain, title: String,
                    version: String, platform: String, osVersion: String,
                    gate: ReportReviewGate,
                    entries: [FileExport.BundleEntry],
                    showToast: @escaping (String) -> Void,
                    copyToPasteboard: @escaping (String) -> Void) {
        // Review-before-share is mandatory: do nothing until the user has confirmed.
        guard shouldProceed(gate: gate) else { return }
        let name = Plan.bundleName(profile: profile, platform: platform, version: version)
        _ = FileExport.exportBundle(entries: entries, suggestedName: name)
        if let url = TestReportLink.reportURL(profile: profile, title: title,
                                              version: version, platform: platform, osVersion: osVersion) {
            #if canImport(UIKit)
            UIApplication.shared.open(url)
            #elseif canImport(AppKit)
            NSWorkspace.shared.open(url)
            #endif
        }
        showToast(Plan.attachToast(savedName: name))
        if Plan.offersCopyFallback(platform: platform),
           let report = entries.first(where: { $0.name == "report.txt" }),
           let text = String(data: report.data, encoding: .utf8) {
            // Offer the copy fallback by priming the pasteboard closure; the UI exposes a "Copy report.txt"
            // button bound to this same text so a mobile user who can't attach can paste a <details> block.
            copyToPasteboard(text)
        }
    }
}
