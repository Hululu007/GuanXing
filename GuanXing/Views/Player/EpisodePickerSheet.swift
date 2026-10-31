import SwiftUI
import GuanXingCore

struct EpisodePickerSheet: View {
    let model: PlayerModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLine = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    lineSection
                    episodeSection
                }
                .padding(18)
            }
            .gxScreenBackground()
            .navigationTitle("选集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(GXTheme.gold)
                }
            }
            .onAppear {
                selectedLine = model.currentLineIndex
            }
        }
        .presentationBackground(GXTheme.background)
    }

    private var lineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("播放线路")
                .font(.headline)
                .foregroundStyle(.white)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.detail.lines.indices, id: \.self) { index in
                        Button {
                            selectedLine = index
                        } label: {
                            Text(model.detail.lines[index].name)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(selectedLine == index ? Color.black.opacity(0.84) : .white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selectedLine == index ? GXTheme.gold : GXTheme.surface, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var episodeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("选集")
                .font(.headline)
                .foregroundStyle(.white)
            let episodes = model.detail.lines.indices.contains(selectedLine)
                ? model.detail.lines[selectedLine].episodes
                : []
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 54), spacing: 8)], spacing: 8) {
                ForEach(episodes.indices, id: \.self) { index in
                    let episode = episodes[index]
                    let current = selectedLine == model.currentLineIndex && index == model.currentEpisodeIndex
                    Button {
                        model.select(line: selectedLine, episode: index)
                        dismiss()
                    } label: {
                        Text(episode.name)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(current ? Color.black.opacity(0.84) : Color.white.opacity(0.86))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(
                                current ? GXTheme.gold : GXTheme.surface,
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
