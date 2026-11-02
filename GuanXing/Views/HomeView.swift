import SwiftUI
import GuanXingCore

@MainActor
@Observable
final class HomeModel {
    var sections: [String: [VodItem]] = [:]
    var categories: [String] = []
    var selectedCategory = "全部"
    var selectedSourceID: String?
    var isLoading = false
    var errorMessage: String?
    var hasLoaded = false
    var currentPage = 1
    var pageCount = 1
    var heroItem: VodItem?
    private var storedApp: AppModel?

    func bind(_ app: AppModel) {
        storedApp = app
    }

    func load(app: AppModel, force: Bool = false) async {
        if hasLoaded && !force { return }
        let source: VodSource?
        if let selectedSourceID {
            source = app.sources.first { $0.id == selectedSourceID }
        } else {
            source = app.enabledSources.first
        }
        guard let source else {
            errorMessage = "还没有可用的点播源，请先在设置中导入。"
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let client = SourceClient(source: source)
            let page = try await client.latest(page: 1)
            let classes: [VodCategory]
            do {
                classes = try await client.categories()
            } catch {
                classes = []
            }
            sections["最新上线"] = page.items
            heroItem = page.items.randomElement()
            categories = classes
                .filter { ($0.parentID ?? "0") == "0" || $0.parentID == nil }
                .map(\.name)
            currentPage = page.page
            pageCount = page.pageCount
            hasLoaded = true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func refresh() async {
        guard let app = storedApp else { return }
        hasLoaded = false
        await load(app: app, force: true)
    }

    func select(sourceID: String) {
        guard selectedSourceID != sourceID else { return }
        selectedSourceID = sourceID
        selectedCategory = "全部"
        sections = [:]
        categories = []
        heroItem = nil
        hasLoaded = false
    }

    func loadCategory(app: AppModel, category: String) async {
        guard selectedCategory == category else { return }
        guard let source = app.sources.first(where: { $0.id == selectedSourceID }) ?? app.enabledSources.first else {
            return
        }
        isLoading = true
        defer { isLoading = false }
        sections = [:]
        do {
            let client = SourceClient(source: source)
            if category == "全部" {
                let page = try await client.latest()
                sections["最新上线"] = page.items
            } else {
                let categories = try await client.categories()
                guard let matched = categories.first(where: { $0.name == category }) else { return }
                let page = try await client.list(typeID: matched.id, page: 1)
                sections[category] = page.items
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router
    @State private var model = HomeModel()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                header
                hero
                quickStats
                categoryStrip
                content
                sourceShelf
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background {
            ZStack {
                GXTheme.heroGradient.ignoresSafeArea()
                StarfieldBackground()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            model.bind(app)
            await model.load(app: app)
        }
        .refreshable {
            await model.refresh()
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(GXTheme.gold)
                    Text("观星")
                        .font(.system(size: 26, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                        .tracking(2)
                }
                Text("在内容的星海里，找到想看的那一颗")
                    .font(.caption)
                    .foregroundStyle(GXTheme.secondaryText)
            }
            Spacer()
            Button {
                router.openSearch()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(GXTheme.surfaceElevated, in: Circle())
                    .overlay(Circle().stroke(GXTheme.stroke, lineWidth: 1))
            }
            .accessibilityLabel("搜索")
        }
    }

    private var hero: some View {
        Group {
            if let item = model.heroItem {
                Button {
                    router.push(.detail(item))
                } label: {
                    ZStack(alignment: .bottomLeading) {
                        RemoteImage(url: item.pic)
                            .frame(height: 248)
                            .frame(maxWidth: .infinity)
                            .clipped()
                        LinearGradient(
                            colors: [.clear, GXTheme.background.opacity(0.86), GXTheme.background],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                        VStack(alignment: .leading, spacing: 8) {
                            Pill(text: item.sourceName.uppercased(), tint: GXTheme.gold)
                            Text(item.name)
                                .font(.system(size: 26, weight: .bold, design: .serif))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            HStack(spacing: 10) {
                                if let year = item.year, !year.isEmpty { Text(year) }
                                if let remarks = item.remarks, !remarks.isEmpty { Text(remarks) }
                                if let score = item.score, !score.isEmpty, score != "0.0" {
                                    Label(score, systemImage: "star.fill")
                                        .foregroundStyle(GXTheme.gold)
                                }
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(GXTheme.secondaryText)
                            HStack(spacing: 10) {
                                Label("立即观看", systemImage: "play.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.black.opacity(0.82))
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 9)
                                    .background(GXTheme.gold, in: Capsule())
                                Text("今日上新")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            .padding(.top, 3)
                        }
                        .padding(18)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(GXTheme.stroke, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            } else {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(GXTheme.surface)
                    .frame(height: 230)
                    .overlay {
                        if model.isLoading {
                            ProgressView().tint(GXTheme.gold)
                        } else {
                            EmptyViewState(
                                icon: "sparkles.tv",
                                title: "正在寻找星光",
                                message: model.errorMessage ?? "加载最新影片后，这里会显示今日推荐。",
                                actionTitle: "重新加载"
                            ) {
                                Task { await model.load(app: app, force: true) }
                            }
                        }
                    }
            }
        }
    }

    private var quickStats: some View {
        HStack(spacing: 10) {
            statCard(value: "\(app.enabledSources.count)", label: "在线源", icon: "antenna.radiowaves.left.and.right")
            statCard(value: "\(app.enabledLiveSources.count)", label: "直播源", icon: "tv")
            statCard(value: "\(app.favorites.count)", label: "收藏", icon: "star")
        }
    }

    private func statCard(value: String, label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(GXTheme.gold)
            Text(value)
                .font(.system(size: 21, weight: .semibold, design: .serif))
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(GXTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gxCard(padding: 13, radius: 15)
    }

    private var categoryStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "片单", subtitle: "从当前源里挑一部")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryButton("全部")
                    ForEach(model.categories, id: \.self) { category in
                        categoryButton(category)
                    }
                }
            }
        }
    }

    private func categoryButton(_ title: String) -> some View {
        Button {
            model.selectedCategory = title
            Task { await model.loadCategory(app: app, category: title) }
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(model.selectedCategory == title ? Color.black.opacity(0.84) : .white.opacity(0.82))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    model.selectedCategory == title ? GXTheme.gold : GXTheme.surface,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.isLoading && model.sections.isEmpty {
                ProgressView("正在连接片源…")
                    .tint(GXTheme.gold)
                    .foregroundStyle(GXTheme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 50)
            } else if let error = model.errorMessage, model.sections.isEmpty {
                EmptyViewState(
                    icon: "wifi.exclamationmark",
                    title: "没有连上片源",
                    message: error,
                    actionTitle: "重试"
                ) {
                    Task { await model.load(app: app, force: true) }
                }
            } else {
                ForEach(model.sections.keys.sorted(), id: \.self) { key in
                    if let items = model.sections[key], !items.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: key, subtitle: "共 \(items.count) 部")
                            posterGrid(items)
                        }
                    }
                }
            }
        }
    }

    private func posterGrid(_ items: [VodItem]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 108), spacing: 12)],
            spacing: 18
        ) {
            ForEach(items) { item in
                Button {
                    router.push(.detail(item))
                } label: {
                    PosterCard(item: item)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sourceShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "我的片源",
                subtitle: "导入 TVBox / LibreTV 配置，扩展可搜索范围",
                actionTitle: "管理"
            ) {
                router.push(.sourceManager)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(app.sources.prefix(12)) { source in
                        Button {
                            model.select(sourceID: source.id)
                            Task { await model.load(app: app, force: true) }
                        } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text(source.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Spacer(minLength: 3)
                                    Image(systemName: source.isEnabled ? "checkmark.circle.fill" : "circle")
                                        .font(.caption)
                                        .foregroundStyle(source.isEnabled ? GXTheme.success : GXTheme.secondaryText)
                                }
                                Text(source.host)
                                    .font(.caption2)
                                    .foregroundStyle(GXTheme.secondaryText)
                                    .lineLimit(1)
                                SourceHealthBadge(health: app.health[source.id])
                            }
                            .frame(width: 148, alignment: .leading)
                            .gxCard(padding: 12, radius: 14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(
                                        model.selectedSourceID == source.id ? GXTheme.gold.opacity(0.8) : Color.clear,
                                        lineWidth: 1.5
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
