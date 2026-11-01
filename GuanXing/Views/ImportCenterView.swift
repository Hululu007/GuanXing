import SwiftUI
import UniformTypeIdentifiers
import GuanXingCore

struct ImportCenterView: View {
    @Environment(AppModel.self) private var app
    @State private var mode = 0
    @State private var urlText = ""
    @State private var jsonText = ""
    @State private var isWorking = false
    @State private var showFileImporter = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("导入方式", selection: $mode) {
                    Text("远程地址").tag(0)
                    Text("粘贴 JSON").tag(1)
                    Text("本地文件").tag(2)
                }
                .pickerStyle(.segmented)

                switch mode {
                case 0:
                    remoteBlock
                case 1:
                    pasteBlock
                default:
                    fileBlock
                }
                formatHelp
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
        .gxScreenBackground()
        .navigationTitle("导入配置")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.json, .plainText, .data, .m3uPlaylist],
            allowsMultipleSelection: false
        ) { result in
            handleFile(result)
        }
    }

    private var remoteBlock: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("从订阅链接导入")
                .font(.headline)
                .foregroundStyle(.white)
            Text("支持 TVBox 配置、LibreTV-SourceList、接口目录 JSON 与 M3U 直播列表。")
                .font(.caption)
                .foregroundStyle(GXTheme.secondaryText)
            TextField("https://example.com/tvbox.json", text: $urlText, axis: .vertical)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(2...4)
                .padding(12)
                .background(GXTheme.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Button {
                importRemote()
            } label: {
                HStack {
                    if isWorking { ProgressView().tint(Color.black) }
                    Text(isWorking ? "正在导入" : "拉取并导入")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(GXPrimaryButtonStyle())
            .disabled(isWorking || urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .gxCard(padding: 16)
    }

    private var pasteBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("粘贴配置 JSON")
                .font(.headline)
                .foregroundStyle(.white)
            Text("把 TVBox / LibreTV 的配置内容直接贴进来，带注释和尾随逗号也能识别。")
                .font(.caption)
                .foregroundStyle(GXTheme.secondaryText)
            TextEditor(text: $jsonText)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 220)
                .padding(8)
                .background(GXTheme.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Button {
                do {
                    try app.importConfig(text: jsonText, name: "粘贴配置")
                    jsonText = ""
                } catch {
                    app.setImportAlert(
                        title: "解析失败",
                        message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    )
                }
            } label: {
                Text("解析并导入")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GXPrimaryButtonStyle())
            .disabled(jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .gxCard(padding: 16)
    }

    private var fileBlock: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("从本地文件导入")
                .font(.headline)
                .foregroundStyle(.white)
            Text("支持 .json、.txt、.m3u、.m3u8。直播列表会自动识别 M3U、TXT（#genre#）与 JSON，GBK 编码的频道表也能读取。")
                .font(.caption)
                .foregroundStyle(GXTheme.secondaryText)
            Button {
                showFileImporter = true
            } label: {
                Label("选择文件", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GXPrimaryButtonStyle())
        }
        .gxCard(padding: 16)
    }

    private var formatHelp: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "兼容格式")
            formatRow(icon: "square.stack.3d.up", title: "TVBox", detail: "sites 中 type=1 的苹果 CMS 接口；lives 中的 M3U。")
            formatRow(icon: "sparkles.tv", title: "LibreTV", detail: "sources / liveSources 数组，语义与 LibreTV 保持一致。")
            formatRow(icon: "list.bullet.rectangle", title: "接口目录", detail: "裸数组，每项包含 name 与 baseUrl。")
            formatRow(icon: "dot.radiowaves.left.and.right", title: "M3U", detail: "标准播放列表，支持 tvg-logo、group-title 与 EXTGRP。")
            formatRow(icon: "xmark.octagon", title: "不支持", detail: "需要 Spider 引擎的 jar / js / py 源；iOS 无法运行动态脚本。")
        }
        .gxCard(padding: 15)
    }

    private func formatRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(GXTheme.gold)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(GXTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func importRemote() {
        let text = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isWorking = true
        Task {
            await app.importRemote(urlString: text)
            await MainActor.run {
                isWorking = false
                urlText = ""
            }
        }
    }

    private func handleFile(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            app.setImportAlert(title: "读取失败", message: error.localizedDescription)
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                guard let text = TextDecoder.decode(data) else {
                    throw GuanXingError.decode("文件编码无法识别")
                }
                if ConfigLoader.looksLikeLivePlaylist(text) {
                    try app.importLocalPlaylist(
                        text: text,
                        name: url.deletingPathExtension().lastPathComponent
                    )
                } else {
                    try app.importConfig(text: text, name: url.deletingPathExtension().lastPathComponent)
                }
            } catch {
                app.setImportAlert(
                    title: "导入失败",
                    message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                )
            }
        }
    }
}

struct AboutView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [GXTheme.gold.opacity(0.35), GXTheme.surface],
                                    center: .center,
                                    startRadius: 5,
                                    endRadius: 60
                                )
                            )
                            .frame(width: 100, height: 100)
                        Image(systemName: "sparkles")
                            .font(.system(size: 38, weight: .light))
                            .foregroundStyle(GXTheme.gold)
                    }
                    Text("观星")
                        .font(.system(size: 30, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                        .tracking(3)
                    Text("Version 1.0.0")
                        .font(.caption.monospaced())
                        .foregroundStyle(GXTheme.secondaryText)
                }
                .padding(.top, 16)

                Text("把 LibreTV 的聚合搜索体验与 TVBox 的源配置生态，带到 iOS 上。\n所有内容均来自第三方接口，本应用不存储、不传播任何影视资源。")
                    .font(.subheadline)
                    .foregroundStyle(GXTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .padding(.horizontal, 12)

                VStack(spacing: 0) {
                    aboutRow(label: "内置点播源", value: "\(app.sources.filter { $0.origin == .builtin }.count)")
                    Divider().overlay(GXTheme.stroke)
                    aboutRow(label: "导入点播源", value: "\(app.sources.filter { $0.origin != .builtin }.count)")
                    Divider().overlay(GXTheme.stroke)
                    aboutRow(label: "直播源", value: "\(app.liveSources.count)")
                    Divider().overlay(GXTheme.stroke)
                    aboutRow(label: "解析接口", value: "\(app.parsers.count)")
                }
                .padding(.horizontal, 14)
                .background(GXTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    Text("技术与致谢")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GXTheme.secondaryText)
                    Text("SwiftUI · AVPlayer · 苹果 CMS · TVBox 配置兼容")
                    Text("参考 LibreTV（AGPL-3.0）的产品思路与数据格式；借鉴 DpadTV、TVBox-tvs 的直播源格式与交互设计。解析与播放代码均为独立 Swift 实现。")
                }
                .font(.caption)
                .foregroundStyle(GXTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .gxCard(padding: 15)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
        .gxScreenBackground()
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func aboutRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.88))
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(GXTheme.gold)
        }
        .padding(.vertical, 12)
    }
}
