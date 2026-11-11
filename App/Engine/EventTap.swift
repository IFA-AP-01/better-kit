import CoreGraphics
import Foundation

/// Marks events BetterKit posts itself so its own taps let them through.
let betterKitEventMarker: Int64 = 0x4245_544B  // "BETK"

extension CGEvent {
    var isFromBetterKit: Bool {
        getIntegerValueField(.eventSourceUserData) == betterKitEventMarker
    }

    func markAsBetterKit() {
        setIntegerValueField(.eventSourceUserData, value: betterKitEventMarker)
    }
}

/// An active CGEventTap running on its own thread, so a busy main thread never delays input
/// (macOS disables taps that answer too slowly).
final class EventTap {
    typealias Handler = (CGEventTapProxy, CGEventType, CGEvent) -> CGEvent?

    private let name: String
    private let mask: CGEventMask
    private let handler: Handler
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var thread: Thread?
    private(set) var runLoop: CFRunLoop?

    init(name: String, events: [CGEventType], handler: @escaping Handler) {
        self.name = name
        mask = events.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        self.handler = handler
    }

    var isRunning: Bool { tap != nil }

    /// Returns false when macOS refuses the tap (Accessibility not granted yet).
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: eventTapCallback, userInfo: refcon) else {
            return false
        }
        tap = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        self.source = source
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self else { return }
            self.runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "BetterKit.\(name)"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.thread = thread
        ready.wait()
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        if let runLoop {
            if let source { CFRunLoopRemoveSource(runLoop, source, .commonModes) }
            CFRunLoopStop(runLoop)
        }
        self.tap = nil
        source = nil
        runLoop = nil
        thread = nil
    }

    /// Schedules work on the tap's own thread (for timers that post events).
    func perform(_ block: @escaping () -> Void) {
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }

    fileprivate func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard let result = handler(proxy, type, event) else { return nil }
        return Unmanaged.passUnretained(result)
    }
}

private func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
    return tap.handle(proxy: proxy, type: type, event: event)
}
