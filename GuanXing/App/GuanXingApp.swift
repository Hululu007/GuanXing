import SwiftUI
import GuanXingCore

@main
struct GuanXingApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var app = AppModel()
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(router)
                .preferredColorScheme(.dark)
                .tint(GXTheme.gold)
        }
    }
}

@MainActor
@Observable
final class AppRouter {
    enum Tab: Hashable {
        case home
        case search
        case live
        case library
        case settings
    }

    var selectedTab: Tab = .home
    var homePath = NavigationPath()
    var searchPath = NavigationPath()
    var livePath = NavigationPath()
    var libraryPath = NavigationPath()
    var settingsPath = NavigationPath()
    var searchSeed: String?
    /// 首页点了搜索钮后置位，搜索页消费完就清掉。
    /// 用它而不用 onAppear，避免从详情页返回时把结果清空。
    var pendingSearchFocus = false

    func openSearch(_ text: String? = nil) {
        // 先切回搜索 tab，再清掉上一次遗留的导航栈，
        // 否则会停在上次看过的详情页而不是搜索框。
        selectedTab = .search
        searchPath = NavigationPath()
        searchSeed = text
        pendingSearchFocus = true
    }

    func push(_ route: Route) {
        switch selectedTab {
        case .home: homePath.append(route)
        case .search: searchPath.append(route)
        case .live: livePath.append(route)
        case .library: libraryPath.append(route)
        case .settings: settingsPath.append(route)
        }
    }
}

enum Route: Hashable {
    case detail(VodItem)
    case player(PlayerLaunch)
    case livePlayer(LiveChannel)
    case resume(HistoryEntry)
    case sourceManager
    case importCenter
    case about
}

struct PlayerLaunch: Hashable {
    var item: VodItem
    var detail: VodDetail
    var lineName: String
    var episodeIndex: Int
    var startPosition: Double
}
