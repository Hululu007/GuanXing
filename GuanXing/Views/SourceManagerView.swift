import SwiftUI
import GuanXingCore
import UniformTypeIdentifiers

struct SourceManagerView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router
    @State private var tab = 0
    @State private var showAddSource = false
    @State private var showAddLive = false
    @State private var newName = ""
    @State private var newURL = ""
    @State private var newDetail = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summary
                Picker("类型", selection: $tab) {
                    Text("点播源").tag(0)
                    Text("直播源").tag(1)
                }
                .pickerStyle(.segmented)

                if tab == 0 {
                    vodSourceList
                } else {
                    liveSourceList
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
        .gxScreenBackground()
        .navigationTitle("源管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newName = ""
                    newURL = ""
                    newDetail = ""
                    if tab == 0 { showAddSource = true } else { showAddLive = true }
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(GXTheme.gold)
                }
            }
        }
        .sheet(isPresented: $showAddSource) {
            addSourceSheet
                .presentationDetents([.medium])
                .presentationBackground(GXTheme.background)
        }
        .sheet(isPresented: $showAddLive) {
            addLiveSheet
                .presentationDetents([.medium])
                .presentationBackground(GXTheme.background)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("片源配置")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("支持苹果 CMS / TVBox 直连接口，Spider 源无法在 iOS 运行。")
                        .font(.caption)
                        .foregroundStyle(GXTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.title2)
                    .foregroundStyle(GXTheme.gold)
            }
            HStack(spacing: 8) {
                Button {
                    router.push(.importCenter)
                } label: {
                    Label("导入配置", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(GXPrimaryButtonStyle())
                Button {
                    Task { await app.checkAllHealth() }
                } label: {
                    Label(app.isRefreshingHealth ? "检测中" : "检测", systemImage: "waveform.path.ecg")
                }
                .buttonStyle(GXSecondaryButtonStyle())
                .disabled(app.isRefreshingHealth)
            }
        }
        .gxCard(padding: 16)
    }

    private var vodSourceList: some View {
        VStack(spacing: 8) {
            if app.sources.isEmpty {
                EmptyViewState(
                    icon: "antenna.radiowaves.left.and.right.slash",
                    title: "还没有点播源",
                    message: "导入 TVBox / LibreTV 配置，或手动添加一个苹果 CMS 接口。",
                    actionTitle: "导入配置"
                ) {
                    router.push(.importCenter)
                }
            } else {
                ForEach(app.sources) { source in
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(GXTheme.surfaceElevated)
                            Text(String(source.name.prefix(1)))
                                .font(.headline)
                                .foregroundStyle(GXTheme.gold)
                        }
                        .frame(width: 42, height: 42)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(source.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                if source.origin == .builtin {
                                    Pill(text: "内置")
                                }
                            }
                            Text(source.host)
                                .font(.caption2)
                                .foregroundStyle(GXTheme.secondaryText)
                                .lineLimit(1)
                            SourceHealthBadge(health: app.health[source.id])
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { source.isEnabled },
                            set: { _ in app.toggleSource(source) }
                        ))
                        .labelsHidden()
                        .tint(GXTheme.gold)
                    }
                    .gxCard(padding: 11, radius: 14)
                    .contextMenu {
                        Button {
                            Task {
                                let result = await CMSClient(source: source).healthCheck()
                                app.health[source.id] = result
                                app.save()
                            }
                        } label: {
                            Label("检测连接", systemImage: "waveform.path.ecg")
                        }
                        Button(role: .destructive) {
                            app.deleteSource(source)
                        } label: {
                            Label("删除源", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private var liveSourceList: some View {
        VStack(spacing: 8) {
            if app.liveSources.isEmpty {
                EmptyViewState(
                    icon: "tv.slash",
                    title: "还没有直播源",
                    message: "添加 M3U 播放列表后，就可以在这里按分组浏览频道。"
                )
            } else {
                ForEach(app.liveSources) { source in
                    HStack(spacing: 12) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.subheadline)
                            .foregroundStyle(GXTheme.comet)
                            .frame(width: 42, height: 42)
                            .background(GXTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)
                            Text(source.url)
                                .font(.caption2)
                                .foregroundStyle(GXTheme.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { source.isEnabled },
                            set: { _ in app.toggleLiveSource(source) }
                        ))
                        .labelsHidden()
                        .tint(GXTheme.gold)
                    }
                    .gxCard(padding: 11, radius: 14)
                    .contextMenu {
                        Button(role: .destructive) {
                            app.deleteLiveSource(source)
                        } label: {
                            Label("删除源", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private var addSourceSheet: some View {
        NavigationStack {
            Form {
                Section("点播接口") {
                    TextField("名称（可选）", text: $newName)
                    TextField("https://example.com/api.php/provide/vod", text: $newURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("详情页地址（可选）", text: $newDetail)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Text("需要是苹果 CMS V10 的 JSON 接口。带 Spider / jar / js 的 TVBox 源无法在 iOS 上运行。")
                        .font(.caption)
                        .foregroundStyle(GXTheme.secondaryText)
                }
            }
            .scrollContentBackground(.hidden)
            .background(GXTheme.background)
            .navigationTitle("添加点播源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showAddSource = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        do {
                            try app.addSource(name: newName, api: newURL, detail: newDetail.isEmpty ? nil : newDetail)
                            showAddSource = false
                            app.setImportAlert(title: "已添加", message: "点播源已加入列表。")
                        } catch {
                            app.setImportAlert(title: "添加失败", message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                        }
                    }
                    .foregroundStyle(GXTheme.gold)
                }
            }
        }
    }

    private var addLiveSheet: some View {
        NavigationStack {
            Form {
                Section("M3U 直播列表") {
                    TextField("名称（可选）", text: $newName)
                    TextField("https://example.com/live.m3u", text: $newURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Text("支持标准 M3U / M3U8 播放列表。HTTP-FLV 频道在 iOS 上无法直接播放。")
                        .font(.caption)
                        .foregroundStyle(GXTheme.secondaryText)
                }
            }
            .scrollContentBackground(.hidden)
            .background(GXTheme.background)
            .navigationTitle("添加直播源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showAddLive = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        do {
                            try app.addLiveSource(name: newName, url: newURL)
                            showAddLive = false
                            app.setImportAlert(title: "已添加", message: "直播源已加入列表。")
                        } catch {
                            app.setImportAlert(title: "添加失败", message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                        }
                    }
                    .foregroundStyle(GXTheme.gold)
                }
            }
        }
    }
}
