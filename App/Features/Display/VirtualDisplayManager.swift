import CoreGraphics
import Foundation

/// HiDPI for low-density panels: a virtual display with 2× ("Retina") modes is created,
/// and the physical panel mirrors it. macOS renders at double resolution and the panel
/// shows the downsampled image, so text is smooth at the chosen "looks like" size.
final class VirtualDisplayManager {
    enum Failure: LocalizedError {
        case createFailed
        case modeMissing
        case mirrorFailed(CGError)

        var errorDescription: String? {
            switch self {
            case .createFailed: "macOS refused to create the virtual display."
            case .modeMissing: "The HiDPI mode did not appear on the virtual display."
            case .mirrorFailed(let e): "Mirroring failed (CGError \(e.rawValue))."
            }
        }
    }

    private var virtual: CGVirtualDisplay?
    private(set) var physicalID: CGDirectDisplayID?
    private(set) var looksLike: ResolutionChoice?

    var virtualID: CGDirectDisplayID? { virtual?.displayID }
    var isActive: Bool { virtual != nil }

    /// Builds the virtual display and mirrors `physical` to it. Completion runs on the main queue.
    func enable(physical: CGDirectDisplayID, looksLike: ResolutionChoice, refreshRate: Double,
                completion: @escaping (Error?) -> Void) {
        disable()

        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.queue = DispatchQueue.main
        descriptor.name = "BetterKit HiDPI"
        let maxW = ResolutionChoice.choices.map(\.width).max()! * 2
        let maxH = ResolutionChoice.choices.map(\.height).max()! * 2
        descriptor.maxPixelsWide = UInt32(maxW)
        descriptor.maxPixelsHigh = UInt32(maxH)
        let mm = CGDisplayScreenSize(physical)
        descriptor.sizeInMillimeters = mm.width > 0 ? mm : CGSize(width: 527, height: 296)
        descriptor.vendorID = DisplayInfo.virtualVendorID
        descriptor.productID = 0x0001
        descriptor.serialNum = CGDisplaySerialNumber(physical) &+ 1
        descriptor.terminationHandler = { _, _ in
            Log.display.notice("virtual display terminated")
        }

        guard let display = CGVirtualDisplay(descriptor: descriptor) else {
            completion(Failure.createFailed)
            return
        }

        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 1
        let rate = refreshRate > 0 ? refreshRate : 60
        settings.modes = ResolutionChoice.choices.flatMap { choice in
            [CGVirtualDisplayMode(width: UInt(choice.width * 2), height: UInt(choice.height * 2), refreshRate: rate),
             CGVirtualDisplayMode(width: UInt(choice.width), height: UInt(choice.height), refreshRate: rate)]
        }
        guard display.apply(settings) else {
            completion(Failure.createFailed)
            return
        }

        virtual = display
        physicalID = physical
        self.looksLike = looksLike
        let id = display.displayID
        Log.display.info("virtual display \(id) created for \(physical)")

        waitForMode(on: id, looksLike: looksLike, attempts: 20) { [weak self] mode in
            guard let self, self.virtual === display else { return }
            guard let mode else {
                self.disable()
                completion(Failure.modeMissing)
                return
            }
            CGDisplaySetDisplayMode(id, mode, nil)
            var config: CGDisplayConfigRef?
            CGBeginDisplayConfiguration(&config)
            CGConfigureDisplayMirrorOfDisplay(config, physical, id)
            let result = CGCompleteDisplayConfiguration(config, .forSession)
            if result != .success {
                self.disable()
                completion(Failure.mirrorFailed(result))
            } else {
                completion(nil)
            }
        }
    }

    /// Changes the "looks like" size without rebuilding the virtual display.
    func setLooksLike(_ choice: ResolutionChoice) -> Bool {
        guard let id = virtualID, let mode = Self.hiDPIMode(on: id, looksLike: choice) else { return false }
        looksLike = choice
        return CGDisplaySetDisplayMode(id, mode, nil) == .success
    }

    func disable() {
        guard let display = virtual else { return }
        if let physicalID, CGDisplayMirrorsDisplay(physicalID) == display.displayID {
            var config: CGDisplayConfigRef?
            CGBeginDisplayConfiguration(&config)
            CGConfigureDisplayMirrorOfDisplay(config, physicalID, kCGNullDirectDisplay)
            CGCompleteDisplayConfiguration(config, .forSession)
        }
        virtual = nil
        physicalID = nil
        Log.display.info("virtual display removed")
    }

    private func waitForMode(on id: CGDirectDisplayID, looksLike: ResolutionChoice, attempts: Int,
                             completion: @escaping (CGDisplayMode?) -> Void) {
        if let mode = Self.hiDPIMode(on: id, looksLike: looksLike) {
            completion(mode)
            return
        }
        guard attempts > 0 else {
            completion(nil)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.waitForMode(on: id, looksLike: looksLike, attempts: attempts - 1, completion: completion)
        }
    }

    static func hiDPIMode(on id: CGDirectDisplayID, looksLike: ResolutionChoice) -> CGDisplayMode? {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let modes = (CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode]) ?? []
        return modes.first { $0.width == looksLike.width && $0.height == looksLike.height && $0.pixelWidth == looksLike.width * 2 }
    }
}
