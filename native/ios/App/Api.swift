import Foundation

enum ApiError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let s): return s }
    }
}

final class HgApi {
    let model: AppModel
    private let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    init(model: AppModel) { self.model = model }

    func feed(page: Int) async throws -> ([VideoCard], PageInfo) {
        let data = try await get("/api/videos?page=\(page)&size=8")
        return (data.rows("items").map { $0.card() }, data.page())
    }

    func category(_ cate: String, page: Int, size: Int = 20) async throws -> ([VideoCard], PageInfo) {
        let data = try await get("/api/videos/category/\(enc(cate))?page=\(page)&size=\(size)")
        return (data.rows("items").map { $0.card() }, data.page())
    }

    func search(_ q: String, page: Int) async throws -> ([VideoCard], PageInfo) {
        let data = try await get("/api/search?q=\(enc(q))&page=\(page)&size=20")
        return (data.rows("items").map { $0.card() }, data.page())
    }

    func rank(_ kind: String) async throws -> [RankItem] {
        let k = (kind == "recommend" || kind == "potential") ? kind : "hot"
        return try await get("/api/ranks/\(k)").rows("items").map { $0.rank() }
    }

    func posts(page: Int) async throws -> ([PostItem], PageInfo) {
        let data = try await get("/api/posts?page=\(page)&size=20")
        return (data.rows("items").map { $0.post() }, data.page())
    }

    func post(_ id: Int) async throws -> PostItem { try await get("/api/posts/\(id)").post() }
    func video(_ id: Int) async throws -> Detail { try await get("/api/videos/\(id)").detail() }
    func play(_ id: Int, ep: Int, origin: String? = nil) async throws -> PlayInfo {
        try await call("GET", "/api/videos/\(id)/play?ep=\(ep)&page_texts=0", nil, auth: false, origin: origin).play()
    }

    /// 当前站点的播放地址从这里取，旧的 play 接口会返回空的 video_url。
    func playback(_ id: Int, ep: Int) async throws -> PlayInfo {
        try await call("POST", "/api/videos/\(id)/episodes/\(ep)/playback", [:], auth: false).playback()
    }
    func comments(_ id: Int, ep: Int) async throws -> [CommentItem] {
        try await get("/api/videos/\(id)/comments?ep=\(ep)&page=1&size=20").rows("items").map { $0.comment() }
    }

    func sendComment(_ id: Int, ep: Int, text: String) async throws {
        _ = try await call("POST", "/api/videos/\(id)/comments?ep=\(ep)", ["text": text], auth: true)
    }

    func like(_ id: Int, ep: Int, on: Bool) async throws {
        _ = try await call(on ? "POST" : "DELETE", "/api/videos/\(id)/like?ep=\(ep)", nil, auth: true)
    }

    func collect(_ id: Int, on: Bool) async throws {
        _ = try await call(on ? "POST" : "DELETE", "/api/videos/\(id)/collect", nil, auth: true)
    }

    func login(username: String, password: String) async throws -> Account {
        try await ensureTrusted()
        let data = try await call("POST", "/api/account/loginByPassword", ["username": username, "password": password], auth: false)
        return try await save(data)
    }

    func register(username: String, password: String, email: String) async throws -> Account {
        try await ensureTrusted()
        var body: [String: Any] = ["username": username, "password": password, "confirm_password": password]
        if !email.isEmpty { body["email"] = email }
        let data = try await call("POST", "/api/account/registerByPassword", body, auth: false)
        return try await save(data)
    }

    func logout() async {
        _ = try? await call("POST", "/api/account/logout", nil, auth: true)
        await model.logout()
    }

    func mirrors() async throws -> [String] {
        let page = "https://huangguoai.pages.dev/"
        let html = try await text(page)
        let src = scriptSrc(html) ?? "publish.js"
        let jsURL = src.hasPrefix("http") ? src : page + src.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let js = try await text(jsURL)
        let domains = jsArray(js, "var urls")
        let subs = jsArray(js, "var subdomains")
        if domains.isEmpty { throw ApiError.message("没有找到镜像域名") }
        var out: [String] = []
        for domain in domains {
            let host = domain.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let names = subs.isEmpty ? [host] : subs.map { "\($0).\(host)" }
            for name in names {
                let url = "https://\(name)"
                if allow(url) { out.append(url) }
                if out.count >= 40 { return out }
            }
        }
        if out.isEmpty { throw ApiError.message("没有可用镜像") }
        return out
    }

    func bytes(_ url: String) async throws -> Data {
        guard allow(url) else { throw ApiError.message("地址不可用") }
        let origin = await model.base
        var req = URLRequest(url: URL(string: url)!)
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue(origin + "/", forHTTPHeaderField: "Referer")
        req.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ApiError.message("封面加载失败")
        }
        return data
    }

    private func get(_ path: String) async throws -> [String: Any] {
        try await call("GET", path, nil, auth: false)
    }

    private func call(_ method: String, _ path: String, _ body: [String: Any]?, auth: Bool, origin override: String? = nil) async throws -> [String: Any] {
        let current = await model.base
        let origin = (override ?? current).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let token = await model.token
        guard allow(origin) else { throw ApiError.message("线路地址无效") }
        if auth && token.isEmpty { throw ApiError.message("请先登录") }
        var encoded = ""
        var ctype = ""
        if let body {
            let raw = try JSONSerialization.data(withJSONObject: body)
            encoded = raw.base64EncodedString()
            ctype = "application/json"
        }
        let envelope: [String: Any] = ["method": method, "path": path, "body": encoded, "content_type": ctype]
        var req = URLRequest(url: URL(string: origin + "/api/edge/request")!)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: envelope)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue(origin + "/", forHTTPHeaderField: "Referer")
        if auth && !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 || code == 403 { throw ApiError.message("请先登录") }
        if !(200..<300).contains(code) { throw ApiError.message("服务器请求失败（HTTP \(code)），请稍后重试或切换线路") }
        if data.isEmpty { return [:] }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ApiError.message("接口返回无法解析")
        }
        if (obj["status"] as? NSNumber)?.intValue == 1 || (obj["status"] as? Int) == 1 {
            return obj["data"] as? [String: Any] ?? [:]
        }
        let msg = (obj["msg"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "接口返回失败"
        throw ApiError.message(msg)
    }

    private func save(_ data: [String: Any]) async throws -> Account {
        let token = data.str("token")
        guard !token.isEmpty, let user = data.child("user")?.account() else {
            throw ApiError.message("登录返回不完整")
        }
        await model.setSession(token: token, user: user)
        return user
    }

    private func ensureTrusted() async throws {
        let ok = await model.trustedLine
        if !ok { throw ApiError.message("镜像线路仅供游客浏览，登录请切换到固定线路") }
    }

    private func text(_ url: String) async throws -> String {
        guard allow(url), let u = URL(string: url) else { throw ApiError.message("地址不可用") }
        var req = URLRequest(url: u)
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let text = String(data: data, encoding: .utf8) else {
            throw ApiError.message("镜像清单不可用")
        }
        return text
    }

    private func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }
}

func allow(_ raw: String) -> Bool {
    guard let url = URL(string: raw), url.scheme?.lowercased() == "https", let host = url.host?.lowercased(), !host.isEmpty else { return false }
    if host == "localhost" || host.hasSuffix(".local") { return false }
    let parts = host.split(separator: ".").compactMap { Int($0) }
    guard parts.count == 4 else { return true }
    if parts[0] == 10 || parts[0] == 127 || parts[0] == 0 { return false }
    if parts[0] == 192 && parts[1] == 168 { return false }
    if parts[0] == 172 && (16...31).contains(parts[1]) { return false }
    if parts[0] == 169 && parts[1] == 254 { return false }
    return true
}

private func scriptSrc(_ html: String) -> String? {
    var rest = html
    while let range = rest.range(of: "src=\"") {
        let after = rest[range.upperBound...]
        guard let end = after.firstIndex(of: "\"") else { return nil }
        let candidate = String(after[..<end])
        if candidate.contains(".js") { return candidate }
        rest = String(after[end...])
    }
    return nil
}

private func jsArray(_ src: String, _ decl: String) -> [String] {
    guard let at = src.range(of: decl) else { return [] }
    let rest = src[at.lowerBound...]
    guard let open = rest.firstIndex(of: "["), let close = rest[open...].firstIndex(of: "]") else { return [] }
    let body = rest[rest.index(after: open)..<close]
    return body.split(separator: ",").map { item in
        item.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }.filter { !$0.isEmpty && !$0.hasPrefix("//") }
}
