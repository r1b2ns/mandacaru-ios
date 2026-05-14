import Foundation
import os

#if DEBUG
nonisolated enum Log {
    static let subsystem = Bundle.main.bundleIdentifier ?? "zeroSixteen.br.com.MandacaruiOS"

    static let floresta = Logger(subsystem: subsystem, category: "Floresta")
    static let node = Logger(subsystem: subsystem, category: "Node")
    static let ui = Logger(subsystem: subsystem, category: "UI")
}
#else
nonisolated enum Log {
    static let subsystem = Bundle.main.bundleIdentifier ?? "zeroSixteen.br.com.MandacaruiOS"

    static let floresta = Logger(OSLog.disabled)
    static let node = Logger(OSLog.disabled)
    static let ui = Logger(OSLog.disabled)
}
#endif
