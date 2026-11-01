import SwiftUI
import GuanXingCore

@MainActor
@Observable
final class SearchModel {
    struct SourceCount: Identifiable {
        let source: VodSource
        let count: Int
        var id: String { source.id }
    }

    var keyword = ""
    var items: [VodItem] = []
    var outcomes: [SearchOutcome] = []
    var isSearching = false
    var hasSearched = false
    var errorMessage: String?
    var filterSourceID: String?
    var groupByTitle = true
    /// 已完成的源数 / 总源数，用于展示进度。
    var finishedCount = 0
    var totalCount = 0
    private var runToken = 0
    private var inFlight: Task<Void, Never>?

    var filteredItems: [VodItem] {
        guard let filterSourceID else { return items }
        return items.filter { $0.sourceID == filterSourceID }
    }

    var titleGroups: [TitleGroup] {
        TitleGrouper.group(filteredItems)
    }

    var mergedGroupCount: Int {
        titleGroups.filter { $0.sourceCount > 1 }.count
    }

    var sourceCounts: [SourceCount] {
        outcomes.compactMap { outcome -> SourceCount? in
            guard !outcome.items.isEmpty else { return nil }
            return SourceCount(source: outcome.source, count: outcome.items.count)
        }
    }

    /// 取消当前这轮搜索，已经出来的结果保留。
    func cancel() {
        runToken &+= 1
        inFlight?.cancel()
        inFlight = nil
        isSearching = false
    }

    /// 发起一轮新搜索，自动停掉上一轮。
    func search(_ text: String, app: AppModel) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }

        inFlight?.cancel()
        runToken &+= 1
        let token = runToken

        keyword = value
        hasSearched = true
        errorMessage = nil
        filterSourceID = nil
        items = []
        outcomes = []
        finishedCount = 0

        let targets = app.enabledSources.filter { $0.isSearchable && !$0.isAdult }
        totalCount = targets.count

        guard !targets.isEmpty else {
            isSearching = false
            errorMessage = "没有启用中的可搜索片源，先去片源管理开一些。"
            return
        }

        isSearching = true
        // 哪个源先回来先上屏，不再等最慢的那个。
        inFlight = Task { @MainActor [weak self] in
            for await outcome in SearchService.stream(keyword: value, sources: targets) {
                guard let self, !Task.isCancelled, token == self.runToken else { return }
                self.finishedCount += 1
                self.apply(outcome)
            }
            guard let self, !Task.isCancelled, token == self.runToken else { return }
            self.isSearching = false
            if self.items.isEmpty, !self.outcomes.isEmpty,
               self.outcomes.allSatisfy({ $0.error != nil }) {
                self.errorMessage = "所有源都没响应。可以稍后重试，或在设置里更新片源。"
            }
        }
    }

    private func apply(_ outcome: SearchOutcome) {
        outcomes.removeAll { $0.source.id == outcome.source.id }
        outcomes.append(outcome)
        let merged = SearchService.aggregate(outcomes, keyword: keyword)
        outcomes = merged.outcomes
        items = merged.items
    }
}

struct SearchView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router
    @State private var model = SearchModel()
    @FocusState private var focused: Bool

    private let suggestions = ["庆余年", "流浪地球", "繁花", "三体", "沙丘", "甄嬛传", "奥本海默", "狂飙"]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                titleBlock
                searchField
                if !model.hasSearched {
                    suggestionsBlock
                } else {
                    resultBlock
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .gxScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { consumePendingRequest() }
        .onChange(of: router.pendingSearchFocus) { _, pending in
            if pending { consumePendingRequest() }
        }
    }

    private func consumePendingRequest() {
        guard router.pendingSearchFocus || router.searchSeed != nil else { return }
        router.pendingSearchFocus = false
        handleSearchRequest()
    }

    /// 首页右上角的搜索按钮会把请求号加一，
    /// 这里负责清掉旧结果、把光标放回输入框，并在带关键词时直接开搜。
    private func handleSearchRequest() {
        if let seed = router.searchSeed {
            router.searchSeed = nil
            model.keyword = seed
            focused = false
            model.search(seed, app: app)
            return
        }
        model.keyword = ""
        model.hasSearched = false
        model.items = []
        model.outcomes = []
        model.filterSourceID = nil
        model.errorMessage = nil
        // 刚切 tab 的那一帧输入框还没上树，稍微让一步再聚焦。
        focused = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            focused = true
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("全源搜索")
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(.white)
                Text("一次搜索 \(app.enabledSources.count) 个点播源，同一部片在不同源的结果都会保留。")
                .font(.caption)
                .foregroundStyle(GXTheme.secondaryText)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(GXTheme.secondaryText)
            TextField("搜索电影、剧集、综艺或动漫", text: $model.keyword)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit {
                    focused = false
                    model.search(model.keyword, app: app)
                }
            if !model.keyword.isEmpty {
                Button {
                    model.keyword = ""
                    model.hasSearched = false
                    model.items = []
                    model.outcomes = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(GXTheme.secondaryText)
                }
            }
            Button {
                focused = false
                model.search(model.keyword, app: app)
            } label: {
                Text("搜索")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.black.opacity(0.84))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(GXTheme.gold, in: Capsule())
            }
            .disabled(model.isSearching)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(GXTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(focused ? GXTheme.gold.opacity(0.6) : GXTheme.stroke, lineWidth: 1)
        )
    }

    private var suggestionsBlock: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "热搜试试", subtitle: "点击直接开始多源搜索")
                FlowLayout(spacing: 8) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            model.keyword = suggestion
                            model.search(suggestion, app: app)
                        } label: {
                            Text(suggestion)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.86))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(GXTheme.surface, in: Capsule())
                                .overlay(Capsule().stroke(GXTheme.stroke, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "搜索提示", subtitle: "让结果更准")
                searchTip(icon: "textformat", title: "输入完整片名", detail: "例如「庆余年 第二季」比「庆余年」更容易命中。")
                searchTip(icon: "square.stack.3d.up", title: "多源会合并", detail: "同名影片来自不同源，点开后可以比较线路。")
                searchTip(icon: "bolt", title: "失败不影响结果", detail: "个别源超时会自动忽略，其余源的结果仍会展示。")
            }
        }
    }

    private func searchTip(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(GXTheme.gold)
                .frame(width: 30, height: 30)
                .background(GXTheme.gold.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(GXTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var resultBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.isSearching && model.items.isEmpty {
                searchingSkeletons
            } else if model.items.isEmpty {
                EmptyViewState(
                    icon: "moon.stars",
                    title: "没有找到这颗星",
                    message: model.errorMessage ?? "换一个片名试试，或者到设置里加入更多片源。",
                    actionTitle: "去管理片源"
                ) {
                    router.push(.sourceManager)
                }
            } else {
                if model.isSearching {
                    progressLine
                }
                HStack {
                    Text("找到 \(model.items.count) 个结果")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("来自 \(model.sourceCounts.count) 个源")
                        .font(.caption)
                        .foregroundStyle(GXTheme.secondaryText)
                }
                sourceFilterStrip
                groupingBar
                if model.groupByTitle {
                    groupedResults
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 108), spacing: 12)],
                        spacing: 18
                    ) {
                        ForEach(model.filteredItems) { item in
                            Button {
                                router.push(.detail(item))
                            } label: {
                                PosterCard(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var groupingBar: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    model.groupByTitle.toggle()
                }
            } label: {
                Label(
                    model.groupByTitle ? "按片名合并" : "平铺结果",
                    systemImage: model.groupByTitle ? "rectangle.stack" : "square.grid.2x2"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(model.groupByTitle ? Color.black.opacity(0.84) : .white.opacity(0.82))
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(model.groupByTitle ? GXTheme.gold : GXTheme.surface, in: Capsule())
            }
            .buttonStyle(.plain)
            if model.groupByTitle, model.mergedGroupCount > 0 {
                Text("\(model.mergedGroupCount) 部有多个源")
                    .font(.caption2)
                    .foregroundStyle(GXTheme.secondaryText)
            }
            Spacer(minLength: 0)
        }
    }

    private var groupedResults: some View {
        LazyVStack(spacing: 10) {
            ForEach(model.titleGroups) { group in
                titleGroupCard(group)
            }
        }
    }

    private func titleGroupCard(_ group: TitleGroup) -> some View {
        Button {
            if let primary = group.primary {
                router.push(.detail(primary))
            }
        } label: {
            HStack(spacing: 12) {
                RemoteImage(url: group.primary?.pic)
                    .frame(width: 66, height: 92)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(group.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let meta = group.primary?.displayMeta, !meta.isEmpty {
                        Text(meta)
                            .font(.caption2)
                            .foregroundStyle(GXTheme.secondaryText)
                            .lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        Text("\(group.sourceCount) 个源")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(group.sourceCount > 1 ? GXTheme.gold : GXTheme.secondaryText)
                        if group.items.count != group.sourceCount {
                            Text("· \(group.items.count) 条线路")
                                .font(.caption2)
                                .foregroundStyle(GXTheme.secondaryText)
                        }
                    }
                    if let remarks = group.primary?.remarks, !remarks.isEmpty {
                        Text(remarks)
                            .font(.caption2)
                            .foregroundStyle(GXTheme.secondaryText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GXTheme.secondaryText)
            }
            .gxCard(padding: 10, radius: 14)
        }
        .buttonStyle(.plain)
    }

    /// 搜索进行中的轻提示：已经回来多少个源。
    private var progressLine: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(GXTheme.gold)
            Text("正在搜索，已完成 \(model.finishedCount)/\(model.totalCount) 个源")
                .font(.caption)
                .foregroundStyle(GXTheme.secondaryText)
            Spacer(minLength: 0)
            Button("停止") {
                model.cancel()
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(GXTheme.gold)
        }
        .padding(.vertical, 2)
    }

    private var sourceFilterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                filterChip(title: "全部", count: model.items.count, id: nil)
                ForEach(model.sourceCounts) { item in
                    filterChip(title: item.source.name, count: item.count, id: item.source.id)
                }
            }
        }
    }

    private func filterChip(title: String, count: Int, id: String?) -> some View {
        let selected = model.filterSourceID == id
        return Button {
            model.filterSourceID = id
        } label: {
            HStack(spacing: 5) {
                Text(title)
                Text("\(count)")
                    .font(.caption2)
                    .foregroundStyle(selected ? Color.black.opacity(0.6) : GXTheme.secondaryText)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(selected ? Color.black.opacity(0.84) : .white.opacity(0.82))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(selected ? GXTheme.gold : GXTheme.surface, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var searchingSkeletons: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                ProgressView().tint(GXTheme.gold)
                Text("正在并行搜索多个片源…")
                    .font(.subheadline)
                    .foregroundStyle(GXTheme.secondaryText)
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 108), spacing: 12)],
                spacing: 18
            ) {
                ForEach(0..<6, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(GXTheme.surface)
                            .frame(height: 152)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(GXTheme.surface)
                            .frame(height: 12)
                    }
                }
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
