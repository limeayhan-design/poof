import SwiftUI

struct TransferCard: View {
    var body: some View {
        ZStack {
            // Card background gradient
            RoundedRectangle(cornerRadius: 28)
                .fill(
                    LinearGradient(
                        colors: [Color.poofCardBlue, Color.poofCardBlueDark],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            VStack(spacing: 0) {
                // Top label
                Text("Transfer every devices")
                    .font(.system(size: 16, weight: .medium, design: .default))
                    .foregroundColor(.white)
                    .padding(.top, 32)

                Spacer()

                // Poof cloud icon
                Image(systemName: "cloud.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.white)
                    .overlay(
                        Image(systemName: "figure.walk")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                            .offset(x: 2, y: -28)
                    )
                    .padding(.bottom, 8)

                // App name
                Text("Poof")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Spacer()

                // See subscriptions
                VStack(spacing: 4) {
                    Text("See subscriptions")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                    Text("5 plans for all devices")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.bottom, 28)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 340)
    }
}

#Preview {
    TransferCard()
        .padding()
        .background(Color.black)
}
