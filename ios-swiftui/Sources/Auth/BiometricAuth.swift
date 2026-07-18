import LocalAuthentication

enum BiometricAuthError: LocalizedError {
    case unavailable
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "อุปกรณ์นี้ไม่รองรับ Face ID / Touch ID"
        case .cancelled:
            return "ยกเลิกการยืนยันตัวตน"
        case .failed(let detail):
            return detail
        }
    }
}

enum BiometricAuth {
    static var canEvaluate: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    static var biometryLabel: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        default:
            return "Biometrics"
        }
    }

    static func authenticate(reason: String) async throws {
        let context = LAContext()
        context.localizedCancelTitle = "ใช้รหัสผ่าน"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw BiometricAuthError.unavailable
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            guard success else {
                throw BiometricAuthError.failed("ยืนยันตัวตนไม่สำเร็จ")
            }
        } catch let laError as LAError {
            switch laError.code {
            case .userCancel, .appCancel, .systemCancel:
                throw BiometricAuthError.cancelled
            case .userFallback:
                throw BiometricAuthError.cancelled
            case .biometryNotAvailable, .biometryNotEnrolled, .biometryLockout:
                throw BiometricAuthError.unavailable
            default:
                throw BiometricAuthError.failed(laError.localizedDescription)
            }
        }
    }
}
