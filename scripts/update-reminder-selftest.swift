import Foundation

@main
struct UpdateReminderSelfTest {
    static func main() {
        let current = "1.7.1"
        precondition(UpdateSupport.majorMinorUpgradeID("1.7.2", than: current) == nil)
        precondition(UpdateSupport.majorMinorUpgradeID("1.8.0", than: current) == "1.8")
        precondition(UpdateSupport.majorMinorUpgradeID("2.0.0", than: current) == "2.0")
        precondition(UpdateSupport.majorMinorUpgradeID("v1.10.0", than: current) == "1.10")
        precondition(UpdateSupport.majorMinorUpgradeID("1.7.1", than: current) == nil)
        precondition(UpdateSupport.majorMinorUpgradeID("1.6.9", than: current) == nil)
        precondition(UpdateSupport.shouldRemindForMajorMinorUpgrade(
            "1.8.0", than: current, lastReminded: nil
        ))
        precondition(!UpdateSupport.shouldRemindForMajorMinorUpgrade(
            "1.8.1", than: current, lastReminded: "1.8"
        ))
        precondition(UpdateSupport.shouldRemindForMajorMinorUpgrade(
            "2.0.0", than: current, lastReminded: "1.8"
        ))
        print("UPDATE_REMINDER_OK")
    }
}
