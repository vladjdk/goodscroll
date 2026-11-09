import CoreGraphics
import Darwin

/// Access to the IOHIDEvent that macOS attaches to every hardware scroll event.
///
/// Trackpad scroll events carry two copies of their deltas: the public CGEvent fields and the
/// underlying IOHIDEvent. AppKit (precise `scrollingDelta`, momentum), WebKit and Chromium read the
/// IOHIDEvent, so reversing only the CGEvent fields leaves those apps seeing the original direction
/// and scrolling fights itself. These are private but long-stable symbols (LinearMouse and others
/// rely on them); they are resolved at runtime and every call is a no-op if one is missing.
enum HIDScroll {
    enum Axis: UInt32 {
        // IOHIDEventFieldBase(kIOHIDEventTypeScroll = 6) | index
        case x = 0x0006_0000
        case y = 0x0006_0001
    }

    private typealias CopyFn = @convention(c) (CGEvent) -> UnsafeMutableRawPointer?
    private typealias GetFn = @convention(c) (UnsafeMutableRawPointer, UInt32) -> Double
    private typealias SetFn = @convention(c) (UnsafeMutableRawPointer, UInt32, Double) -> Void

    private static let fns: (copy: CopyFn, get: GetFn, set: SetFn)? = {
        _ = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
        let h = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        guard let c = dlsym(h, "CGEventCopyIOHIDEvent"),
              let g = dlsym(h, "IOHIDEventGetFloatValue"),
              let s = dlsym(h, "IOHIDEventSetFloatValue") else { return nil }
        return (unsafeBitCast(c, to: CopyFn.self), unsafeBitCast(g, to: GetFn.self), unsafeBitCast(s, to: SetFn.self))
    }()

    static var isAvailable: Bool { fns != nil }

    /// Negates the given axis on the event's attached IOHIDEvent, if it has one.
    /// The returned IOHIDEvent is the event's own (not a copy), so the write sticks.
    static func negate(_ axis: Axis, of event: CGEvent) {
        guard let fns, let hid = fns.copy(event) else { return }
        let v = fns.get(hid, axis.rawValue)
        if v != 0 { fns.set(hid, axis.rawValue, -v) }
        Unmanaged<AnyObject>.fromOpaque(hid).release() // balance the Copy
    }
}
