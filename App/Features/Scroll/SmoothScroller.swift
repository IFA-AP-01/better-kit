import CoreGraphics
import CoreVideo
import Foundation

/// Turns mouse-wheel notches into smooth pixel scrolling, following Mos: each notch adds distance
/// to a buffer that every display frame consumes exponentially, and a low-pass on the resulting
/// velocity softens the onset, so scrolling builds momentum and coasts out instead of stopping.
/// Trackpads and Magic Mouse already send continuous events and pass through untouched.
final class SmoothScroller {
    struct Config {
        var smooth = true
        var reverse = false
        var step: Double = 60
        var speed: Double = 1.6
        var duration: Double = 0.32
        var exceptions: Set<String> = []
    }

    private struct Axis {
        var remaining = 0.0
        var velocity = 0.0
        var fraction = 0.0

        mutating func add(_ distance: Double) {
            if remaining != 0, (remaining > 0) != (distance > 0) {
                self = Axis()
            }
            remaining += distance
        }

        mutating func advance(dt: Double, follow: Double, smoothing: Double) -> Int32 {
            let step = remaining * follow
            remaining -= step
            velocity += (step / dt - velocity) * smoothing
            let move = velocity * dt + fraction
            let whole = move.rounded(.towardZero)
            fraction = move - whole
            return Int32(whole)
        }

        var settled: Bool { abs(remaining) < 0.5 && abs(velocity) < 20 }
    }

    private struct Glide {
        var y = Axis()
        var x = Axis()
        var lastFrame: Double?
        var tau = 0.19
        var active = false
    }

    private static let velocityTau = 0.064

    private let lock = NSLock()
    private var config = Config()
    private var glide = Glide()
    private var displayLink: CVDisplayLink?
    private var linkRunning = false
    private lazy var tap = EventTap(name: "scroll", events: [.scrollWheel]) { [weak self] _, _, event in
        guard let self else { return event }
        return self.handle(event)
    }
    private let source = CGEventSource(stateID: .hidSystemState)
    private static let secondsPerHostTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()

    var isRunning: Bool { tap.isRunning }

    func update(_ config: Config) {
        lock.lock(); self.config = config; lock.unlock()
    }

    @discardableResult
    func start() -> Bool {
        tap.start()
    }

    func stop() {
        tap.stop()
        lock.lock()
        glide = Glide()
        let link = linkRunning ? displayLink : nil
        linkRunning = false
        lock.unlock()
        if let link { CVDisplayLinkStop(link) }
    }

    private func handle(_ event: CGEvent) -> CGEvent? {
        if event.isFromBetterKit { return event }
        if event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 { return event }

        lock.lock()
        let config = self.config
        lock.unlock()

        if let app = FrontmostApp.shared.bundleID, config.exceptions.contains(app) { return event }

        var dy = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        var dx = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        if dy == 0 { dy = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)) }
        if dx == 0 { dx = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)) }
        if config.reverse {
            dy = -dy
            dx = -dx
        }

        guard config.smooth else {
            if config.reverse {
                event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: dy)
                event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: dx)
                event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(dy.rounded()))
                event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64(dx.rounded()))
                let py = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
                let px = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
                event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -py)
                event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -px)
            }
            return event
        }

        let gain = config.step * config.speed
        lock.lock()
        if !glide.active { glide = Glide() }
        if dy != 0 { glide.y.add(dy * gain) }
        if dx != 0 { glide.x.add(dx * gain) }
        glide.tau = max(config.duration, 0.05) * 0.6
        glide.active = true
        lock.unlock()
        startDisplayLink(at: event.location)
        return nil
    }

    private func startDisplayLink(at point: CGPoint) {
        lock.lock()
        defer { lock.unlock() }
        if displayLink == nil {
            var link: CVDisplayLink?
            CVDisplayLinkCreateWithActiveCGDisplays(&link)
            guard let link else { return }
            CVDisplayLinkSetOutputHandler(link) { [weak self] _, _, output, _, _ in
                let o = output.pointee
                let period = o.videoTimeScale > 0 ? Double(o.videoRefreshPeriod) / Double(o.videoTimeScale) : 1.0 / 60
                self?.frame(hostTime: o.hostTime, period: period)
                return kCVReturnSuccess
            }
            displayLink = link
        }
        guard let link = displayLink, !linkRunning else { return }
        var display = CGMainDisplayID()
        var count: UInt32 = 0
        CGGetDisplaysWithPoint(point, 1, &display, &count)
        CVDisplayLinkSetCurrentCGDisplay(link, count > 0 ? display : CGMainDisplayID())
        linkRunning = true
        CVDisplayLinkStart(link)
    }

    private func frame(hostTime: UInt64, period: Double) {
        let time = Double(hostTime) * Self.secondsPerHostTick
        lock.lock()
        guard glide.active else { lock.unlock(); return }
        let dt = glide.lastFrame.map { min(max(time - $0, 0.001), 0.05) } ?? period
        glide.lastFrame = time
        let follow = 1 - exp(-dt / glide.tau)
        let smoothing = 1 - exp(-dt / Self.velocityTau)
        let outY = glide.y.advance(dt: dt, follow: follow, smoothing: smoothing)
        let outX = glide.x.advance(dt: dt, follow: follow, smoothing: smoothing)
        let done = glide.y.settled && glide.x.settled
        var stopLink: CVDisplayLink?
        if done {
            glide = Glide()
            stopLink = displayLink
            linkRunning = false
        }
        lock.unlock()

        if outY != 0 || outX != 0 {
            post(dy: outY, dx: outX)
        }
        if let stopLink {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let idle = !self.linkRunning
                self.lock.unlock()
                if idle { CVDisplayLinkStop(stopLink) }
            }
        }
    }

    private func post(dy: Int32, dx: Int32) {
        guard let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                                  wheel1: dy, wheel2: dx, wheel3: 0) else { return }
        event.markAsBetterKit()
        if let location = CGEvent(source: nil)?.location {
            event.location = location
        }
        event.post(tap: .cgSessionEventTap)
    }
}
