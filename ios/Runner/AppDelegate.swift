import UIKit
import Flutter
import flutter_downloader

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
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
        windowLayout.setMethodCallHandler { call, result in
            guard call.method == "windowControlInsets" else {
                result(FlutterMethodNotImplemented)
                return
            }
            guard #available(iOS 26.0, *), UIDevice.current.userInterfaceIdiom == .pad,
                  let window = UIApplication.shared.connectedScenes
                      .compactMap({ $0 as? UIWindowScene })
                      .first(where: { $0.activationState == .foregroundActive })?.keyWindow,
                  let view = window.rootViewController?.view else {
                result(nil)
                return
            }

            let safeArea = view.safeAreaInsets
            let adapted = view.edgeInsets(for: .safeArea(cornerAdaptation: .horizontal))
            result([
                "left": Double(max(0, adapted.left - safeArea.left)),
                "right": Double(max(0, adapted.right - safeArea.right)),
            ])
        }
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

