import Combine
import Foundation
import SwiftUI

// Admin inbox — vue support pour toi (Poof team). Nécessite le
// SUPPORT_ADMIN_TOKEN configuré sur Render. Persisté local via @AppStorage
// (jamais dans le code source). Liste des threads → détail → reply.

@MainActor
final class PoofAdminClient: ObservableObject {
    static let shared = PoofAdminClient()

    @Published private(set) var threads: [AdminThread] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    struct AdminThread: Identifiable, Codable, Equatable {
        let deviceId: String
        let name: String
        let messages: [SupportMessage]

        var id: String {
            deviceId
        }

        var lastMessage: SupportMessage? {
            messages.max(by: { $0.ts < $1.ts })
        }
    }

    /// Force le serveur Render officiel — évite qu'un LAN gateway Bonjour
    /// (qui n'a pas les routes /admin/*) prenne le dessus via
    /// `PoofSession.signalingURL` et casse le fetch avec un 404.
    private var baseURL: URL {
        URL(string: "https://poof-fgb8.onrender.com")!
    }

    private init() {}

    func fetchAll(token: String) async {
        guard !token.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        // Build URL directement en string — évite le bug potentiel de
        // `appendingPathComponent` qui peut encoder les slashes en %2F sur
        // certaines URLs et retourner un 404 (→ HTML → decode fail JSON).
        let base = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
        guard let url = URL(string: "\(base)/admin/threads?token=\(encoded)") else {
            lastError = "URL invalide"
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 {
                lastError = "Admin token refused"
                return
            }
            guard status == 200 else {
                let bodyPreview = String(data: data.prefix(120), encoding: .utf8) ?? "<binary>"
                lastError = "HTTP \(status) — \(bodyPreview)"
                return
            }
            // Le serveur renvoie { deviceId: { name, messages } } — on aplatit.
            let raw = try JSONDecoder().decode([String: ThreadPayload].self, from: data)
            threads = raw.map { key, value in
                AdminThread(
                    deviceId: key,
                    name: value.name ?? "Anonymous",
                    messages: value.messages.sorted { $0.ts < $1.ts }
                )
            }
            .sorted { ($0.lastMessage?.ts ?? 0) > ($1.lastMessage?.ts ?? 0) }
            lastError = nil
        } catch {
            let bodyPreview = "\(error)"
            lastError = "Decode: \(bodyPreview.prefix(200))"
        }
    }

    func reply(deviceId: String, text: String, token: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !token.isEmpty else { return }
        let base = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
        guard let url = URL(string: "\(base)/admin/reply?token=\(encoded)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "deviceId": deviceId,
            "text": trimmed
        ])
        _ = try? await URLSession.shared.data(for: req)
        await fetchAll(token: token)
    }

    private struct ThreadPayload: Codable {
        var name: String?
        var messages: [SupportMessage]
    }
}

// MARK: - Inbox sheet

struct PoofAdminInbox: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var client = PoofAdminClient.shared
    @AppStorage("poof.admin.token") private var token: String = ""

    @State private var selectedThread: PoofAdminClient.AdminThread?
    @State private var draftToken: String = ""

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
                if token.isEmpty {
                    tokenGate
                } else {
                    threadList
                }
            }
        }
        .task { await client.fetchAll(token: token) }
        .sheet(item: $selectedThread) { thread in
            PoofAdminThreadDetail(thread: thread, token: token)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Admin Inbox")
                .font(.system(size: 22, weight: .heavy))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 2)
            Spacer()
            if !token.isEmpty {
                Button {
                    Task { await client.fetchAll(token: token) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.18)))
                }
                .buttonStyle(.plain)
            }
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
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Token gate

    private var tokenGate: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
            Text("Admin token")
                .font(.system(size: 18, weight: .heavy))
                .foregroundColor(.white)
            Text("Paste the SUPPORT_ADMIN_TOKEN value configured on Render here.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            SecureField("token…", text: $draftToken)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.6)
                        )
                )
                .padding(.horizontal, 30)

            Button {
                token = draftToken
                Task { await client.fetchAll(token: token) }
            } label: {
                Text("Se connecter")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
                    .padding(.horizontal, 30)
            }
            .buttonStyle(.plain)
            .disabled(draftToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(draftToken.isEmpty ? 0.5 : 1)

            Spacer()
        }
    }

    // MARK: - Thread list

    @ViewBuilder
    private var threadList: some View {
        if let err = client.lastError {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white.opacity(0.7))
                Text(err)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Button("Reset token") { token = "" }
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
            }
        } else if client.threads.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "tray")
                    .font(.system(size: 40))
                    .foregroundColor(.white.opacity(0.7))
                Text("No message yet")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
            }
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    ForEach(client.threads) { thread in
                        threadRow(thread)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }

    private func threadRow(_ thread: PoofAdminClient.AdminThread) -> some View {
        Button {
            selectedThread = thread
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 38, height: 38)
                    .overlay(
                        Text(String(thread.name.prefix(1)).uppercased())
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundColor(.white)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(thread.name)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundColor(.white)
                    Text(thread.lastMessage?.text ?? "—")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.65))
                        .lineLimit(1)
                }
                Spacer()
                if let last = thread.lastMessage {
                    Text(shortTime(last.date))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func shortTime(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale.current
        if Calendar.current.isDateInToday(date) {
            df.dateFormat = "HH:mm"
        } else {
            df.dateFormat = "d MMM"
        }
        return df.string(from: date)
    }
}

// MARK: - Thread detail

struct PoofAdminThreadDetail: View {
    let thread: PoofAdminClient.AdminThread
    let token: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var client = PoofAdminClient.shared
    @State private var reply: String = ""

    private var current: PoofAdminClient.AdminThread {
        client.threads.first(where: { $0.deviceId == thread.deviceId }) ?? thread
    }

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
                messagesList
                inputBar
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(current.name)
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundColor(.white)
                Text(current.deviceId)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.middle)
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
        .padding(.bottom, 12)
    }

    private var messagesList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 8) {
                ForEach(current.messages) { msg in
                    HStack {
                        if msg.isAdmin {
                            Spacer(minLength: 40)
                        }
                        VStack(alignment: msg.isAdmin ? .trailing : .leading, spacing: 2) {
                            Text(msg.text)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(msg.isAdmin ? .black : .white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(msg.isAdmin ? Color.white : Color.white.opacity(0.15))
                                )
                        }
                        if !msg.isAdmin {
                            Spacer(minLength: 40)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Reply…", text: $reply, axis: .vertical)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1 ... 4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(Color.white.opacity(0.15))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.6))
                )

            Button {
                let text = reply
                reply = ""
                Task { await client.reply(deviceId: thread.deviceId, text: text, token: token) }
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white))
            }
            .buttonStyle(.plain)
            .disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.20))
    }
}
