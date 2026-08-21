import AuthenticationServices
import PhotosUI
import SwiftUI

// Sheet Account — l'utilisateur choisit sa photo de profil (remplissage du
// nuage top-right) et son nom d'affichage. Stocké local (UserDefaults + PNG
// dans Documents/). Ouvert depuis PoofCloudMenu → cercle person.fill.

struct PoofAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var profile = PoofProfileImage.shared

    @State private var selectedItem: PhotosPickerItem?
    @State private var draftName: String = ""

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
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        avatarBlock
                        nameField
                        iCloudBlock
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
        }
        .onAppear { draftName = profile.displayName }
        .onChange(of: selectedItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = PoofImage(data: data)
                {
                    profile.setCustomImage(img)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Account")
                .font(.system(size: 24, weight: .heavy))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 2)
            Spacer()
            Button {
                profile.displayName = draftName
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

    // MARK: - Avatar

    private var avatarBlock: some View {
        VStack(spacing: 14) {
            avatarPreview

            PhotosPicker(selection: $selectedItem, matching: .images) {
                Text(profile.image == nil ? "Add photo" : "Change photo")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.18))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.30), lineWidth: 0.8))
                    )
            }

            if profile.image != nil {
                Button(role: .destructive) {
                    profile.setCustomImage(nil)
                    selectedItem = nil
                } label: {
                    Text("Remove photo")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.70))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var avatarPreview: some View {
        if let img = profile.image {
            Image(poofImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 108, height: 108)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        } else {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.15))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.30), lineWidth: 1))
                Image(systemName: "person.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
            }
            .frame(width: 108, height: 108)
            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        }
    }

    // MARK: - Name

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DISPLAY NAME")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.55))
                .tracking(0.6)
                .padding(.leading, 4)

            TextField("Your name", text: $draftName)
                .font(.system(size: 16, weight: .semibold))
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
            #if canImport(UIKit)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(true)
            #endif
                .onChange(of: draftName) { _, new in
                    profile.displayName = new
                }
        }
    }

    // MARK: - iCloud (Sign in with Apple)

    private var iCloudBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("APPLE ID")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.55))
                .tracking(0.6)
                .padding(.leading, 4)

            if profile.isSignedIn {
                signedInRow
            } else {
                SignInWithAppleButton(.signIn) { req in
                    req.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handleAppleResult(result)
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Text(
                "Apple doesn't share the iCloud photo for privacy reasons — use « Change photo » above for your custom photo."
            )
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white.opacity(0.55))
            .padding(.leading, 4)
            .padding(.top, 4)
        }
    }

    private var signedInRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName.isEmpty ? "Signed in" : profile.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    if let email = profile.appleEmail {
                        Text(email)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.60))
                    }
                }
                Spacer()
                Button {
                    profile.signOutApple()
                } label: {
                    Text("Sign out")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.18)))
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.6)
                    )
            )
        }
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        guard case let .success(auth) = result,
              let cred = auth.credential as? ASAuthorizationAppleIDCredential
        else { return }
        let name: String? = {
            let n = cred.fullName
            let parts = [n?.givenName, n?.familyName].compactMap { $0 }.filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: " ")
        }()
        profile.applyAppleSignIn(
            userId: cred.user,
            fullName: name,
            email: cred.email
        )
        if let name, !name.isEmpty {
            draftName = name
        }
    }
}

#Preview {
    PoofAccountView()
}
