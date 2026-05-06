import Foundation

@MainActor
protocol TerminalRenderingEngine: AnyObject {
    var snapshot: TerminalRenderSnapshot { get }
    var onSnapshotChange: ((TerminalRenderSnapshot) -> Void)? { get set }

    func start(session: TerminalSession)
    func processOutput(_ data: Data)
    func sendInput(_ input: Data)
    func sendKeyEvent(_ event: TerminalKeyEvent)
    func scrollViewport(deltaRows: Int)
    func resize(cols: Int, rows: Int)
    func focus()
    func blur()
}
