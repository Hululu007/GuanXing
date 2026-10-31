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

    var filteredItems: [VodItem] {
        guard let filterSourceID else { return items }
        return items.filter { $0.sourceID == filterSourceID }
    }

    var sourceCounts: [SourceCount] {
        outcomes.compactMap { outcome -> SourceCount? in
            guard !outcome.items.isEmpty else { return nil }
            return SourceCount(source: outcome.source, count: outcome.items.count)
        }
    }

    func search(_ text: String, app: AppModel) async {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        keyword = value
        isSearching = true
        hasSearched = true
        errorMessage = nil
        filterSourceID = nil
        defer { isSearching = false }
        let result = await SearchService.search(keyword: value, sources: app.enabledSources)
        items = result.items
        outcomes = result.outcomes
        if items.isEmpty {
            let failures = result.outcomes.filter { $0.error != nil }
            if failures.count == result.outcomes.count, !failures.isEmpty {
                errorMessage = "所有源都没有响应。可以稍后重试，或在设置里更换源。"
            }
        }
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
        .task {
            if let seed = router.searchSeed {
                router.searchSeed = nil
                model.keyword = seed
                await model.search(seed, app: app)
            }
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
                    Task { await model.search(model.keyword, app: app) }
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
                Task { await model.search(model.keyword, app: app) }
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
                            Task { await model.search(suggestion, app: app) }
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
            if model.isSearching {
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
