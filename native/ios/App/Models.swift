import Foundation

struct Author: Hashable { var id: Int; var name: String; var avatar: String }
struct VideoCard: Hashable, Identifiable {
    var id: Int
    var title: String
    var cover: String
    var desc: String
    var tags: [String]
    var episodeCount: Int
    var hot: Int
    var likeCount: Int
    var author: String
}
struct Episode: Hashable, Identifiable { var id: Int { ep }; var ep: Int; var title: String }
struct Detail: Hashable {
    var id: Int
    var title: String
    var desc: String
    var cover: String
    var tags: [String]
    var episodes: [Episode]
    var like: Int
    var comment: Int
    var videoUrl: String
    var liked: Bool
    var collected: Bool
}
struct PlayInfo {
    var ep: Int
    var title: String
    var videoUrl: String
    var hevcUrl: String
    var cdnHeader: String = ""
    var cdnValue: String = ""
}
struct PageInfo { var page: Int; var pages: Int }
struct CommentItem: Identifiable, Hashable { var id: Int; var nickname: String; var text: String; var time: String }
struct RankItem: Identifiable, Hashable {
    var id: Int { videoId }
    var rank: Int
    var videoId: Int
    var title: String
    var cover: String
    var metric: String
}
struct PostItem: Identifiable, Hashable {
    var id: Int
    var title: String
    var cover: String
    var content: String
    var videoUrl: String
    var desc: String
}
struct Account: Hashable { var id: Int; var username: String; var nickname: String; var like: Int; var collect: Int }
struct Watch: Hashable { var id: Int; var ep: Int; var t: Double; var dur: Double; var at: Double }

enum JSONMap {
    static func obj(_ any: Any?) -> [String: Any] { any as? [String: Any] ?? [:] }
    static func list(_ any: Any?) -> [[String: Any]] {
        if let rows = any as? [[String: Any]] { return rows }
        if let rows = any as? [NSDictionary] { return rows.compactMap { $0 as? [String: Any] } }
        return []
    }
}

extension Dictionary where Key == String, Value == Any {
    func str(_ k: String) -> String {
        switch self[k] {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return ""
        }
    }
    func int(_ k: String) -> Int {
        switch self[k] {
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s) ?? 0
        default: return 0
        }
    }
    func dbl(_ k: String) -> Double {
        switch self[k] {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s) ?? 0
        default: return 0
        }
    }
    func bool(_ k: String) -> Bool {
        switch self[k] {
        case let b as Bool: return b
        case let n as NSNumber: return n.intValue != 0
        case let s as String: return s == "1" || s.lowercased() == "true"
        default: return false
        }
    }
    func strings(_ k: String) -> [String] { self[k] as? [String] ?? [] }
    func rows(_ k: String) -> [[String: Any]] { JSONMap.list(self[k]) }
    func child(_ k: String) -> [String: Any]? { self[k] as? [String: Any] }

    func card() -> VideoCard {
        VideoCard(
            id: int("id"),
            title: str("title"),
            cover: str("cover"),
            desc: str("description"),
            tags: strings("tags"),
            episodeCount: int("episode_count"),
            hot: int("hot"),
            likeCount: int("like_count"),
            author: child("author")?.str("name") ?? ""
        )
    }

    func detail() -> Detail {
        let counts = child("counts")
        let metrics = child("metrics")
        let interaction = child("interaction")
        let episodes = rows("episodes").map { row in
            Episode(ep: row.int("ep_num"), title: row.str("title").isEmpty ? "第\(row.int("ep_num"))集" : row.str("title"))
        }
        return Detail(
            id: int("id"),
            title: str("title"),
            desc: str("description"),
            cover: str("cover"),
            tags: strings("tags"),
            episodes: episodes,
            like: counts?.int("like") ?? int("like_count"),
            comment: counts?.int("comment") ?? metrics?.int("comment") ?? int("comment_count"),
            videoUrl: str("video_url"),
            liked: interaction?.bool("liked") ?? false,
            collected: interaction?.bool("collected") ?? false
        )
    }

    func play() -> PlayInfo {
        PlayInfo(ep: Swift.max(int("ep_num"), 1), title: str("title"), videoUrl: str("video_url"), hevcUrl: str("video_url_hevc"))
    }

    func playback() -> PlayInfo {
        let streams = child("streams")
        let cdn = child("cdn")
        let header = cdn?.str("authKey") ?? ""
        let value = cdn?.str("authValue") ?? ""
        let allowed = header.lowercased() == "x-cdn-auth" && !value.isEmpty
        let episode = int("ep") > 0 ? int("ep") : Swift.max(int("ep_num"), 1)
        let main = streams?.str("main") ?? ""
        let hevc = streams?.str("hevc") ?? ""
        return PlayInfo(
            ep: episode,
            title: str("title"),
            videoUrl: main.isEmpty ? str("video_url") : main,
            hevcUrl: hevc.isEmpty ? str("video_url_hevc") : hevc,
            cdnHeader: allowed ? "x-cdn-auth" : "",
            cdnValue: allowed ? value : ""
        )
    }

    func page() -> PageInfo {
        let p = child("pagination") ?? [:]
        return PageInfo(page: Swift.max(p.int("page"), 1), pages: Swift.max(p.int("pages"), 1))
    }

    func comment() -> CommentItem {
        CommentItem(id: int("id"), nickname: str("nickname").isEmpty ? "用户" : str("nickname"), text: str("text").isEmpty ? str("content") : str("text"), time: str("time").isEmpty ? str("created_at") : str("time"))
    }

    func rank() -> RankItem {
        RankItem(rank: int("rank"), videoId: int("video_id"), title: str("title"), cover: str("cover"), metric: "\(str("metric_label")) \(fmtCount(int("metric_value")))")
    }

    func post() -> PostItem {
        PostItem(id: int("id"), title: str("title"), cover: str("cover"), content: str("content"), videoUrl: str("video_url"), desc: str("desc"))
    }

    func account() -> Account {
        let counts = child("counts")
        let name = str("nickname").isEmpty ? str("username") : str("nickname")
        return Account(id: int("id"), username: str("username"), nickname: name, like: counts?.int("like") ?? 0, collect: counts?.int("collect") ?? 0)
    }
}

func fmtCount(_ n: Int) -> String {
    if n >= 100_000_000 { return trim(Double(n) / 100_000_000) + "亿" }
    if n >= 10_000 { return trim(Double(n) / 10_000) + "万" }
    return String(max(n, 0))
}

func fmtClock(_ sec: Double) -> String {
    let s = Int(max(sec, 0))
    return "\(s / 60):" + String(format: "%02d", s % 60)
}

private func trim(_ v: Double) -> String {
    let s = String(format: "%.1f", v)
    return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
}
