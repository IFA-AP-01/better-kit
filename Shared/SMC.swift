import Foundation
import IOKit

/// Swift wrapper over the C AppleSMC client. Reads work as any user; writes need root (the helper).
final class SMC {
    private let connection: io_connect_t
    private let lock = NSLock()

    init?() {
        let conn = bk_smc_open()
        guard conn != 0 else { return nil }
        connection = conn
    }

    deinit {
        bk_smc_close(connection)
    }

    static func code(_ key: String) -> UInt32 {
        key.withCString { bk_smc_fourcc($0) }
    }

    static func string(_ code: UInt32) -> String {
        var chars = [CChar](repeating: 0, count: 5)
        bk_smc_fourcc_string(code, &chars)
        return String(cString: chars)
    }

    struct Value {
        let key: String
        let type: String
        let bytes: [UInt8]

        /// Decodes the numeric SMC types seen on Apple Silicon and older Macs.
        var double: Double? {
            switch type {
            case "flt ":
                guard bytes.count >= 4 else { return nil }
                let raw = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
                return Double(Float(bitPattern: raw))
            case "ui8 ", "flag":
                return bytes.first.map(Double.init)
            case "ui16":
                guard bytes.count >= 2 else { return nil }
                return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            case "ui32":
                guard bytes.count >= 4 else { return nil }
                return Double(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
            case "fpe2":
                guard bytes.count >= 2 else { return nil }
                return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
            case "sp78":
                guard bytes.count >= 2 else { return nil }
                return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
            default:
                return nil
            }
        }
    }

    func read(_ key: String) -> Value? {
        lock.lock(); defer { lock.unlock() }
        var value = BKSMCValue()
        guard bk_smc_read(connection, Self.code(key), &value) == KERN_SUCCESS else { return nil }
        let bytes = withUnsafeBytes(of: value.bytes) { Array($0.prefix(Int(value.dataSize))) }
        return Value(key: key, type: Self.string(value.dataType), bytes: bytes)
    }

    func double(_ key: String) -> Double? {
        read(key)?.double
    }

    @discardableResult
    func write(_ key: String, bytes: [UInt8]) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return bytes.withUnsafeBufferPointer { buffer in
            bk_smc_write(connection, Self.code(key), buffer.baseAddress, UInt32(buffer.count)) == KERN_SUCCESS
        }
    }

    /// Writes a number in the key's own encoding.
    @discardableResult
    func write(_ key: String, value: Double) -> Bool {
        guard let current = read(key) else { return false }
        switch current.type {
        case "flt ":
            let raw = Float(value).bitPattern
            return write(key, bytes: [UInt8(raw & 0xFF), UInt8(raw >> 8 & 0xFF), UInt8(raw >> 16 & 0xFF), UInt8(raw >> 24)])
        case "ui8 ", "flag":
            return write(key, bytes: [UInt8(max(0, min(255, value)))])
        case "fpe2":
            let raw = UInt16(max(0, value) * 4)
            return write(key, bytes: [UInt8(raw >> 8), UInt8(raw & 0xFF)])
        case "ui16":
            let raw = UInt16(max(0, value))
            return write(key, bytes: [UInt8(raw >> 8), UInt8(raw & 0xFF)])
        default:
            return false
        }
    }

    /// Every key name the SMC exposes, used to discover temperature sensors.
    func allKeys() -> [String] {
        guard let count = double("#KEY").map(Int.init) else { return [] }
        lock.lock(); defer { lock.unlock() }
        var keys: [String] = []
        keys.reserveCapacity(count)
        for index in 0..<count {
            var code: UInt32 = 0
            if bk_smc_key_at_index(connection, UInt32(index), &code) == KERN_SUCCESS {
                keys.append(Self.string(code))
            }
        }
        return keys
    }
}

/// Fan keys, shared by the reader (app) and the writer (helper).
enum FanKeys {
    static let count = "FNum"
    static func actual(_ i: Int) -> String { "F\(i)Ac" }
    static func minimum(_ i: Int) -> String { "F\(i)Mn" }
    static func maximum(_ i: Int) -> String { "F\(i)Mx" }
    static func target(_ i: Int) -> String { "F\(i)Tg" }
    static func mode(_ i: Int) -> String { "F\(i)Md" }
    static func id(_ i: Int) -> String { "F\(i)ID" }
    /// Unlocks manual fan control on Apple Silicon models that ignore F0Md alone.
    static let forceTest = "Ftst"
}
