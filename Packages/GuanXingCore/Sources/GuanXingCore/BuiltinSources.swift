import Foundation

/// 内置点播源目录。
///
/// 每个条目都经过实测：`?ac=detail&pg=1` 必须返回非空的 `list`，
/// 且能从详情里拿到至少一条真实播放地址（m3u8 / mp4）。
/// 只有片单接口、Spider、jar、js 类型的 TVBox 源不在此列，因为 iOS 无法加载它们。
/// 列表里的源用户可以随时停用、修改地址或删除，删除后不会被“更新内置源”重新加回。
public enum BuiltinSources {

    /// 最近一次全量验证时间。
    public static let verifiedAt = "2026-11-02"

    /// 内置源目录版本；目录变动时改这个值，App 会提示可更新。
    public static let catalogVersion = "2026.11.02"

    /// 本次验证覆盖的候选接口数（juwanhezi 三类清单 + GitHub 同类配置）。
    public static let verifiedCandidateCount = 101

    /// 要求片单可用且能拿到真实播放地址的数量。
    public static let verifiedAvailableCount = 37

    /// 实测能直接加载视频流的数量（余下为片单可用、播放链路可拿到但 CDN 对机房 IP 限制）。
    public static let verifiedMediaCount = 14

    public static let vod: [VodSource] = [
        VodSource(
            id: "builtin_maoyan",
            name: "猫眼资源",
            api: "https://api.maoyanapi.top/api.php/provide/vod",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_aadan",
            name: "艾旦资源",
            api: "https://www.lovedan.net/api.php/provide/vod",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_ikun",
            name: "ikun资源",
            api: "https://ikunzyapi.com/api.php/provide/vod/from/ikm3u8/at/json",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_modu_anime",
            name: "魔都动漫",
            api: "https://caiji.moduapi.cc/api.php/provide/vod",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_modu",
            name: "魔都资源",
            api: "https://www.mdzyapi.com/api.php/provide/vod",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_guangsu",
            name: "光速资源",
            api: "https://api.guangsuapi.com/api.php/provide/vod/from/gsm3u8",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_iqiyi",
            name: "爱奇艺资源",
            api: "https://iqiyizyapi.com/api.php/provide/vod",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_yingju",
            name: "影剧资源",
            api: "https://caiji.maotaizy.cc/api.php/provide/vod",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_maotai",
            name: "茅台资源",
            api: "https://mtzy.me/api.php/provide/vod",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_baofeng",
            name: "暴风资源",
            api: "https://bfzyapi.com/api.php/provide/vod",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_zy360",
            name: "360资源",
            api: "https://360zy.com/api.php/provide/vod",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_yinghua",
            name: "樱花资源",
            api: "https://m3u8.apiyhzy.com/api.php/provide/vod",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_ruyi",
            name: "如意资源",
            api: "https://cj.rycjapi.com/api.php/provide/vod",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_ckzy",
            name: "CK资源",
            api: "https://ckzy.me/api.php/provide/vod",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_liangzi",
            name: "量子资源",
            api: "https://cj.lziapi.com/api.php/provide/vod",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_hongniu",
            name: "红牛资源",
            api: "https://www.hongniuzy2.com/api.php/provide/vod",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_ffzy_direct",
            name: "非凡直连",
            api: "https://ffzy.tv/api.php/provide/vod",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_ffzy",
            name: "非凡资源",
            api: "https://cj.ffzyapi.com/api.php/provide/vod",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_dytt",
            name: "电影天堂",
            api: "http://caiji.dyttzyapi.com/api.php/provide/vod/from/dyttm3u8/at/m3u8",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_haohua",
            name: "豪华资源",
            api: "https://hhzyapi.com/api.php/provide/vod",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_subo",
            name: "速博资源",
            api: "https://subocaiji.com/api.php/provide/vod",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_zuid",
            name: "最大资源",
            api: "https://api.zuidapi.com/api.php/provide/vod",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_jisu",
            name: "极速资源",
            api: "https://jszyapi.com/api.php/provide/vod",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_ok",
            name: "OK资源",
            api: "https://api.okzyw.net/api.php/provide/vod",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_yaya",
            name: "丫丫资源",
            api: "https://cj.yayazy.net/api.php/provide/vod",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_shandian",
            name: "闪电资源",
            api: "https://sdzyapi.com/api.php/provide/vod",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_niuniu",
            name: "牛牛资源",
            api: "https://api.niuniuzy.me/api.php/provide/vod",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_jinying",
            name: "金鹰资源",
            api: "https://jyzyapi.com/api.php/provide/vod",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_tianya_backup",
            name: "天涯备用",
            api: "http://tyyszy.com/api.php/provide/vod",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_tianya",
            name: "天涯资源",
            api: "https://tyyszyapi.com/api.php/provide/vod",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_huya",
            name: "虎牙资源",
            api: "https://www.huyaapi.com/api.php/provide/vod",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_uku",
            name: "尤酷资源",
            api: "https://api.ukuapi.com/api.php/provide/vod",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_uku88",
            name: "U酷资源",
            api: "https://api.ukuapi88.com/api.php/provide/vod",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_sony",
            name: "索尼资源",
            api: "https://suoniapi.com/api.php/provide/vod",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_wujin",
            name: "无尽资源",
            api: "https://api.wujinapi.com/api.php/provide/vod",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_wujin_backup",
            name: "无尽备用",
            api: "https://api.wujinapi.me/api.php/provide/vod",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_wujin_mirror",
            name: "无尽镜像",
            api: "https://api.wujinapi.net/api.php/provide/vod",
            origin: .builtin
        ),
        VodSource(
            id: "builtin_app_wangzi",
            name: "王子 APP",
            api: "https://app.95112475.xyz",
            origin: .builtin,
            spider: SpiderBinding(kind: .appGet, payload: "{\"url\":\"https://app.95112475.xyz\",\"dataKey\":\"5a9w6x58dsq6z3a6\",\"dataIv\":\"5a9w6x58dsq6z3a6\"}")
        ),
        VodSource(
            id: "builtin_app_mifan",
            name: "米饭动漫",
            api: "https://get.mymifun.com",
            origin: .builtin,
            spider: SpiderBinding(kind: .appGet, payload: "{\"url\":\"https://get.mymifun.com\",\"site\":\"\",\"dataKey\":\"GETMIFUNGEIMIFUN\",\"dataIv\":\"GETMIFUNGEIMIFUN\",\"deviceId\":\"\",\"version\":\"\"}")
        ),
        VodSource(
            id: "builtin_app_fanshu",
            name: "番薯动漫",
            api: "https://new.app.bytegooty.com",
            origin: .builtin,
            spider: SpiderBinding(kind: .appGet, payload: "{\"url\":\"https://new.app.bytegooty.com\",\"site\":\"\",\"dataKey\":\"N4yj7l7xKxHF4*gz\",\"dataIv\":\"N4yj7l7xKxHF4*gz\",\"deviceId\":\"\",\"version\":\"\",\"ua\":\"\"}")
        ),
        VodSource(
            id: "builtin_app_yuanxiao",
            name: "元咲动漫",
            api: "http://cic.aicg.fun",
            origin: .builtin,
            spider: SpiderBinding(kind: .appGet, payload: "{\"url\":\"http://cic.aicg.fun\",\"site\":\"\",\"dataKey\":\"2c4h36abd96se10u\",\"dataIv\":\"2c4h36abd96se10u\",\"deviceId\":\"\",\"version\":\"\",\"ua\":\"\"}")
        ),
        VodSource(
            id: "builtin_app_lanying",
            name: "蓝鹰 APP",
            api: "http://103.217.190.91:5566",
            origin: .builtin,
            spider: SpiderBinding(kind: .appQi, payload: "{\"url\":\"http://103.217.190.91:5566\",\"dataKey\":\"hagYExMdMkeWfemK\",\"dataIv\":\"hagYExMdMkeWfemK\",\"init\":\"initV122\",\"ua\":\"https://9877.kstore.space/okhttp/3.10.0\"}")
        ),
        VodSource(
            id: "builtin_app_rebo",
            name: "热播 APP",
            api: "http://v.rbotv.cn",
            origin: .builtin,
            spider: SpiderBinding(kind: .appRJ, payload: "{\"url\":\"http://v.rbotv.cn\"}")
        ),
    ]

    /// APP 采集型源（csp_AppGet / csp_AppQi / csp_AppRJ 的纯 Swift 复刻）。
    /// 这些不是标准 CMS，接口需要签名与 AES 解密，密钥取自站点 ext。
    public static let appCms: [VodSource] = vod.filter { $0.spider != nil }

    public static let live: [LiveSource] = [
        LiveSource(
            id: "builtin_live_iptvorg",
            name: "IPTV-org 中国",
            url: "https://iptv-org.github.io/iptv/countries/cn.m3u",
            origin: .builtin
        ),
        LiveSource(
            id: "builtin_live_gather",
            name: "Gather 直播",
            url: "https://raw.githubusercontent.com/YanG-1989/m3u/main/Gather.m3u",
            origin: .builtin
        )
    ]

    /// 推荐的多仓配置地址，供「导入中心」一键导入使用。
    public static let repositoryURLs: [String] = [
        "http://xhztv.top/dc",
        "http://ztha.top/TVBox/GYCK.json",
        "http://xmbjm.fh4u.org/dc.txt"
    ]

    /// 「批量导入」页的预填内容：多仓 + 已实测可用的单仓接口。
    /// 用户可以直接在此基础上删改，导入时会按指纹自动去重。
    /// APP 采集型源不走这里（它们需要 spider 绑定），由内置目录直接提供。
    public static var batchSeed: String {
        (repositoryURLs + vod.filter { $0.spider == nil }.map(\.api)).joined(separator: "\n")
    }

    /// 接口地址或 ID 重复即视为同一个源，用于导入与更新时去重。
    public static func isDuplicate(_ source: VodSource, in list: [VodSource]) -> Bool {
        let api = source.api.lowercased()
        return list.contains { $0.id == source.id || $0.api.lowercased() == api }
    }

    /// 按 ID 查找目录里的标准定义。
    public static func canonical(id: String) -> VodSource? {
        vod.first { $0.id == id }
    }
}
