# TVBox-tvs（TVS）拆解

> 分析对象：<https://github.com/yuluoos/TVBox-tvs>  
> 快照：`c5745f6`（2026-10-27，`Release tvs 1.2.6 with local player`），单一 squashed 提交  
> 许可证：MIT（仅覆盖仓库内实际存在的内容）

## 一句话结论

这是一个**只公开文档、发布脚本与下载站，不公开应用源码**的仓库：19 个文件、2022 行，没有一行 Dart/Kotlin/Swift 业务代码。可复用的是它写清楚的**三种直播源格式规范**和**发布工程做法**，不是播放器实现。

## 仓库实际构成

| 部分 | 文件 | 说明 |
| --- | --- | --- |
| 说明 | `README.md`（13 KB） | 功能清单、技术栈、下载表、版本记录、已知限制 |
| 下载站 | `docs/*.html`（6 页）+ `style.css` | GitHub Pages 站点：首页、iOS、Android TV、macOS、订阅、直播源 |
| 图片 | `docs/assets/tg-group-qr.jpeg` | TG 群二维码 |
| 发布脚本 | `scripts/release.sh`（154 行） | 一条命令完成构建 → 校验 → 改文档 → 提交 → 建 Release |
| 文档生成 | `scripts/update_readme.py`、`update_site.py` | 按 `artifacts.json` 重写 README 下载区与站点下载块 |
| 链接工具 | `scripts/download_links.py` | GitHub 原链 + GHFast / GH-Proxy 两个加速前缀 |
| 测试 | `scripts/tests/test_release_pages.py`（172 行） | 用 unittest 校验下载页与 Release Notes 的链接、SHA-256、旧版本清理 |

**不存在**：`lib/`、`pubspec.yaml`、任何 `*.dart`、任何原生工程文件。`release.sh` 里引用的 `$TVS_SRC`（默认 `~/Desktop/GIt/tvs`）是作者本机的私有 Flutter 工程，不在仓库内。

## 它声称的产品能力（来自 README / docs，未经源码验证）

- 平台：Android / Android TV / 电视盒子 / iOS / iPadOS / macOS（Apple Silicon）。
- 技术栈：Flutter + `yl_player`（视频，内置 libmpv）+ `just_audio` / `audio_service`（音频）+ 本地 Node.js 服务跑 nodejs 类型 spider 源 + Isar 数据库。
- 点播订阅：只吃「羊壳（PeekPro）」格式，**明确不支持 TVBox 原生接口配置**。
- 直播：识别 **M3U / TXT（`#genre#`）/ JSON** 三种通用格式，独立直播播放页，支持多线路、台标、播放模式选择。
- 播放器：片头片尾跳过、m3u8 疑似广告分片过滤、断点续播、倍速、手势调节、加载时显示下载速度。
- 其它：听剧（后台/息屏）、云盘目录浏览与图片/PDF/文本预览、D-pad 遥控器适配。
- 内置本地 HTTP 代理：台标防盗链、请求头转发、m3u8 分片过滤；重定向逐跳保留自定义请求头（1.1.2 修复）。

## 三种直播源格式（可直接对标的规范）

### 1. M3U / M3U8

```text
#EXTM3U
#EXTINF:-1 tvg-name="频道名" tvg-logo="https://.../logo.png" group-title="央视",频道名
http://example.com/stream.m3u8
```

`group-title` 决定分组，`tvg-logo` 决定台标。

### 2. TXT（`#genre#` 分组）

```text
央视,#genre#
CCTV-1,http://example.com/cctv1.m3u8
CCTV-2,http://example.com/cctv2.m3u8
卫视,#genre#
湖南卫视,http://example.com/hunan.m3u8
```

`分组名,#genre#` 单独成行开启一个分组，其后每行是 `频道名,播放地址`。

### 3. JSON

文档只写「结构化的 JSON 直播源同样支持，导入后一样会解析出分组与频道列表」，**没有给出 schema**。这是它最含糊的一处，也说明各家 JSON 结构并不统一。

## 失败排查表（原文归纳）

| 现象 | 原因 |
| --- | --- |
| 导入后没有任何频道 | 格式不在这三种之内，或内容为空 / 地址已失效 |
| 有频道列表但全部播不了 | 网络环境、限流、组播地址不可达 |
| 个别频道卡顿 | 单流服务端问题，换同名线路 |
| 台标不显示 | 源里没写 `tvg-logo`，或 logo 已失效 |
| 分组全挤在一起 | 源本身没有 `group-title` / `#genre#` |

## 工程做法里值得借鉴的点

1. **发布流水线即文档流水线**：`release.sh` 先校验 `pubspec.yaml` 版本与传入版本一致、工作区干净，再构建三平台产物，算 SHA-256 写入 `artifacts.json`，然后用脚本把 README 下载区、站点下载块整体重写，最后 `gh release create`。文档不会和产物脱节。
2. **版本号强一致**：`pubspec.yaml` → 文件名 → tag → 文档表格，全部由脚本串起来，人只输入一次版本号。
3. **多线路下载**：每个产物都同时给 GitHub 原链与两个第三方加速前缀，并在文档里明确「第三方加速，速度因地区而异」。
4. **发布页有测试**：`test_release_pages.py` 断言每个产物的原链与两个镜像链接都存在、SHA-256 出现在页面上、旧版本号被清理干净。文档回归也能被测。
5. **已知限制直接写在下载页首屏**：1.2.6 首页就写明「本地开发版播放器，仍有未闭环的格式播放、部分 iOS 解码/输出及自动码率恢复验收问题」。不藏。

## 与观星（GuanXing）的关系

已吸收：

- 三种直播源格式自动识别（`LivePlaylist.detect` / `parse`），TXT 支持 `#genre#` 分组、无分组、注释、一行多地址、去重。
- 编码兜底：国内频道表常见 GBK，`TextDecoder` 走 UTF-8 → UTF-16(BOM) → GB18030 → GB2312 → Latin-1。
- 独立的直播播放页（观星本来就是 `LivePlayerView` + `PlayerView` 两套）。
- 刷新失败保留已有频道（对应它「刷新失败时保留已有频道」的描述）。

**没有**吸收，也不打算吸收：

- 羊壳（PeekPro）订阅格式：私有格式，且与观星已有的 TVBox / LibreTV / 苹果 CMS 生态冲突。
- 内嵌 Node.js 跑 spider 源：iOS 上无法上架，也与「原生 AVPlayer」的定位不符。
- libmpv：观星坚持系统 AVPlayer，换取体积、后台与系统级 HDR/杜比能力。

## 需要说清的边界

- 仓库是 MIT，但**MIT 只覆盖它真正发布的文件**（文档、脚本）。应用本体闭源，无法从中复制任何播放器代码，也不存在「移植 TVS 播放内核」这回事。
- 它的 Releases（APK/IPA/DMG，1.2.6 各约 30–36 MB，单版本下载量数百到近千）是真实产物；仓库只是发布门面。
- 本文档中所有「它支持 X」都来自其自述，未经独立验证。

## 参考

- 仓库：<https://github.com/yuluoos/TVBox-tvs>
- 下载站：<https://yuluoos.github.io/TVBox-tvs/>
- 直播源说明原文：`docs/live.html`
- 订阅说明原文：`docs/peekpili.html`
