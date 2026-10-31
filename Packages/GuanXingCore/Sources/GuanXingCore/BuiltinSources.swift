import Foundation

public enum BuiltinSources {
    public static let vod: [VodSource] = [
        VodSource(id: "builtin_ffzy", name: "非凡资源", api: "https://cj.ffzyapi.com/api.php/provide/vod", origin: .builtin),
        VodSource(id: "builtin_lzi", name: "量子资源", api: "https://cj.lziapi.com/api.php/provide/vod", origin: .builtin),
        VodSource(id: "builtin_zuid", name: "最大资源", api: "https://api.zuidapi.com/api.php/provide/vod", origin: .builtin),
        VodSource(id: "builtin_sdzy", name: "闪电资源", api: "https://sdzyapi.com/api.php/provide/vod", origin: .builtin),
        VodSource(id: "builtin_gs", name: "光速资源", api: "https://api.guangsuapi.com/api.php/provide/vod", origin: .builtin),
        VodSource(id: "builtin_bfzy", name: "暴风资源", api: "https://bfzyapi.com/api.php/provide/vod", origin: .builtin),
        VodSource(id: "builtin_md", name: "魔都资源", api: "https://www.mdzyapi.com/api.php/provide/vod", origin: .builtin),
        VodSource(id: "builtin_dytt", name: "电影天堂", api: "https://caiji.dyttzyapi.com/api.php/provide/vod", origin: .builtin),
        VodSource(id: "builtin_jy", name: "金鹰资源", api: "https://jyzyapi.com/api.php/provide/vod", origin: .builtin),
        VodSource(id: "builtin_xinlang", name: "新浪资源", api: "https://api.xinlangapi.com/xinlangapi.php/provide/vod", origin: .builtin),
        VodSource(id: "builtin_p2100", name: "飘零资源", api: "https://p2100.net/api.php/provide/vod", origin: .builtin)
    ]

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

    public static let repositoryURLs: [String] = []
}
