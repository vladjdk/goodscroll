import Foundation
import Combine
import GoodScrollCore

/// User-facing settings, persisted to UserDefaults. Every change is pushed to the tap as a value snapshot.
final class AppSettings: ObservableObject {
    private enum Key {
        static let enabled = "enabled"
        static let discrete = "discrete"
        static let lines = "linesPerNotch"
        static let horizontal = "applyHorizontal"
        static let mouseDirection = "mouseDirection"
        static let trackpadDirection = "trackpadDirection"
        static let bypass = "bypassModifier"
        static let showIcon = "showMenuBarIcon"
    }

    private let defaults: UserDefaults

    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: Key.enabled) } }
    @Published var discrete: Bool { didSet { defaults.set(discrete, forKey: Key.discrete) } }
    @Published var linesPerNotch: Int {
        didSet {
            let clamped = min(max(linesPerNotch, ScrollConfig.lineRange.lowerBound), ScrollConfig.lineRange.upperBound)
            if clamped != linesPerNotch { linesPerNotch = clamped; return }
            defaults.set(linesPerNotch, forKey: Key.lines)
        }
    }
    @Published var applyHorizontal: Bool { didSet { defaults.set(applyHorizontal, forKey: Key.horizontal) } }
    @Published var mouseDirection: ScrollDirection { didSet { defaults.set(mouseDirection.rawValue, forKey: Key.mouseDirection) } }
    @Published var trackpadDirection: ScrollDirection { didSet { defaults.set(trackpadDirection.rawValue, forKey: Key.trackpadDirection) } }
    @Published var bypassModifier: BypassModifier { didSet { defaults.set(bypassModifier.rawValue, forKey: Key.bypass) } }
    @Published var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: Key.showIcon) } }

    /// Mirrors System Settings → Trackpad/Mouse → Natural scrolling. Not persisted; refreshed live.
    @Published private(set) var systemNatural: Bool = SystemScrollSetting.isNatural

    private var naturalObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.enabled: true,
            Key.discrete: true,
            Key.lines: 3,
            Key.horizontal: false,
            Key.mouseDirection: ScrollDirection.followSystem.rawValue,
            Key.trackpadDirection: ScrollDirection.followSystem.rawValue,
            Key.bypass: BypassModifier.none.rawValue,
            Key.showIcon: true,
        ])
        enabled = defaults.bool(forKey: Key.enabled)
        discrete = defaults.bool(forKey: Key.discrete)
        linesPerNotch = defaults.integer(forKey: Key.lines)
        applyHorizontal = defaults.bool(forKey: Key.horizontal)
        mouseDirection = ScrollDirection(rawValue: defaults.string(forKey: Key.mouseDirection) ?? "") ?? .followSystem
        trackpadDirection = ScrollDirection(rawValue: defaults.string(forKey: Key.trackpadDirection) ?? "") ?? .followSystem
        bypassModifier = BypassModifier(rawValue: defaults.string(forKey: Key.bypass) ?? "") ?? .none
        showMenuBarIcon = defaults.bool(forKey: Key.showIcon)

        // System Settings broadcasts this when the Natural scrolling checkbox changes.
        naturalObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("SwipeScrollDirectionDidChangeNotification"), object: nil, queue: .main
        ) { [weak self] _ in self?.refreshSystemNatural() }
    }

    func refreshSystemNatural() {
        let v = SystemScrollSetting.isNatural
        if v != systemNatural { systemNatural = v }
    }

    var scrollConfig: ScrollConfig {
        ScrollConfig(enabled: enabled,
                     discrete: discrete,
                     linesPerNotch: linesPerNotch,
                     applyHorizontal: applyHorizontal,
                     mouseDirection: mouseDirection,
                     trackpadDirection: trackpadDirection,
                     bypassModifier: bypassModifier,
                     systemNatural: systemNatural)
    }

    /// Emits a new config whenever any scroll-related setting changes.
    var scrollConfigPublisher: AnyPublisher<ScrollConfig, Never> {
        objectWillChange
            .receive(on: DispatchQueue.main) // objectWillChange fires before the write; hop so we read the new value
            .map { [unowned self] in self.scrollConfig }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    func resetToDefaults() {
        enabled = true
        discrete = true
        linesPerNotch = 3
        applyHorizontal = false
        mouseDirection = .followSystem
        trackpadDirection = .followSystem
        bypassModifier = .none
    }
}

enum SystemScrollSetting {
    /// `com.apple.swipescrolldirection` in the global domain; macOS treats a missing key as natural (true).
    static var isNatural: Bool {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        let v = CFPreferencesCopyAppValue("com.apple.swipescrolldirection" as CFString, kCFPreferencesAnyApplication)
        return (v as? Bool) ?? true
    }
}
