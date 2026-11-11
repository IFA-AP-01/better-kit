import Foundation
import ServiceManagement

/// Registers the privileged fan helper (SMAppService daemon) and talks to it over XPC.
@MainActor
final class FanHelperClient: ObservableObject {
    enum State: Equatable {
        case notRegistered
        case requiresApproval
        case enabled
        case unavailable(String)
    }

    @Published private(set) var state: State = .notRegistered
    @Published private(set) var connected = false

    private let service = SMAppService.daemon(plistName: fanHelperPlistName)
    private var connection: NSXPCConnection?

    init() {
        refresh()
    }

    func refresh() {
        let previous = state
        defer {
            if previous != .enabled, state == .enabled {
                GrantPanelController.shared.permissionGranted(.backgroundItems)
            }
        }
        switch service.status {
        case .enabled: state = .enabled
        case .requiresApproval: state = .requiresApproval
        case .notRegistered, .notFound: state = .notRegistered
        @unknown default: state = .notRegistered
        }
    }

    func register() {
        var failure: String?
        do {
            try service.register()
        } catch {
            Log.fan.error("helper register: \(error.localizedDescription)")
            failure = error.localizedDescription
        }
        refresh()
        if state == .requiresApproval {
            GrantPanelController.shared.show(.backgroundItems)
        } else if let failure, state != .enabled {
            state = .unavailable(failure)
        }
    }

    func unregister() {
        disconnect()
        try? service.unregister()
        refresh()
    }

    private func proxy(_ failure: @escaping (String) -> Void) -> FanHelperProtocol? {
        guard state == .enabled else {
            failure("Fan helper is not enabled")
            return nil
        }
        if connection == nil {
            let c = NSXPCConnection(machServiceName: fanHelperMachService, options: .privileged)
            c.remoteObjectInterface = NSXPCInterface(with: FanHelperProtocol.self)
            c.setCodeSigningRequirement(CodeSigning.requirement(identifier: fanHelperMachService))
            c.invalidationHandler = { [weak self] in
                DispatchQueue.main.async { self?.connection = nil; self?.connected = false }
            }
            c.interruptionHandler = { [weak self] in
                DispatchQueue.main.async { self?.connected = false }
            }
            c.resume()
            connection = c
            connected = true
        }
        return connection?.remoteObjectProxyWithErrorHandler { error in
            DispatchQueue.main.async { failure(error.localizedDescription) }
        } as? FanHelperProtocol
    }

    func setSpeed(index: Int, rpm: Double, completion: @escaping (String?) -> Void) {
        proxy(completion)?.setFanSpeed(index: index, rpm: rpm) { ok, message in
            DispatchQueue.main.async { completion(ok ? nil : message ?? "Failed") }
        }
    }

    func setAutomatic(completion: @escaping (String?) -> Void) {
        proxy(completion)?.setAutomatic(index: -1) { ok, message in
            DispatchQueue.main.async { completion(ok ? nil : message ?? "Failed") }
        }
    }

    /// Synchronous "back to automatic" used while quitting.
    func restoreAutomaticBlocking() {
        guard let connection else { return }
        let semaphore = DispatchSemaphore(value: 0)
        let proxy = connection.synchronousRemoteObjectProxyWithErrorHandler { _ in semaphore.signal() } as? FanHelperProtocol
        proxy?.setAutomatic(index: -1) { _, _ in semaphore.signal() }
        _ = semaphore.wait(timeout: .now() + 2)
    }

    func disconnect() {
        connection?.invalidate()
        connection = nil
        connected = false
    }
}
