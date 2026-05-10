import Foundation

enum AuthEmailValidationState: Equatable {
    case idle
    case validating
    case available(message: String)
    case unavailable(message: String)

    var message: String? {
        switch self {
        case .idle:
            return nil
        case .validating:
            return "이메일 사용 가능 여부를 확인하고 있어요."
        case .available(let message), .unavailable(let message):
            return message
        }
    }

    var isAvailable: Bool {
        if case .available = self {
            return true
        }
        return false
    }

    var isValidating: Bool {
        if case .validating = self {
            return true
        }
        return false
    }
}

struct AuthProviderButtonState: Equatable, Identifiable {
    let provider: AuthProvider
    let title: String
    let systemImage: String
    var isEnabled = true
    var isLoading = false
    var helperText: String?

    var id: String { provider.id }
}

struct AuthViewState: Equatable {
    var title = "서비스 이용을 위해 로그인이 필요합니다."
    var subtitle = "로그인 후 Pikko의 픽업 주문 서비스를 이용할 수 있습니다."
    var providerButtons = AuthProvider.visibleProviders.map(AuthProviderButtonState.defaultState(for:))
    var email = ""
    var password = ""
    var passwordConfirmation = ""
    var nick = ""
    var emailValidationState: AuthEmailValidationState = .idle
    var isLoading = false
    var loadingProvider: AuthProvider?
    var isFormSubmitting = false
    var errorMessage: String?
    var configurationMessage: String?
    var showsStubSignIn = false
    var showsDismissButton = false
    var stubDescription = "DEBUG 내부 플래그에서만 노출되는 테스트 로그인입니다."
    var loginValidationHint = "가입한 이메일과 비밀번호를 입력해 주세요."
    var signUpValidationHint = "Swagger 기준 필수값은 이메일, 비밀번호, 닉네임입니다."

    var stubActionTitle: String {
        isLoading ? "테스트 로그인 중..." : "테스트 로그인"
    }

    var loginSubmitTitle: String {
        isFormSubmitting ? "로그인 중..." : "로그인"
    }

    var signUpSubmitTitle: String {
        isFormSubmitting ? "가입 중..." : "회원가입"
    }

    var emailValidationButtonTitle: String {
        if emailValidationState.isValidating {
            return "확인 중..."
        }

        return emailValidationState.isAvailable ? "확인 완료" : "중복 확인"
    }

    var canRequestEmailValidation: Bool {
        emailFormatValid && !isLoading
    }

    var canSubmitSignUp: Bool {
        emailFormatValid
            && passwordRuleValid
            && passwordsMatch
            && nicknameValid
            && emailValidationState.isAvailable
            && !isLoading
    }

    var emailFormatValid: Bool {
        matches(
            pattern: "^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$",
            value: email.trimmingCharacters(in: .whitespacesAndNewlines),
            options: [.caseInsensitive]
        )
    }

    var passwordRuleValid: Bool {
        matches(
            pattern: "^(?=.*[A-Za-z])(?=.*\\d)(?=.*[@$!%*#?&])[A-Za-z\\d@$!%*#?&]{8,}$",
            value: password
        )
    }

    var passwordsMatch: Bool {
        !passwordConfirmation.isEmpty && password == passwordConfirmation
    }

    var nicknameValid: Bool {
        let trimmed = nick.trimmingCharacters(in: .whitespacesAndNewlines)
        let forbiddenCharacters = CharacterSet(charactersIn: "-.,?*@+^${}()|[]\\")
        return !trimmed.isEmpty && trimmed.rangeOfCharacter(from: forbiddenCharacters) == nil
    }

    private func matches(
        pattern: String,
        value: String,
        options: NSRegularExpression.Options = []
    ) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return false
        }

        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.firstMatch(in: value, options: [], range: range) != nil
    }
}

private extension AuthProviderButtonState {
    static func defaultState(for provider: AuthProvider) -> AuthProviderButtonState {
        AuthProviderButtonState(
            provider: provider,
            title: "\(provider.displayName)로 계속하기",
            systemImage: provider.systemImageName
        )
    }
}

extension AuthProvider {
    static var visibleProviders: [AuthProvider] {
        [.kakao, .apple]
    }

    var systemImageName: String {
        switch self {
        case .kakao:
            return "message.fill"
        case .apple:
            return "apple.logo"
        }
    }
}
