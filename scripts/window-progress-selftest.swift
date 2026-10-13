import Foundation

@main
struct WindowProgressSelfTest {
    static func main() {
        precondition(WindowProgressValue.normalized(value: 89, minimum: 0, maximum: 100) == 0.89)
        precondition(WindowProgressValue.normalized(value: 45, minimum: 10, maximum: 80) == 0.5)
        precondition(WindowProgressValue.normalized(value: 0.4, minimum: 0, maximum: 1) == 0.4)
        precondition(WindowProgressValue.normalized(value: 0, minimum: 0, maximum: 100) == nil)
        precondition(WindowProgressValue.normalized(value: 100, minimum: 0, maximum: 100) == nil)
        precondition(WindowProgressValue.normalized(value: .nan, minimum: 0, maximum: 100) == nil)
        print("WINDOW_PROGRESS_OK")
    }
}
