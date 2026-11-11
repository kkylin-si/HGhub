import SwiftUI

enum OrientationLock {
    static var mask: UIInterfaceOrientationMask = .portrait

    static func apply(fullscreen: Bool) {
        mask = fullscreen ? [.landscapeLeft, .landscapeRight] : .portrait
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let target: UIInterfaceOrientationMask = fullscreen ? .landscapeRight : .portrait
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: target)) { _ in }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}

@main
struct HGhubApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    @StateObject private var proxy = MediaProxy()

    var body: some Scene {
        WindowGroup {
            ShellView()
                .environmentObject(model)
                .environmentObject(proxy)
                .environment(\.hg, model.dark ? .dark : .light)
                .preferredColorScheme(model.dark ? .dark : .light)
                .onAppear {
                    proxy.start(referer: model.base + "/")
                }
                .onChange(of: model.base) { next in
                    proxy.updateReferer(next + "/")
                }
        }
    }
}
