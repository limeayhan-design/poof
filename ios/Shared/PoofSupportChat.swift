import Combine
import Foundation
import SwiftUI

// Sheet Support Chat — thread 1-to-1 entre l'utilisateur et l'équipe Poof.
// Bulles style iMessage (user à droite, admin à gauche). Backend REST minimal
// exposé par le server Render (routes /messages GET/POST + /admin/*).
// Poll léger toutes les 15s pour refresh les réponses.

struct SupportMessage: Identifiable, Codable, Equatable {
    let id: String
    let text: String
    let isAdmin: Bool
    let ts: TimeInterval

    var date: Date {
        Date(timeIntervalSince1970: ts)
    }
}

private struct SupportThread: Codable {
    var name: String?
    var messages: [SupportMessage]
}

@MainActor
final class PoofSupportClient: ObservableObject {
    static let shared = PoofSupportClient()

    @Published private(set) var messages: [SupportMessage] = []
    @Published private(set) var isSending = false
    @Published private(set) var lastError: String?

    private var pollTask: Task<Void, Never>?

    /// Force le serveur Render officiel — évite qu'un LAN gateway Bonjour
    /// (qui n'a pas les routes /messages) prenne le dessus via
    /// `PoofSession.signalingURL` et casse le chat avec un 404.
    private var baseURL: URL {
        URL(string: "https://poof-fgb8.onrender.com")!
    }

    private var deviceId: String {
        PoofDeviceIdentity.deviceId
    }

    private var displayName: String {
        let n = PoofProfileImage.shared.displayName
        return n.isEmpty ? PoofPlatform.deviceName : n
    }

    private init() {}

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        var comps = URLComponents(url: baseURL.appendingPathComponent("messages"), resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "deviceId", value: deviceId)]
        guard let url = comps?.url else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let thread = try JSONDecoder().decode(SupportThread.self, from: data)
            messages = thread.messages.sorted { $0.ts < $1.ts }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSending = true
        defer { isSending = false }

        // Insert optimiste — la bulle apparaît instantanément côté UI,
        // le poll suivant la confirmera avec l'id serveur.
        let optimistic = SupportMessage(
            id: UUID().uuidString,
            text: trimmed,
            isAdmin: false,
            ts: Date().timeIntervalSince1970
        )
        messages.append(optimistic)

        var req = URLRequest(url: baseURL.appendingPathComponent("messages"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "deviceId": deviceId,
            "name": displayName,
            "text": trimmed
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        _ = try? await URLSession.shared.data(for: req)
        await refresh()
    }
}

// MARK: - Sheet UI

struct PoofSupportChat: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var client = PoofSupportClient.shared
    @State private var draft: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0 / 255, green: 94 / 255, blue: 255 / 255),
                    Color(red: 121 / 255, green: 121 / 255, blue: 121 / 255)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                chatArea
                inputBar
            }
        }
        .task {
            await client.refresh()
            client.startPolling()
        }
        .onDisappear { client.stopPolling() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.white.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Poof Support")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundColor(.white)
                Text("We'll get back to you as soon as possible.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.65))
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.18)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    // MARK: - Chat

    @ViewBuilder
    private var chatArea: some View {
        if client.messages.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(client.messages) { msg in
                            MessageBubble(msg: msg)
                                .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .onChange(of: client.messages.count) { _, _ in
                    if let last = client.messages.last?.id {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bubble.left")
                .font(.system(size: 40, weight: .semibold))
                .foregroundColor(.white.opacity(0.55))
            Text("No message yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.75))
            Text("Write to us: idea, bug, question — we read everything.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Write a message…", text: $draft, axis: .vertical)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .focused($inputFocused)
                .lineLimit(1 ... 4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(Color.white.opacity(0.15))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.6))
                )

            Button {
                let text = draft
                draft = ""
                Task { await client.send(text) }
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white))
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Color.black.opacity(0.20)
                .overlay(Rectangle().fill(Color.white.opacity(0.10)).frame(height: 0.5), alignment: .top)
        )
    }
}

// MARK: - Bubble

private struct MessageBubble: View {
    let msg: SupportMessage

    var body: some View {
        HStack {
            if !msg.isAdmin {
                Spacer(minLength: 40)
            }
            VStack(alignment: msg.isAdmin ? .leading : .trailing, spacing: 3) {
                if msg.isAdmin {
                    Text("Poof team")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(.white.opacity(0.65))
                        .padding(.leading, 2)
                }
                Text(msg.text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(msg.isAdmin ? .white : .black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleBackground)
                Text(shortTime)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.horizontal, 4)
            }
            if msg.isAdmin {
                Spacer(minLength: 40)
            }
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if msg.isAdmin {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.6)
                )
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
        }
    }

    private var shortTime: String {
        let df = DateFormatter()
        df.locale = Locale.current
        if Calendar.current.isDateInToday(msg.date) {
            df.dateFormat = "HH:mm"
        } else {
            df.dateFormat = "d MMM · HH:mm"
        }
        return df.string(from: msg.date)
    }
}

#Preview {
    PoofSupportChat()
}
