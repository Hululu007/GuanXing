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
        guard let scene = activeScene else { return }

        let controller = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
            ?? scene.windows.first?.rootViewController

        // 顺序很重要：先把新的支持方向告知系统，再请求几何更新。
        // 反过来的话系统仍按旧 mask 校验，会直接拒绝旋转，表现就是点了全屏没反应。
        controller?.setNeedsUpdateOfSupportedInterfaceOrientations()

        request(mask, in: scene, attempt: 0)
    }

    /// 系统有时会在 popover / sheet 收起前拒绝几何更新，
    /// 这里补两次重试，避免用户第一次点全屏「没反应」。
    private static func request(
        _ mask: UIInterfaceOrientationMask,
        in scene: UIWindowScene,
        attempt: Int
    ) {
        let preferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: mask)
        scene.requestGeometryUpdate(preferences) { error in
            guard attempt < 2 else {
                #if DEBUG
                print("[Orientation] 旋转失败：\(error.localizedDescription)")
                #endif
                return
            }
            // 回调是异步的，回主线程稍等再试，给 UIKit 一个完成转场的机会。
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                request(mask, in: scene, attempt: attempt + 1)
            }
        }
    }

    private static var activeScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
    }

    /// 当前界面方向，用来判断全屏按钮该不该触发旋转。
    static var isLandscape: Bool {
        activeScene?.interfaceOrientation.isLandscape ?? false
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
