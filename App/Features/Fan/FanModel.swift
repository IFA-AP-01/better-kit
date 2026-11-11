import Foundation

struct FanReading: Identifiable, Equatable {
    let index: Int
    var actual: Double
    var minimum: Double
    var maximum: Double
    var target: Double
    var manual: Bool
    var id: Int { index }
    var name: String { index == 0 ? "Fan" : "Fan \(index + 1)" }
}

struct SensorReading: Identifiable, Equatable {
    let key: String
    let name: String
    var value: Double
    var id: String { key }
}

@MainActor
final class FanModel: ObservableObject {
    @Published var settings: FanSettings {
        didSet {
            guard settings != oldValue else { return }
            onChange?()
            lastApplied = [:]
            applyPreset()
        }
    }
    @Published private(set) var fans: [FanReading] = []
    @Published private(set) var sensors: [SensorReading] = []
    @Published private(set) var lastError: String?
    let helper = FanHelperClient()
    var onChange: (() -> Void)?

    private let smc = SMC()
    private var sensorKeys: [(key: String, name: String)] = []
    private var timer: Timer?
    private var lastApplied: [Int: Double] = [:]

    init(settings: FanSettings) {
        self.settings = settings
        discover()
        poll()
    }

    var hasFans: Bool { !fans.isEmpty }

    var cpuTemperature: Double? {
        let cores = sensors.filter { $0.key.hasPrefix("Tp") || $0.key.hasPrefix("Te") }
        return cores.map(\.value).max() ?? sensors.map(\.value).max()
    }

    var curveTemperature: Double? {
        if let key = settings.curveSensor, let s = sensors.first(where: { $0.key == key }) { return s.value }
        return cpuTemperature
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        if settings.preset != .automatic { applyPreset() }
    }

    func shutdown() {
        timer?.invalidate()
        if settings.preset != .automatic { helper.restoreAutomaticBlocking() }
        helper.disconnect()
    }

    private func tick() {
        if helper.state != .enabled { helper.refresh() }
        poll()
        if settings.preset != .automatic { applyPreset() }
    }

    private func discover() {
        guard let smc else { return }
        let count = Int(smc.double(FanKeys.count) ?? 0)
        fans = (0..<count).map { FanReading(index: $0, actual: 0, minimum: 0, maximum: 0, target: 0, manual: false) }
        var found: [(String, String)] = []
        for key in smc.allKeys() where key.hasPrefix("T") {
            guard let value = smc.read(key), value.type == "flt ", let v = value.double, v > 5, v < 130 else { continue }
            found.append((key, Self.sensorName(key)))
        }
        sensorKeys = found.sorted { $0.0 < $1.0 }
    }

    func poll() {
        guard let smc else { return }
        fans = fans.map { fan in
            var f = fan
            f.actual = smc.double(FanKeys.actual(f.index)) ?? 0
            f.minimum = smc.double(FanKeys.minimum(f.index)) ?? 0
            f.maximum = smc.double(FanKeys.maximum(f.index)) ?? 0
            f.target = smc.double(FanKeys.target(f.index)) ?? 0
            f.manual = (smc.double(FanKeys.mode(f.index)) ?? 0) == 1
            return f
        }
        sensors = sensorKeys.compactMap { entry in
            guard let v = smc.double(entry.key), v > 0, v < 150 else { return nil }
            return SensorReading(key: entry.key, name: entry.name, value: v)
        }
    }

    func applyPreset() {
        guard hasFans else { return }
        switch settings.preset {
        case .automatic:
            guard helper.state == .enabled else { return }
            helper.setAutomatic { [weak self] error in self?.lastError = error }
        case .constant:
            setAll(level: settings.constantLevel)
        case .curve:
            guard let t = curveTemperature else { return }
            let span = max(settings.curveHigh - settings.curveLow, 1)
            setAll(level: min(max((t - settings.curveLow) / span, 0), 1))
        }
    }

    private func setAll(level: Double) {
        guard helper.state == .enabled else {
            lastError = "Enable the fan helper first."
            return
        }
        for fan in fans where fan.maximum > 0 {
            let rpm = (fan.minimum + level * (fan.maximum - fan.minimum)).rounded()
            if fan.manual, let last = lastApplied[fan.index], abs(last - rpm) < 50 { continue }
            lastApplied[fan.index] = rpm
            helper.setSpeed(index: fan.index, rpm: rpm) { [weak self] error in
                self?.lastError = error
                if error != nil { self?.lastApplied[fan.index] = nil }
            }
        }
    }

    static func sensorName(_ key: String) -> String {
        let prefixes: [(String, String)] = [
            ("Tp", "CPU Performance Core"), ("Te", "CPU Efficiency Core"), ("Tg", "GPU"),
            ("Tm", "Memory"), ("TW", "Wi-Fi"), ("Ts", "SSD"), ("TB", "Battery"), ("TH", "SSD"),
            ("Ta", "Airflow"), ("TP", "Power Supply"), ("TV", "Voltage Regulator"), ("Tf", "Fan Area"),
        ]
        let label = prefixes.first { key.hasPrefix($0.0) }?.1 ?? "Sensor"
        return "\(label) \(key.dropFirst(2))"
    }
}
