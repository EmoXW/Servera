import LocalAuthentication

enum BiometricAvailability {
    case available(BiometricType)
    case notAvailable
    case denied
    case lockedOut
}

enum BiometricType: Sendable {
    case faceID
    case touchID
    case none
}

actor BiometricAuthService {
    static let shared = BiometricAuthService()
    
    private init() {}
    
    func biometricType() -> BiometricType {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        switch context.biometryType {
        case .faceID:
            return .faceID
        case .touchID:
            return .touchID
        default:
            return .none
        }
    }
    
    func availability() -> BiometricAvailability {
        let context = LAContext()
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        guard canEvaluate else {
            guard let laError = error as? LAError else {
                return .notAvailable
            }
            switch laError.code {
            case .biometryNotAvailable, .biometryNotEnrolled:
                return .notAvailable
            case .biometryLockout:
                return .lockedOut
            default:
                return .denied
            }
        }
        switch context.biometryType {
        case .faceID:
            return .available(.faceID)
        case .touchID:
            return .available(.touchID)
        default:
            return .notAvailable
        }
    }
    
    @discardableResult
    func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()
        return try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            ) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }
}

extension BiometricAvailability {
    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
    
    var type: BiometricType {
        switch self {
        case .available(let type):
            return type
        default:
            return .none
        }
    }
}
