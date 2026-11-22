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
        notifyWindowLayoutChanged()
    }

    @available(iOS 26.0, *)
    override func windowScene(_ windowScene: UIWindowScene, didUpdateEffectiveGeometry previousGeometry: UIWindowScene.Geometry) {
        notifyWindowLayoutChanged()
    }

    private func notifyWindowLayoutChanged() {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        (UIApplication.shared.delegate as? AppDelegate)?.notifyWindowLayoutChanged()
    }

    override func sceneWillEnterForeground(_ scene: UIScene) {
        super.sceneWillEnterForeground(scene)
        print("sceneWillEnterForeground")
        SecurityBlurEffect.removeBlurEffect(from: window)
    }
}
