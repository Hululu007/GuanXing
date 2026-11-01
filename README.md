# 观星 GuanXing

> GitHub 仓库：<https://github.com/waiwaicai/GuanXing>  
> 最新未签名安装包由 GitHub Actions 产出，见仓库 `Actions` → `iOS Build` → `Artifacts` → `GuanXing-unsigned-ipa`。

一个原生 iOS 影视聚合客户端，把 [LibreTV](https://github.com/waiwaicai/LibreTV) 的聚合搜索与多源浏览体验，以及 TVBox、影视仓的源配置生态，带到 iPhone 与 iPad。

项目参考 LibreTV 的产品思路与数据格式，并借鉴 GitHub 上同类 TVBox 客户端（[DpadTV](https://github.com/AresCNZJ/DpadTV)、[TVBox-tvs](https://github.com/yuluoos/TVBox-tvs)）的交互与源格式约定；业务与播放代码为独立 Swift 实现，没有嵌入或打包这些项目的前端或播放器代码。

## 功能

- 聚合搜索：多个苹果 CMS 源并行搜索，可按源筛选，并显示结果的来源；支持按片名合并同名结果，直接看到「几个源有这部片」。
- 首页发现：最新上线、分类片单、精选大图，支持切换当前片源。
- 播放：AVPlayer 原生 HLS / MP4 播放，支持自定义请求头、断点续播、倍速、快退快进 10 秒、全屏横屏、自动下一集，并显示已缓冲时长与实测码率。
- 直播：自动识别 M3U / TXT（`#genre#` 分组）/ JSON 三种直播源，按分组浏览、频道搜索、常看频道收藏。
- 片库：收藏、观看记录与进度、直播收藏，全部保存在本地。
- 源管理：内置 11 个点播源、2 个直播源，可增删、启用、检测可用性。
- 配置导入：TVBox JSON、LibreTV SourceList、接口目录 JSON、远程订阅链接、本地 JSON / M3U / TXT 文件。支持带注释与尾随逗号的 JSONC、Base64 配置，以及 GBK / GB18030 编码的频道表。

## 系统要求

- iOS / iPadOS 17.0 及以上。
- 构建需要 macOS 14+、Xcode 16+ 与 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

## 构建

```bash
brew install xcodegen
cd GuanXing
xcodegen generate
open GuanXing.xcodeproj
```

在 Xcode 中选择自己的 Team 与真机即可运行。首次运行请在 Signing & Capabilities 中选择开发团队；Bundle Identifier 可改成自己的域名反写（默认 `com.guanxing.player`）。

### 命令行打包

```bash
DEVELOPMENT_TEAM=你的10位TeamID ./scripts/build_ipa.sh
```

默认按 `development` 方式导出；要导出 Ad Hoc 或 App Store 包，加上 `EXPORT_METHOD=ad-hoc` 或 `EXPORT_METHOD=app-store`。产物在 `build/GuanXing.ipa`。

### 未签名 IPA

```bash
./scripts/package_unsigned_ipa.sh
```

生成 `build/GuanXing-unsigned.ipa`。该包不含证书与描述文件，不能直接安装，需要用 AltStore、Sideloadly、爱思助手等工具以自己的 Apple ID 或证书重签后再安装。

### GitHub Actions

`.github/workflows/ios.yml` 在每次 push 时执行：

1. `swift test` 运行核心层测试
2. 用 `xcodebuild` 以 `iphoneos` + 关闭签名的方式编译整个 App
3. 打包并上传 `GuanXing-unsigned.ipa` 工件（保留 30 天）
4. 上传 `build.log` 方便排查编译问题

下载后仍需用 AltStore / Sideloadly / 爱思助手重签才能安装。签名导出需要在仓库中配置证书 Secret 后自行扩展该工作流。

## 配置格式

点播源需要苹果 CMS V10 的 JSON 接口，例如：

```text
https://example.com/api.php/provide/vod
```

支持的请求：`?ac=list`、`?ac=videolist&pg=1`、`?ac=videolist&wd=关键词&pg=1`、`?ac=detail&ids=ID`。

### 直播源格式

导入时会自动识别，无需手动选择格式：

```text
# 1) M3U
#EXTM3U
#EXTINF:-1 tvg-logo="https://a.example.com/1.png" group-title="央视",CCTV-1
http://a.example.com/cctv1.m3u8

# 2) TXT（#genre# 分组）
央视,#genre#
CCTV-1,http://a.example.com/cctv1.m3u8
CCTV-2,http://a.example.com/cctv2.m3u8
卫视,#genre#
湖南卫视,http://a.example.com/hunan.m3u8

# 3) JSON（支持 groups / channels 嵌套，也支持扁平数组）
{"groups":[{"name":"央视","channels":[{"name":"CCTV-1","url":"http://a.example.com/1.m3u8"}]}]}
```

TXT 一行可写多个地址，当前只取第一个，其余计入导入报告的「忽略备用地址」；解码顺序为 UTF-8 → UTF-16（带 BOM）→ GB18030 → GB2312 → Latin-1。

TVBox 配置中的 `sites`、`lives`、`parses` 会被识别。以下类型无法在 iOS 上运行，导入时会被跳过并在报告中说明：

- 需要 Spider / jar / py / js 引擎的源（type 3、4 等）
- XML 接口
- HTTP-FLV 等 iOS 系统播放器不支持的直播流（TXT / JSON 频道表本身已支持）

直播播放依赖系统解码能力：HLS 与 MP4 可直接播放，HTTP-FLV 与部分 DRM 流无法播放。

## 数据与隐私

- 收藏、历史与源配置保存在 App 沙盒的 `Application Support/GuanXing` 目录，不会上传服务器。
- App 启用 `UIFileSharingEnabled`，可通过「文件」App 导出或替换本地配置。
- 应用只请求用户添加的第三方接口，不内置、不缓存影视文件。

## 已知限制

- 本仓库在 Windows 上完成开发与核心层测试，没有在本机生成签名 IPA：iOS 打包与签名强依赖 macOS 与 Xcode，Windows 无法完成。
- SwiftUI 界面层无法在 Windows 编译校验（缺少 SwiftUI / UIKit SDK），首轮 Xcode 构建可能需要修少量 UI 编译问题；核心层已有 24 个测试覆盖配置解析、三种直播源格式、接口请求与播放地址解析。
- 未做 App Store 上架适配（无隐私清单细项、无内购、无审核用资源授权证明）。
- 内置源为公开采集接口，可用性会随时间变化，请以「检测源状态」结果为准。

## 许可证与声明

本项目以 AGPL-3.0-or-later 发布，见 `LICENSE`。LibreTV 同样使用 AGPL-3.0，本项目参考其产品设计与数据格式；分发本应用时需要遵守 AGPL 的源码开放义务。

参考项目与使用边界：

- [LibreTV](https://github.com/waiwaicai/LibreTV)（AGPL-3.0）：产品思路与源列表格式。
- [DpadTV](https://github.com/AresCNZJ/DpadTV)（GPL-3.0，Android / Kotlin）：借鉴「同名影片按源合并」「源可用性检测结果持久化」等交互设计，未复用其 Kotlin 代码。
- [TVBox-tvs](https://github.com/yuluoos/TVBox-tvs)（MIT，仅公开文档与发布脚本，Flutter 应用闭源）：参考其公开文档中 M3U / TXT（`#genre#`）/ JSON 三种直播源格式与「独立直播播放页」的思路，代码为独立实现。

本项目不提供、不存储、不分发任何影视内容。所有内容来自用户自行添加的第三方接口，请确保使用方式符合所在地区法律，并尊重版权方的授权范围。
