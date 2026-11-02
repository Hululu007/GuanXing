import SwiftUI
import UIKit

@MainActor
enum OrientationHelper {
    static func lockLandscape() {
        apply(.landscapeRight)
    }

    static func lockPortrait() {
        apply(.portrait)
    }

    private static func apply(_ mask: UIInterfaceOrientationMask) {
        AppDelegate.orientationLock = mask
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }

        let controller = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
            ?? scene.windows.first?.rootViewController

        // 顺序很重要：先把新的支持方向告知系统，再请求几何更新。
        // 反过来的话系统仍按旧 mask 校验，会直接拒绝旋转，表现就是点了全屏没反应。
        controller?.setNeedsUpdateOfSupportedInterfaceOrientations()

        let preferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: mask)
        scene.requestGeometryUpdate(preferences) { error in
            #if DEBUG
            print("[Orientation] 旋转失败：\(error.localizedDescription)")
            #endif
        }
    }

    /// 当前界面方向，用来判断全屏按钮该不该触发旋转。
    static var isLandscape: Bool {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return false }
        return scene.interfaceOrientation.isLandscape
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .portrait

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppDelegate.orientationLock
    }
}
