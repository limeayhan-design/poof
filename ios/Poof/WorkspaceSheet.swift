import SwiftUI

// Business tier: edit workspace name, logo char, accent color.
// All persisted in UserDefaults via BusinessWorkspace.

struct WorkspaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(BusinessWorkspace.keyName) private var name: String = ""
    @AppStorage(BusinessWorkspace.keyLogo) private var logo: String = BusinessWorkspace.defaultLogo
    @AppStorage(BusinessWorkspace.keyColor) private var color: String = BusinessWorkspace.defaultColor

    private var accent: Color {
        Color(hex: color) ?? PoofTier.business.accent
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PoofBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        preview
                        nameBlock
                        logoBlock
                        colorBlock
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Workspace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(accent)
                }
            }
        }
    }

    private var preview: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(
                        colors: [accent, accent.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 52, height: 52)
                Text(logo)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? "Your workspace" : name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(PoofTheme.textPrimary)
                    .lineLimit(1)
                Text("Live preview")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(PoofTheme.textTertiary)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: PoofTheme.radiusMd)
    }

    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("WORKSPACE NAME")
            TextField("Acme Corp", text: $name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(true)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(PoofTheme.textPrimary)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: PoofTheme.radiusSm, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: PoofTheme.radiusSm)
                        .strokeBorder(PoofTheme.glassStroke, lineWidth: 1)
                )
        }
    }

    private var logoBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("LOGO (1–2 CHARACTERS)")
            TextField("P", text: Binding(
                get: { logo },
                set: { logo = String($0.prefix(2)) }
            ))
            .autocorrectionDisabled(true)
            .font(.system(size: 20, weight: .heavy, design: .rounded))
            .foregroundColor(PoofTheme.textPrimary)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: PoofTheme.radiusSm, style: .continuous)
                    .fill(Color.black.opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: PoofTheme.radiusSm)
                    .strokeBorder(PoofTheme.glassStroke, lineWidth: 1)
            )
        }
    }

    private var colorBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("ACCENT COLOR")
            HStack(spacing: 10) {
                ForEach(BusinessWorkspace.colorPresets, id: \.self) { hex in
                    let c = Color(hex: hex) ?? PoofTier.business.accent
                    let selected = hex.lowercased() == color.lowercased()
                    Button {
                        color = hex
                    } label: {
                        Circle()
                            .fill(c)
                            .frame(width: 36, height: 36)
                            .overlay(
                                Circle().strokeBorder(
                                    selected ? Color.white : Color.white.opacity(0.15),
                                    lineWidth: selected ? 3 : 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(PoofTheme.textTertiary)
            .kerning(0.6)
    }
}
