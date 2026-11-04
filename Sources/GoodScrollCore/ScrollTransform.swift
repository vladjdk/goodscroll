import CoreGraphics

/// The raw scroll-wheel fields we care about, pulled out of a CGEvent so the logic is testable.
public struct WheelInput: Equatable, Sendable {
    /// true for trackpads / Magic Mouse (pixel-precise), false for classic notched wheels.
    public var isContinuous: Bool
    public var delta1: Int64      // vertical, in lines (integer)
    public var fixed1: Double     // vertical, fixed-point lines
    public var delta2: Int64      // horizontal
    public var fixed2: Double
    public var flags: CGEventFlags

    public init(isContinuous: Bool, delta1: Int64, fixed1: Double,
                delta2: Int64 = 0, fixed2: Double = 0, flags: CGEventFlags = []) {
        self.isContinuous = isContinuous
        self.delta1 = delta1; self.fixed1 = fixed1
        self.delta2 = delta2; self.fixed2 = fixed2
        self.flags = flags
    }
}

/// What to do to one axis.
public enum AxisAction: Equatable, Sendable {
    /// Replace with exactly this many lines (discrete mode).
    case setLines(Int64)
    /// Flip direction, keeping magnitude and acceleration.
    case negate
}

/// `nil` for an axis means "leave it as is".
public struct WheelOutput: Equatable, Sendable {
    public var axis1: AxisAction?
    public var axis2: AxisAction?
    public init(axis1: AxisAction? = nil, axis2: AxisAction? = nil) { self.axis1 = axis1; self.axis2 = axis2 }
}

public enum ScrollTransform {
    /// Returns `nil` when the event should pass through untouched.
    public static func apply(_ input: WheelInput, config: ScrollConfig) -> WheelOutput? {
        guard config.enabled else { return nil }

        if input.isContinuous {
            // Trackpad: never change speed or acceleration, only (optionally) direction.
            guard config.trackpadDirection.needsFlip(systemNatural: config.systemNatural) else { return nil }
            let out = WheelOutput(axis1: hasMotion(input.delta1, input.fixed1) ? .negate : nil,
                                  axis2: hasMotion(input.delta2, input.fixed2) ? .negate : nil)
            return out == WheelOutput() ? nil : out
        }

        // Mouse wheel.
        let flip = config.mouseDirection.needsFlip(systemNatural: config.systemNatural)
        let bypassed = config.bypassModifier.flag.map { input.flags.contains($0) } ?? false
        let discrete = config.discrete && !bypassed
        let lines = Int64(config.linesPerNotch)

        func action(_ delta: Int64, _ fixed: Double, discreteAxis: Bool) -> AxisAction? {
            let s = sign(delta, fixed)
            guard s != 0 else { return nil }
            if discreteAxis { return .setLines(s * lines * (flip ? -1 : 1)) }
            return flip ? .negate : nil
        }

        let out = WheelOutput(axis1: action(input.delta1, input.fixed1, discreteAxis: discrete),
                              axis2: action(input.delta2, input.fixed2, discreteAxis: discrete && config.applyHorizontal))
        return out == WheelOutput() ? nil : out
    }

    static func hasMotion(_ delta: Int64, _ fixed: Double) -> Bool { delta != 0 || fixed != 0 }

    static func sign(_ delta: Int64, _ fixed: Double) -> Int64 {
        if delta != 0 { return delta > 0 ? 1 : -1 }
        if fixed > 0 { return 1 }
        if fixed < 0 { return -1 }
        return 0
    }
}
