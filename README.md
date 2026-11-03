# 观星 GuanXing

> GitHub 仓库：<https://github.com/waiwaicai/GuanXing>  
> 最新未签名安装包由 GitHub Actions 产出，见仓库 `Actions` → `iOS Build` → `Artifacts` → `GuanXing-unsigned-ipa`。

一个原生 iOS 影视聚合客户端，把 [LibreTV](https://github.com/waiwaicai/LibreTV) 的聚合搜索与多源浏览体验，以及 TVBox、影视仓的源配置生态，带到 iPhone 与 iPad。

项目参考 LibreTV 的产品思路与数据格式，并借鉴 GitHub 上同类 TVBox 客户端（[DpadTV](https://github.com/AresCNZJ/DpadTV)、[TVBox-tvs](https://github.com/yuluoos/TVBox-tvs)）的交互与源格式约定；业务与播放代码为独立 Swift 实现，没有嵌入或打包这些项目的前端或播放器代码。

## 功能

- 聚合搜索：多个苹果 CMS 源并行搜索，结果边出边上屏（不再等最慢的那个源），显示进度并随时可停止；可按源筛选，并按片名合并同名结果，直接看到「几个源有这部片」。
- 首页发现：最新上线、分类片单、精选大图，支持切换当前片源。
- 播放：AVPlayer 原生 HLS / MP4 播放，支持自定义请求头、断点续播、倍速、快退快进 10 秒、全屏横屏、自动下一集，并显示已缓冲时长与实测码率。
- 直播：自动识别 M3U / TXT（`#genre#` 分组）/ JSON 三种直播源，按分组浏览、频道搜索、常看频道收藏。
- 片库：收藏、观看记录与进度、直播收藏，全部保存在本地。
- 源管理：内置 46 个点播源（全部逐个实测）+ 22 个直播源，可停用、改地址替换、删除、一键更新与恢复。被删掉的内置源不会被「更新内置源」偷偷加回来。
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

TVBox 配置中的 `sites`、`lives`、`parses` 会被识别。`type=3/4` 的 `csp_*` 站点不再一律丢弃，能纯 Swift 复刻的协议会被识别并直接接管（见下节）。以下类型仍然无法在 iOS 上运行，导入时会被跳过并在报告中说明：

- 需要 JVM（spider.jar）或 JS 运行时的源
- XML 接口
- HTTP-FLV 等 iOS 系统播放器不支持的直播流（TXT / JSON 频道表本身已支持）

### Spider 的三类实现

| 协议 | 代表类 | iOS 实现方式 |
| --- | --- | --- |
| 规则 DSL | `csp_XBPQ` / `csp_XYQHiker` | 把「数组」「标题」「播放列表」等规则当数据解释，纯字符串匹配抓 HTML |
| APP 采集（AES） | `csp_AppGet` / `csp_AppQi` | 请求头带版本与设备号，响应 `data` 用站点 `ext` 里的 `dataKey` / `dataIv` 做 AES/CBC/PKCS7 解密 |
| APP 采集（MD5） | `csp_AppRJ` | `MD5(固定盐 + 时间戳)` 作为 `sign`，POST 表单取 JSON |

判定只看协议是否已知、`ext` 里有没有必需参数，判不出来的一律当「需要 Spider 运行时」跳过，不做「看起来能跑」的猜测。

导入配置时，这几个类会自动带上 `SpiderBinding`；导入后在「源管理」里仍可改名、换地址或删除，手动改过地址的源会自动解绑原有协议，避免拿旧签名去打新接口。

直播播放依赖系统解码能力：HLS 与 MP4 可直接播放，HTTP-FLV 与部分 DRM 流无法播放。

## 数据与隐私

- 收藏、历史与源配置保存在 App 沙盒的 `Application Support/GuanXing` 目录，不会上传服务器。
- App 启用 `UIFileSharingEnabled`，可通过「文件」App 导出或替换本地配置。
- 应用只请求用户添加的第三方接口，不内置、不缓存影视文件。

## 播放手势

播放器支持全屏手势操作，进入全屏后视频画面铺满整个屏幕（`resizeAspectFill`），不再保留 16:9 黑边。

- 左侧区域上下滑动：调节屏幕亮度，退出播放时自动还原为进入前的亮度。
- 右侧区域上下滑动：调节系统音量。
- 任意位置左右滑动：拖动播放进度，横向滑过整个屏幕宽度约等于 60～120 秒（按片长自适应）。
- 单击画面：显示或隐藏控制条；控制条底部进度条可直接拖动定位。
- 右下角全屏按钮：命中区 44×44pt（图标本身只有 16pt），点全屏后视频按 `resizeAspectFill` 铺满整块屏幕。

手势进行中会显示浮层提示（图标 + 百分比或 时间/总时长 + 进度条），松手后约 0.7 秒自动隐藏。

### 全屏的几处坑（1.1.0 已修）

1. **按钮点不到**：图标只有 15–16pt，且紧贴视频底边，点偏几像素就落到下方手势层，被当成「单击隐藏控件」，主观感受就是「点了没反应」。现在按钮容器固定 44pt，并加了 `contentShape`。
2. **切换时视频层被重建**：原来用 `if/else` 返回两套布局，视图身份改变会让 `AVPlayerLayer` 整块重建，表现为黑屏或画面不跟着铺满。现在统一走 `GeometryReader` 显式计算高度（竖屏 16:9、全屏满高），视图身份不变。
3. **旋转被系统拒绝**：`requestGeometryUpdate` 有时在转场/弹层收起前直接失败。现在失败会自动重试两次（间隔 80ms），并在退出时按真实方向决定是否强制回竖屏。

版本号也从三处硬编码改为统一读 `Info.plist`（`AppVersion`），当前 `1.1.1 (3)`。

### 1.1.1 修的三处显示问题

1. **我的片源只显示十来个**：首页 `sourceShelf` 写死了 `app.sources.prefix(12)`，横向滑动到第 12 个就到底。现在改成两列 `LazyVGrid` 展示全部片源，46 个内置源一次列完，标题里同步显示总数。
2. **首页左右被裁**：`LazyVStack` 只设了 `.padding(.horizontal, 18)`，一旦有子视图报出比视口更宽的宽度，整块内容就会被居中并截掉两侧。现在用 `GeometryReader` 把内容宽度钉死在视口宽度上，海报网格改用 `adaptive(minimum: 104, maximum: 168)`。
3. **海报贴边切图**：`PosterCard` 原来写死 210pt 高度，列宽小于 148pt 时 `.fill` 会把左右裁掉。现在高度由列宽按 0.7 的比例推出，图片作为 overlay 正好铺满，不再裁切。

同一版还修了全屏四周露底：`.ignoresSafeArea` 改为直接挂在量尺寸的 `GeometryReader` 上，播放页把窗口底色压成纯黑，`AVPlayerLayer` 开启 `masksToBounds`；全屏控件层固定留出 44pt 侧边距避开横屏刘海。


### 1.1.5 修的两处交互问题

1. **切换片源后整页空白**：`HomeView` 的外层 `GeometryReader` 在 TabView 内重建时会先报出宽度 0，
   把整块 `LazyVStack` 压成 0×0，于是只剩背景，必须下滑触发一次重排才恢复。已去掉这层包裹，
   改用 `frame(maxWidth: .infinity, alignment: .leading)`，宽高都由父视图正常推导。
2. **右上角搜索按钮点了没反应**：`TabView` 的 selection 之前直接绑 `router.selectedTab`，
   程序化切页在部分系统版本上不驱动换页；首页视图重建时还会把搜索请求吃掉。现在 TabView 用本地
   `@State` 承载选中项并与 `router` 双向同步，搜索请求改为自增序号 `searchRequestID`，
   `SearchView` 用 `handledRequestID` 去重，重建后的新实例不会误判成已处理。

### 1.1.6 修的点击错位

首页右上角的搜索按钮点下去会进「创业面对面」详情页。原因是 hero 用了
`RemoteImage(...).frame(height: 248).clipped()`：竖版海报在 `.fill` 下会纵向溢出约上百 pt，
而 `.clipped()` 只裁画面**不裁命中区**，溢出的透明区域盖到了 header 上，点击就被 hero 的
Button 接走。现在两处都改成 `Color.clear` 定尺寸 + `overlay` 装图片，并给 header 加了
`zIndex(2)`。`DetailView` 的 backdrop 是同样的写法（会盖住返回按钮），一并修了。

### 1.1.7 搜索页的续播入口

搜索页的「搜索历史」存的是**关键词**，点一下只会拿这个词重新搜一遍，所以它本来就不可能
「续播」——这是之前容易误解的地方。这一版补了两件事：

1. 搜索页新增「继续观看」横向卡片，取最近 10 条观看记录，点一下直接按上次的集数和秒数接着播。
2. 搜索历史标签如果刚好对上一条观看记录的片名，标签上会出现播放角标，点它直接续播；没对上
   的仍是原来的重新搜索。
3. `ResumePlaybackView` 加了换源兜底：原源被删、域名挂了、条目下架时，会按片名在其它已启用
   源里重找一部同名的接着播（换源后集数编号不可信，从头开始），失败页的按钮也改成「换源重找」。

## 已知限制

- 本仓库在 Windows 上完成开发与核心层测试，没有在本机生成签名 IPA：iOS 打包与签名强依赖 macOS 与 Xcode，Windows 无法完成。
- SwiftUI 界面层无法在 Windows 编译校验（缺少 SwiftUI / UIKit SDK），首轮 Xcode 构建可能需要修少量 UI 编译问题；核心层已有 94 个测试覆盖配置解析、三种直播源格式、接口请求、播放地址解析，以及内置源目录的唯一性、去重、删除与更新规则。
- 未做 App Store 上架适配（无隐私清单细项、无内购、无审核用资源授权证明）。
- 内置源为公开采集接口，可用性会随时间变化，请以「检测源状态」结果为准，失效时可在「源管理」里改地址、停用或删除。

## 内置源目录

内置源目录版本 `2026.11.02.3`，验证日期 `2026-11-02`。共 46 个点播源：40 个标准 CMS 接口 + 6 个 APP 采集接口（王子、米饭动漫、番薯动漫、元咲动漫、蓝鹰、热播）；另有 22 个直播源。

选源时对候选接口逐个跑了同一条链路：

1. `GET {api}?ac=detail&pg=1` 必须返回非空 `list`
2. 从 `vod_play_url` 里取出真实播放地址（跳过 `$$$` 多线路分隔与 `#` 分集）
3. 对播放地址发 `Range: bytes=0-…` 请求，确认返回 `#EXTM3U` 或视频内容

候选来自三处：`juwanhezi.com/jsonlist` 的 `type=many` / `type=one` 清单、这些多仓配置展开后的子配置，以及 GitHub 上同类仓库（`gaotianliuyun/gao`、`qist/tvbox` 等）里的 TVBox 配置。共验证 110 个候选接口，40 个标准 CMS 去重后保留（含本轮新增的飘零影院、百度资源、创享资源）；其中 23 个在本机网络下能直接拉到视频流，其余为片单与播放地址可用、但 CDN 对机房 IP 返回 403（家用宽带通常正常）。

### 23 个「片单可播但未收录」接口的处置

上一轮实测到 23 个接口能返回片单并拉到视频流，但没进内置目录。逐个查明后按性质分成四类：

| 类别 | 数量 | 处置 |
| --- | --- | --- |
| 成人站（91麻豆、废柴、155、森林、滴滴、成人07、成人24、辣椒、乐播、老色逼、jkun、越南、魔法、精品下） | 14 | 不收录。App 会把 `isAdult` 源从首页与搜索中排除，收进来等于不可用 |
| 与现有内置源同主机、同片库的变体（天堂/电影天堂 `caiji.dyttzyapi.com`、量子 `cj.lziapi.com`、非凡 `cj.ffzyapi.com`，含 http/https 与 m3u8 子路径） | 3 组 | 不重复收录；去重指纹会判为同一个源 |
| 同主机但当前不可达的旧路径（`ikunzyapi.com` 两条、`jingpinx.com`） | 3 | 不收录，该主机已有内置条目 |
| 真正新增、非成人、可播（飘零影院、百度资源、创享资源） | 3 | 已收录 |

另有两个同主机 m3u8 变体（`api.zuidapi.com/.../from/zuidam3u8`、`caiji.maotaizy.cc/.../from/mtm3u8`）实测片库与现有条目重合（20/20、12/20），撤掉以免产生重复。

### 直播源

内置 22 个直播列表，全部为实测能打开、抽样频道能取到 `#EXTM3U` 的地址：

- 央视/卫视为主：小雅 IPTV（M3U 与 TXT 两种格式）、Free-TV 中国、Guovin 直播。
- 港澳台与海外：IPTV-org 的中国、香港、台湾、汉语、日本、韩国、新加坡、泰国、越南、菲律宾、美国、英国、加拿大、澳洲、德国、法国。
- 补充：Kimentanm、Fanmingming。

抽样通过率参考：小雅 27/30、Free-TV 中国 20/21、Kimentanm 19/30、Guovin 10/30、Fanmingming 7/30、IPTV-org 各地区 4/12 到 26/30。直播源本身随时会失效，App 内刷新失败会保留原有频道。

已剔除：Gather（123 个频道全部 403，移动 CDN 拒绝）、vbskycn IPv6（仅 1 条且不可播）、Free-TV 台湾（13 条全为 HTML 落地页）、以及一批 404 的旧仓库地址。

直播源同样可停用、改名、删除；删除内置直播源后「更新内置源」不会把它加回来，「恢复全部」才会。

内置源可在 App 内「源管理」页停用、改名、换成别的接口或直接删除；「更新内置源」只补齐目录里的新条目并清理已下线的旧条目，「恢复全部」才会把删掉的一并找回。

### APP 采集源的验证记录

对 25 个单仓/多仓地址展开后的 927 个 `csp_*` 站点（322 个不同类）做过一轮分类与实测：

- 规则型（`csp_XBPQ` / `csp_XYQHiker` 等）141 个站点，已由规则引擎覆盖。
- APP 采集型（`csp_AppGet` / `csp_AppQi` / `csp_AppRJ`）44 个站点。逐个用还原出的签名与解密逻辑打真实接口，最终 **6 个站点的列表/搜索/详情能返回真实播放地址**，另有 4 个能登录接口但片源为空或播放地址为占位死链，其余域名已失效或只返回 HTML 落地页。
- 剩余 742 个站点多是 `csp_*Guard` 加密壳（277 个）、B 站/豆瓣/网盘搜索（需要账号 cookie 或本身不提供视频地址），以及私有 APP 协议；这些没有稳定的公开算法，静态解析无法还原，仍需 JVM，故不集成。

6 个内置 APP 源实测细节：列表与搜索返回 30 条左右真实条目，详情页 `vod_play_list` 里多数线路直接给 `m3u8`（无需第三方解析），实测 6 条直链中 5 条返回 `#EXTM3U`。

- 全屏铺满与亮度/音量/进度手势已通过 GitHub Actions（macOS 15 + Xcode）编译验证，但尚未在真机上做逐项手感验收：亮度写入依赖 `UIScreen.brightness`，音量写入依赖 `MPVolumeView` 内部 slider，个别系统版本若取不到 slider 会回退为只更新 UI 数值。

## 许可证与声明

本项目以 AGPL-3.0-or-later 发布，见 `LICENSE`。LibreTV 同样使用 AGPL-3.0，本项目参考其产品设计与数据格式；分发本应用时需要遵守 AGPL 的源码开放义务。

参考项目与使用边界：

- [LibreTV](https://github.com/waiwaicai/LibreTV)（AGPL-3.0）：产品思路与源列表格式。
- [DpadTV](https://github.com/AresCNZJ/DpadTV)（GPL-3.0，Android / Kotlin）：借鉴「同名影片按源合并」「源可用性检测结果持久化」等交互设计，未复用其 Kotlin 代码。
- [TVBox-tvs](https://github.com/yuluoos/TVBox-tvs)（MIT，仅公开文档与发布脚本，Flutter 应用闭源）：参考其公开文档中 M3U / TXT（`#genre#`）/ JSON 三种直播源格式与「独立直播播放页」的思路，代码为独立实现。

本项目不提供、不存储、不分发任何影视内容。所有内容来自用户自行添加的第三方接口，请确保使用方式符合所在地区法律，并尊重版权方的授权范围。
