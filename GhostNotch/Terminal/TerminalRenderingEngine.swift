import Foundation

@MainActor
protocol TerminalRenderingEngine: AnyObject {
    var snapshot: TerminalRenderSnapshot { get }
    var lastAppliedGridResize: TerminalGridResize? { get }
    var onSnapshotChange: ((TerminalRenderSnapshot) -> Void)? { get set }

    func start(session: TerminalSession)
    func processOutput(_ data: Data)
    func sendInput(_ input: Data)
    func sendKeyEvent(_ event: TerminalKeyEvent)
    func handleScrollWheel(_ event: TerminalScrollEvent)
    func handleMouseEvent(_ event: TerminalMouseEvent)
    func resize(cols: Int, rows: Int, cellWidthPixels: Int, cellHeightPixels: Int)
    func reset(cols: Int, rows: Int)
    func focus()
    func blur()
}
