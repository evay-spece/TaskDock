@main
struct TaskbarArrivalOrderSelfTest {
    static func main() {
        var policy = TaskbarArrivalOrder()
        func window(_ id: String, _ app: String) -> TaskbarArrivalOrder.Window {
            .init(id: id, appKey: app)
        }
        let initial = policy.reconcile([window("a1", "A"), window("b1", "B")], appOrder: ["B", "A"])
        precondition(initial.apps == ["B", "A"])
        precondition(initial.windows == ["a1", "b1"])

        let sameApp = policy.reconcile(
            [window("a2", "A"), window("b1", "B"), window("a1", "A")], appOrder: initial.apps
        )
        precondition(sameApp.apps == ["B", "A"])
        precondition(sameApp.windows == ["a1", "b1", "a2"])

        let newApp = policy.reconcile(
            [window("c1", "C"), window("a2", "A"), window("b1", "B"), window("a1", "A")],
            appOrder: sameApp.apps
        )
        precondition(newApp.apps == ["B", "A", "C"])

        let closed = policy.reconcile([window("a1", "A"), window("c1", "C")], appOrder: newApp.apps)
        let returned = policy.reconcile(
            [window("b2", "B"), window("c1", "C"), window("a1", "A")], appOrder: closed.apps
        )
        precondition(returned.apps == ["A", "C", "B"])
        precondition(returned.windows == ["a1", "c1", "b2"])
        print("TASKBAR_ARRIVAL_ORDER_OK")
    }
}
