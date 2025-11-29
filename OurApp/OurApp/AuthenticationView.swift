import SwiftUI
import FirebaseAuth

// MARK: - Authentication Manager
class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()

    @Published var isAuthenticated = false
    @Published var isLoading = true
    @Published var showWelcome = false
    @Published var authenticatedUser: AppUser?

    private let authStateKey = "com.ourapp.isAuthenticated"
    private let userPhoneKey = "com.ourapp.userPhone"

    // Phone numbers for each user (without formatting)
    private let ahmadPhone = "+18324691172"
    private let luisaPhone = "+16823471186"

    private init() {
        checkAuthState()
    }

    private func checkAuthState() {
        // Check if user was previously authenticated
        if UserDefaults.standard.bool(forKey: authStateKey) {
            if let phoneNumber = UserDefaults.standard.string(forKey: userPhoneKey) {
                authenticatedUser = userForPhone(phoneNumber)
                isAuthenticated = true
            }
        }
        isLoading = false
    }

    func userForPhone(_ phone: String) -> AppUser? {
        let normalizedPhone = normalizePhone(phone)
        if normalizedPhone == ahmadPhone {
            return .ahmad
        } else if normalizedPhone == luisaPhone {
            return .luisa
        }
        return nil
    }

    func normalizePhone(_ phone: String) -> String {
        let digits = phone.filter { $0.isNumber }
        if digits.count == 10 {
            return "+1" + digits
        } else if digits.count == 11 && digits.hasPrefix("1") {
            return "+" + digits
        }
        return phone
    }

    func completeAuthentication(phoneNumber: String) {
        let normalizedPhone = normalizePhone(phoneNumber)
        authenticatedUser = userForPhone(normalizedPhone)

        // Save auth state
        UserDefaults.standard.set(true, forKey: authStateKey)
        UserDefaults.standard.set(normalizedPhone, forKey: userPhoneKey)

        // Also update UserIdentityManager
        if let user = authenticatedUser {
            UserIdentityManager.shared.setUser(user)
        }

        // Show welcome screen first
        showWelcome = true
    }

    func dismissWelcome() {
        showWelcome = false
        isAuthenticated = true
    }
}

// MARK: - Authentication View
struct AuthenticationView: View {
    @StateObject private var authManager = AuthenticationManager.shared
    @State private var phoneNumber = ""
    @State private var verificationCode = ""
    @State private var verificationID: String?
    @State private var isVerifying = false
    @State private var isSendingCode = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.93, blue: 1.0),
                    Color(red: 0.9, green: 0.85, blue: 0.98),
                    Color(red: 0.85, green: 0.8, blue: 0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // App logo/icon area
                VStack(spacing: 16) {
                    Image(systemName: "heart.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.7, green: 0.5, blue: 0.95),
                                    Color(red: 0.9, green: 0.5, blue: 0.7)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Text("OurApp")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))
                }

                // Phone input section
                VStack(spacing: 24) {
                    if verificationID == nil {
                        // Phone number input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Enter your phone number")
                                .font(.headline)
                                .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.6))

                            HStack(spacing: 12) {
                                Text("+1")
                                    .font(.title2)
                                    .foregroundColor(.white.opacity(0.8))
                                    .padding(.leading, 16)

                                TextField("(000) 000-0000", text: $phoneNumber)
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .keyboardType(.phonePad)
                                    .tint(.white)
                                    .onChange(of: phoneNumber) { _, newValue in
                                        phoneNumber = formatPhoneNumber(newValue)
                                    }
                            }
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(red: 0.5, green: 0.35, blue: 0.75))
                                    .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                            )
                        }

                        Button(action: sendVerificationCode) {
                            HStack {
                                if isSendingCode {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Send Code")
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.7, green: 0.5, blue: 0.95),
                                        Color(red: 0.6, green: 0.4, blue: 0.85)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(16)
                        }
                        .disabled(phoneNumber.filter { $0.isNumber }.count < 10 || isSendingCode)
                        .opacity(phoneNumber.filter { $0.isNumber }.count < 10 ? 0.6 : 1)

                    } else {
                        // Verification code input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Enter verification code")
                                .font(.headline)
                                .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.6))

                            TextField("000000", text: $verificationCode)
                                .font(.system(size: 32, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .tint(.white)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(red: 0.5, green: 0.35, blue: 0.75))
                                        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                                )
                                .onChange(of: verificationCode) { _, newValue in
                                    verificationCode = String(newValue.filter { $0.isNumber }.prefix(6))
                                }

                            Text("Code sent to +1 \(phoneNumber)")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }

                        Button(action: verifyCode) {
                            HStack {
                                if isVerifying {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Verify")
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.7, green: 0.5, blue: 0.95),
                                        Color(red: 0.6, green: 0.4, blue: 0.85)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(16)
                        }
                        .disabled(verificationCode.count < 6 || isVerifying)
                        .opacity(verificationCode.count < 6 ? 0.6 : 1)

                        Button(action: {
                            verificationID = nil
                            verificationCode = ""
                        }) {
                            Text("Change phone number")
                                .font(.subheadline)
                                .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                        }
                    }
                }
                .padding(.horizontal, 32)

                Spacer()
                Spacer()
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
    }

    private func formatPhoneNumber(_ input: String) -> String {
        let digits = input.filter { $0.isNumber }
        let limited = String(digits.prefix(10))

        var result = ""
        for (index, digit) in limited.enumerated() {
            if index == 0 {
                result += "("
            }
            if index == 3 {
                result += ") "
            }
            if index == 6 {
                result += "-"
            }
            result += String(digit)
        }
        return result
    }

    private func sendVerificationCode() {
        let digits = phoneNumber.filter { $0.isNumber }
        guard digits.count == 10 else { return }

        // Check if this is a valid user phone number
        let normalizedPhone = "+1" + digits
        guard authManager.userForPhone(normalizedPhone) != nil else {
            errorMessage = "This phone number is not authorized to use this app."
            showError = true
            return
        }

        isSendingCode = true

        let fullPhoneNumber = "+1" + digits

        PhoneAuthProvider.provider().verifyPhoneNumber(fullPhoneNumber, uiDelegate: nil) { verificationID, error in
            DispatchQueue.main.async {
                isSendingCode = false

                if let error = error {
                    errorMessage = error.localizedDescription
                    showError = true
                    return
                }

                self.verificationID = verificationID
            }
        }
    }

    private func verifyCode() {
        guard let verificationID = verificationID else { return }

        isVerifying = true

        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: verificationID,
            verificationCode: verificationCode
        )

        Auth.auth().signIn(with: credential) { authResult, error in
            DispatchQueue.main.async {
                isVerifying = false

                if let error = error {
                    errorMessage = error.localizedDescription
                    showError = true
                    return
                }

                // Successfully authenticated
                let digits = phoneNumber.filter { $0.isNumber }
                authManager.completeAuthentication(phoneNumber: "+1" + digits)
            }
        }
    }
}

// MARK: - Welcome Screen
struct WelcomeView: View {
    let user: AppUser
    let onContinue: () -> Void

    @State private var showContent = false
    @State private var showButton = false

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.93, blue: 1.0),
                    Color(red: 0.9, green: 0.85, blue: 0.98),
                    Color(red: 0.85, green: 0.8, blue: 0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                if showContent {
                    VStack(spacing: 24) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.9, green: 0.4, blue: 0.6),
                                        Color(red: 0.7, green: 0.5, blue: 0.95)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        Text("Welcome, \(user.rawValue)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

                        Text("So happy to see you!")
                            .font(.title3)
                            .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }

                Spacer()

                if showButton {
                    Button(action: onContinue) {
                        Text("Let's Go")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.7, green: 0.5, blue: 0.95),
                                        Color(red: 0.6, green: 0.4, blue: 0.85)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(16)
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 60)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2)) {
                showContent = true
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.8)) {
                showButton = true
            }
        }
    }
}

#Preview {
    AuthenticationView()
}
