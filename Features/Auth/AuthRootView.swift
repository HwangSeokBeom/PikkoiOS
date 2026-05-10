import AuthenticationServices
import SwiftUI

struct AuthRootView: View {
    private enum Screen {
        case hub
        case emailLogin
        case signUp
    }

    @StateObject private var presenter: AuthPresenter
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionStore: SessionStore

    @State private var screen: Screen = .hub
    @State private var isSignUpPasswordVisible = false
    @State private var isSignUpPasswordConfirmationVisible = false
    @FocusState private var focusedSignUpField: SignUpField?

    init(presenter: AuthPresenter) {
        _presenter = StateObject(wrappedValue: presenter)
    }

    var body: some View {
        ZStack {
            PikkoColor.background.ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: PikkoSpacing.xl) {
                        switch screen {
                        case .hub:
                            hubContent
                        case .emailLogin:
                            emailLoginContent
                        case .signUp:
                            signUpContent
                        }
                    }
                    .padding(.horizontal, PikkoSpacing.xl)
                    .padding(.top, PikkoSpacing.lg)
                    .padding(.bottom, PikkoSpacing.xxl)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .safeAreaPadding(.top, PikkoSpacing.md)
            .safeAreaPadding(.bottom, PikkoSpacing.md)
        }
        .onChange(of: sessionStore.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                dismiss()
            }
        }
        .task {
            await presenter.send(.onAppear)
        }
    }

    private enum SignUpField: Hashable {
        case email
        case password
        case passwordConfirmation
        case nickname
    }

    private var headerBar: some View {
        HStack {
            if screen != .hub {
                navigationButton(systemImage: "chevron.left") {
                    switchScreen(.hub)
                }
            } else if presenter.viewState.showsDismissButton {
                navigationButton(systemImage: "xmark") {
                    dismiss()
                }
            } else {
                Color.clear
                    .frame(width: 40, height: 40)
            }

            Spacer()
        }
        .padding(.horizontal, PikkoSpacing.xl)
        .padding(.bottom, PikkoSpacing.sm)
    }

    private var hubContent: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.xl) {
            VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
                Text(presenter.viewState.title)
                    .font(PikkoTypography.hero)
                    .foregroundStyle(PikkoColor.primaryText)

                Text(presenter.viewState.subtitle)
                    .font(PikkoTypography.body)
                    .foregroundStyle(PikkoColor.secondaryText)
                    .lineSpacing(4)
            }

            serviceRequirementCard
            statusCards

            VStack(spacing: PikkoSpacing.sm) {
                PrimaryButton(
                    title: "이메일로 로그인",
                    systemImage: "envelope.fill"
                ) {
                    switchScreen(.emailLogin)
                }

                SecondaryButton(
                    title: "회원가입",
                    systemImage: "person.badge.plus"
                ) {
                    switchScreen(.signUp)
                }
            }

            VStack(alignment: .leading, spacing: PikkoSpacing.md) {
                ForEach(presenter.viewState.providerButtons) { providerButton in
                    VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
                        providerButtonView(for: providerButton)

                        if let helperText = providerButton.helperText {
                            Text(helperText)
                                .font(PikkoTypography.caption)
                                .foregroundStyle(PikkoColor.secondaryText)
                        }
                    }
                }
            }

            if presenter.viewState.showsStubSignIn {
                VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
                    PrimaryButton(
                        title: presenter.viewState.stubActionTitle,
                        systemImage: "hammer.fill",
                        isLoading: presenter.viewState.isLoading && presenter.viewState.loadingProvider == nil
                    ) {
                        Task {
                            await presenter.send(.stubSignInTapped)
                        }
                    }

                    Text(presenter.viewState.stubDescription)
                        .font(PikkoTypography.caption)
                        .foregroundStyle(PikkoColor.secondaryText)
                }
            }
        }
    }

    private var emailLoginContent: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.xl) {
            screenHeader(
                title: "이메일로 로그인",
                subtitle: "가입한 이메일과 비밀번호를 입력해 주세요."
            )

            statusCards

            VStack(spacing: PikkoSpacing.sm) {
                VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
                    TextField(
                        "",
                        text: Binding(
                            get: { presenter.viewState.email },
                            set: { value in
                                Task { await presenter.send(.emailChanged(value)) }
                            }
                        ),
                        prompt: Text("이메일").foregroundStyle(PikkoColor.secondaryText)
                    )
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .authInputStyle()

                }

                SecureField(
                    "",
                    text: Binding(
                        get: { presenter.viewState.password },
                        set: { value in
                            Task { await presenter.send(.passwordChanged(value)) }
                        }
                    ),
                    prompt: Text("비밀번호").foregroundStyle(PikkoColor.secondaryText)
                )
                .authInputStyle()
            }
            .disabled(presenter.viewState.isLoading)

            PrimaryButton(
                title: presenter.viewState.loginSubmitTitle,
                systemImage: "arrow.right.circle.fill",
                isLoading: presenter.viewState.isFormSubmitting
            ) {
                Task {
                    await presenter.send(.emailSignInTapped)
                }
            }

            Text(presenter.viewState.loginValidationHint)
                .font(PikkoTypography.caption)
                .foregroundStyle(PikkoColor.secondaryText)

            inlineLinkRow(
                leadingText: "계정이 없나요?",
                actionTitle: "회원가입"
            ) {
                switchScreen(.signUp)
            }
        }
    }

    private var signUpContent: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.xl) {
            VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
                Text("회원가입")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(PikkoColor.primaryText)

                Text("이메일, 비밀번호, 닉네임을 입력하고 Pikko를 시작해 보세요.")
                    .font(PikkoTypography.body)
                    .foregroundStyle(PikkoColor.secondaryText)
                    .lineSpacing(4)
            }

            statusCards

            signUpFormCard

            VStack(spacing: PikkoSpacing.sm) {
                PrimaryButton(
                    title: presenter.viewState.signUpSubmitTitle,
                    systemImage: "person.badge.plus.fill",
                    isLoading: presenter.viewState.isFormSubmitting,
                    isEnabled: presenter.viewState.canSubmitSignUp
                ) {
                    Task {
                        await presenter.send(.signUpTapped)
                    }
                }
                .opacity(presenter.viewState.canSubmitSignUp ? 1 : 0.72)

                Text(presenter.viewState.signUpValidationHint)
                    .font(PikkoTypography.caption)
                    .foregroundStyle(PikkoColor.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            inlineLinkRow(
                leadingText: "이미 계정이 있나요?",
                actionTitle: "로그인"
            ) {
                switchScreen(.emailLogin)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var signUpFormCard: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.md) {
            signUpEmailField

            Divider()
                .overlay(PikkoColor.divider.opacity(0.5))

            signUpPasswordField
            signUpPasswordConfirmationField
            signUpNicknameField
        }
        .padding(PikkoSpacing.lg)
        .background(.ultraThinMaterial)
        .background(PikkoColor.surface.opacity(0.72))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(PikkoColor.primary.opacity(0.18), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: PikkoColor.primary.opacity(0.14), radius: 22, y: 12)
        .disabled(presenter.viewState.isLoading)
    }

    private var signUpEmailField: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
            signUpFieldShell(
                title: "이메일",
                systemImage: "envelope.fill",
                isFocused: focusedSignUpField == .email
            ) {
                TextField(
                    "pikko@example.com",
                    text: Binding(
                        get: { presenter.viewState.email },
                        set: { value in
                            Task { await presenter.send(.emailChanged(value)) }
                        }
                    )
                )
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .focused($focusedSignUpField, equals: .email)
            } trailing: {
                Button {
                    Task { await presenter.send(.validateEmailTapped) }
                } label: {
                    Text(presenter.viewState.emailValidationButtonTitle)
                        .font(PikkoTypography.captionStrong)
                        .foregroundStyle(.white)
                        .padding(.horizontal, PikkoSpacing.sm)
                        .frame(height: 32)
                        .background(
                            presenter.viewState.canRequestEmailValidation
                                ? PikkoColor.primary
                                : PikkoColor.gray300
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!presenter.viewState.canRequestEmailValidation || presenter.viewState.emailValidationState.isValidating)
            }

            validationLine(
                text: presenter.viewState.emailValidationState.message ?? "사용 가능한 이메일인지 중복 확인이 필요해요.",
                isSatisfied: presenter.viewState.emailValidationState.isAvailable,
                isActive: !presenter.viewState.email.isEmpty || presenter.viewState.emailValidationState.message != nil
            )
            validationLine(
                text: "올바른 이메일 형식",
                isSatisfied: presenter.viewState.emailFormatValid,
                isActive: !presenter.viewState.email.isEmpty
            )
        }
    }

    private var signUpPasswordField: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
            signUpFieldShell(
                title: "비밀번호",
                systemImage: "lock.fill",
                isFocused: focusedSignUpField == .password
            ) {
                Group {
                    if isSignUpPasswordVisible {
                        TextField(
                            "비밀번호",
                            text: Binding(
                                get: { presenter.viewState.password },
                                set: { value in
                                    Task { await presenter.send(.passwordChanged(value)) }
                                }
                            )
                        )
                    } else {
                        SecureField(
                            "비밀번호",
                            text: Binding(
                                get: { presenter.viewState.password },
                                set: { value in
                                    Task { await presenter.send(.passwordChanged(value)) }
                                }
                            )
                        )
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedSignUpField, equals: .password)
            } trailing: {
                Button {
                    isSignUpPasswordVisible.toggle()
                } label: {
                    Image(systemName: isSignUpPasswordVisible ? "eye.slash.fill" : "eye.fill")
                        .foregroundStyle(PikkoColor.secondaryText)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }

            validationLine(
                text: "8자 이상, 영문/숫자/특수문자 포함",
                isSatisfied: presenter.viewState.passwordRuleValid,
                isActive: !presenter.viewState.password.isEmpty
            )
        }
    }

    private var signUpPasswordConfirmationField: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
            signUpFieldShell(
                title: "비밀번호 확인",
                systemImage: "checkmark.shield.fill",
                isFocused: focusedSignUpField == .passwordConfirmation
            ) {
                Group {
                    if isSignUpPasswordConfirmationVisible {
                        TextField(
                            "비밀번호 확인",
                            text: Binding(
                                get: { presenter.viewState.passwordConfirmation },
                                set: { value in
                                    Task { await presenter.send(.passwordConfirmationChanged(value)) }
                                }
                            )
                        )
                    } else {
                        SecureField(
                            "비밀번호 확인",
                            text: Binding(
                                get: { presenter.viewState.passwordConfirmation },
                                set: { value in
                                    Task { await presenter.send(.passwordConfirmationChanged(value)) }
                                }
                            )
                        )
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedSignUpField, equals: .passwordConfirmation)
            } trailing: {
                Button {
                    isSignUpPasswordConfirmationVisible.toggle()
                } label: {
                    Image(systemName: isSignUpPasswordConfirmationVisible ? "eye.slash.fill" : "eye.fill")
                        .foregroundStyle(PikkoColor.secondaryText)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }

            validationLine(
                text: "비밀번호가 일치해요",
                isSatisfied: presenter.viewState.passwordsMatch,
                isActive: !presenter.viewState.passwordConfirmation.isEmpty
            )
        }
    }

    private var signUpNicknameField: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
            signUpFieldShell(
                title: "닉네임",
                systemImage: "person.crop.circle.fill",
                isFocused: focusedSignUpField == .nickname
            ) {
                TextField(
                    "닉네임",
                    text: Binding(
                        get: { presenter.viewState.nick },
                        set: { value in
                            Task { await presenter.send(.nickChanged(value)) }
                        }
                    )
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedSignUpField, equals: .nickname)
            } trailing: {
                EmptyView()
            }

            validationLine(
                text: "필수 닉네임",
                isSatisfied: presenter.viewState.nicknameValid,
                isActive: !presenter.viewState.nick.isEmpty
            )
        }
    }

    private func signUpFieldShell<Field: View, Trailing: View>(
        title: String,
        systemImage: String,
        isFocused: Bool,
        @ViewBuilder field: () -> Field,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: PikkoSpacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isFocused ? PikkoColor.primary : PikkoColor.secondaryText)
                .frame(width: 30, height: 30)
                .background(PikkoColor.primarySoft.opacity(isFocused ? 1 : 0.58))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PikkoColor.tertiaryText)

                field()
                    .font(PikkoTypography.body)
                    .foregroundStyle(PikkoColor.primaryText)
                    .tint(PikkoColor.primary)
            }

            trailing()
        }
        .padding(.horizontal, PikkoSpacing.md)
        .frame(minHeight: 62)
        .background(PikkoColor.elevatedSurface.opacity(isFocused ? 0.98 : 0.76))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isFocused ? PikkoColor.primary.opacity(0.52) : PikkoColor.divider.opacity(0.58), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func validationLine(text: String, isSatisfied: Bool, isActive: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isSatisfied ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(PikkoTypography.caption)
                .lineLimit(2)
        }
        .foregroundStyle(isSatisfied ? PikkoColor.success : (isActive ? PikkoColor.warning : PikkoColor.secondaryText))
        .padding(.horizontal, PikkoSpacing.xs)
    }

    private var serviceRequirementCard: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.md) {
            Text("로그인 후 이용할 수 있어요")
                .font(PikkoTypography.cardTitle)
                .foregroundStyle(PikkoColor.primaryText)

            authRequirementRow(
                title: "주문과 결제",
                subtitle: "주문 생성, 결제 검증, 주문 내역 조회",
                systemImage: "creditcard"
            )
            authRequirementRow(
                title: "커뮤니티와 리뷰",
                subtitle: "게시글 조회/작성, 댓글, 리뷰, 좋아요",
                systemImage: "bubble.left.and.bubble.right.fill"
            )
            authRequirementRow(
                title: "가게 정보와 프로필",
                subtitle: "홈, 가게 상세, 찜, 프로필 기능",
                systemImage: "storefront"
            )
        }
        .padding(PikkoSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PikkoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous))
        .pikkoShadow(PikkoShadow.card)
    }

    @ViewBuilder
    private var statusCards: some View {
        if let configurationMessage = presenter.viewState.configurationMessage {
            noticeCard(
                title: "로그인 설정 안내",
                message: configurationMessage,
                tone: .warning
            )
        }

        if let errorMessage = presenter.viewState.errorMessage {
            noticeCard(
                title: "로그인에 실패했어요",
                message: errorMessage,
                tone: .error
            )
        }
    }

    private func screenHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
            Text(title)
                .font(PikkoTypography.hero)
                .foregroundStyle(PikkoColor.primaryText)

            Text(subtitle)
                .font(PikkoTypography.body)
                .foregroundStyle(PikkoColor.secondaryText)
                .lineSpacing(4)
        }
    }

    private func authRequirementRow(
        title: String,
        subtitle: String,
        systemImage: String
    ) -> some View {
        HStack(alignment: .top, spacing: PikkoSpacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PikkoColor.accentStrong)
                .frame(width: 28, height: 28)
                .background(PikkoColor.surfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(PikkoTypography.bodyStrong)
                    .foregroundStyle(PikkoColor.primaryText)

                Text(subtitle)
                    .font(PikkoTypography.caption)
                    .foregroundStyle(PikkoColor.secondaryText)
            }
        }
    }

    @ViewBuilder
    private func noticeCard(
        title: String,
        message: String,
        tone: NoticeTone
    ) -> some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
            Text(title)
                .font(PikkoTypography.bodyStrong)
                .foregroundStyle(tone.titleColor)

            Text(message)
                .font(PikkoTypography.caption)
                .foregroundStyle(PikkoColor.secondaryText)
                .lineSpacing(3)
        }
        .padding(PikkoSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
    }

    private func inlineLinkRow(
        leadingText: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 4) {
            Text(leadingText)
                .font(PikkoTypography.caption)
                .foregroundStyle(PikkoColor.secondaryText)

            Button(actionTitle, action: action)
                .font(PikkoTypography.captionStrong)
                .foregroundStyle(PikkoColor.accentStrong)
        }
    }

    private func navigationButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(PikkoColor.primaryText)
                .frame(width: 40, height: 40)
                .background(PikkoColor.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous)
                        .stroke(PikkoColor.line, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func switchScreen(_ target: Screen) {
        screen = target
        Task {
            await presenter.send(.clearError)
        }
    }

    @ViewBuilder
    private func providerButtonView(for providerButton: AuthProviderButtonState) -> some View {
        let isEnabled = providerButton.isEnabled && (!presenter.viewState.isLoading || providerButton.isLoading)

        switch providerButton.provider {
        case .apple:
            AppleContinueButton(
                isLoading: providerButton.isLoading,
                isEnabled: isEnabled
            ) {
                Task {
                    await presenter.send(.providerTapped(providerButton.provider))
                }
            }
        case .kakao:
            KakaoContinueButton(
                title: providerButton.title,
                isLoading: providerButton.isLoading,
                isEnabled: isEnabled
            ) {
                Task {
                    await presenter.send(.providerTapped(providerButton.provider))
                }
            }
        }
    }
}

private extension AuthRootView {
    enum NoticeTone {
        case warning
        case error

        var backgroundColor: Color {
            switch self {
            case .warning:
                return PikkoColor.accentSoft
            case .error:
                return PikkoColor.accentSoft
            }
        }

        var titleColor: Color {
            switch self {
            case .warning:
                return PikkoColor.accentStrong
            case .error:
                return PikkoColor.danger
            }
        }
    }
}

private struct SocialContinueButton<Leading: View>: View {
    let title: String
    let isLoading: Bool
    let isEnabled: Bool
    let backgroundColor: Color
    let foregroundColor: Color
    let borderColor: Color
    let action: () -> Void
    let leadingContent: () -> Leading

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous)
                    .fill(backgroundColor)

                RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)

                HStack(spacing: PikkoSpacing.sm) {
                    leadingContent()
                    Text(title)
                        .font(PikkoTypography.bodyStrong)
                }
                .foregroundStyle(foregroundColor)

                if isLoading {
                    ProgressView()
                        .tint(foregroundColor)
                }
            }
            .frame(height: PrimaryButton.Size.regular.height)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .opacity(isEnabled ? 1 : 0.55)
        .pikkoShadow(PikkoShadow.card)
    }
}

private struct KakaoContinueButton: View {
    let title: String
    let isLoading: Bool
    let isEnabled: Bool
    let action: () -> Void

    private let kakaoColor = Color(red: 254 / 255, green: 229 / 255, blue: 0)

    var body: some View {
        SocialContinueButton(
            title: title,
            isLoading: isLoading,
            isEnabled: isEnabled,
            backgroundColor: kakaoColor,
            foregroundColor: .black,
            borderColor: kakaoColor,
            action: action
        ) {
            Image(systemName: "message.fill")
                .font(.system(size: 15, weight: .semibold))
        }
    }
}

private struct AppleContinueButton: View {
    let isLoading: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        ZStack {
            AppleIDSystemButtonRepresentable(
                style: .whiteOutline,
                isEnabled: isEnabled && !isLoading,
                action: action
            )
            .frame(maxWidth: .infinity)
            .frame(height: PrimaryButton.Size.regular.height)

            if isLoading {
                RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous)
                    .fill(Color.black.opacity(0.06))

                ProgressView()
                    .tint(.black)
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(isEnabled ? 1 : 0.55)
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous))
        .pikkoShadow(PikkoShadow.card)
    }
}

private struct AppleIDSystemButtonRepresentable: UIViewRepresentable {
    let style: ASAuthorizationAppleIDButton.Style
    let isEnabled: Bool
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .continue, style: style)
        button.addTarget(
            context.coordinator,
            action: #selector(Coordinator.didTapButton),
            for: .touchUpInside
        )
        button.cornerRadius = PikkoRadius.hero
        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
        uiView.isEnabled = isEnabled
        uiView.cornerRadius = PikkoRadius.hero
    }

    final class Coordinator: NSObject {
        private let action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc
        func didTapButton() {
            action()
        }
    }
}

extension View {
    func authInputStyle() -> some View {
        self
            .font(PikkoTypography.body)
            .foregroundStyle(PikkoColor.primaryText)
            .padding(.horizontal, PikkoSpacing.md)
            .frame(height: 52)
            .background(PikkoColor.surface)
            .overlay {
                RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous)
                    .stroke(PikkoColor.divider.opacity(0.85), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous))
            .tint(PikkoColor.primary)
    }
}
