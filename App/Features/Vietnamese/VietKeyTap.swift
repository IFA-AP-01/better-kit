import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Keyboard frontend for the uvie engine, ported from uvie-host's dispatcher:
/// every keystroke goes to the engine on the tap thread, and the engine's diff
/// is replayed as backspaces plus a Unicode string posted right behind the tap.
final class VietKeyTap {
    struct Config {
        var method: InputMethod = .telex
        var modern = true
        var englishOverride = true
        var quickTelex = false
        var hotkey = ModifierHotkey()
        var exclusions: Set<String> = []
    }

    private enum Action {
        case backspace(Int)
        case text(String)
    }

    /// Called on the main thread when the hotkey flips the language.
    var onToggle: ((Bool) -> Void)?

    private let lock = NSLock()
    private var config = Config()
    private var vietnamese = true
    private var configDirty = true
    private let engine = UvieEngine()
    private var hotkeyArmed = false
    private let source = CGEventSource(stateID: .privateState)
    private lazy var tap = EventTap(name: "vietnamese",
                                    events: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]) {
        [weak self] proxy, type, event in
        guard let self else { return event }
        return self.handle(proxy: proxy, type: type, event: event)
    }

    var isRunning: Bool { tap.isRunning }

    var isVietnamese: Bool {
        lock.lock(); defer { lock.unlock() }
        return vietnamese
    }

    func setVietnamese(_ on: Bool) {
        lock.lock()
        let changed = vietnamese != on
        vietnamese = on
        if changed { configDirty = true }
        lock.unlock()
    }

    func update(_ config: Config) {
        lock.lock()
        self.config = config
        configDirty = true
        lock.unlock()
    }

    /// Drops the word being composed (app switch, click elsewhere).
    func resetWord() {
        lock.lock(); configDirty = true; lock.unlock()
    }

    @discardableResult
    func start() -> Bool { tap.start() }

    func stop() { tap.stop() }

    // MARK: - Tap thread

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> CGEvent? {
        lock.lock()
        let config = self.config
        let on = vietnamese
        if configDirty {
            configDirty = false
            lock.unlock()
            engine.configure(method: config.method, modern: config.modern,
                             englishOverride: config.englishOverride, quickTelex: config.quickTelex)
        } else {
            lock.unlock()
        }

        switch type {
        case .flagsChanged:
            handleFlags(event.flags, hotkey: config.hotkey)
            return event
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            engine.reset()
            return event
        case .keyDown:
            hotkeyArmed = false
        default:
            return event
        }

        if event.isFromBetterKit { return event }
        guard on else { return event }
        if let app = FrontmostApp.shared.bundleID, config.exclusions.contains(app) {
            engine.reset()
            return event
        }

        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate)
            || flags.contains(.maskSecondaryFn) && !isFnNavigation(event) {
            engine.reset()
            return event
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        switch keyCode {
        case kVK_Delete:
            return handleBackspace(proxy: proxy, event: event)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            return commitAndPass(proxy: proxy, event: event)
        case kVK_Escape:
            return handleEscape(proxy: proxy, event: event)
        case kVK_Tab, kVK_UpArrow, kVK_DownArrow, kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_ForwardDelete:
            engine.reset()
            return event
        case kVK_LeftArrow, kVK_RightArrow:
            if flags.contains(.maskShift) {
                engine.reset()
                return event
            }
            let result = commitAndPass(proxy: proxy, event: event)
            engine.reset()
            return result
        default:
            break
        }

        guard let ch = typedCharacter(event) else {
            engine.reset()
            return event
        }
        guard ch.isASCII, let ascii = ch.asciiValue, ascii >= 0x20, ascii < 0x7F else {
            return commitAndPass(proxy: proxy, event: event, resetAfter: true)
        }
        if Self.wordBreaks.contains(ch) {
            return commitAndPass(proxy: proxy, event: event)
        }

        let (bs, out) = engine.feed(CChar(bitPattern: ascii))
        if bs == 0 && out.isEmpty && !engine.isComposing {
            return event
        }
        apply(plan(bs, out), proxy: proxy)
        return nil
    }

    private func isFnNavigation(_ event: CGEvent) -> Bool {
        let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
        return [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Home, kVK_End,
                kVK_PageUp, kVK_PageDown, kVK_ForwardDelete].contains(code)
    }

    private func handleFlags(_ flags: CGEventFlags, hotkey: ModifierHotkey) {
        let relevant: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
        let current = flags.intersection(relevant)
        if current.isEmpty {
            if hotkeyArmed {
                hotkeyArmed = false
                toggle()
            }
        } else if current == hotkey.flags {
            hotkeyArmed = true
        } else if !hotkey.flags.isSuperset(of: current) {
            hotkeyArmed = false
        }
    }

    private func toggle() {
        engine.reset()
        lock.lock()
        vietnamese.toggle()
        let now = vietnamese
        lock.unlock()
        DispatchQueue.main.async { [weak self] in self?.onToggle?(now) }
    }

    private func typedCharacter(_ event: CGEvent) -> Character? {
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        guard length > 0 else { return nil }
        let s = String(utf16CodeUnits: chars, count: length)
        return s.count == 1 ? s.first : nil
    }

    private func handleBackspace(proxy: CGEventTapProxy, event: CGEvent) -> CGEvent? {
        guard engine.isComposing else { return event }
        var (bs, out) = engine.backspace()
        var drain = 0
        while bs == 0 && out.isEmpty && engine.isComposing && drain < 24 {
            (bs, out) = engine.backspace()
            drain += 1
        }
        if bs == 0 && out.isEmpty && !engine.isComposing {
            return event
        }
        apply(plan(bs, out), proxy: proxy)
        return nil
    }

    private func handleEscape(proxy: CGEventTapProxy, event: CGEvent) -> CGEvent? {
        if engine.isComposing {
            let out = engine.currentOutput
            let raw = engine.rawChars
            if !raw.isEmpty && raw != out {
                apply(plan(out.count, raw), proxy: proxy)
                engine.reset()
                return nil
            }
        }
        engine.reset()
        return event
    }

    private func commitAndPass(proxy: CGEventTapProxy, event: CGEvent, resetAfter: Bool = false) -> CGEvent? {
        if engine.isComposing {
            let (bs, out) = engine.commit()
            apply(plan(bs, out), proxy: proxy)
        }
        if resetAfter { engine.reset() }
        return event
    }

    private func plan(_ bs: Int, _ out: String) -> [Action] {
        var actions: [Action] = []
        if bs > 0 { actions.append(.backspace(bs)) }
        if !out.isEmpty { actions.append(.text(out)) }
        return actions
    }

    private func apply(_ actions: [Action], proxy: CGEventTapProxy) {
        let browser = FrontmostApp.shared.bundleID.map(Self.isBrowser) ?? false
        for action in actions {
            switch action {
            case .backspace(var count):
                if browser {
                    postText([Self.placeholder], proxy: proxy)
                    count += 1
                }
                for _ in 0..<count {
                    postKey(CGKeyCode(kVK_Delete), proxy: proxy)
                }
            case .text(let text):
                let units = Array(text.utf16)
                var index = 0
                while index < units.count {
                    let end = min(index + 16, units.count)
                    postText(Array(units[index..<end]), proxy: proxy)
                    index = end
                }
            }
        }
    }

    private func postKey(_ code: CGKeyCode, proxy: CGEventTapProxy) {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
            e.flags = []
            e.markAsBetterKit()
            e.tapPostEvent(proxy)
        }
    }

    private func postText(_ units: [UniChar], proxy: CGEventTapProxy) {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
            e.flags = []
            units.withUnsafeBufferPointer { buf in
                e.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
            }
            e.markAsBetterKit()
            e.tapPostEvent(proxy)
        }
    }

    /// Browsers select an inline autocomplete suggestion after the caret, so a plain backspace
    /// removes the suggestion instead of the composed letter. Typing a placeholder first replaces
    /// the selection, and one extra backspace removes the placeholder.
    private static let placeholder: UniChar = 0x202F
    private static let browserPrefixes = [
        "com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.",
        "com.operasoftware.", "com.vivaldi.Vivaldi", "org.chromium.Chromium", "com.coccoc.",
        "com.apple.Safari", "org.mozilla.firefox", "app.zen-browser.",
    ]

    private static func isBrowser(_ bundleID: String) -> Bool {
        browserPrefixes.contains { bundleID.hasPrefix($0) }
    }

    private static let wordBreaks: Set<Character> = [
        " ", ".", ",", ";", ":", "?", "!", "'", "\"", "(", ")", "[", "]", "{", "}", "<", ">",
        "/", "\\", "|", "-", "_", "=", "+", "*", "&", "^", "%", "$", "#", "@", "~", "`",
    ]
}
