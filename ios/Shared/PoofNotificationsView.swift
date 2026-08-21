import SwiftUI

// Sheet Notifications — liste tous les événements Track (fichier ouvert par
// un peer) triés du plus récent au plus ancien. État vide gracieux.

struct PoofNotificationsView: View {
    @EnvironmentObject var session: PoofSession
    @Environment(\.dismiss) private var dismiss

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
                content
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Notifications")
                .font(.system(size: 24, weight: .heavy))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 2)
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
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if notifications.isEmpty {
            emptyState
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    ForEach(notifications) { notif in
                        NotificationRow(notif: notif)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            Image(systemName: "bell.slash")
                .font(.system(size: 40, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .padding(24)
                .background(
                    Circle().fill(Color.white.opacity(0.10))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6))
                )
            Text("No notifications yet")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            Text("You'll see here when someone opens a file you sent, or when a new file arrives.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data

    /// Aplatit `trackEvents` en flat list + ajoute les fichiers reçus récents,
    /// trié par date desc. Chaque item = 1 notification affichable.
    private var notifications: [NotificationItem] {
        var items: [NotificationItem] = []

        for (transferId, events) in session.trackEvents {
            let sentFile = session.sentFiles.first { $0.id == transferId }
            for event in events {
                items.append(NotificationItem(
                    id: event.id,
                    icon: "eye.fill",
                    title: "\(event.device ?? "Someone") opened your file",
                    subtitle: sentFile?.name ?? "Untitled",
                    date: event.timestamp
                ))
            }
        }

        for file in session.receivedFiles {
            items.append(NotificationItem(
                id: file.id,
                icon: "tray.and.arrow.down.fill",
                title: "New file received",
                subtitle: file.name,
                date: file.date
            ))
        }

        return items.sorted { $0.date > $1.date }
    }
}

// MARK: - Row + Item

private struct NotificationItem: Identifiable {
    let id: UUID
    let icon: String
    let title: String
    let subtitle: String
    let date: Date
}

private struct NotificationRow: View {
    let notif: NotificationItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: notif.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.18))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.30), lineWidth: 0.6))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(notif.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(notif.subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(1)
            }

            Spacer()

            Text(shortDate)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6)
                )
        )
    }

    private var shortDate: String {
        let df = DateFormatter()
        df.locale = Locale.current
        if Calendar.current.isDateInToday(notif.date) {
            df.dateFormat = "HH:mm"
            return df.string(from: notif.date)
        }
        df.dateFormat = "d MMM"
        return df.string(from: notif.date)
    }
}

#Preview {
    PoofNotificationsView()
        .environmentObject(PoofSession())
}
