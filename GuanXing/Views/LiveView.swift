import SwiftUI
import GuanXingCore

@MainActor
@Observable
final class LiveModel {
    var channels: [LiveChannel] = []
    var selectedGroup: String?
    var searchText = ""
    var isLoading = false
    var errorMessages: [String] = []
    var hasLoaded = false
    private var storedApp: AppModel?

    func bind(_ app: AppModel) {
        storedApp = app
    }

    var groups: [(String, [LiveChannel])] {
        M3UParser.groupChannels(channels)
    }

    var filteredChannels: [LiveChannel] {
        var result = channels
        if let selectedGroup {
            result = result.filter { ($0.group ?? "未分组") == selectedGroup }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }
        return result
    }

    func load(sources: [LiveSource], force: Bool = false) async {
        if hasLoaded && !force { return }
        isLoading = true
        errorMessages = []
        defer { isLoading = false }
        let result = await LiveService.loadAll(sources: sources)
        channels = result.channels
        errorMessages = result.errors
        hasLoaded = true
        if selectedGroup == nil, let first = groups.first?.0 {
            selectedGroup = first
        }
    }

    func refresh() async {
        guard let storedApp else { return }
        await load(sources: storedApp.enabledLiveSources, force: true)
    }
}

struct LiveView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router
    @State private var model = LiveModel()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                header
                searchField
                if model.isLoading && model.channels.isEmpty {
                    loading
                } else if model.channels.isEmpty {
                    EmptyViewState(
                        icon: "antenna.radiowaves.left.and.right.slash",
                        title: "没有可用频道",
                        message: model.errorMessages.first ?? "在设置中导入 M3U 直播源后即可观看。",
                        actionTitle: "管理直播源"
                    ) {
                        router.push(.sourceManager)
                    }
                } else {
                    groupStrip
                    favoriteStrip
                    channelList
                    if !model.errorMessages.isEmpty {
                        errorNotice
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .gxScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            model.bind(app)
            await model.load(sources: app.enabledLiveSources)
        }
        .refreshable {
            await model.refresh()
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("直播")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                Text("\(app.enabledLiveSources.count) 个源 · \(model.channels.count) 个频道")
                    .font(.caption)
                    .foregroundStyle(GXTheme.secondaryText)
            }
            Spacer()
            Button {
                router.push(.sourceManager)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(GXTheme.surfaceElevated, in: Circle())
                    .overlay(Circle().stroke(GXTheme.stroke, lineWidth: 1))
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(GXTheme.secondaryText)
            TextField("搜索频道", text: $model.searchText)
                .autocorrectionDisabled()
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(GXTheme.secondaryText)
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(GXTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(GXTheme.stroke, lineWidth: 1))
    }

    private var groupStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(model.groups.indices, id: \.self) { index in
                    let group = model.groups[index].0
                    let channels = model.groups[index].1
                    Button {
                        model.selectedGroup = group
                    } label: {
                        HStack(spacing: 5) {
                            Text(group)
                            Text("\(channels.count)")
                                .font(.caption2)
                                .opacity(0.65)
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(model.selectedGroup == group ? Color.black.opacity(0.84) : .white.opacity(0.82))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(model.selectedGroup == group ? GXTheme.gold : GXTheme.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var favoriteStrip: some View {
        if model.searchText.isEmpty, !app.favoriteChannels.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("常看频道")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GXTheme.secondaryText)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(app.favoriteChannels) { favorite in
                            Button {
                                router.push(.livePlayer(favorite.channel))
                            } label: {
                                Text(favorite.channel.name)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.88))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(GXTheme.surface, in: Capsule())
                                    .overlay(Capsule().stroke(GXTheme.gold.opacity(0.35), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var channelList: some View {
        VStack(spacing: 8) {
            if model.filteredChannels.isEmpty {
                EmptyViewState(
                    icon: "magnifyingglass",
                    title: "没有匹配频道",
                    message: "换个关键词试试，或切换到其他分组。"
                )
            } else {
                ForEach(model.filteredChannels) { channel in
                    Button {
                        router.push(.livePlayer(channel))
                    } label: {
                        channelRow(channel)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func channelRow(_ channel: LiveChannel) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(GXTheme.surfaceElevated)
                RemoteImage(url: channel.logo, referer: nil)
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                if channel.logo == nil {
                    Image(systemName: "tv")
                        .font(.caption)
                        .foregroundStyle(GXTheme.gold)
                }
            }
            .frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text(channel.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(channel.group ?? "未分组")
                    Text("·")
                    Text(channel.sourceName)
                }
                .font(.caption2)
                .foregroundStyle(GXTheme.secondaryText)
                .lineLimit(1)
            }
            Spacer()
            if app.isFavoriteChannel(channel) {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(GXTheme.gold)
            }
            Image(systemName: "play.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(GXTheme.gold.opacity(0.9))
        }
        .gxCard(padding: 10, radius: 14)
    }

    private var errorNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("部分直播源加载失败", systemImage: "exclamationmark.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(GXTheme.gold)
            ForEach(model.errorMessages, id: \.self) { message in
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(GXTheme.secondaryText)
            }
        }
        .gxCard(padding: 12, radius: 12)
    }

    private var loading: some View {
        VStack(spacing: 10) {
            ProgressView().tint(GXTheme.gold)
            Text("正在加载 M3U 频道…")
                .font(.caption)
                .foregroundStyle(GXTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}
