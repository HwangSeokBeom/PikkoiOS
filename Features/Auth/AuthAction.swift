import Foundation

enum AuthAction {
    case onAppear
    case providerTapped(AuthProvider)
    case emailChanged(String)
    case validateEmailTapped
    case passwordChanged(String)
    case passwordConfirmationChanged(String)
    case nickChanged(String)
    case emailSignInTapped
    case signUpTapped
    case clearError
    case stubSignInTapped
}
