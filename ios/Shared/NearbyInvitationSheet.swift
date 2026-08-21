import SwiftUI

/// Sheet système-like « Accept / Deny » présentée globalement quand un autre
/// device Poof à proximité envoie une demande de pairing sans code. Le
/// modifier `nearbyInvitationSheet()` doit être appliqué sur la root view
/// (iOS + macOS) pour que la demande soit visible n'importe où dans l'app.
extension View {
    func nearbyInvitationSheet() -> some View {
        modifier(NearbyInvitationSheetModifier())
    }
}

private struct NearbyInvitationSheetModifier: ViewModifier {
    @StateObject private var pairing = PoofNearbyPairing.shared

    func body(content: Content) -> some View {
        content.sheet(
            isPresented: Binding(
                get: { pairing.pendingInvitation != nil },
                set: {
                    if !$0 {
                        pairing.pendingInvitation?.respond(false)
                    }
                }
            )
        ) {
            if let request = pairing.pendingInvitation {
                NearbyInvitationView(request: request)
                #if canImport(UIKit)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                #endif
            }
        }
    }
}

private struct NearbyInvitationView: View {
    let request: PoofNearbyPairing.PendingInvitation

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0 / 255, green: 94 / 255, blue: 255 / 255),
                    Color(red: 121 / 255, green: 121 / 255, blue: 121 / 255)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.white.opacity(0.28), Color.white.opacity(0.03)],
                                center: .center, startRadius: 4, endRadius: 60
                            )
                        )
                        .frame(width: 130, height: 130)
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundColor(.white)
                        .shadow(color: .white.opacity(0.3), radius: 12)
                }

                VStack(spacing: 6) {
                    Text(request.fromName)
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text("wants to pair with this device")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                }

                Spacer()

                VStack(spacing: 10) {
                    Button {
                        PoofHaptics.impactMedium()
                        request.respond(true)
                    } label: {
                        Text("Accept")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        PoofHaptics.tap()
                        request.respond(false)
                    } label: {
                        Text("Deny")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .padding(.top, 40)
        }
        #if canImport(UIKit)
        .preferredColorScheme(.dark)
        #endif
    }
}
