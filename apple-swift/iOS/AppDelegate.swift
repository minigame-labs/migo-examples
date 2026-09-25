import MigoApplePerformancePlus
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = GameViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

/// Holds the game full screen. The game lays itself out once, at its first
/// size, so the controller is locked to the game's orientation (`demo` is
/// portrait; see its game.json).
final class GameViewController: UIViewController {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func loadView() {
        do {
            let gameView = try ExampleGame.makeView()
            view = gameView
            // iOS apps do not quit themselves; a real app would show its own
            // screen here.
            ExampleGame.run(in: gameView, onExit: {})
        } catch {
            let label = UILabel()
            label.text = "Could not install the game: \(error.localizedDescription)"
            label.numberOfLines = 0
            label.textAlignment = .center
            view = label
        }
    }
}
