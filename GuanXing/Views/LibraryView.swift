import SwiftUI
import GuanXingCore

struct LibraryView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router
    @State private var mode = 0
    @State private var showClearHistoryAlert = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                header
                Picker("内容", selection: $mode) {
                    Text("收藏").tag(0)
                    Text("观看记录").tag(1)
                    Text("直播收藏").tag(2)
                }
                .pickerStyle(.segmented)

                switch mode {
                case 0:
                    favorites
                case 1:
                    history
                default:
                    liveFavorites
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .gxScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .alert("清空全部观看记录？", isPresented: $showClearHistoryAlert) {
            Button("清空", role: .destructive) { app.clearHistory() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("共 \(app.history.count) 条记录，清空后无法恢复。")
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("片库")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                Text("\(app.favorites.count) 个收藏 · \(app.history.count) 条记录")
                    .font(.caption)
                    .foregroundStyle(GXTheme.secondaryText)
            }
            Spacer()
            if mode == 1 && !app.history.isEmpty {
                Button("清空") {
                    showClearHistoryAlert = true
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(GXTheme.secondaryText)
                .buttonStyle(.plain)
                .padding(.vertical, 8)
                .padding(.leading, 12)
                .contentShape(Rectangle())
            }
        }
    }

    @ViewBuilder
    private var favorites: some View {
        if app.favorites.isEmpty {
            EmptyViewState(
                icon: "star",
                title: "还没有收藏",
                message: "在详情页点亮星标，想看的片就会出现在这里。"
            )
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 168), spacing: 10)], spacing: 18) {
                ForEach(app.favorites) { favorite in
                    Button {
                        router.push(.detail(favorite.item))
                    } label: {
                        PosterCard(item: favorite.item)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            app.toggleFavorite(favorite.item)
                        } label: {
                            Label("取消收藏", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var history: some View {
        if app.history.isEmpty {
            EmptyViewState(
                icon: "clock.arrow.circlepath",
                title: "还没有观看记录",
                message: "开始播放后，会在这里保留集数与进度。"
            )
        } else {
            VStack(spacing: 10) {
                ForEach(app.history) { entry in
                    Button {
                        // 直接续播：跳过详情页，从上次的集数与秒数接着放。
                        router.push(.resume(entry))
                    } label: {
                        HStack(spacing: 12) {
                            RemoteImage(url: entry.item.pic)
                                .frame(width: 58, height: 82)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(entry.item.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text("\(entry.lineName) · \(entry.episodeName)")
                                    .font(.caption2)
                                    .foregroundStyle(GXTheme.secondaryText)
                                    .lineLimit(1)
                                ProgressView(value: entry.progress)
                                    .tint(GXTheme.gold)
                                    .scaleEffect(x: 1, y: 0.7, anchor: .center)
                                Text("已看 \(Int(entry.progress * 100))%")
                                    .font(.caption2)
                                    .foregroundStyle(GXTheme.gold.opacity(0.85))
                            }
                            Spacer()
                            Image(systemName: "play.circle")
                                .font(.title3)
                                .foregroundStyle(GXTheme.gold)
                        }
                        .gxCard(padding: 10, radius: 14)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            router.push(.detail(entry.item))
                        } label: {
                            Label("查看详情", systemImage: "info.circle")
                        }
                        Button(role: .destructive) {
                            app.history.removeAll { $0.id == entry.id }
                            app.save()
                        } label: {
                            Label("移除记录", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var liveFavorites: some View {
        if app.favoriteChannels.isEmpty {
            EmptyViewState(
                icon: "dot.radiowaves.left.and.right",
                title: "还没有常看频道",
                message: "在直播播放页点亮星标，常看的频道会集中在这里。"
            )
        } else {
            VStack(spacing: 8) {
                ForEach(app.favoriteChannels) { favorite in
                    Button {
                        router.push(.livePlayer(favorite.channel))
                    } label: {
                        HStack(spacing: 12) {
                            RemoteImage(url: favorite.channel.logo)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(favorite.channel.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.white)
                                Text(favorite.channel.sourceName)
                                    .font(.caption2)
                                    .foregroundStyle(GXTheme.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "play.circle.fill")
                                .foregroundStyle(GXTheme.gold)
                        }
                        .gxCard(padding: 10, radius: 14)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            app.toggleFavoriteChannel(favorite.channel)
                        } label: {
                            Label("取消收藏", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
}
