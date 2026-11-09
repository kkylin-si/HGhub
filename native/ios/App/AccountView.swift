import SwiftUI

struct ProfileScreen: View {
    var settings: () -> Void
    var login: () -> Void
    var library: (String) -> Void
    @EnvironmentObject private var model: AppModel
    @Environment(\.hg) private var hg

    var body: some View {
        let name = model.account?.nickname ?? "未登录"
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("我的").font(.hgTitle(34)).foregroundStyle(hg.ink)
                        Text("收藏和观看都留在这台设备上").font(.subheadline).foregroundStyle(hg.muted)
                    }
                    Spacer()
                    Button(action: settings) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(hg.ink)
                            .frame(width: 40, height: 40)
                            .background(hg.card)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        Text(String(name.prefix(1)))
                            .font(.hgTitle(22))
                            .foregroundStyle(hg.accent)
                            .frame(width: 56, height: 56)
                            .background(hg.soft)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(name).font(.hgTitle(22)).foregroundStyle(hg.ink)
                            Text(model.account == nil ? "登录后可以同步点赞、收藏和评论" : "@\(model.account?.username ?? "")")
                                .font(.subheadline).foregroundStyle(hg.muted).lineLimit(2)
                        }
                    }
                    HStack(spacing: 0) {
                        stat("收藏", model.account == nil ? "\(model.favs.count)" : fmtCount(model.account?.collect ?? 0))
                        stat("喜欢", model.account == nil ? "\(model.likes.count)" : fmtCount(model.account?.like ?? 0))
                        stat("观看", "\(model.history.count)")
                    }
                    if model.account == nil {
                        Button(action: login) {
                            Text("登录").frame(maxWidth: .infinity).padding(.vertical, 12)
                        }
                        .background(hg.accent).foregroundStyle(hg.onAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(hg.card)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .padding(.horizontal, 20)

                VStack(spacing: 10) {
                    entry("star", "收藏", "\(model.favs.count) 部") { library("fav") }
                    entry("clock.arrow.circlepath", "观看历史", "\(model.history.count) 部") { library("history") }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 24)
        }
        .background(hg.paper)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.hgTitle(20)).foregroundStyle(hg.ink)
            Text(label).font(.caption).foregroundStyle(hg.faint)
        }
        .frame(maxWidth: .infinity)
    }

    private func entry(_ icon: String, _ title: String, _ sub: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(hg.accent)
                    .frame(width: 44, height: 44)
                    .background(hg.soft)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.hgTitle(18)).foregroundStyle(hg.ink)
                    Text(sub).font(.caption).foregroundStyle(hg.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(hg.faint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(hg.card)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }
}

struct LibraryScreen: View {
    var kind: String
    var back: () -> Void
    var open: (Int, Int, Double) -> Void
    var series: (Int, Int, Double) -> Void
    @EnvironmentObject private var model: AppModel
    @Environment(\.hg) private var hg
    @State private var cards: [Detail] = []
    @State private var swipe = false

    var body: some View {
        let ids = kind == "fav" ? model.favs : model.history.map(\.id)
        let title = kind == "fav" ? "收藏" : "观看历史"
        VStack(alignment: .leading, spacing: 8) {
            if swipe {
                HStack {
                    Button(action: back) {
                        Image(systemName: "chevron.left").foregroundStyle(.white).frame(width: 40, height: 40)
                    }
                    Text(title).font(.hgTitle(22)).foregroundStyle(.white)
                    Spacer()
                    Button { swipe = false } label: {
                        Text("列表").font(.subheadline).foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Color.white.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 12)
                if ids.isEmpty {
                    VStack(spacing: 6) {
                        Text(kind == "fav" ? "还没有收藏" : "还没有观看记录")
                            .font(.hgTitle(18)).foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    FeedScreen(
                        ids: ids,
                        start: 0,
                        startEp: kind == "history" ? (model.history.first?.ep ?? 1) : 1,
                        startTime: kind == "history" ? (model.history.first?.t ?? 0) : 0,
                        showsBack: false,
                        onEnterSeries: series,
                        progressFor: { id in
                            guard kind == "history", let watch = model.history.first(where: { $0.id == id }) else { return nil }
                            return (ep: watch.ep, time: watch.t)
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                PageHeader(title: title, sub: kind == "fav" ? "看到喜欢的短剧会留在这里" : "看过的剧会记在这里", back: back)
                HStack {
                    Spacer()
                    Button { swipe = true } label: {
                        Text("滑动").font(.subheadline).foregroundStyle(hg.ink)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(hg.card)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 20)
                ScrollView {
                    VStack(spacing: 12) {
                        if cards.isEmpty {
                            VStack(spacing: 6) {
                                Text(ids.isEmpty ? (kind == "fav" ? "还没有收藏" : "还没有观看记录") : "正在读取…")
                                    .font(.hgTitle(18)).foregroundStyle(hg.ink)
                                Text(ids.isEmpty ? (kind == "fav" ? "看到喜欢的短剧，点一下收藏" : "看过的剧会记在这里") : "稍等一下")
                                    .font(.subheadline).foregroundStyle(hg.muted)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 36)
                        }
                        ForEach(cards, id: \.id) { item in
                            let progress = model.history.first { $0.id == item.id }
                            let epName = item.episodes.first { $0.ep == progress?.ep }?.title ?? ""
                            let named = progress != nil && !epName.isEmpty && epName != "第\(progress!.ep)集"
                            Button {
                                open(item.id, progress?.ep ?? 1, kind == "history" ? (progress?.t ?? 0) : 0)
                            } label: {
                                HStack(spacing: 12) {
                                    CoverView(url: item.cover).frame(width: 64, height: 86).clipShape(RoundedRectangle(cornerRadius: 12))
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(item.title).font(.hgTitle(16)).foregroundStyle(hg.ink).lineLimit(2)
                                        Text(historyLine(kind: kind, episodes: item.episodes.count, progress: progress, epName: named ? epName : ""))
                                            .font(.caption).foregroundStyle(hg.muted)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(hg.faint)
                                }
                                .padding(12)
                                .background(hg.card)
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .background(swipe ? Color.black : hg.paper)
        .task(id: ids) { await reload(ids) }
    }

    private func reload(_ ids: [Int]) async {
        var loaded: [Detail] = []
        for id in ids.prefix(16) {
            if let detail = try? await model.api.video(id) { loaded.append(detail) }
        }
        cards = loaded
    }
}

private func historyLine(kind: String, episodes: Int, progress: Watch?, epName: String) -> String {
    guard kind == "history", let progress else { return "\(episodes) 集" }
    if epName.isEmpty { return "第 \(progress.ep) 集 · 看到 \(fmtClock(progress.t))" }
    return "第 \(progress.ep) 集 · \(epName) · 看到 \(fmtClock(progress.t))"
}

struct SettingsScreen: View {
    var back: () -> Void
    @EnvironmentObject private var model: AppModel
    @Environment(\.hg) private var hg
    @State private var mirrors: [String] = []
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                PageHeader(title: "设置", sub: "线路 · 外观 · 播放", back: back)
                label("外观")
                group {
                    toggle("深色外观", "暖色纸面，晚上更舒服", model.dark) { model.setDark($0) }
                }
                label("播放")
                group {
                    toggle("启动时静音", "下次打开仍然静音", model.muteOnStartup) { model.setMuteOnStartup($0) }
                    toggle("优先高清", "有高清就用 HEVC，播不了会回到标准", model.preferHevc) { model.setPreferHevc($0) }
                }
                label("线路")
                group {
                    ForEach(AppModel.fixed, id: \.1) { name, url in
                        line(name, url.replacingOccurrences(of: "https://", with: ""), model.base == url) {
                            guard model.base != url else { return }
                            model.setLine(url)
                            model.show("已切换到\(name)，账号需要重新登录")
                        }
                    }
                    ForEach(mirrors, id: \.self) { url in
                        line(url.replacingOccurrences(of: "https://", with: ""), "镜像，仅游客", model.base == url) {
                            model.setLine(url)
                            model.show("已切换镜像线路")
                        }
                    }
                    HStack {
                        VStack(alignment: .leading) {
                            Text("刷新镜像").foregroundStyle(hg.ink)
                            Text(busy ? "正在读取地址发布页" : "从发布页拉取").font(.caption).foregroundStyle(hg.muted)
                        }
                        Spacer()
                        Button("刷新") {
                            busy = true
                            Task {
                                do {
                                    mirrors = try await model.api.mirrors()
                                    model.show("已更新 \(mirrors.count) 条镜像")
                                } catch {
                                    model.show(error.localizedDescription)
                                }
                                busy = false
                            }
                        }
                        .disabled(busy).foregroundStyle(hg.accent)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
                label("本地")
                group {
                    row("清理封面缓存", "不影响收藏和历史", "清理", hg.accent) {
                        Covers.clear(); model.show("封面缓存已清理")
                    }
                    row("清空收藏和历史", "只清这台设备", "清空", hg.danger) {
                        model.clearLocal(); model.show("已清空")
                    }
                }
                Text("HGhub  \(model.base.replacingOccurrences(of: "https://", with: ""))\n包名 app.hghub.mobile\n未签名，需在 Xcode 里手动签名后安装。个人学习使用，不提供下载。")
                    .font(.caption).foregroundStyle(hg.faint).padding(20)
            }
        }
        .background(hg.paper)
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(hg.faint).padding(.horizontal, 24).padding(.top, 8)
    }

    private func group<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(hg.card).clipShape(RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 20)
    }

    private func toggle(_ title: String, _ sub: String, _ on: Bool, set: @escaping (Bool) -> Void) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title).foregroundStyle(hg.ink)
                Text(sub).font(.caption).foregroundStyle(hg.muted)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { on }, set: set)).labelsHidden().tint(hg.accent)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func line(_ title: String, _ sub: String, _ on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading) {
                    Text(title).foregroundStyle(hg.ink)
                    Text(sub).font(.caption).foregroundStyle(hg.muted)
                }
                Spacer()
                Text(on ? "当前" : "切换").foregroundStyle(on ? hg.accent : hg.muted)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }

    private func row(_ title: String, _ sub: String, _ actionTitle: String, _ color: Color, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title).foregroundStyle(hg.ink)
                Text(sub).font(.caption).foregroundStyle(hg.muted)
            }
            Spacer()
            Button(actionTitle, action: action).foregroundStyle(color)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

struct LoginSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.hg) private var hg
    @Environment(\.dismiss) private var dismiss
    @State private var mode = "login"
    @State private var username = ""
    @State private var password = ""
    @State private var email = ""
    @State private var error = ""
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(mode == "login" ? "登录" : "注册").font(.hgTitle(28)).foregroundStyle(hg.ink)
            Text("使用黄果短剧账号。镜像线路不能登录。").font(.subheadline).foregroundStyle(hg.muted)
            HStack {
                modeButton("登录", mode == "login") { mode = "login"; error = "" }
                modeButton("注册", mode == "register") { mode = "register"; error = "" }
            }
            .padding(4).background(hg.card).clipShape(RoundedRectangle(cornerRadius: 12))
            field("账号", text: $username)
            SecureField("密码", text: $password).padding(14).background(hg.card).clipShape(RoundedRectangle(cornerRadius: 14))
            if mode == "register" { field("邮箱，可选", text: $email) }
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(hg.danger) }
            Button { submit() } label: {
                Text(busy ? "处理中…" : (mode == "login" ? "登录" : "注册并登录"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .background(hg.accent).foregroundStyle(hg.onAccent)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .disabled(busy)
            if model.loggedIn {
                Button("退出登录") {
                    Task { await model.api.logout(); dismiss() }
                }
                .foregroundStyle(hg.danger)
            }
            Spacer()
        }
        .padding(22)
        .background(hg.paper)
    }

    private func modeButton(_ title: String, _ on: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .foregroundStyle(on ? hg.onAccent : hg.muted)
            .padding(.horizontal, 18).padding(.vertical, 8)
            .background(on ? hg.accent : hg.card)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func field(_ hint: String, text: Binding<String>) -> some View {
        TextField(hint, text: text).padding(14).background(hg.card).clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func submit() {
        guard !username.trimmingCharacters(in: .whitespaces).isEmpty, !password.isEmpty else {
            error = "请输入账号和密码"
            return
        }
        busy = true
        error = ""
        Task {
            do {
                let user = try await (mode == "login"
                    ? model.api.login(username: username.trimmingCharacters(in: .whitespaces), password: password)
                    : model.api.register(username: username.trimmingCharacters(in: .whitespaces), password: password, email: email.trimmingCharacters(in: .whitespaces)))
                password = ""
                model.show("欢迎，\(user.nickname)")
                busy = false
                dismiss()
            } catch let failure {
                error = failure.localizedDescription
                busy = false
            }
        }
    }
}
