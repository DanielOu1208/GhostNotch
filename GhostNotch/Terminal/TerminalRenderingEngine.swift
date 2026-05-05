import Foundation

@MainActor
protocol TerminalRenderingEngine: AnyObject {
    func start(session: TerminalSession)
    func sendInput(_ input: Data)
    func resize(cols: Int, rows: Int)
    func focus()
    func blur()
}
