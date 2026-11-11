import Foundation

let fanHelperMachService = "dev.ifateam.betterkit.helper"
let fanHelperPlistName = "dev.ifateam.betterkit.helper.plist"
let appBundleIdentifier = "dev.ifateam.betterkit"

/// XPC interface of the privileged fan helper. Every call validates its arguments on the helper side.
@objc protocol FanHelperProtocol {
    func version(reply: @escaping (String) -> Void)
    /// Sets fan `index` to a fixed RPM, clamped to the fan's own min/max.
    func setFanSpeed(index: Int, rpm: Double, reply: @escaping (Bool, String?) -> Void)
    /// Returns fan `index` (or every fan when index < 0) to automatic control.
    func setAutomatic(index: Int, reply: @escaping (Bool, String?) -> Void)
}

let fanHelperVersion = "1"
