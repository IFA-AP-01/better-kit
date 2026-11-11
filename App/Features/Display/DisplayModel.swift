import AppKit
import CoreGraphics

@MainActor
final class DisplayModel: ObservableObject {
    @Published var settings: DisplaySettings {
        didSet {
            guard settings != oldValue else { return }
            onChange?()
            if settings.hiDPIEnabled != oldValue.hiDPIEnabled || settings.targetDisplay != oldValue.targetDisplay {
                applyHiDPI()
            } else if settings.looksLike != oldValue.looksLike, manager.isActive {
                if !manager.setLooksLike(settings.looksLike) { applyHiDPI(force: true) }
                refreshDisplays()
            }
            if settings.fontSmoothing != oldValue.fontSmoothing {
                FontSmoothing.set(settings.fontSmoothing)
            }
            if settings.softwareDimming != oldValue.softwareDimming {
                if settings.softwareDimming { applyBrightness() } else { GammaDimmer.reset() }
            }
        }
    }
    @Published private(set) var displays: [DisplayInfo] = []
    @Published private(set) var hiDPIActive = false
    @Published private(set) var hiDPIError: String?
    @Published private(set) var isWorking = false
    @Published private(set) var ddcAvailable = false
    @Published var brightness: Double = 0.8
    @Published var contrast: Double = 0.75
    var onChange: (() -> Void)?

    private let manager = VirtualDisplayManager()
    private var ddc: DDC?
    private var brightnessMax: UInt16 = 100
    private var contrastMax: UInt16 = 100
    private var pendingBrightness: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []

    init(settings: DisplaySettings) {
        self.settings = settings
        refreshDisplays()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didWake() }
        })
    }

    func start() {
        applyHiDPI()
        probeDDC()
    }

    var target: DisplayInfo? {
        let candidates = displays.filter { !$0.isBuiltin }
        if let key = settings.targetDisplay, let match = candidates.first(where: { $0.key == key }) {
            return match
        }
        return candidates.first
    }

    func refreshDisplays() {
        displays = DisplayInfo.all()
        hiDPIActive = manager.isActive
    }

    func applyHiDPI(force: Bool = false) {
        hiDPIError = nil
        guard settings.hiDPIEnabled else {
            manager.disable()
            refreshDisplays()
            return
        }
        guard let target else {
            manager.disable()
            hiDPIError = "No external display connected."
            refreshDisplays()
            return
        }
        if !force, manager.isActive, manager.physicalID == target.id, manager.looksLike == settings.looksLike {
            return
        }
        if target.isHiDPI, !manager.isActive {
            hiDPIError = "\(target.name) already renders in HiDPI."
        }
        isWorking = true
        let rate = target.refreshRate
        manager.enable(physical: target.id, looksLike: settings.looksLike, refreshRate: rate) { [weak self] error in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isWorking = false
                if let error {
                    self.hiDPIError = error.localizedDescription
                    Log.display.error("HiDPI failed: \(error.localizedDescription)")
                }
                self.refreshDisplays()
            }
        }
    }

    /// Removes the virtual display so the panel never stays mirrored to a dead display.
    func shutdown() {
        manager.disable()
        if settings.softwareDimming { GammaDimmer.reset() }
    }

    private func screensChanged() {
        refreshDisplays()
        guard settings.hiDPIEnabled, !isWorking else { return }
        if manager.isActive {
            if let physical = manager.physicalID, !displays.contains(where: { $0.id == physical }) {
                manager.disable()
                refreshDisplays()
            }
        } else if target != nil {
            applyHiDPI()
        }
    }

    private func didWake() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshDisplays()
                if self.settings.hiDPIEnabled, let physical = self.manager.physicalID,
                   CGDisplayMirrorsDisplay(physical) != self.manager.virtualID ?? 0 {
                    self.applyHiDPI(force: true)
                }
                self.probeDDC()
            }
        }
    }

    // MARK: - Brightness

    func probeDDC() {
        guard let service = DDC.externalServices().first else {
            ddc = nil
            ddcAvailable = false
            return
        }
        ddc = service
        service.read(.brightness) { [weak self] value in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard let value else {
                    self.ddcAvailable = false
                    Log.display.notice("DDC brightness read failed; using software dimming")
                    return
                }
                self.ddcAvailable = true
                self.brightnessMax = value.max
                self.brightness = Double(value.current) / Double(value.max)
                service.read(.contrast) { contrast in
                    MainActor.assumeIsolated {
                        guard let contrast else { return }
                        self.contrastMax = contrast.max
                        self.contrast = Double(contrast.current) / Double(contrast.max)
                    }
                }
            }
        }
    }

    func setBrightness(_ value: Double) {
        brightness = value
        applyBrightness()
    }

    func setContrast(_ value: Double) {
        contrast = value
        guard ddcAvailable, let ddc else { return }
        ddc.write(.contrast, value: UInt16((value * Double(contrastMax)).rounded()))
    }

    private func applyBrightness() {
        if ddcAvailable, let ddc {
            pendingBrightness?.cancel()
            let raw = UInt16((brightness * Double(brightnessMax)).rounded())
            let work = DispatchWorkItem { ddc.write(.brightness, value: raw) }
            pendingBrightness = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
        } else if settings.softwareDimming, let target {
            GammaDimmer.set(target.id, level: brightness)
        }
    }
}
