import SwiftUI

private struct AppIconCell: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.poofIconBlue.opacity(0.5))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            )
            .overlay(
                // Circuit-board style inner lines
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                        .padding(10)
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                        .padding(18)
                }
            )
            .frame(width: 72, height: 72)
    }
}

struct ExploreCard: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(
                    LinearGradient(
                        colors: [Color.poofExploreTop, Color.poofExploreBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            VStack(alignment: .leading, spacing: 20) {
                Text("Explore")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .center)

                // 2×2 grid of app icons
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ],
                    spacing: 16
                ) {
                    ForEach(0 ..< 4, id: \.self) { _ in
                        AppIconCell()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .padding(.top, 28)
        }
        .frame(height: 240)
    }
}

#Preview {
    ExploreCard()
        .padding()
        .background(Color.black)
}
