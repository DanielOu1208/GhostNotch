import Foundation

@MainActor
protocol TerminalRenderingEngine: AnyObject {
    var snapshot: TerminalRenderSnapshot { get }
    var onSnapshotChange: ((TerminalRenderSnapshot) -> Void)? { get set }

    func start(session: TerminalSession)
    func processOutput(_ data: Data)
    func sendInput(_ input: Data)
    func resize(cols: Int, rows: Int)
    func focus()
    func blur()
}
