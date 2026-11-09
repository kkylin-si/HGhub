import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var base: String
    @Published var token: String
    @Published var account: Account?
    @Published var dark: Bool
    @Published var muted: Bool
    @Published var muteOnStartup: Bool
    /// 为真时优先播 HEVC 高清；这一集没有高清地址就用标准。
    @Published var preferHevc: Bool
    @Published var favs: [Int]
    @Published var likes: [Int]
    @Published var history: [Watch]
    @Published var searches: [String]
    @Published var toast: String?
    @Published var loginOpen = false
    /// 全屏播放时收起底栏，避免和小横条抢手势。
    @Published var immersive = false

    let defaults = UserDefaults.standard
    lazy var api = HgApi(model: self)

    var loggedIn: Bool { !token.isEmpty }
    var trustedLine: Bool { base == "https://huangguoai.com" || base == "https://huangguoai.ai" }

    static let fixed = [
        ("固定线路 1", "https://huangguoai.com"),
        ("固定线路 2", "https://huangguoai.ai"),
    ]

    init() {
        let d = UserDefaults.standard
        base = d.string(forKey: "hg_base") ?? "https://huangguoai.com"
        token = d.string(forKey: "hg_token") ?? ""
        dark = d.bool(forKey: "hg_dark")
        muteOnStartup = d.object(forKey: "hg_mute_startup") == nil ? true : d.bool(forKey: "hg_mute_startup")
        preferHevc = d.bool(forKey: "hg_hevc")
        muted = d.object(forKey: "hg_muted") == nil ? true : d.bool(forKey: "hg_muted")
        favs = d.array(forKey: "hg_favs") as? [Int] ?? []
        likes = d.array(forKey: "hg_likes") as? [Int] ?? []
        searches = d.stringArray(forKey: "hg_searches") ?? []
        if let data = d.data(forKey: "hg_history"),
           let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            history = rows.map { Watch(id: $0.int("id"), ep: max($0.int("ep"), 1), t: $0.dbl("t"), dur: $0.dbl("dur"), at: $0.dbl("at")) }.filter { $0.id > 0 }
        } else {
            history = []
        }
        account = nil
        if let raw = d.string(forKey: "hg_user"),
           let data = raw.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            account = obj.account()
        }
        if muteOnStartup { muted = true }
    }

    func show(_ text: String) { toast = text }

    func setDark(_ on: Bool) { dark = on; defaults.set(on, forKey: "hg_dark") }
    func setMuted(_ on: Bool) { muted = on; defaults.set(on, forKey: "hg_muted") }
    func setMuteOnStartup(_ on: Bool) { muteOnStartup = on; defaults.set(on, forKey: "hg_mute_startup") }
    func setPreferHevc(_ on: Bool) { preferHevc = on; defaults.set(on, forKey: "hg_hevc") }

    func setLine(_ url: String) {
        let next = url.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard next != base else { return }
        base = next
        token = ""
        account = nil
        defaults.set(next, forKey: "hg_base")
        defaults.removeObject(forKey: "hg_token")
        defaults.removeObject(forKey: "hg_user")
    }

    func setSession(token: String, user: Account) {
        self.token = token
        account = user
        defaults.set(token, forKey: "hg_token")
        let obj: [String: Any] = ["id": user.id, "username": user.username, "nickname": user.nickname, "like": user.like, "collect": user.collect]
        if let data = try? JSONSerialization.data(withJSONObject: obj), let text = String(data: data, encoding: .utf8) {
            defaults.set(text, forKey: "hg_user")
        }
    }

    func logout() {
        token = ""
        account = nil
        defaults.removeObject(forKey: "hg_token")
        defaults.removeObject(forKey: "hg_user")
    }

    func isFav(_ id: Int) -> Bool { favs.contains(id) }
    func isLiked(_ id: Int) -> Bool { likes.contains(id) }

    @discardableResult
    func toggleFav(_ id: Int) -> Bool {
        let on = !favs.contains(id)
        favs = on ? [id] + favs : favs.filter { $0 != id }
        defaults.set(favs, forKey: "hg_favs")
        return on
    }

    @discardableResult
    func toggleLike(_ id: Int) -> Bool {
        let on = !likes.contains(id)
        likes = on ? [id] + likes : likes.filter { $0 != id }
        defaults.set(likes, forKey: "hg_likes")
        return on
    }

    func rememberSearch(_ q: String) {
        let k = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        searches = Array(([k] + searches.filter { $0 != k }).prefix(12))
        defaults.set(searches, forKey: "hg_searches")
    }

    func clearSearch() {
        searches = []
        defaults.removeObject(forKey: "hg_searches")
    }

    func saveWatch(id: Int, ep: Int, t: Double, dur: Double) {
        guard id > 0 else { return }
        let item = Watch(id: id, ep: max(ep, 1), t: max(t, 0), dur: max(dur, 0), at: Date().timeIntervalSince1970)
        history = Array(([item] + history.filter { $0.id != id }).prefix(40))
        let rows: [[String: Any]] = history.map { ["id": $0.id, "ep": $0.ep, "t": $0.t, "dur": $0.dur, "at": $0.at] }
        if let data = try? JSONSerialization.data(withJSONObject: rows) {
            defaults.set(data, forKey: "hg_history")
        }
    }

    func clearLocal() {
        favs = []
        likes = []
        history = []
        defaults.removeObject(forKey: "hg_favs")
        defaults.removeObject(forKey: "hg_likes")
        defaults.removeObject(forKey: "hg_history")
    }
}
