import Foundation

actor OrderPaymentCoordinator {
    static let shared = OrderPaymentCoordinator()

    private var activePaymentOrderCodes = Set<String>()
    private var validationTasks: [String: Task<ValidatedPaymentReceipt, Error>] = [:]

    func beginPayment(orderCode: String) -> Bool {
        activePaymentOrderCodes.insert(orderCode).inserted
    }

    func endPayment(orderCode: String) {
        activePaymentOrderCodes.remove(orderCode)
    }

    func validation(
        request: PaymentValidationRequest,
        operation: @escaping @MainActor @Sendable () async throws -> ValidatedPaymentReceipt
    ) async throws -> ValidatedPaymentReceipt {
        let key = validationKey(orderCode: request.orderCode, impUID: request.impUID)
        if let existingTask = validationTasks[key] {
            return try await existingTask.value
        }

        let task = Task { @MainActor in
            try await operation()
        }
        validationTasks[key] = task
        defer {
            validationTasks[key] = nil
        }
        return try await task.value
    }

    private func validationKey(orderCode: String?, impUID: String) -> String {
        "\(orderCode ?? "-")|\(impUID.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
}
