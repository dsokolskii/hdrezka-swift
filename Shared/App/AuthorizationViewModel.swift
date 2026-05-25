import Foundation
import Observation

@MainActor
@Observable
final class AuthorizationViewModel {
    private(set) var isAuthenticated: Bool
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var sessionID = UUID()

    private let service: RezkaAuthorizationService
    @ObservationIgnored
    nonisolated(unsafe) private var authorizationTask: Task<Void, Never>?

    init(service: RezkaAuthorizationService) {
        self.service = service
        service.restorePersistedCookies()
        isAuthenticated = service.hasActiveSession

        authorizationTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .rezkaAuthorizationRequired) {
                await self?.handleAuthorizationRequired()
            }
        }
    }

    deinit {
        authorizationTask?.cancel()
    }

    var fallbackProfileName: String {
        "Профиль"
    }

    func login(email: String, password: String) async {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalizedEmail.isEmpty == false, normalizedPassword.isEmpty == false else {
            errorMessage = "Введите email и пароль"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            try await service.login(email: normalizedEmail, password: normalizedPassword)
            isAuthenticated = true
            sessionID = UUID()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func logout() {
        service.clearSession()
        isAuthenticated = false
        errorMessage = nil
        isLoading = false
        sessionID = UUID()
    }

    private func handleAuthorizationRequired() async {
        service.clearSession()
        isAuthenticated = false
        isLoading = false
        errorMessage = "Сессия \(ConstantsApi.host) истекла. Войдите снова."
        sessionID = UUID()
    }
}
