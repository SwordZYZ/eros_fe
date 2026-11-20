import UIKit
import Flutter

class SceneDelegate: FlutterSceneDelegate {
    override func sceneDidEnterBackground(_ scene: UIScene) {
        super.sceneDidEnterBackground(scene)
        print("sceneDidEnterBackground")
        let isBlurredInRecentTasks = UserDefaults.standard.bool(forKey: "flutter.blurredInRecentTasks")
        print("isBlurredInRecentTasks :", isBlurredInRecentTasks)
        if isBlurredInRecentTasks {
            SecurityBlurEffect.addBlurEffect(to: window)
        }
    }

    override func sceneDidBecomeActive(_ scene: UIScene) {
        super.sceneDidBecomeActive(scene)
        print("sceneDidBecomeActive")
        SecurityBlurEffect.removeBlurEffect(from: window)
    }

    override func sceneWillEnterForeground(_ scene: UIScene) {
        super.sceneWillEnterForeground(scene)
        print("sceneWillEnterForeground")
        SecurityBlurEffect.removeBlurEffect(from: window)
    }
}
