#if os(iOS)
import MigoApplePerformancePlus
#else
import MigoMacV8
#endif
import Foundation

/// The game this example ships and how either app runs it. iOS and macOS use
/// the same two calls -- install the package, load it into a `MigoGameView` --
/// and differ only in the window that holds the view.
enum ExampleGame {
    /// `games/demo`, copied into the app bundle by the project.
    static let id = "demo"

    /// Installs the bundled game and returns a view ready to run it.
    ///
    /// The package is part of this signed app, so it is installed `.unsigned`;
    /// downloaded packages would use `.verified(publicKey:)`. Passing the build
    /// number as the version makes relaunches free: the same version is not
    /// copied again.
    static func makeView() throws -> MigoGameView {
        guard let package = Bundle.main.url(forResource: id, withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(id) in the app bundle"])
        }
        let configuration = try MigoGameView.Configuration.standard(contentSigning: .unsigned)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        try MigoGameInstaller.install(
            package: package, id: id, version: version, into: configuration.directories)
        return MigoGameView(configuration: configuration)
    }

    /// Reports the view's events on standard output and starts the game.
    ///
    /// Launched with `-MigoExampleRunSeconds N` the app exits after N seconds:
    /// 0 if the game became ready and the display clock delivered frames to
    /// it, 1 otherwise. That is how CI runs the example; a person just
    /// launches it.
    static func run(in view: MigoGameView, onExit: @escaping () -> Void) {
        var ready = false
        view.onEvent = { event in
            switch event {
            case .ready:
                ready = true
                report("ready")
            case .exitRequested:
                report("the game asked to exit")
                onExit()
            case .failed(let reason):
                report("failed: \(reason)")
            case .error(let code, let message, let recoverable):
                report("error \(code) recoverable=\(recoverable): \(message)")
            case .gameLog(let entry):
                report("game log: \(entry)")
            default:
                break
            }
        }
        if let reason = MigoGameView.unavailabilityReason {
            report("this device cannot run the game: \(reason)")
        }
        view.loadGame(id: id)

        let seconds = UserDefaults.standard.double(forKey: "MigoExampleRunSeconds")
        guard seconds > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            let frames = view.frameClockStatistics?.delivered ?? 0
            report("done after \(seconds) s: ready=\(ready) frames=\(frames)")
            exit(ready && frames > 0 ? 0 : 1)
        }
    }

    private static func report(_ line: String) {
        print("[host] \(line)")
        fflush(stdout)
    }
}
