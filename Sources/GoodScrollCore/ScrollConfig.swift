import CoreGraphics

/// Modifier key that, while held, skips discrete-line conversion (direction settings still apply).
public enum BypassModifier: String, CaseIterable, Sendable {
    case none, option, control, command

    public var flag: CGEventFlags? {
        switch self {
        case .none: return nil
        case .option: return .maskAlternate
        case .control: return .maskControl
        case .command: return .maskCommand
        }
    }

    public var label: String {
        switch self {
        case .none: return "None"
        case .option: return "⌥ Option"
        case .control: return "⌃ Control"
        case .command: return "⌘ Command"
        }
    }
}

/// Scroll direction for one class of device, independent of the system-wide "Natural scrolling" checkbox.
public enum ScrollDirection: String, CaseIterable, Sendable {
    case followSystem, natural, traditional

    public var label: String {
        switch self {
        case .followSystem: return "Follow System"
        case .natural: return "Natural"
        case .traditional: return "Traditional"
        }
    }

    /// Whether events (which arrive already shaped by the system setting) must be negated.
    public func needsFlip(systemNatural: Bool) -> Bool {
        switch self {
        case .followSystem: return false
        case .natural: return !systemNatural
        case .traditional: return systemNatural
        }
    }
}

/// Immutable snapshot of everything the event tap needs. Read on the tap thread, so keep it a plain value.
public struct ScrollConfig: Equatable, Sendable {
    /// Master switch: when off, every event passes through untouched.
    public var enabled: Bool
    /// Convert mouse-wheel notches to a fixed number of lines (no acceleration).
    public var discrete: Bool
    public var linesPerNotch: Int
    public var applyHorizontal: Bool
    public var mouseDirection: ScrollDirection
    public var trackpadDirection: ScrollDirection
    public var bypassModifier: BypassModifier
    /// Current value of the system "Natural scrolling" setting.
    public var systemNatural: Bool

    public static let lineRange = 1...20

    public init(enabled: Bool = true,
                discrete: Bool = true,
                linesPerNotch: Int = 3,
                applyHorizontal: Bool = false,
                mouseDirection: ScrollDirection = .followSystem,
                trackpadDirection: ScrollDirection = .followSystem,
                bypassModifier: BypassModifier = .none,
                systemNatural: Bool = true) {
        self.enabled = enabled
        self.discrete = discrete
        self.linesPerNotch = min(max(linesPerNotch, Self.lineRange.lowerBound), Self.lineRange.upperBound)
        self.applyHorizontal = applyHorizontal
        self.mouseDirection = mouseDirection
        self.trackpadDirection = trackpadDirection
        self.bypassModifier = bypassModifier
        self.systemNatural = systemNatural
    }
}
