import CoreGraphics
import Foundation
import os
import GoodScrollCore

/// Owns the scroll-wheel event tap.
///
/// Why this doesn't "time out" like other discrete-scroll tools:
///  1. The tap runs on its own thread with its own run loop, so a busy main thread
///     (menus, settings window, app launch) can never stall the callback.
///  2. The callback does no allocation, no UserDefaults, no logging on the hot path —
///     it reads a value snapshot under an unfair lock and writes one integer field.
///  3. If macOS still disables the tap (`tapDisabledByTimeout` / `ByUserInput`, e.g. after
///     sleep or secure input), the callback re-enables it immediately, and a watchdog on
///     the main thread re-checks every few seconds and rebuilds the tap if needed.
final class ScrollTap {
    enum State: Equatable { case stopped, running, failed }

    private let log = Logger(subsystem: "io.github.vladjdk.GoodScroll", category: "tap")
    private let configLock = OSAllocatedUnfairLock(initialState: ScrollConfig())

    private var port: CFMachPort?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private var watchdog: Timer?

    private(set) var state: State = .stopped
    /// How many times macOS disabled the tap and we brought it back. Shown in the menu for transparency.
    private(set) var recoveries = 0
    var onStateChange: ((State) -> Void)?

    var config: ScrollConfig {
        get { configLock.withLock { $0 } }
        set { configLock.withLock { $0 = newValue } }
    }

    // MARK: Lifecycle (main thread)

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard port == nil else { return }

        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: scrollTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            log.error("CGEvent.tapCreate failed (missing Accessibility permission?)")
            setState(.failed)
            return
        }
        port = tap

        let ready = DispatchSemaphore(value: 0)
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let t = Thread { [weak self] in
            let rl = CFRunLoopGetCurrent()
            self?.runLoop = rl
            CFRunLoopAddSource(rl, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            ready.signal()
            CFRunLoopRun()
        }
        t.name = "GoodScroll.ScrollTap"
        t.qualityOfService = .userInteractive
        t.start()
        thread = t
        ready.wait()

        startWatchdog()
        setState(.running)
        log.info("Scroll tap started")
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        watchdog?.invalidate(); watchdog = nil
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let runLoop { CFRunLoopStop(runLoop) }
        port = nil; runLoop = nil; thread = nil
        setState(.stopped)
    }

    func restart() { stop(); start() }

    /// Called after wake from sleep, display reconfiguration, etc.
    func ensureHealthy() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let port else { return }
        if !CFMachPortIsValid(port) {
            log.notice("Tap port invalidated — rebuilding")
            recoveries += 1
            restart()
        } else if !CGEvent.tapIsEnabled(tap: port) {
            log.notice("Tap found disabled — re-enabling")
            recoveries += 1
            CGEvent.tapEnable(tap: port, enable: true)
        }
    }

    private func startWatchdog() {
        watchdog?.invalidate()
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.ensureHealthy() }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private func setState(_ s: State) {
        guard s != state else { return }
        state = s
        onStateChange?(s)
    }

    // MARK: Hot path (tap thread)

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.recoveries += 1
                self.log.notice("macOS disabled the tap (\(type.rawValue)); re-enabled")
            }
            return Unmanaged.passUnretained(event)

        case .scrollWheel:
            let input = WheelInput(
                isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
                delta1: event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
                fixed1: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
                delta2: event.getIntegerValueField(.scrollWheelEventDeltaAxis2),
                fixed2: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2),
                flags: event.flags
            )
            if let out = ScrollTransform.apply(input, config: config) {
                if let a = out.axis1 {
                    Self.write(a, to: event, hid: .y, line: .scrollWheelEventDeltaAxis1,
                               fixed: .scrollWheelEventFixedPtDeltaAxis1, point: .scrollWheelEventPointDeltaAxis1)
                }
                if let a = out.axis2 {
                    Self.write(a, to: event, hid: .x, line: .scrollWheelEventDeltaAxis2,
                               fixed: .scrollWheelEventFixedPtDeltaAxis2, point: .scrollWheelEventPointDeltaAxis2)
                }
            }
            return Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private static func write(_ action: AxisAction, to event: CGEvent, hid: HIDScroll.Axis,
                              line: CGEventField, fixed: CGEventField, point: CGEventField) {
        switch action {
        case .setLines(let n):
            // Setting the integer line delta makes CoreGraphics recompute the
            // fixed-point and pixel deltas consistently.
            let original = event.getDoubleValueField(fixed)
            event.setIntegerValueField(line, value: n)
            // Apps that read the attached HID event must at least agree on direction.
            if n != 0, original != 0, (n < 0) != (original < 0) { HIDScroll.negate(hid, of: event) }
        case .negate:
            // Read all three first: writing the line field recomputes (and rounds) the others.
            // Pixel deltas are fractional on trackpads, so they must be read as doubles;
            // reading them as integers rounds small movements away and makes scrolling choppy.
            let l = event.getIntegerValueField(line)
            let f = event.getDoubleValueField(fixed)
            let p = event.getDoubleValueField(point)
            event.setIntegerValueField(line, value: -l)
            event.setDoubleValueField(fixed, value: -f)
            event.setDoubleValueField(point, value: -p)
            // AppKit, WebKit and Chromium read trackpad deltas from the attached IOHIDEvent.
            HIDScroll.negate(hid, of: event)
        }
    }
}

private func scrollTapCallback(proxy: CGEventTapProxy,
                               type: CGEventType,
                               event: CGEvent,
                               userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<ScrollTap>.fromOpaque(userInfo).takeUnretainedValue()
    return tap.handle(type: type, event: event)
}
