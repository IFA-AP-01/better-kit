import os

enum Log {
    static let app = Logger(subsystem: "dev.ifateam.betterkit", category: "app")
    static let scroll = Logger(subsystem: "dev.ifateam.betterkit", category: "scroll")
    static let display = Logger(subsystem: "dev.ifateam.betterkit", category: "display")
    static let vietnamese = Logger(subsystem: "dev.ifateam.betterkit", category: "vietnamese")
    static let fan = Logger(subsystem: "dev.ifateam.betterkit", category: "fan")
}
