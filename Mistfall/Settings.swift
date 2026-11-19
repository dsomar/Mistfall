import AppKit

// Mistfall settings shared by the preview app and the screen saver: particle
// glow on or off, and either a random pattern that changes every so many
// minutes or one pattern only. Also the small panel that edits them.

extension Pattern {
    /// A stable name for saving (it does not change if patterns are reordered).
    var key: String { String(describing: self) }
}

struct MistfallSettings: Equatable {
    var glow = true
    /// The one pattern to show; nil picks patterns at random.
    var only: Pattern?
    /// How long a random pattern stays before the next one.
    var changeMinutes: Double = 1
    /// Shows how many frames a second are being drawn, in the top-left corner.
    var showFPS = false
    /// Settings for the flow patterns (Currents and Kaleidoscope).
    var flow = ParticleFlow()

    static let minMinutes = 0.25, maxMinutes = 240.0
    /// The times the T key and the menu step through.
    static let presets: [Double] = [0.5, 1, 2, 5, 10, 15, 30]

    static func clampMinutes(_ m: Double) -> Double { min(max(m, minMinutes), maxMinutes) }

    static func label(minutes m: Double) -> String {
        if m < 1 { return "\(Int((m * 60).rounded())) seconds" }
        let whole = m.rounded() == m
        let n = whole ? String(Int(m)) : String(format: "%.2g", m)
        return n + (m == 1 ? " minute" : " minutes")
    }

    static func load(_ d: UserDefaults) -> MistfallSettings {
        var s = MistfallSettings()
        if d.object(forKey: "glow") != nil { s.glow = d.bool(forKey: "glow") }
        if d.object(forKey: "showFPS") != nil { s.showFPS = d.bool(forKey: "showFPS") }
        if let n = d.string(forKey: "onlyPattern"), !n.isEmpty { s.only = Pattern.named(n) }
        let m = d.double(forKey: "changeMinutes")
        if m > 0 { s.changeMinutes = clampMinutes(m) }
        if d.object(forKey: "flowDensity") != nil { s.flow.density = d.double(forKey: "flowDensity") }
        if d.object(forKey: "flowSize") != nil { s.flow.size = d.double(forKey: "flowSize") }
        if d.object(forKey: "flowStrength") != nil { s.flow.strength = d.double(forKey: "flowStrength") }
        if d.object(forKey: "flowScale") != nil { s.flow.scale = d.double(forKey: "flowScale") }
        if let h = d.string(forKey: "flowBackground") { s.flow.background = h }
        if let p = d.string(forKey: "flowPalette"), let pal = ParticleFlow.Palette(rawValue: p) { s.flow.palette = pal }
        s.flow.seed = d.integer(forKey: "flowSeed")
        s.flow = s.flow.clamped()
        return s
    }

    func save(to d: UserDefaults) {
        d.set(glow, forKey: "glow")
        d.set(showFPS, forKey: "showFPS")
        d.set(only?.key ?? "", forKey: "onlyPattern")
        d.set(changeMinutes, forKey: "changeMinutes")
        d.set(flow.density, forKey: "flowDensity")
        d.set(flow.size, forKey: "flowSize")
        d.set(flow.strength, forKey: "flowStrength")
        d.set(flow.scale, forKey: "flowScale")
        d.set(flow.background, forKey: "flowBackground")
        d.set(flow.palette.rawValue, forKey: "flowPalette")
        d.set(flow.seed, forKey: "flowSeed")
        d.synchronize()
    }

    func apply(to engine: Engine) {
        engine.glowEnabled = glow
        engine.changeEvery = changeMinutes * 60
        engine.fixedPattern = only
        engine.particleFlow = flow.clamped()
    }

    /// The next preset time after this one, going round.
    var nextPreset: Double {
        MistfallSettings.presets.first { $0 > changeMinutes + 0.001 } ?? MistfallSettings.presets[0]
    }
}

/// Counts the frames really drawn and shows the rate, refreshed twice a second.
struct FrameMeter {
    private var count = 0
    private var since: CFTimeInterval = 0
    private(set) var fps: Double = 0

    /// Call once for every frame drawn.
    mutating func frame(at now: CFTimeInterval) {
        if since == 0 { since = now; return }
        count += 1
        let span = now - since
        if span >= 0.5 { fps = Double(count) / span; count = 0; since = now }
    }

    func draw(in bounds: NSRect) {
        guard fps > 0 else { return }
        let size: CGFloat = bounds.height < 400 ? 10 : 13
        let s = NSAttributedString(string: "\(Int(fps.rounded())) fps", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium),
            .foregroundColor: NSColor(white: 1, alpha: 0.75),
        ])
        let inset: CGFloat = bounds.height < 400 ? 6 : 14
        s.draw(at: NSPoint(x: inset, y: bounds.height - s.size().height - inset))
    }
}

/// The settings window: shown as a sheet by System Settings (screen saver
/// Options) and by the preview app.
final class SettingsPanel: NSObject, NSTextFieldDelegate {
    let window: NSWindow
    private var settings: MistfallSettings
    private let done: (MistfallSettings?) -> Void

    private let glowBox = NSButton(checkboxWithTitle: "Particle glow", target: nil, action: nil)
    private let fpsBox = NSButton(checkboxWithTitle: "Show frame rate on screen", target: nil, action: nil)
    private let randomRadio = NSButton(radioButtonWithTitle: "Choose a pattern at random", target: nil, action: nil)
    private let onlyRadio = NSButton(radioButtonWithTitle: "Show only:", target: nil, action: nil)
    private let everyLabel = NSTextField(labelWithString: "Change every")
    private let minutesField = NSTextField(string: "")
    private let minutesLabel = NSTextField(labelWithString: "minutes")
    private let stepper = NSStepper()
    private let popup = NSPopUpButton(frame: .zero, pullsDown: false)

    // Particle Flow section.
    private let densitySlider = NSSlider(), sizeSlider = NSSlider(), strengthSlider = NSSlider(), scaleSlider = NSSlider()
    private let densityValue = NSTextField(labelWithString: ""), sizeValue = NSTextField(labelWithString: "")
    private let strengthValue = NSTextField(labelWithString: ""), scaleValue = NSTextField(labelWithString: "")
    private let backgroundField = NSTextField(string: "")
    private let swatch = NSBox()
    private let palettePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let seedField = NSTextField(string: "")

    init(settings: MistfallSettings, done: @escaping (MistfallSettings?) -> Void) {
        self.settings = settings
        self.done = done
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 240),
                          styleMask: [.titled], backing: .buffered, defer: false)
        super.init()
        window.title = "Mistfall Settings"
        window.isReleasedWhenClosed = false

        for p in Pattern.allCases {
            popup.addItem(withTitle: p.title)
            popup.lastItem?.tag = p.rawValue
        }
        minutesField.alignment = .right
        minutesField.delegate = self
        minutesField.widthAnchor.constraint(equalToConstant: 56).isActive = true
        stepper.minValue = 1; stepper.maxValue = MistfallSettings.maxMinutes; stepper.increment = 1
        stepper.valueWraps = false
        stepper.target = self; stepper.action = #selector(stepped)
        for b in [randomRadio, onlyRadio] { b.target = self; b.action = #selector(modePicked(_:)) }
        popup.target = self; popup.action = #selector(patternPicked)

        let title = NSTextField(labelWithString: "Mistfall")
        title.font = .boldSystemFont(ofSize: 15)
        let ok = NSButton(title: "OK", target: self, action: #selector(okPressed))
        ok.keyEquivalent = "\r"
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelPressed))
        cancel.keyEquivalent = "\u{1b}"
        for b in [ok, cancel] { b.widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true }

        // Particle Flow controls.
        func setUp(_ s: NSSlider, _ r: ClosedRange<Double>) {
            s.minValue = r.lowerBound; s.maxValue = r.upperBound
            s.isContinuous = true
            s.target = self; s.action = #selector(flowChanged)
            s.widthAnchor.constraint(equalToConstant: 170).isActive = true
        }
        setUp(densitySlider, ParticleFlow.densityRange); setUp(sizeSlider, ParticleFlow.sizeRange)
        setUp(strengthSlider, ParticleFlow.strengthRange); setUp(scaleSlider, ParticleFlow.scaleRange)
        for (i, p) in ParticleFlow.Palette.allCases.enumerated() {
            palettePopup.addItem(withTitle: p.title)
            palettePopup.lastItem?.tag = i
        }
        palettePopup.target = self; palettePopup.action = #selector(flowChanged)
        backgroundField.delegate = self; seedField.delegate = self
        backgroundField.widthAnchor.constraint(equalToConstant: 76).isActive = true
        seedField.widthAnchor.constraint(equalToConstant: 76).isActive = true
        seedField.alignment = .right
        swatch.boxType = .custom; swatch.borderWidth = 1; swatch.cornerRadius = 3
        swatch.borderColor = .separatorColor
        swatch.widthAnchor.constraint(equalToConstant: 28).isActive = true
        swatch.heightAnchor.constraint(equalToConstant: 16).isActive = true
        func name(_ text: String) -> NSTextField {
            let l = NSTextField(labelWithString: text)
            l.widthAnchor.constraint(equalToConstant: 118).isActive = true
            return l
        }
        func note(_ text: String) -> NSTextField {
            let l = NSTextField(labelWithString: text)
            l.textColor = .secondaryLabelColor; l.font = .systemFont(ofSize: 11)
            return l
        }
        let flowTitle = NSTextField(labelWithString: "Particle Flow")
        flowTitle.font = .boldSystemFont(ofSize: 13)
        let flowNote = note("For the Currents and Kaleidoscope patterns.")
        let defaults = NSButton(title: "Reset Particle Flow", target: self, action: #selector(resetFlow))
        defaults.controlSize = .small; defaults.font = .systemFont(ofSize: 11)
        let line2 = NSBox(); line2.boxType = .separator

        func row(_ views: [NSView], indent: CGFloat = 0) -> NSStackView {
            let r = NSStackView(views: views)
            r.orientation = .horizontal; r.spacing = 6; r.alignment = .firstBaseline
            r.edgeInsets = NSEdgeInsets(top: 0, left: indent, bottom: 0, right: 0)
            return r
        }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = row([spacer, cancel, ok])
        let line = NSBox(); line.boxType = .separator
        let stack = NSStackView(views: [
            title, glowBox, fpsBox, line, randomRadio,
            row([everyLabel, minutesField, stepper, minutesLabel], indent: 20),
            row([onlyRadio, popup]), line2, flowTitle, flowNote,
            row([name("Particle density"), densitySlider, densityValue]),
            row([name("Particle size"), sizeSlider, sizeValue]),
            row([name("Flow strength"), strengthSlider, strengthValue]),
            row([name("Flow scale"), scaleSlider, scaleValue]),
            { let r = row([name("Background color"), backgroundField, swatch, note("hex, 000000 = black")]); r.alignment = .centerY; return r }(),
            row([name("Color palette"), palettePopup]),
            row([name("Random seed"), seedField, note("0 = different every time")]),
            defaults, buttons,
        ])
        stack.setCustomSpacing(4, after: flowTitle)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.setCustomSpacing(16, after: stack.views[stack.views.count - 2])
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.widthAnchor.constraint(greaterThanOrEqualToConstant: 380),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            line.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            line2.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
        ])
        window.contentView = content
        window.setContentSize(content.fittingSize)
        show()
    }

    private func minutesText(_ m: Double) -> String {
        m.rounded() == m ? String(Int(m)) : String(format: "%.2f", m)
    }

    /// Puts the settings into the controls.
    private func show() {
        glowBox.state = settings.glow ? .on : .off
        fpsBox.state = settings.showFPS ? .on : .off
        let random = settings.only == nil
        randomRadio.state = random ? .on : .off
        onlyRadio.state = random ? .off : .on
        minutesField.stringValue = minutesText(settings.changeMinutes)
        stepper.doubleValue = max(settings.changeMinutes, 1)
        if let p = settings.only { popup.selectItem(withTag: p.rawValue) }
        for v in [everyLabel, minutesLabel] { v.textColor = random ? .labelColor : .disabledControlTextColor }
        minutesField.isEnabled = random; stepper.isEnabled = random
        popup.isEnabled = !random
        let f = settings.flow
        densitySlider.doubleValue = f.density; sizeSlider.doubleValue = f.size
        strengthSlider.doubleValue = f.strength; scaleSlider.doubleValue = f.scale
        backgroundField.stringValue = f.background.uppercased()
        seedField.stringValue = String(f.seed)
        palettePopup.selectItem(withTag: ParticleFlow.Palette.allCases.firstIndex(of: f.palette) ?? 0)
        showFlowValues()
    }

    /// The numbers beside the sliders, and the colour sample.
    private func showFlowValues() {
        let f = settings.flow
        densityValue.stringValue = "\(Int((f.density * 100).rounded()))%"
        sizeValue.stringValue = f.size <= 1.05 ? "Fine" : String(format: "%.1f", f.size)
        strengthValue.stringValue = String(format: "%.2f×", f.strength)
        scaleValue.stringValue = String(format: "%.2f×", f.scale)
        let c = f.backgroundRGB
        swatch.fillColor = NSColor(srgbRed: CGFloat(c.0), green: CGFloat(c.1), blue: CGFloat(c.2), alpha: 1)
    }

    @objc private func flowChanged() { read(); showFlowValues() }

    @objc private func resetFlow() {
        window.makeFirstResponder(nil)
        read()
        settings.flow = ParticleFlow()
        show()
    }

    /// Reads the controls back into the settings.
    private func read() {
        settings.glow = glowBox.state == .on
        settings.showFPS = fpsBox.state == .on
        let typed = Double(minutesField.stringValue.replacingOccurrences(of: ",", with: "."))
        if let m = typed, m > 0 { settings.changeMinutes = MistfallSettings.clampMinutes(m) }
        if onlyRadio.state == .on {
            settings.only = Pattern(rawValue: popup.selectedTag()) ?? .orb
        } else {
            settings.only = nil
        }
        var f = settings.flow
        f.density = densitySlider.doubleValue; f.size = sizeSlider.doubleValue
        f.strength = strengthSlider.doubleValue; f.scale = scaleSlider.doubleValue
        if let h = ParticleFlow.cleanHex(backgroundField.stringValue) { f.background = h }
        if let n = Int(seedField.stringValue.trimmingCharacters(in: .whitespaces)) { f.seed = n }
        let all = ParticleFlow.Palette.allCases
        f.palette = all[min(max(palettePopup.selectedTag(), 0), all.count - 1)]
        settings.flow = f.clamped()
    }

    @objc private func modePicked(_ sender: NSButton) {
        randomRadio.state = sender === randomRadio ? .on : .off
        onlyRadio.state = sender === onlyRadio ? .on : .off
        read(); show()
    }

    @objc private func patternPicked() { read() }

    @objc private func stepped() {
        minutesField.stringValue = minutesText(stepper.doubleValue)
        read()
    }

    func controlTextDidEndEditing(_ obj: Notification) { read(); show() }

    @objc private func okPressed() {
        window.makeFirstResponder(nil)
        read()
        close()
        done(settings)
    }

    @objc private func cancelPressed() {
        close()
        done(nil)
    }

    private func close() {
        if let parent = window.sheetParent { parent.endSheet(window) } else { window.orderOut(nil) }
    }
}
