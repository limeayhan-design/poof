import Foundation
import SwiftUI

// Kid Mode (Family tier) — on-device only. Persisted in UserDefaults.
// When enabled on this device, every incoming file must be approved.
// Quiet hours auto-block incoming files silently.

enum KidControls {
    static let keyEnabled = "poof.kid.enabled"
    static let keyQuietStart = "poof.kid.quietStart" // "HH:mm"
    static let keyQuietEnd = "poof.kid.quietEnd" // "HH:mm"

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: keyEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: keyEnabled) }
    }

    static var quietStart: String {
        get { UserDefaults.standard.string(forKey: keyQuietStart) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: keyQuietStart) }
    }

    static var quietEnd: String {
        get { UserDefaults.standard.string(forKey: keyQuietEnd) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: keyQuietEnd) }
    }

    static func isInQuietHours(now: Date = Date()) -> Bool {
        let s = quietStart, e = quietEnd
        guard !s.isEmpty, !e.isEmpty, s != e,
              let start = minutesFrom(s), let end = minutesFrom(e) else { return false }
        let cal = Calendar.current
        let nowMin = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        return start < end ? (nowMin >= start && nowMin < end)
            : (nowMin >= start || nowMin < end)
    }

    private static func minutesFrom(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return h * 60 + m
    }
}

struct KidControlsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(KidControls.keyEnabled) private var enabled: Bool = false
    @State private var quietStart: Date = Self.dateFromHHMM(KidControls.quietStart) ?? Self.defaultQuietStart()
    @State private var quietEnd: Date = Self.dateFromHHMM(KidControls.quietEnd) ?? Self.defaultQuietEnd()

    private static let hhmmFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func dateFromHHMM(_ s: String) -> Date? {
        guard !s.isEmpty else { return nil }
        return hhmmFmt.date(from: s)
    }

    private static func hhmmFromDate(_ d: Date) -> String {
        hhmmFmt.string(from: d)
    }

    private static func defaultQuietStart() -> Date {
        Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private static func defaultQuietEnd() -> Date {
        Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
    }

    var body: some View {
        let accent = PoofTier.family.accent
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Approve or block incoming files on this device before they land.")
                        .font(.system(size: 13))
                        .foregroundColor(PoofTheme.textSecondary)

                    row {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Kid Mode").font(.system(size: 15, weight: .semibold))
                            Text("Every incoming file needs approval")
                                .font(.system(size: 12)).foregroundColor(PoofTheme.textTertiary)
                        }
                        Spacer()
                        Toggle("", isOn: $enabled)
                            .labelsHidden()
                            .tint(accent)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Quiet hours").font(.system(size: 15, weight: .semibold))
                            Text("Auto-block files during this window")
                                .font(.system(size: 12)).foregroundColor(PoofTheme.textTertiary)
                        }
                        HStack(spacing: 10) {
                            DatePicker("", selection: $quietStart, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                            Text("→").foregroundColor(PoofTheme.textTertiary)
                            DatePicker("", selection: $quietEnd, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                            Spacer()
                        }
                    }
                    .padding(14)
                    .glassCard(radius: PoofTheme.radiusMd)
                }
                .padding(18)
            }
            .background(PoofBackground())
            .navigationTitle("Kid controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        KidControls.quietStart = Self.hhmmFromDate(quietStart)
                        KidControls.quietEnd = Self.hhmmFromDate(quietEnd)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(accent)
                }
            }
        }
    }

    private func row(@ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 12) { content() }
            .padding(14)
            .glassCard(radius: PoofTheme.radiusMd)
    }
}
