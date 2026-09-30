#if os(iOS)
import MigoApplePerformancePlus
#else
import MigoMacV8
#endif
import CryptoKit
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
    /// downloaded packages would use `.verified(publicKey:)`. The version is a
    /// digest of the package, so relaunches are free -- the same version is not
    /// copied again -- and editing `games/demo` takes effect on the next run.
    /// (The build number would not: it stays the same while the game changes, and
    /// the installer would go on running the game it already has.)
    static func makeView() throws -> MigoGameView {
        guard let package = Bundle.main.url(forResource: id, withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(id) in the app bundle"])
        }
        let configuration = try MigoGameView.Configuration.standard(contentSigning: .unsigned)
        try MigoGameInstaller.install(
            package: package, id: id, version: try digest(of: package), into: configuration.directories)
        return MigoGameView(configuration: configuration)
    }

    /// SHA-256 over every file's path (relative to the package) and bytes, in path order.
    private static func digest(of package: URL) throws -> String {
        var hash = SHA256()
        let files = (FileManager.default.enumerator(at: package, includingPropertiesForKeys: [.isRegularFileKey])?
            .compactMap { $0 as? URL } ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { $0.path < $1.path }
        for file in files {
            hash.update(data: Data(file.path.dropFirst(package.path.count).utf8))
            hash.update(data: try Data(contentsOf: file))
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
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
            #if os(iOS)
            // Only the iOS view has these (WebKit's content process restarting, the
            // game's console); the example has nothing to do for either.
            case .restarted, .console:
                break
            #endif
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
