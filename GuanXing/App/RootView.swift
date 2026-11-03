import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router

    /// TabView 的选中项用本地状态承载，再由 onChange 与 router 双向同步。
    /// 直接绑定 router.selectedTab 时，程序化切页（首页右上角搜索按钮）在部分
    /// 系统版本上不会驱动 TabView 换页，表现就是「点搜索没反应」。
    @State private var selectedTab: AppRouter.Tab = .home

    var body: some View {
        TabView(selection: Binding(
            get: { selectedTab },
            set: { tab in
                // 已经停在搜索页时再次点「搜索」页签，等同于「重新搜一次」：
                // 清掉上次结果并把光标放回输入框，不用先滑回顶部再点。
                if tab == .search, selectedTab == .search {
                    selectedTab = .search
                    router.selectedTab = .search
                    router.openSearch()
                    return
                }
                selectedTab = tab
                router.selectedTab = tab
            }
        )) {
            NavigationStack(path: Binding(
                get: { router.homePath },
                set: { router.homePath = $0 }
            )) {
                HomeView()
                    .navigationDestination(for: Route.self) { route in
                        RouteDestination(route: route)
                    }
            }
            .tabItem {
                Label("发现", systemImage: "sparkles.tv")
            }
            .tag(AppRouter.Tab.home)

            NavigationStack(path: Binding(
                get: { router.searchPath },
                set: { router.searchPath = $0 }
            )) {
                SearchView()
                    .navigationDestination(for: Route.self) { route in
                        RouteDestination(route: route)
                    }
            }
            .tabItem {
                Label("搜索", systemImage: "magnifyingglass")
            }
            .tag(AppRouter.Tab.search)

            NavigationStack(path: Binding(
                get: { router.livePath },
                set: { router.livePath = $0 }
            )) {
                LiveView()
                    .navigationDestination(for: Route.self) { route in
                        RouteDestination(route: route)
                    }
            }
            .tabItem {
                Label("直播", systemImage: "dot.radiowaves.left.and.right")
            }
            .tag(AppRouter.Tab.live)

            NavigationStack(path: Binding(
                get: { router.libraryPath },
                set: { router.libraryPath = $0 }
            )) {
                LibraryView()
                    .navigationDestination(for: Route.self) { route in
                        RouteDestination(route: route)
                    }
            }
            .tabItem {
                Label("片库", systemImage: "bookmark")
            }
            .tag(AppRouter.Tab.library)

            NavigationStack(path: Binding(
                get: { router.settingsPath },
                set: { router.settingsPath = $0 }
            )) {
                SettingsView()
                    .navigationDestination(for: Route.self) { route in
                        RouteDestination(route: route)
                    }
            }
            .tabItem {
                Label("设置", systemImage: "slider.horizontal.3")
            }
            .tag(AppRouter.Tab.settings)
        }
        .onChange(of: router.selectedTab) { _, newValue in
            if selectedTab != newValue { selectedTab = newValue }
        }
        .alert(item: Binding(
            get: { app.importMessage },
            set: { app.importMessage = $0 }
        )) { alert in
            Alert(
                title: Text(alert.title),
                message: Text([alert.message, alert.detail].compactMap { $0 }.joined(separator: "\n\n")),
                dismissButton: .default(Text("知道了"))
            )
        }
    }
}

struct RouteDestination: View {
    let route: Route

    var body: some View {
        switch route {
        case .detail(let item):
            DetailView(item: item)
        case .player(let launch):
            PlayerView(launch: launch)
        case .livePlayer(let channel):
            LivePlayerView(channel: channel)
        case .resume(let entry):
            ResumePlaybackView(entry: entry)
        case .sourceManager:
            SourceManagerView()
        case .importCenter:
            ImportCenterView()
        case .about:
            AboutView()
        }
    }
}
