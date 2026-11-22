import UIKit
import Flutter
import flutter_downloader

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
    private var windowLayout: FlutterMethodChannel?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        FlutterDownloaderPlugin.setPluginRegistrantCallback(registerPlugins)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

        let windowLayout = FlutterMethodChannel(
            name: "eros_fe/window_layout",
            binaryMessenger: engineBridge.applicationRegistrar.messenger()
        )
        self.windowLayout = windowLayout
        windowLayout.setMethodCallHandler { call, result in
            guard call.method == "windowControlInsets" else {
                result(FlutterMethodNotImplemented)
                return
            }
            guard #available(iOS 26.0, *), UIDevice.current.userInterfaceIdiom == .pad else {
                result(nil)
                return
            }

            // This app has one window scene. Its window can be laid out
            // before the scene becomes foregroundActive.
            let window = UIApplication.shared.connectedScenes
                .compactMap { ($0.delegate as? SceneDelegate)?.window }
                .first { !$0.isHidden }
            guard let window, let scene = window.windowScene,
                  let view = window.rootViewController?.viewIfLoaded,
                  view.window === window, !view.bounds.isEmpty else {
                result(["pending": 1.0])
                return
            }
            window.layoutIfNeeded()

            // Corner adaptation can report display rounding in full screen.
            // Only add an inset for a scene that occupies part of its display.
            let sceneSpace = scene.effectiveGeometry.coordinateSpace
            let screenSpace = scene.screen.coordinateSpace
            let sceneFrame = sceneSpace.convert(sceneSpace.bounds, to: screenSpace)
            guard !sceneFrame.isEmpty else {
                result(["pending": 1.0])
                return
            }
            let pixel = 1 / scene.screen.scale
            let fillsScreen = sceneFrame.insetBy(dx: -pixel, dy: -pixel).contains(screenSpace.bounds)
            let safeArea = view.safeAreaInsets
            let adapted = fillsScreen
                ? safeArea
                : view.edgeInsets(for: .safeArea(cornerAdaptation: .horizontal))
            result([
                "left": Double(max(0, adapted.left - safeArea.left)),
                "right": Double(max(0, adapted.right - safeArea.right)),
            ])
        }
    }
    
    func notifyWindowLayoutChanged() {
        windowLayout?.invokeMethod("windowLayoutChanged", arguments: nil)
    }

    @objc func step(displaylink: CADisplayLink) {
        // Will be called once a frame has been built while matching desired frame rate
    }
    
}

private func registerPlugins(registry: FlutterPluginRegistry) {
    if (!registry.hasPlugin("FlutterDownloaderPlugin")) {
        FlutterDownloaderPlugin.register(with: registry.registrar(forPlugin: "FlutterDownloaderPlugin")!)
    }
}

