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
    @State private var editing: VodSource?
    @State private var editName = ""
    @State private var editAPI = ""
    @State private var editDetail = ""
    @State private var showRestoreDeletedConfirm = false

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
        .sheet(item: $editing) { source in
            editSourceSheet(source)
                .presentationDetents([.medium, .large])
                .presentationBackground(GXTheme.background)
        }
        .confirmationDialog("把之前删掉的内置源全部找回来？", isPresented: $showRestoreDeletedConfirm, titleVisibility: .visible) {
            Button("恢复全部内置源") {
                let result = app.restoreBuiltinSources(includeDeleted: true)
                app.setImportAlert(
                    title: "内置源已恢复",
                    message: "新增 \(result.added) 个，移出 \(result.removed) 个失效条目。",
                    detail: "目录版本 \(BuiltinSources.catalogVersion)，验证日期 \(BuiltinSources.verifiedAt)"
                )
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("内置源可以随时删除、改名或换成其他接口；这里会把它们恢复成官方目录的样子。")
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("片源配置")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("内置 \(app.builtinSourceCount) 个点播源，均已实测可用；随时可停用、改地址或删除。")
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
                Label("目录 \(BuiltinSources.catalogVersion)", systemImage: "shippingbox")
                Text("·")
                Text("验证 \(BuiltinSources.verifiedAt)")
                if app.hasBuiltinCatalogUpdate {
                    Pill(text: "可更新")
                }
            }
            .font(.caption2)
            .foregroundStyle(app.hasBuiltinCatalogUpdate ? GXTheme.gold : GXTheme.secondaryText)

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

            HStack(spacing: 8) {
                Button {
                    let result = app.restoreBuiltinSources()
                    app.setImportAlert(
                        title: "内置源已更新",
                        message: "新增 \(result.added) 个，移出 \(result.removed) 个失效条目。",
                        detail: "之前手动删掉的内置源会保持删除；要全部找回用下面那个按钮。"
                    )
                } label: {
                    Label("更新内置源", systemImage: "arrow.down.circle")
                }
                .buttonStyle(GXSecondaryButtonStyle())

                Button {
                    showRestoreDeletedConfirm = true
                } label: {
                    Label("恢复全部", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(GXSecondaryButtonStyle())
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
                    message: "内置源都删了也没关系，可以一键恢复，也可以导入 TVBox 配置。",
                    actionTitle: "恢复内置源"
                ) {
                    let result = app.restoreBuiltinSources(includeDeleted: true)
                    app.setImportAlert(
                        title: "内置源已恢复",
                        message: "新增 \(result.added) 个日常可用的点播源。"
                    )
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
                                    Pill(text: app.isBuiltinSourceModified(source) ? "已换" : "内置")
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
                    .contentShape(Rectangle())
                    .onTapGesture { beginEdit(source) }
                    .gxCard(padding: 11, radius: 14)
                    .contextMenu {
                        Button {
                            beginEdit(source)
                        } label: {
                            Label("修改／替换地址", systemImage: "square.and.pencil")
                        }
                        Button {
                            Task {
                                let result = await SourceClient(source: source).healthCheck()
                                app.health[source.id] = result
                                app.save()
                            }
                        } label: {
                            Label("检测连接", systemImage: "waveform.path.ecg")
                        }
                        if app.isBuiltinSourceModified(source) {
                            Button {
                                if app.restoreBuiltinSource(id: source.id) {
                                    app.setImportAlert(title: "已还原", message: "\(source.name) 已恢复为目录里的官方地址。")
                                }
                            } label: {
                                Label("还原官方地址", systemImage: "arrow.uturn.backward")
                            }
                        }
                        Button(role: .destructive) {
                            app.deleteSource(source)
                            if source.origin == .builtin {
                                app.setImportAlert(
                                    title: "已删除内置源",
                                    message: "\(source.name) 不会被“更新内置源”重新加回，需要时可以恢复全部。"
                                )
                            }
                        } label: {
                            Label("删除源", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func beginEdit(_ source: VodSource) {
        editing = source
        editName = source.name
        editAPI = source.api
        editDetail = source.detailURL ?? ""
    }

    private func editSourceSheet(_ source: VodSource) -> some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("源名称", text: $editName)
                }
                Section("接口地址") {
                    TextField("https://example.com/api.php/provide/vod", text: $editAPI)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("详情页地址（选填）", text: $editDetail)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Text("把这个源指向另一个可用的苹果 CMS 接口即可替换。内置来源改完也不会被自动改回去。")
                        .font(.caption)
                        .foregroundStyle(GXTheme.secondaryText)
                    if source.origin == .builtin {
                        Button {
                            if let canonical = BuiltinSources.canonical(id: source.id) {
                                editName = canonical.name
                                editAPI = canonical.api
                                editDetail = canonical.detailURL ?? ""
                            }
                        } label: {
                            Label("填入官方地址", systemImage: "arrow.uturn.backward")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(GXTheme.background)
            .navigationTitle("修改片源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { editing = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do {
                            try app.updateSource(
                                id: source.id,
                                name: editName,
                                api: editAPI,
                                detail: editDetail.isEmpty ? nil : editDetail
                            )
                            editing = nil
                            app.setImportAlert(title: "已保存", message: "片源地址已更新。")
                        } catch {
                            app.setImportAlert(
                                title: "保存失败",
                                message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                            )
                        }
                    }
                    .foregroundStyle(GXTheme.gold)
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
                Section("直播源地址") {
                    TextField("名称（可选）", text: $newName)
                    TextField("https://example.com/live.m3u", text: $newURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Text("支持 M3U / M3U8、TXT（#genre# 分组频道表）与 JSON 直播列表，导入后自动识别格式。HTTP-FLV 频道在 iOS 上无法直接播放。")
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
