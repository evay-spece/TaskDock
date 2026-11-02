import Foundation

enum NativeDockReservationSettings {
    static let enabledKey = "taskdock.nativeDockReservationExperimentV1"
    static let statusKey = "taskdock.nativeDockReservationStatusV1"
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
}
