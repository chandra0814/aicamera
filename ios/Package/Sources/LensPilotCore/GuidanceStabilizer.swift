import Foundation

public struct GuidanceStabilizer: Sendable {
    public struct Configuration: Equatable, Sendable {
        public static let standard = Configuration()

        public let minimumHoldMs: Int
        public let completedActionMemoryMs: Int

        public init(minimumHoldMs: Int = 1_200, completedActionMemoryMs: Int = 2_500) {
            self.minimumHoldMs = max(0, minimumHoldMs)
            self.completedActionMemoryMs = max(0, completedActionMemoryMs)
        }
    }

    private let configuration: Configuration
    private var activeAction: GuidanceAction?
    private var activeUntil: Date?
    private var minimumHoldUntil: Date?
    private var suppressedActionUntil: [GuidanceAction.Action: Date] = [:]
    private var completedActionUntil: [String: Date] = [:]

    public init(configuration: Configuration = .standard) {
        self.configuration = configuration
    }

    public mutating func reset() {
        activeAction = nil
        activeUntil = nil
        minimumHoldUntil = nil
        suppressedActionUntil.removeAll()
        completedActionUntil.removeAll()
    }

    public mutating func stabilize(_ proposedAction: GuidanceAction?, now: Date = Date()) -> GuidanceAction? {
        expireMemory(now: now)

        guard let proposedAction else {
            clearActive()
            return nil
        }

        if isReadyAction(proposedAction), let activeAction, !isReadyAction(activeAction) {
            rememberCompleted(activeAction, now: now)
            begin(proposedAction, now: now)
            return proposedAction
        }

        if isCompleted(proposedAction, now: now) {
            if let activeAction, isReadyAction(activeAction), isActive(now: now) {
                return activeAction
            }
            return nil
        }

        if isSuppressed(proposedAction.action, now: now) {
            if let activeAction, isActive(now: now) {
                return activeAction
            }
            return nil
        }

        if let activeAction, isActive(now: now), sameInstruction(activeAction, proposedAction) {
            begin(proposedAction, now: now)
            return proposedAction
        }

        if let activeAction,
           isActive(now: now),
           let minimumHoldUntil,
           minimumHoldUntil > now,
           !canInterrupt(proposedAction, activeAction: activeAction) {
            return activeAction
        }

        begin(proposedAction, now: now)
        return proposedAction
    }

    private mutating func begin(_ action: GuidanceAction, now: Date) {
        activeAction = action
        activeUntil = now.addingTimeInterval(milliseconds(action.ttlMs))
        minimumHoldUntil = now.addingTimeInterval(milliseconds(min(configuration.minimumHoldMs, action.ttlMs)))

        guard let oppositeAction = Self.oppositeAction(for: action.action) else { return }
        suppressedActionUntil[oppositeAction] = now.addingTimeInterval(milliseconds(action.suppressOppositeUntilMs))
    }

    private mutating func rememberCompleted(_ action: GuidanceAction, now: Date) {
        guard !isReadyAction(action) else { return }
        completedActionUntil[Self.completedKey(for: action)] = now.addingTimeInterval(milliseconds(configuration.completedActionMemoryMs))
    }

    private mutating func expireMemory(now: Date) {
        suppressedActionUntil = suppressedActionUntil.filter { $0.value > now }
        completedActionUntil = completedActionUntil.filter { $0.value > now }

        if !isActive(now: now) {
            clearActive()
        }
    }

    private mutating func clearActive() {
        activeAction = nil
        activeUntil = nil
        minimumHoldUntil = nil
    }

    private func isActive(now: Date) -> Bool {
        guard let activeUntil else { return false }
        return activeUntil > now
    }

    private func isSuppressed(_ action: GuidanceAction.Action, now: Date) -> Bool {
        guard let suppressedUntil = suppressedActionUntil[action] else { return false }
        return suppressedUntil > now
    }

    private func isCompleted(_ action: GuidanceAction, now: Date) -> Bool {
        guard let completedUntil = completedActionUntil[Self.completedKey(for: action)] else { return false }
        return completedUntil > now
    }

    private func isReadyAction(_ action: GuidanceAction) -> Bool {
        action.reason == .readyToCapture || action.action == .captureNow
    }

    private func sameInstruction(_ lhs: GuidanceAction, _ rhs: GuidanceAction) -> Bool {
        lhs.actor == rhs.actor &&
        lhs.action == rhs.action &&
        lhs.reason == rhs.reason &&
        lhs.direction == rhs.direction
    }

    private func canInterrupt(_ proposedAction: GuidanceAction, activeAction: GuidanceAction) -> Bool {
        if proposedAction.actor == .camera, activeAction.actor != .camera {
            return true
        }

        if proposedAction.reason == .reduceMotionBlur, activeAction.reason != .reduceMotionBlur {
            return true
        }

        if proposedAction.priority >= activeAction.priority + 12 {
            return true
        }

        return proposedAction.expectedGain >= activeAction.expectedGain + 0.08
    }

    private static func completedKey(for action: GuidanceAction) -> String {
        [
            action.actor.rawValue,
            action.action.rawValue,
            action.reason.rawValue,
            action.direction?.rawValue ?? "none"
        ].joined(separator: "|")
    }

    private static func oppositeAction(for action: GuidanceAction.Action) -> GuidanceAction.Action? {
        switch action {
        case .moveLeft:
            return .moveRight
        case .moveRight:
            return .moveLeft
        case .moveForward:
            return .ifSafeMove
        case .moveBackward, .ifSafeMove:
            return .moveForward
        case .raiseCamera:
            return .lowerCamera
        case .lowerCamera:
            return .raiseCamera
        case .rotateClockwise:
            return .rotateCounterclockwise
        case .rotateCounterclockwise:
            return .rotateClockwise
        default:
            return nil
        }
    }

    private func milliseconds(_ value: Int) -> TimeInterval {
        Double(max(0, value)) / 1_000
    }
}
