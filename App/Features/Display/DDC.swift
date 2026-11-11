import CoreGraphics
import Foundation
import IOKit

/// DDC/CI over the Apple Silicon display coprocessor (the m1ddc / MonitorControl technique).
/// Not every port carries DDC (the Mac mini's HDMI often does not); callers fall back to gamma dimming.
final class DDC {
    enum VCP: UInt8 {
        case brightness = 0x10
        case contrast = 0x12
    }

    private let service: IOAVService
    private let queue = DispatchQueue(label: "dev.ifateam.betterkit.ddc")

    private init(service: IOAVService) {
        self.service = service
    }

    /// External displays' AV services, in IORegistry order.
    static func externalServices() -> [DDC] {
        var result: [DDC] = []
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            let location = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String
            guard location == "External", let service = IOAVServiceCreateWithService(kCFAllocatorDefault, entry) else { continue }
            result.append(DDC(service: service))
        }
        return result
    }

    func write(_ vcp: VCP, value: UInt16, completion: ((Bool) -> Void)? = nil) {
        queue.async { [service] in
            var packet: [UInt8] = [0x84, 0x03, vcp.rawValue, UInt8(value >> 8), UInt8(value & 0xFF), 0]
            packet[5] = Self.checksum(seed: 0x6E ^ 0x51, packet[0..<5])
            var ok = false
            for _ in 0..<2 {
                if IOAVServiceWriteI2C(service, 0x37, 0x51, &packet, UInt32(packet.count)) == kIOReturnSuccess {
                    ok = true
                    break
                }
                usleep(10_000)
            }
            if let completion { DispatchQueue.main.async { completion(ok) } }
        }
    }

    /// Reads (current, max) for a VCP code. Completion runs on the main queue.
    func read(_ vcp: VCP, completion: @escaping ((current: UInt16, max: UInt16)?) -> Void) {
        queue.async { [service] in
            var result: (UInt16, UInt16)?
            for _ in 0..<3 {
                var request: [UInt8] = [0x82, 0x01, vcp.rawValue, 0]
                request[3] = Self.checksum(seed: 0x6E ^ 0x51, request[0..<3])
                guard IOAVServiceWriteI2C(service, 0x37, 0x51, &request, UInt32(request.count)) == kIOReturnSuccess else {
                    usleep(20_000)
                    continue
                }
                usleep(50_000)
                var reply = [UInt8](repeating: 0, count: 12)
                guard IOAVServiceReadI2C(service, 0x37, 0x51, &reply, UInt32(reply.count)) == kIOReturnSuccess else {
                    usleep(20_000)
                    continue
                }
                guard reply[2] == 0x02, reply[3] == 0x00, reply[4] == vcp.rawValue else {
                    usleep(20_000)
                    continue
                }
                let max = UInt16(reply[6]) << 8 | UInt16(reply[7])
                let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
                if max > 0 {
                    result = (current, max)
                    break
                }
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func checksum(seed: UInt8, _ bytes: ArraySlice<UInt8>) -> UInt8 {
        bytes.reduce(seed) { $0 ^ $1 }
    }
}

/// Software dimming through the display's gamma table, for panels without DDC.
enum GammaDimmer {
    static func set(_ display: CGDirectDisplayID, level: Double) {
        let v = Float(max(0.1, min(1, level)))
        CGSetDisplayTransferByFormula(display, 0, v, 1, 0, v, 1, 0, v, 1)
    }

    static func reset() {
        CGDisplayRestoreColorSyncSettings()
    }
}

/// Font smoothing (AppleFontSmoothing) for all apps; takes effect as apps relaunch.
enum FontSmoothing {
    private static let key = "AppleFontSmoothing" as CFString

    static var current: Int? {
        CFPreferencesCopyValue(key, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? Int
    }

    static func set(_ value: Int?) {
        let v: CFPropertyList? = value.map { $0 as CFNumber }
        CFPreferencesSetValue(key, v, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
}
