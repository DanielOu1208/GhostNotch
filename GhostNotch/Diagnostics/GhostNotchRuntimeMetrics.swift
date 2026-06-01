import OSLog

enum GhostNotchRuntimeMetrics {
    private static let logger = Logger(subsystem: "com.ghostnotch.local", category: "Runtime")

    static func recordHoverEvent(stateChanged: Bool) {
        #if DEBUG
        guard stateChanged else {
            return
        }

        logger.debug("hover event stateChanged=\(stateChanged)")
        #endif
    }

    static func recordSkippedCollapsedSnapshot() {
        #if DEBUG
        logger.debug("snapshot skipped while collapsed")
        #endif
    }

    static func recordOutputFlush(byteCount: Int) {
        #if DEBUG
        logger.debug("pty output flush bytes=\(byteCount)")
        #endif
    }

    static func recordSnapshotPublish(_ snapshot: TerminalRenderSnapshot, skipped: Bool) {
        #if DEBUG
        logger.debug(
            "snapshot publish skipped=\(skipped) dirty=\(snapshot.dirtyState.rawValue) rows=\(snapshot.rows) cols=\(snapshot.columns) dirtyRows=\(snapshot.dirtyRows.count)"
        )
        #endif
    }

    static func recordGridInvalidation(fullRedraw: Bool, rowCount: Int) {
        #if DEBUG
        logger.debug("grid invalidation fullRedraw=\(fullRedraw) rows=\(rowCount)")
        #endif
    }
}
