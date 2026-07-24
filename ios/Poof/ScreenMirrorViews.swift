import SwiftUI
import ReplayKit
import UIKit

// Broadcast picker embed — tapping this native button starts the system broadcast
// flow. It launches the OS-level picker that lists broadcast upload extensions.
// We pre-select ours by preferredExtension bundle ID.
struct BroadcastPickerButton: UIViewRepresentable {

    let extensionBundleId: String

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear

        let picker = RPSystemBroadcastPickerView(frame: .zero)
        picker.preferredExtension = extensionBundleId
        picker.showsMicrophoneButton = false
        picker.translatesAutoresizingMaskIntoConstraints = false

        // The real system button is nested; tint it so it shows through the transparent picker.
        for sub in picker.subviews {
            if let button = sub as? UIButton {
                button.imageView?.tintColor = .white
            }
        }

        container.addSubview(picker)
        NSLayoutConstraint.activate([
            picker.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            picker.topAnchor.constraint(equalTo: container.topAnchor),
            picker.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

// Sender-side sheet — big "Start Broadcast" button + live preview once broadcasting.
struct ScreenMirrorSenderSheet: View {
    @EnvironmentObject var session: PoofSession
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: session.screenBroadcast.isBroadcasting ? "rectangle.on.rectangle.circle.fill" : "rectangle.on.rectangle")
                    .font(.system(size: 90, weight: .light))
                    .foregroundStyle(session.screenBroadcast.isBroadcasting ? Color.red : Color.accentColor)

                Text(session.screenBroadcast.isBroadcasting ? "Screen shared with peer" : "Share your screen live")
                    .font(.title2.bold())

                Text(session.screenBroadcast.isBroadcasting
                    ? "The peer is watching at ~10 FPS. Stop from the red status bar."
                    : "Tap the broadcast button. Pick “Poof Screen” then Start Broadcast.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)

                Spacer()

                ZStack {
                    Capsule().fill(Color.accentColor.opacity(0.15))
                    Label("Start broadcast", systemImage: "dot.radiowaves.left.and.right")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                    BroadcastPickerButton(extensionBundleId: "com.Poof.App.Poof.ScreenBroadcastExtension")
                        .opacity(0.02)
                }
                .frame(height: 56)
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
            .navigationTitle("Screen Mirror")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// Receiver-side full-screen viewer.
struct ScreenMirrorReceiverSheet: View {
    @EnvironmentObject var session: PoofSession
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = session.screenBroadcast.latestFrame {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                    Text("Waiting for first frame…")
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white.opacity(0.9), .black.opacity(0.4))
                    }
                    .padding(.top, 44)
                    .padding(.trailing, 16)
                }
                Spacer()

                if session.screenBroadcast.isReceiving {
                    Label("Live from peer", systemImage: "dot.radiowaves.left.and.right")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.5), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(.bottom, 32)
                }
            }
        }
        .statusBarHidden()
    }
}
