# 观星 GuanXing

> GitHub 仓库：<https://github.com/waiwaicai/GuanXing>  
> 最新未签名安装包由 GitHub Actions 产出，见仓库 `Actions` → `iOS Build` → `Artifacts` → `GuanXing-unsigned-ipa`。

一个原生 iOS 影视聚合客户端，把 [LibreTV](https://github.com/waiwaicai/LibreTV) 的聚合搜索与多源浏览体验，以及 TVBox、影视仓的源配置生态，带到 iPhone 与 iPad。

项目参考 LibreTV 的产品思路与数据格式，并借鉴 GitHub 上同类 TVBox 客户端的接口组织方式；业务与播放代码为独立 Swift 实现，没有嵌入或打包 LibreTV 的前端代码。

## 功能

- 聚合搜索：多个苹果 CMS 源并行搜索，可按源筛选，并显示结果的来源。
- 首页发现：最新上线、分类片单、精选大图，支持切换当前片源。
- 播放：AVPlayer 原生 HLS / MP4 播放，支持自定义请求头、断点续播、倍速、快退快进 10 秒、全屏横屏、自动下一集。
- 直播：M3U / M3U8 播放列表，按分组浏览、频道搜索、常看频道收藏。
- 片库：收藏、观看记录与进度、直播收藏，全部保存在本地。
- 源管理：内置 11 个点播源、2 个直播源，可增删、启用、检测可用性。
- 配置导入：TVBox JSON、LibreTV SourceList、接口目录 JSON、远程订阅链接、本地 JSON / M3U 文件。支持带注释与尾随逗号的 JSONC，以及 Base64 配置。

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

TVBox 配置中的 `sites`、`lives`、`parses` 会被识别。以下类型无法在 iOS 上运行，导入时会被跳过并在报告中说明：

- 需要 Spider / jar / py / js 引擎的源（type 3、4 等）
- XML 接口
- 非 M3U 的直播源（如 TXT 频道表、HTTP-FLV 专用格式）

直播播放依赖系统解码能力：HLS 与 MP4 可直接播放，HTTP-FLV 与部分 DRM 流无法播放。

## 数据与隐私

- 收藏、历史与源配置保存在 App 沙盒的 `Application Support/GuanXing` 目录，不会上传服务器。
- App 启用 `UIFileSharingEnabled`，可通过「文件」App 导出或替换本地配置。
- 应用只请求用户添加的第三方接口，不内置、不缓存影视文件。

## 已知限制

- 本仓库在 Windows 上完成开发与核心层测试，没有在本机生成签名 IPA：iOS 打包与签名强依赖 macOS 与 Xcode，Windows 无法完成。
- SwiftUI 界面层无法在 Windows 编译校验（缺少 SwiftUI / UIKit SDK），首轮 Xcode 构建可能需要修少量 UI 编译问题；核心层已有 9 个测试覆盖配置解析、接口请求与播放地址解析。
- 未做 App Store 上架适配（无隐私清单细项、无内购、无审核用资源授权证明）。
- 内置源为公开采集接口，可用性会随时间变化，请以「检测源状态」结果为准。

## 许可证与声明

本项目以 AGPL-3.0-or-later 发布，见 `LICENSE`。LibreTV 同样使用 AGPL-3.0，本项目参考其产品设计与数据格式；分发本应用时需要遵守 AGPL 的源码开放义务。

本项目不提供、不存储、不分发任何影视内容。所有内容来自用户自行添加的第三方接口，请确保使用方式符合所在地区法律，并尊重版权方的授权范围。
