import Foundation
import os

/// Privileged fan helper. Runs as root under launchd (registered with SMAppService.daemon by the app).
/// Safety rules:
/// - Only BetterKit signed by the same team may connect.
/// - Target RPMs are clamped to each fan's reported min/max.
/// - When the last client disconnects (app quit or crashed), every fan goes back to automatic.

private let log = Logger(subsystem: "dev.ifateam.betterkit.helper", category: "fan")

final class FanController {
    private let smc: SMC?
    private var manualFans: Set<Int> = []
    private let queue = DispatchQueue(label: "dev.ifateam.betterkit.helper.smc")

    init() {
        smc = SMC()
    }

    var fanCount: Int {
        Int(smc?.double(FanKeys.count) ?? 0)
    }

    func setSpeed(index: Int, rpm: Double) -> (Bool, String?) {
        queue.sync {
            guard let smc else { return (false, "AppleSMC is unavailable") }
            guard index >= 0, index < fanCount else { return (false, "No fan \(index)") }
            guard rpm.isFinite else { return (false, "Invalid RPM") }
            let minimum = smc.double(FanKeys.minimum(index)) ?? 0
            let maximum = smc.double(FanKeys.maximum(index)) ?? 0
            guard maximum > 0 else { return (false, "Fan \(index) reports no maximum speed") }
            let clamped = min(max(rpm, minimum), maximum)

            if !enterManual(index, smc: smc) {
                return (false, "The SMC refused manual mode for fan \(index)")
            }
            guard smc.write(FanKeys.target(index), value: clamped) else {
                return (false, "Writing the target speed failed")
            }
            manualFans.insert(index)
            log.info("fan \(index) -> \(Int(clamped)) rpm")
            return (true, nil)
        }
    }

    func setAutomatic(index: Int) -> (Bool, String?) {
        queue.sync { restore(index < 0 ? Array(0..<max(fanCount, 0)) : [index]) }
    }

    func restoreAll() {
        queue.sync { _ = restore(Array(0..<max(fanCount, 0))) }
    }

    private func restore(_ fans: [Int]) -> (Bool, String?) {
        guard let smc else { return (false, "AppleSMC is unavailable") }
        var ok = true
        for index in fans {
            if smc.read(FanKeys.mode(index)) != nil {
                ok = smc.write(FanKeys.mode(index), value: 0) && ok
            }
            manualFans.remove(index)
        }
        if manualFans.isEmpty, smc.read(FanKeys.forceTest) != nil {
            smc.write(FanKeys.forceTest, value: 0)
        }
        log.info("fans \(fans) -> auto")
        return (ok, ok ? nil : "Some fans did not accept automatic mode")
    }

    /// Apple Silicon: F<i>Md = 1 selects manual. Some models only accept it after Ftst = 1,
    /// and need a moment before the mode sticks.
    private func enterManual(_ index: Int, smc: SMC) -> Bool {
        let key = FanKeys.mode(index)
        guard smc.read(key) != nil else { return true }
        if smc.double(key) == 1 { return true }
        if smc.read(FanKeys.forceTest) != nil {
            smc.write(FanKeys.forceTest, value: 1)
        }
        for _ in 0..<40 {
            smc.write(key, value: 1)
            Thread.sleep(forTimeInterval: 0.25)
            if smc.double(key) == 1 { return true }
        }
        log.error("fan \(index) stayed in automatic mode")
        return false
    }
}

final class HelperService: NSObject, FanHelperProtocol {
    let controller: FanController

    init(controller: FanController) {
        self.controller = controller
    }

    func version(reply: @escaping (String) -> Void) {
        reply(fanHelperVersion)
    }

    func setFanSpeed(index: Int, rpm: Double, reply: @escaping (Bool, String?) -> Void) {
        let result = controller.setSpeed(index: index, rpm: rpm)
        reply(result.0, result.1)
    }

    func setAutomatic(index: Int, reply: @escaping (Bool, String?) -> Void) {
        let result = controller.setAutomatic(index: index)
        reply(result.0, result.1)
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let controller = FanController()
    private var connections = 0
    private let lock = NSLock()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.setCodeSigningRequirement(CodeSigning.requirement(identifier: appBundleIdentifier))
        connection.exportedInterface = NSXPCInterface(with: FanHelperProtocol.self)
        connection.exportedObject = HelperService(controller: controller)
        let onEnd: () -> Void = { [weak self] in self?.connectionEnded() }
        connection.invalidationHandler = onEnd
        lock.lock(); connections += 1; lock.unlock()
        connection.resume()
        return true
    }

    /// Watchdog: no client left means nobody is watching temperatures, so the SMC takes over again.
    private func connectionEnded() {
        lock.lock()
        connections -= 1
        let remaining = connections
        lock.unlock()
        if remaining <= 0 {
            controller.restoreAll()
            exit(0)
        }
    }

    func restoreOnStart() {
        controller.restoreAll()
    }
}

let delegate = ListenerDelegate()
delegate.restoreOnStart()
let listener = NSXPCListener(machServiceName: fanHelperMachService)
listener.delegate = delegate
listener.resume()
signal(SIGTERM, SIG_IGN)
let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termSource.setEventHandler {
    delegate.restoreOnStart()
    exit(0)
}
termSource.resume()
RunLoop.main.run()
