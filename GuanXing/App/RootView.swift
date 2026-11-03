import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router

    var body: some View {
        TabView(selection: Binding(
            get: { router.selectedTab },
            set: { tab in
                // 已经停在搜索页时再次点「搜索」页签，等同于「重新搜一次」：
                // 清掉上次结果并把光标放回输入框，不用先滑回顶部再点。
                // 这里先把 tab 落定再发请求，避免 selectedTab 仍是旧值时
                // openSearch 内部的赋值触发一次多余的 TabView 切换。
                if tab == .search, router.selectedTab == .search {
                    router.selectedTab = .search
                    router.openSearch()
                    return
                }
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
