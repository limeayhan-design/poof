import SwiftUI

// Send a text note directly to the peer over the control channel.

struct SendTextSheet: View {
    @EnvironmentObject var session: PoofSession
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                PoofBackground()
                VStack(alignment: .leading, spacing: 14) {
                    Text("Sent as a text note to your selected device.")
                        .font(.system(size: 13))
                        .foregroundColor(PoofTheme.textSecondary)

                    TextEditor(text: $text)
                        .scrollContentBackground(.hidden)
                        .font(.system(size: 16))
                        .foregroundColor(PoofTheme.textPrimary)
                        .padding(12)
                        .frame(minHeight: 220)
                        .glassCard()
                        .focused($focused)

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Send text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(PoofTheme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Send") {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        session.sendText(trimmed)
                        dismiss()
                    }
                    .foregroundColor(PoofTheme.accent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
    }
}
