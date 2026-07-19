import Foundation

/// User-tunable settings. Pure model (no UserDefaults here) so it is testable;
/// the app layer persists it via `PreferencesStore`.
public struct Preferences: Codable, Equatable {
    /// Rendering scale in points-per-cell multiples (1.0 = one logical point per
    /// sprite pixel at @2x). Clamped to a sane range.
    public var scale: Double
    /// Extra playback-speed multiplier applied on top of each clip's fps.
    public var speedMultiplier: Double
    /// Whether clicks pass through the pet to windows beneath it.
    public var clickThrough: Bool
    /// Whether animation is paused.
    public var paused: Bool
    /// Whether the pet floats above normal windows.
    public var floatOnTop: Bool
    /// Whether the pet is shown on every Space / full-screen app.
    public var showOnAllSpaces: Bool
    /// Base window opacity (dimming for `sleeping` is applied on top of this).
    public var opacity: Double
    /// Whether the pet follows the live bridge state (vs. a manually held state).
    public var followBridge: Bool
    /// Opt-in: surface *what* Claude is doing (file / command / prompt) in the UI.
    public var detailMode: Bool
    /// Whether transcript "watch mode" is on (auto-started on launch).
    public var watchMode: Bool
    /// The active skin id ("khosrow" is the built-in).
    public var currentSkin: String

    public static let scaleRange: ClosedRange<Double> = 0.25...4.0
    public static let speedRange: ClosedRange<Double> = 0.1...4.0
    public static let opacityRange: ClosedRange<Double> = 0.1...1.0

    public init(scale: Double = 1.0,
                speedMultiplier: Double = 1.0,
                clickThrough: Bool = false,
                paused: Bool = false,
                floatOnTop: Bool = true,
                showOnAllSpaces: Bool = true,
                opacity: Double = 1.0,
                followBridge: Bool = true,
                detailMode: Bool = false,
                watchMode: Bool = false,
                currentSkin: String = "khosrow") {
        self.scale = scale
        self.speedMultiplier = speedMultiplier
        self.clickThrough = clickThrough
        self.paused = paused
        self.floatOnTop = floatOnTop
        self.showOnAllSpaces = showOnAllSpaces
        self.opacity = opacity
        self.followBridge = followBridge
        self.detailMode = detailMode
        self.watchMode = watchMode
        self.currentSkin = currentSkin
    }

    /// Decode tolerantly so older saved preferences (missing the newer keys)
    /// still load with sensible defaults instead of resetting everything.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Preferences()
        scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? d.scale
        speedMultiplier = try c.decodeIfPresent(Double.self, forKey: .speedMultiplier) ?? d.speedMultiplier
        clickThrough = try c.decodeIfPresent(Bool.self, forKey: .clickThrough) ?? d.clickThrough
        paused = try c.decodeIfPresent(Bool.self, forKey: .paused) ?? d.paused
        floatOnTop = try c.decodeIfPresent(Bool.self, forKey: .floatOnTop) ?? d.floatOnTop
        showOnAllSpaces = try c.decodeIfPresent(Bool.self, forKey: .showOnAllSpaces) ?? d.showOnAllSpaces
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? d.opacity
        followBridge = try c.decodeIfPresent(Bool.self, forKey: .followBridge) ?? d.followBridge
        detailMode = try c.decodeIfPresent(Bool.self, forKey: .detailMode) ?? d.detailMode
        watchMode = try c.decodeIfPresent(Bool.self, forKey: .watchMode) ?? d.watchMode
        currentSkin = try c.decodeIfPresent(String.self, forKey: .currentSkin) ?? d.currentSkin
    }

    /// Return a copy with all values clamped into their valid ranges.
    public func clamped() -> Preferences {
        var p = self
        p.scale = Self.scaleRange.clamp(scale)
        p.speedMultiplier = Self.speedRange.clamp(speedMultiplier)
        p.opacity = Self.opacityRange.clamp(opacity)
        return p
    }
}

/// Remembered window position, stored per display so multi-monitor setups
/// restore correctly.
public struct SavedPosition: Codable, Equatable {
    public let screenID: String
    public let x: Double
    public let y: Double
    public init(screenID: String, x: Double, y: Double) {
        self.screenID = screenID; self.x = x; self.y = y
    }
}

public extension ClosedRange where Bound == Double {
    func clamp(_ value: Double) -> Double {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}
