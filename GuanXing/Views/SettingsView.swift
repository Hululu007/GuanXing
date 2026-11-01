import SwiftUI
import GuanXingCore

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router
    @State private var showResetConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                sourceSection
                playbackSection(app: app)
                dataSection
                aboutSection
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
        .gxScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("恢复全部初始设置？", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("恢复默认", role: .destructive) {
                app.factoryReset()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将清空导入的源、收藏与观看记录，并把内置源恢复到目录最新版。")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("设置")
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(.white)
            Text("管理片源、播放偏好与本地数据")
                .font(.caption)
                .foregroundStyle(GXTheme.secondaryText)
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "片源")
            actionCard(
                icon: "antenna.radiowaves.left.and.right",
                title: "源管理",
                subtitle: "\(app.sources.count) 个点播源 · \(app.liveSources.count) 个直播源 · 内置 \(app.builtinSourceCount)",
                accent: GXTheme.gold
            ) {
                router.push(.sourceManager)
            }
            actionCard(
                icon: "arrow.triangle.2.circlepath",
                title: app.hasBuiltinCatalogUpdate ? "内置源有新版" : "更新内置源",
                subtitle: app.hasBuiltinCatalogUpdate
                    ? "当前 \(app.settings.builtinCatalogVersion) → 目录 \(BuiltinSources.catalogVersion)"
                    : "目录 \(BuiltinSources.catalogVersion) · 验证于 \(BuiltinSources.verifiedAt)",
                accent: app.hasBuiltinCatalogUpdate ? GXTheme.success : GXTheme.comet
            ) {
                let result = app.restoreBuiltinSources()
                app.setImportAlert(
                    title: "内置源已更新",
                    message: "新增 \(result.added) 个，移出 \(result.removed) 个失效条目。",
                    detail: "验证日期 \(BuiltinSources.verifiedAt)，共 \(BuiltinSources.verifiedAvailableCount) 个可用源。"
                )
            }
            actionCard(
                icon: "square.and.arrow.down",
                title: "导入配置",
                subtitle: "TVBox / LibreTV JSON、M3U、远程链接或文件",
                accent: GXTheme.comet
            ) {
                router.push(.importCenter)
            }
            actionCard(
                icon: "waveform.path.ecg",
                title: "检测源状态",
                subtitle: app.isRefreshingHealth ? "正在检测…" : "检查当前启用的点播源",
                accent: GXTheme.success
            ) {
                Task { await app.checkAllHealth() }
            }
        }
    }

    private func playbackSection(app: AppModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "播放偏好")
            VStack(spacing: 0) {
                settingToggle(
                    icon: "play.rectangle",
                    title: "自动播放",
                    detail: "打开详情页后自动开始播放",
                    isOn: Binding(
                        get: { app.settings.autoPlay },
                        set: { app.settings.autoPlay = $0; app.save() }
                    )
                )
                Divider().overlay(GXTheme.stroke)
                settingToggle(
                    icon: "arrow.right.to.line",
                    title: "自动下一集",
                    detail: "剧集播放结束后连续播放",
                    isOn: Binding(
                        get: { app.settings.autoNext },
                        set: { app.settings.autoNext = $0; app.save() }
                    )
                )
                Divider().overlay(GXTheme.stroke)
                settingToggle(
                    icon: "clock.arrow.circlepath",
                    title: "记住播放进度",
                    detail: "下次从上次停下的地方继续",
                    isOn: Binding(
                        get: { app.settings.rememberProgress },
                        set: { app.settings.rememberProgress = $0; app.save() }
                    )
                )
                Divider().overlay(GXTheme.stroke)
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("默认倍速")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                        Text("进入播放器时使用的速度")
                            .font(.caption2)
                            .foregroundStyle(GXTheme.secondaryText)
                    }
                    Spacer()
                    Picker("倍速", selection: Binding(
                        get: { app.settings.defaultSpeed },
                        set: { app.settings.defaultSpeed = $0; app.save() }
                    )) {
                        ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { value in
                            Text(value == floor(value) ? "\(Int(value))x" : "\(value)x")
                                .tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(GXTheme.gold)
                }
                .padding(.vertical, 10)
            }
            .padding(.horizontal, 14)
            .background(GXTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(GXTheme.stroke, lineWidth: 1))
        }
    }

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "本地数据")
            HStack(spacing: 10) {
                dataTile(value: "\(app.favorites.count)", label: "收藏")
                dataTile(value: "\(app.history.count)", label: "记录")
                dataTile(value: "\(app.favoriteChannels.count)", label: "频道")
            }
            Button {
                showResetConfirm = true
            } label: {
                Label("恢复默认设置", systemImage: "arrow.counterclockwise")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(GXTheme.danger)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(GXTheme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(GXTheme.danger.opacity(0.25), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "关于")
            actionCard(
                icon: "sparkles",
                title: "关于观星",
                subtitle: "版本 1.0.0 · 致敬 LibreTV 与 TVBox",
                accent: GXTheme.gold
            ) {
                router.push(.about)
            }
        }
    }

    private func actionCard(
        icon: String,
        title: String,
        subtitle: String,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: 36, height: 36)
                    .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(GXTheme.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(GXTheme.secondaryText)
            }
            .gxCard(padding: 13, radius: 14)
        }
        .buttonStyle(.plain)
    }

    private func settingToggle(
        icon: String,
        title: String,
        detail: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(GXTheme.gold)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(GXTheme.secondaryText)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(GXTheme.gold)
        }
        .padding(.vertical, 10)
    }

    private func dataTile(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(GXTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .gxCard(padding: 12, radius: 13)
    }
}
