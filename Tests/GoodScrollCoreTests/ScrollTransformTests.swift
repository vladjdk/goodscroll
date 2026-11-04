import Testing
import CoreGraphics
@testable import GoodScrollCore

@Suite struct ScrollTransformTests {
    let config = ScrollConfig(linesPerNotch: 3)
    let wheel = WheelInput(isContinuous: false, delta1: 7, fixed1: 7.4)
    let pad = WheelInput(isContinuous: true, delta1: 2, fixed1: 2.5, delta2: -1, fixed2: -1)

    @Test func acceleratedWheelBecomesFixedLines() {
        #expect(ScrollTransform.apply(wheel, config: config) == WheelOutput(axis1: .setLines(3)))
        let down = WheelInput(isContinuous: false, delta1: -12, fixed1: -12)
        #expect(ScrollTransform.apply(down, config: config) == WheelOutput(axis1: .setLines(-3)))
    }

    @Test func trackpadUntouchedByDefault() {
        #expect(ScrollTransform.apply(pad, config: config) == nil)
    }

    @Test func masterSwitchOffPassesEverything() {
        var c = config; c.enabled = false; c.mouseDirection = .traditional; c.trackpadDirection = .natural; c.systemNatural = false
        #expect(ScrollTransform.apply(wheel, config: c) == nil)
        #expect(ScrollTransform.apply(pad, config: c) == nil)
    }

    @Test func subLineUsesFixedPointSign() {
        let input = WheelInput(isContinuous: false, delta1: 0, fixed1: -0.2)
        #expect(ScrollTransform.apply(input, config: config) == WheelOutput(axis1: .setLines(-3)))
    }

    @Test func zeroEventPassesThrough() {
        #expect(ScrollTransform.apply(.init(isContinuous: false, delta1: 0, fixed1: 0), config: config) == nil)
    }

    // The headline use case: system natural OFF, want natural on trackpad + traditional on mouse.
    @Test func naturalTrackpadTraditionalMouse_systemOff() {
        var c = config; c.systemNatural = false; c.trackpadDirection = .natural; c.mouseDirection = .traditional
        #expect(ScrollTransform.apply(pad, config: c) == WheelOutput(axis1: .negate, axis2: .negate))
        #expect(ScrollTransform.apply(wheel, config: c) == WheelOutput(axis1: .setLines(3)))
    }

    // Same goal with system natural ON: only the mouse needs flipping.
    @Test func naturalTrackpadTraditionalMouse_systemOn() {
        var c = config; c.systemNatural = true; c.trackpadDirection = .natural; c.mouseDirection = .traditional
        #expect(ScrollTransform.apply(pad, config: c) == nil)
        #expect(ScrollTransform.apply(wheel, config: c) == WheelOutput(axis1: .setLines(-3)))
    }

    @Test func directionOnlyKeepsMouseAcceleration() {
        var c = config; c.discrete = false; c.mouseDirection = .traditional; c.systemNatural = true
        #expect(ScrollTransform.apply(wheel, config: c) == WheelOutput(axis1: .negate))
        c.mouseDirection = .followSystem
        #expect(ScrollTransform.apply(wheel, config: c) == nil)
    }

    @Test func horizontalDiscreteOnlyWhenEnabled() {
        let input = WheelInput(isContinuous: false, delta1: 0, fixed1: 0, delta2: 4, fixed2: 4)
        #expect(ScrollTransform.apply(input, config: config) == nil)
        var c = config; c.applyHorizontal = true
        #expect(ScrollTransform.apply(input, config: c) == WheelOutput(axis2: .setLines(3)))
        // Direction still flips horizontal even when it isn't made discrete.
        c.applyHorizontal = false; c.mouseDirection = .traditional; c.systemNatural = true
        #expect(ScrollTransform.apply(input, config: c) == WheelOutput(axis2: .negate))
    }

    @Test func bypassModifierSkipsDiscreteButKeepsDirection() {
        var c = config; c.bypassModifier = .option
        let held = WheelInput(isContinuous: false, delta1: 5, fixed1: 5, flags: .maskAlternate)
        #expect(ScrollTransform.apply(held, config: c) == nil)
        c.mouseDirection = .traditional; c.systemNatural = true
        #expect(ScrollTransform.apply(held, config: c) == WheelOutput(axis1: .negate))
        let notHeld = WheelInput(isContinuous: false, delta1: 5, fixed1: 5, flags: .maskCommand)
        #expect(ScrollTransform.apply(notHeld, config: c) == WheelOutput(axis1: .setLines(-3)))
    }

    @Test func lineCountIsClamped() {
        #expect(ScrollConfig(linesPerNotch: 0).linesPerNotch == 1)
        #expect(ScrollConfig(linesPerNotch: 99).linesPerNotch == 20)
    }
}
