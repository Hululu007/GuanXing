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
    /// 搜索请求序号。每次点搜索按钮都自增，搜索页用 onChange 观察它。
    ///
    /// 之前用 Bool 标志，搜索页消费后翻回 false：如果这次点击恰好伴随
    /// 首页视图重建（例如刚切换过片源），新实例的 onAppear 会先跑一遍，
    /// 把还没送到的请求当成旧请求吃掉，表现就是「点了搜索没反应」。
    /// 序号只会递增，任何一次点击都不会被误判成已处理。
    var searchRequestID = 0

    func openSearch(_ text: String? = nil) {
        // 先切回搜索 tab，再清掉上一次遗留的导航栈，
        // 否则会停在上次看过的详情页而不是搜索框。
        selectedTab = .search
        searchPath = NavigationPath()
        searchSeed = text
        searchRequestID &+= 1
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
