import SwiftUI

/// The lock overlay UI: blur background with centered unlock card.
/// Respects the user's auth method preferences (Touch ID, Password, or both with a primary order).
struct LockOverlayView: View {
    let appName: String
    let bundleIdentifier: String
    let isPrimary: Bool
    let onDismiss: () -> Void

    @State private var isVisible = false
    @State private var showPasswordInput = false
    @State private var authState: AuthState = .authenticating
    @State private var errorMessage: String?

    private enum AuthState {
        case authenticating
        case waitingForUser
    }

    private var settings: AppSettings { Defaults.shared.appSettings }

    /// The method we try first on appear.
    private var primaryMethod: AuthMethod {
        let s = settings
        if s.touchIDEnabled && s.passwordAuthEnabled {
            return s.primaryAuthMethod
        }
        return s.touchIDEnabled ? .touchID : .password
    }

    /// Whether a fallback method is available (the other method when both are on).
    private var hasFallback: Bool {
        settings.touchIDEnabled && settings.passwordAuthEnabled
    }

    private var fallbackLabel: String {
        primaryMethod == .touchID ? "Use Password Instead" : "Use Touch ID Instead"
    }

    var body: some View {
        ZStack {
            BlurView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            Color.black.opacity(0.4)
                .ignoresSafeArea()

            if showPasswordInput {
                PasswordInputView(
                    onSuccess: { onDismiss() },
                    onCancel: {
                        withAnimation(MakLockAnimations.standard) {
                            showPasswordInput = false
                        }
                    }
                )
                .transition(.opacity)
            } else {
                VStack(spacing: 20) {
                    AppIconView(bundleIdentifier: bundleIdentifier, size: 64)

                    Text("\(appName) is Locked")
                        .font(MakLockTypography.largeTitle)
                        .foregroundColor(MakLockColors.textPrimary)

                    if authState == .authenticating {
                        ProgressView()
                            .controlSize(.regular)
                            .padding(.top, 4)

                        Text("Authenticating...")
                            .font(MakLockTypography.body)
                            .foregroundColor(MakLockColors.textSecondary)
                    } else {
                        if let errorMessage {
                            Text(errorMessage)
                                .font(MakLockTypography.caption)
                                .foregroundColor(MakLockColors.error)
                        }

                        // Retry primary
                        if primaryMethod == .touchID {
                            PrimaryButton("Try Again", icon: "touchid") {
                                attemptPrimaryMethod()
                            }
                            .padding(.top, 4)
                        } else {
                            PrimaryButton("Enter Password", icon: "key.fill") {
                                OverlayWindowService.shared.enableKeyboardInput()
                                withAnimation(MakLockAnimations.standard) {
                                    showPasswordInput = true
                                }
                            }
                            .padding(.top, 4)
                        }

                        // Fallback (only shown when both methods are enabled)
                        if hasFallback {
                            SecondaryButton(fallbackLabel) {
                                if primaryMethod == .touchID {
                                    OverlayWindowService.shared.enableKeyboardInput()
                                    withAnimation(MakLockAnimations.standard) {
                                        showPasswordInput = true
                                    }
                                } else {
                                    attemptTouchID()
                                }
                            }
                        }
                    }

                    #if DEBUG
                    Button("Skip (Dev)") { onDismiss() }
                        .font(MakLockTypography.caption)
                        .foregroundColor(MakLockColors.error)
                        .padding(.top, 8)
                    #endif
                }
                .padding(40)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(MakLockColors.cardDark)
                        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
                )
                .scaleEffect(isVisible ? 1.0 : 0.9)
                .opacity(isVisible ? 1.0 : 0.0)
                .transition(.opacity)
            }
        }
        .onAppear {
            withAnimation(MakLockAnimations.overlayAppear) {
                isVisible = true
            }
            if isPrimary {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    attemptPrimaryMethod()
                }
            }
        }
    }

    // MARK: - Auth Dispatch

    private func attemptPrimaryMethod() {
        if primaryMethod == .touchID {
            attemptTouchID()
        } else {
            authState = .waitingForUser
            OverlayWindowService.shared.enableKeyboardInput()
            withAnimation(MakLockAnimations.standard) {
                showPasswordInput = true
            }
        }
    }

    private func attemptTouchID() {
        authState = .authenticating
        errorMessage = nil
        showPasswordInput = false

        OverlayWindowService.shared.setTouchIDMode(true)

        AuthenticationService.shared.authenticateWithTouchID(
            reason: "Unlock \(appName)"
        ) { result in
            OverlayWindowService.shared.setTouchIDMode(false)

            switch result {
            case .success:
                onDismiss()
            case .failure(let error):
                authState = .waitingForUser
                errorMessage = error.localizedDescription
            case .cancelled:
                authState = .waitingForUser
            }
        }
    }
}
