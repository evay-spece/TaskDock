import Foundation

@main
struct WindowRuleSelfTest {
    static func main() {
        let rule = BlockedWindowRule(
            appKey: "com.apple.inputmethod.SCIM",
            applicationName: "简体中文输入方式",
            rawTitle: "Window",
            accessibilityRole: "AXWindow",
            accessibilitySubrole: "AXUnknown"
        )

        precondition(rule.windowLabel == "Window")
        precondition(rule.matches(
            appKey: "com.apple.inputmethod.SCIM",
            rawTitle: " Window ",
            accessibilityRole: "AXWindow",
            accessibilitySubrole: "AXUnknown"
        ))
        precondition(!rule.matches(
            appKey: "com.apple.inputmethod.SCIM",
            rawTitle: "候选词",
            accessibilityRole: "AXWindow",
            accessibilitySubrole: "AXUnknown"
        ))
        precondition(!rule.matches(
            appKey: "com.apple.TextEdit",
            rawTitle: "Window",
            accessibilityRole: "AXWindow",
            accessibilitySubrole: "AXUnknown"
        ))

        let untitledRule = BlockedWindowRule(
            appKey: "com.example.helper",
            applicationName: "Helper",
            rawTitle: "  ",
            accessibilityRole: "AXWindow",
            accessibilitySubrole: nil
        )
        precondition(untitledRule.windowLabel == "无标题窗口")
        print("WINDOW_RULE_OK")
    }
}
