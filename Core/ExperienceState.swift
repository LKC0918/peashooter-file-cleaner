import Foundation

enum ExperienceState: String, CaseIterable {
    case hidden
    case summoned
    case approaching
    case firstConfirmation
    case finalConfirmation
    case charging
    case shooting
    case trashing
    case shattering
    case success
    case zombieExit
    case failure
}

enum ExperienceTransitionError: LocalizedError, Equatable {
    case invalid(from: ExperienceState, to: ExperienceState)

    var errorDescription: String? {
        switch self {
        case let .invalid(from, to):
            return "Invalid experience transition: \(from.rawValue) → \(to.rawValue)"
        }
    }
}

@MainActor
final class ExperienceStateMachine {
    private(set) var state: ExperienceState = .hidden

    private let allowedTransitions: [ExperienceState: Set<ExperienceState>] = [
        .hidden: [.summoned],
        .summoned: [.approaching, .failure],
        .approaching: [.firstConfirmation, .failure],
        .firstConfirmation: [.finalConfirmation, .hidden, .failure],
        .finalConfirmation: [.firstConfirmation, .charging, .hidden, .failure],
        .charging: [.shooting, .failure],
        .shooting: [.trashing, .failure],
        .trashing: [.shattering, .failure],
        .shattering: [.success, .failure],
        .success: [.zombieExit],
        .zombieExit: [.hidden],
        .failure: [.hidden]
    ]

    func transition(to nextState: ExperienceState) throws {
        guard allowedTransitions[state, default: []].contains(nextState) else {
            throw ExperienceTransitionError.invalid(from: state, to: nextState)
        }
        state = nextState
    }

    func resetForTesting() {
        state = .hidden
    }
}
