import Foundation

public extension EspansoError {
    /// The message alone, without the error's type around it.
    var message: String {
        switch self {
        case .Load(let message), .Script(let message), .Render(let message): message
        }
    }
}

/// An error as a person should read it: an `EspansoError`'s message alone, otherwise the system's description.
public func describe(_ error: any Error) -> String {
    (error as? EspansoError)?.message ?? error.localizedDescription
}
