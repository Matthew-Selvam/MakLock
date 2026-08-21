import SwiftUI

/// Security settings tab: authentication methods, primary/secondary ordering, backup password.
struct SecuritySettingsView: View {
    @State private var settings = Defaults.shared.appSettings
    @State private var hasBackupPassword = false
    @State private var showPasswordSheet = false
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var passwordError: String?

    private var touchIDAvailable: Bool { AuthenticationService.shared.isTouchIDAvailable }

    /// At least one method must always stay on — enforced in the toggles below.
    private var bothEnabled: Bool { settings.touchIDEnabled && settings.passwordAuthEnabled }

    var body: some View {
        Form {
            // MARK: Trigger settings
            Section {
                Toggle("Require authentication on app launch", isOn: $settings.requireAuthOnLaunch)
                    .toggleStyle(.goldSwitch)
                    .onChange(of: settings.requireAuthOnLaunch) { _ in save() }

                Toggle("Require authentication on app switch", isOn: $settings.requireAuthOnActivate)
                    .toggleStyle(.goldSwitch)
                    .onChange(of: settings.requireAuthOnActivate) { _ in save() }
            }

            // MARK: Auth Methods
            Section("Authentication Methods") {
                // Touch ID toggle
                HStack {
                    Image(systemName: "touchid")
                        .font(.system(size: 18))
                        .foregroundColor(touchIDAvailable ? MakLockColors.success : MakLockColors.textSecondary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Touch ID (Fingerprint)")
                            .font(MakLockTypography.body)
                        if !touchIDAvailable {
                            Text("Touch ID is not configured on this Mac.")
                                .font(MakLockTypography.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { settings.touchIDEnabled },
                        set: { newVal in
                            if !newVal && !settings.passwordAuthEnabled { return }
                            settings.touchIDEnabled = newVal
                            if !newVal && settings.primaryAuthMethod == .touchID {
                                settings.primaryAuthMethod = .password
                            }
                            save()
                        }
                    ))
                    .toggleStyle(.goldSwitch)
                    .disabled(!touchIDAvailable)
                }

                // Password toggle
                HStack {
                    Image(systemName: "key.fill")
                        .font(.system(size: 18))
                        .foregroundColor(hasBackupPassword ? MakLockColors.success : MakLockColors.locked)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Password")
                            .font(MakLockTypography.body)
                        if !hasBackupPassword {
                            Text("Set a password below to enable this method.")
                                .font(MakLockTypography.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { settings.passwordAuthEnabled },
                        set: { newVal in
                            if !newVal && !settings.touchIDEnabled { return }
                            settings.passwordAuthEnabled = newVal
                            if !newVal && settings.primaryAuthMethod == .password {
                                settings.primaryAuthMethod = .touchID
                            }
                            save()
                        }
                    ))
                    .toggleStyle(.goldSwitch)
                    .disabled(!hasBackupPassword)
                }
            }

            // MARK: Primary / Secondary order (only shown when both are on)
            if bothEnabled {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Primary Method")
                            .font(MakLockTypography.body)
                        Text("The primary method is tried first. The secondary is offered as a fallback.")
                            .font(MakLockTypography.caption)
                            .foregroundColor(.secondary)

                        Picker("Primary", selection: $settings.primaryAuthMethod) {
                            Label("Touch ID", systemImage: "touchid").tag(AuthMethod.touchID)
                            Label("Password", systemImage: "key.fill").tag(AuthMethod.password)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: settings.primaryAuthMethod) { _ in save() }
                    }
                    .padding(.vertical, 4)

                    // Visual summary
                    HStack(spacing: 8) {
                        methodBadge(
                            label: settings.primaryAuthMethod == .touchID ? "Touch ID" : "Password",
                            icon: settings.primaryAuthMethod == .touchID ? "touchid" : "key.fill",
                            tag: "Primary",
                            color: MakLockColors.success
                        )

                        Image(systemName: "arrow.right")
                            .foregroundColor(.secondary)

                        methodBadge(
                            label: settings.primaryAuthMethod == .touchID ? "Password" : "Touch ID",
                            icon: settings.primaryAuthMethod == .touchID ? "key.fill" : "touchid",
                            tag: "Fallback",
                            color: MakLockColors.textSecondary
                        )
                    }
                    .padding(.top, 4)
                } header: {
                    Text("Priority Order")
                }
            }

            // MARK: Backup Password management
            Section("Backup Password") {
                if hasBackupPassword {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(MakLockColors.success)
                        Text("Backup password is set")
                            .font(MakLockTypography.body)
                    }
                    Button("Change Password...") {
                        resetPasswordFields()
                        showPasswordSheet = true
                    }
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(MakLockColors.locked)
                        Text("No backup password set")
                            .font(MakLockTypography.body)
                    }
                    Text("A backup password is required to enable password authentication.")
                        .font(MakLockTypography.caption)
                        .foregroundColor(.secondary)
                    Button("Set Password...") {
                        resetPasswordFields()
                        showPasswordSheet = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            hasBackupPassword = KeychainManager.shared.hasPassword()
            if !hasBackupPassword && settings.passwordAuthEnabled {
                settings.passwordAuthEnabled = false
                if settings.primaryAuthMethod == .password {
                    settings.primaryAuthMethod = .touchID
                }
                save()
            }
        }
        .sheet(isPresented: $showPasswordSheet) {
            passwordSheet
        }
    }

    // MARK: - Helper Views

    private func methodBadge(label: String, icon: String, tag: String, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(label)
                    .font(MakLockTypography.body)
            }
            .foregroundColor(color)

            Text(tag)
                .font(MakLockTypography.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.1))
        )
    }

    // MARK: - Password Sheet

    private var passwordSheet: some View {
        VStack(spacing: 16) {
            Text(hasBackupPassword ? "Change Password" : "Set Backup Password")
                .font(MakLockTypography.title)

            SecureField("New Password", text: $newPassword)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)

            SecureField("Confirm Password", text: $confirmPassword)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)

            if let passwordError {
                Text(passwordError)
                    .font(MakLockTypography.caption)
                    .foregroundColor(MakLockColors.error)
            }

            HStack(spacing: 12) {
                Button("Cancel") { showPasswordSheet = false }
                PrimaryButton("Save") { savePassword() }
            }
        }
        .padding(24)
        .frame(width: 320)
    }

    // MARK: - Helpers

    private func save() {
        Defaults.shared.appSettings = settings
    }

    private func savePassword() {
        guard !newPassword.isEmpty else {
            passwordError = "Password cannot be empty."
            return
        }
        guard newPassword.count >= 4 else {
            passwordError = "Password must be at least 4 characters."
            return
        }
        guard newPassword == confirmPassword else {
            passwordError = "Passwords do not match."
            return
        }

        let saved = KeychainManager.shared.savePassword(newPassword)
        if saved {
            Defaults.shared.isBackupPasswordSet = true
            hasBackupPassword = true
            if !settings.passwordAuthEnabled {
                settings.passwordAuthEnabled = true
                save()
            }
            showPasswordSheet = false
        } else {
            passwordError = "Failed to save password. Please try again."
        }
    }

    private func resetPasswordFields() {
        newPassword = ""
        confirmPassword = ""
        passwordError = nil
    }
}
