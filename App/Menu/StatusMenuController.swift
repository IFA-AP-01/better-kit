import AppKit
import Combine

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var cancellables: Set<AnyCancellable> = []
    private let onOpenMain: (MainSection?) -> Void
    private let onOpenOnboarding: () -> Void
    private let updates: UpdateCoordinator

    init(model: AppModel, onOpenMain: @escaping (MainSection?) -> Void, onOpenOnboarding: @escaping () -> Void,
         updates: UpdateCoordinator) {
        self.model = model
        self.onOpenMain = onOpenMain
        self.onOpenOnboarding = onOpenOnboarding
        self.updates = updates
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        statusItem.button?.toolTip = "BetterKit"
        updateIcon()
        model.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)
    }

    /// The kit glyph; with Vietnamese typing on, the V/E letter stands next to it like EVKey's indicator.
    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "square.grid.2x2.fill", accessibilityDescription: "BetterKit")
        image?.isTemplate = true
        button.image = image
        if let letter = model.vietnamese.menuBarLetter {
            button.imagePosition = .imageLeading
            button.attributedTitle = NSAttributedString(string: " " + letter, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold),
                .baselineOffset: 0.5,
            ])
        } else {
            button.imagePosition = .imageOnly
            button.title = ""
        }
        if model.needsAttention {
            button.toolTip = "BetterKit needs a permission"
        } else {
            button.toolTip = "BetterKit"
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        model.permissions.refresh()
        model.fan.poll()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if model.needsAttention {
            menu.addItem(item("Finish Setup…", symbol: "exclamationmark.triangle") { [onOpenMain] in onOpenMain(.general) })
            menu.addItem(.separator())
        }
        addScrollSection(to: menu)
        menu.addItem(.separator())
        addDisplaySection(to: menu)
        menu.addItem(.separator())
        addVietnameseSection(to: menu)
        if model.fan.hasFans {
            menu.addItem(.separator())
            addFanSection(to: menu)
        }
        menu.addItem(.separator())
        menu.addItem(item("Open BetterKit…", key: ",") { [onOpenMain] in onOpenMain(nil) })
        menu.addItem(item("Setup Guide…") { [onOpenOnboarding] in onOpenOnboarding() })
        let check = item(updates.updateAvailable ? "Update to \(updates.latestVersion)…" : "Check for Updates…") { [updates] in
            updates.checkForUpdates()
        }
        check.isEnabled = updates.canCheckForUpdates
        menu.addItem(check)
        menu.addItem(.separator())
        menu.addItem(item("Quit BetterKit", key: "q") { NSApp.terminate(nil) })
    }

    private func addScrollSection(to menu: NSMenu) {
        let scroll = model.scroll
        menu.addItem(.sectionHeader(title: "Scroll"))
        menu.addItem(item("Smooth Scroll", symbol: "computermouse", state: scroll.settings.enabled) {
            scroll.settings.enabled.toggle()
        })
    }

    private func addDisplaySection(to menu: NSMenu) {
        let display = model.display
        menu.addItem(.sectionHeader(title: "Display"))
        let hidpi = item("HiDPI", symbol: "display", state: display.settings.hiDPIEnabled) {
            display.settings.hiDPIEnabled.toggle()
        }
        if display.settings.hiDPIEnabled {
            hidpi.attributedTitle = titleWithDetail("HiDPI", detail: display.hiDPIActive ? display.settings.looksLike.title : "waiting")
        }
        menu.addItem(hidpi)
        let looks = NSMenu()
        looks.autoenablesItems = false
        for choice in ResolutionChoice.choices {
            looks.addItem(item(choice.title, state: display.settings.looksLike == choice) {
                display.settings.looksLike = choice
            })
        }
        let looksItem = submenuItem("Looks Like", submenu: looks)
        looksItem.isEnabled = display.settings.hiDPIEnabled
        menu.addItem(looksItem)
        if display.ddcAvailable || display.settings.softwareDimming {
            menu.addItem(sliderItem(symbol: "sun.max", value: display.brightness) { display.setBrightness($0) })
        }
    }

    private func addVietnameseSection(to menu: NSMenu) {
        let vn = model.vietnamese
        menu.addItem(.sectionHeader(title: "Typing"))
        let toggle = item("Vietnamese Typing", symbol: "keyboard", state: vn.settings.enabled) {
            vn.settings.enabled.toggle()
        }
        menu.addItem(toggle)
        guard vn.settings.enabled else { return }
        let mode = item(vn.settings.vietnameseOn ? "Switch to English" : "Switch to Vietnamese") { vn.toggleLanguage() }
        mode.attributedTitle = titleWithDetail(vn.settings.vietnameseOn ? "Switch to English" : "Switch to Vietnamese",
                                               detail: vn.settings.hotkey.symbols)
        menu.addItem(mode)
        let methods = NSMenu()
        methods.autoenablesItems = false
        for method in InputMethod.allCases {
            methods.addItem(item(method.title, state: vn.settings.method == method) { vn.settings.method = method })
        }
        let methodItem = submenuItem("Input Method", submenu: methods)
        methodItem.attributedTitle = titleWithDetail("Input Method", detail: vn.settings.method.title)
        menu.addItem(methodItem)
    }

    private func addFanSection(to menu: NSMenu) {
        let fan = model.fan
        menu.addItem(.sectionHeader(title: "Fans"))
        for reading in fan.fans {
            let entry = disabledItem("")
            entry.attributedTitle = titleWithDetail(reading.name, detail: "\(Int(reading.actual)) rpm")
            entry.image = NSImage(systemSymbolName: "fan", accessibilityDescription: nil)
            menu.addItem(entry)
        }
        if let cpu = fan.cpuTemperature {
            let entry = disabledItem("")
            entry.attributedTitle = titleWithDetail("CPU", detail: String(format: "%.0f °C", cpu))
            entry.image = NSImage(systemSymbolName: "thermometer.medium", accessibilityDescription: nil)
            menu.addItem(entry)
        }
        let presets = NSMenu()
        presets.autoenablesItems = false
        for preset in FanPreset.allCases {
            let p = item(preset.title, state: fan.settings.preset == preset) { fan.settings.preset = preset }
            p.isEnabled = fan.helper.state == .enabled || preset == .automatic
            presets.addItem(p)
        }
        let presetItem = submenuItem("Fan Control", submenu: presets)
        presetItem.attributedTitle = titleWithDetail("Fan Control", detail: fan.settings.preset.title)
        menu.addItem(presetItem)
    }

    private func sliderItem(symbol: String, value: Double, onChange: @escaping (Double) -> Void) -> NSMenuItem {
        let item = NSMenuItem()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 28))
        let icon = NSImageView(frame: NSRect(x: 14, y: 6, width: 16, height: 16))
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor
        let slider = ActionSlider(frame: NSRect(x: 36, y: 4, width: 190, height: 20), handler: onChange)
        slider.minValue = 0.05
        slider.maxValue = 1
        slider.doubleValue = value
        slider.isContinuous = true
        container.addSubview(icon)
        container.addSubview(slider)
        item.view = container
        return item
    }

    private func item(_ title: String, symbol: String? = nil, key: String = "", state: Bool? = nil, action: @escaping () -> Void) -> NSMenuItem {
        let item = ActionMenuItem(title: title, keyEquivalent: key, handler: action)
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        if let state {
            item.state = state ? .on : .off
        }
        return item
    }

    private func submenuItem(_ title: String, symbol: String? = nil, submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        item.submenu = submenu
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func titleWithDetail(_ title: String, detail: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: title, attributes: [.font: NSFont.menuFont(ofSize: 0)])
        result.append(NSAttributedString(string: "  \(detail)", attributes: [
            .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        return result
    }
}

final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, keyEquivalent: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(runHandler), keyEquivalent: keyEquivalent)
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func runHandler() {
        handler()
    }
}

final class ActionSlider: NSSlider {
    private let handler: (Double) -> Void

    init(frame: NSRect, handler: @escaping (Double) -> Void) {
        self.handler = handler
        super.init(frame: frame)
        target = self
        action = #selector(changed)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func changed() {
        handler(doubleValue)
    }
}
