import SwiftUI
import UIKit

let Channels: [(String, String)] = [
    ("ai-duanju", "AI成人短剧"),
    ("ai-manju", "AI成人漫剧"),
    ("ai-huanlian", "AI换脸"),
    ("ai-mogai", "AI魔改"),
]
private let hotTags = ["都市", "逆袭", "古风", "系统", "校园", "仙侠", "职场", "脑洞", "奇幻"]

struct SearchScreen: View {
    var open: ([Int], Int) -> Void
    var ranks: () -> Void
    @EnvironmentObject private var model: AppModel
    @Environment(\.hg) private var hg
    @State private var q = ""
    @State private var submitted = ""
    @State private var items: [VideoCard] = []
    @State private var page = 1
    @State private var pages = 1
    @State private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "搜索", sub: "短剧、作者、题材")
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(hg.faint)
                TextField("搜索", text: $q).foregroundStyle(hg.ink)
                    .onSubmit { run(q, 1) }
                Button("搜索") { run(q, 1) }.foregroundStyle(hg.accent)
            }
            .padding(12)
            .background(hg.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 20)
            if submitted.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !model.searches.isEmpty {
                            HStack {
                                Text("最近").font(.hgTitle(18)).foregroundStyle(hg.ink)
                                Spacer()
                                Button("清空") { model.clearSearch() }.font(.caption).foregroundStyle(hg.faint)
                            }
                            chipRow(model.searches)
                        }
                        Text("热门题材").font(.hgTitle(18)).foregroundStyle(hg.ink)
                        chipRow(hotTags)
                        Button("查看排行榜") { ranks() }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(hg.accent).foregroundStyle(hg.onAccent)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(20)
                }
            } else if items.isEmpty && !error.isEmpty {
                Spacer()
                Text(error).foregroundStyle(hg.muted)
                Button("重试") { run(submitted, 1) }.foregroundStyle(hg.accent)
                Spacer()
            } else {
                List {
                    ForEach(items) { item in
                        Button { open(items.map(\.id), items.firstIndex(of: item) ?? 0) } label: { VideoLine(item: item) }
                    }
                    if page < pages {
                        Button("更多") { run(submitted, page + 1) }.foregroundStyle(hg.accent)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(hg.paper)
    }

    private func chipRow(_ values: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(values, id: \.self) { tag in
                    Button(tag) { q = tag; run(tag, 1) }
                        .font(.subheadline).foregroundStyle(hg.ink)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(hg.card).clipShape(Capsule())
                }
            }
        }
    }

    private func run(_ raw: String, _ next: Int) {
        let k = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        submitted = k
        model.rememberSearch(k)
        Task {
            do {
                let (list, info) = try await model.api.search(k, page: next)
                Library.shared.put(list)
                items = next == 1 ? list : unique(items + list)
                page = next
                pages = info.pages
                error = ""
            } catch let failure {
                error = failure.localizedDescription
            }
        }
    }

    private func unique(_ list: [VideoCard]) -> [VideoCard] {
        var seen = Set<Int>()
        return list.filter { seen.insert($0.id).inserted }
    }
}

struct CategoryScreen: View {
    var channel: (String, String) -> Void
    var ranks: () -> Void
    var posts: () -> Void
    var open: ([Int], Int) -> Void
    @EnvironmentObject private var model: AppModel
    @Environment(\.hg) private var hg
    @State private var rows: [String: [VideoCard]] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "分类", sub: "四个频道，持续更新")
                Button { ranks() } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("排行榜").font(.hgTitle(18)).foregroundStyle(hg.ink)
                            Text("热播 · 推荐 · 潜力").font(.caption).foregroundStyle(hg.muted)
                        }
                        Spacer()
                        Text("打开").foregroundStyle(hg.accent)
                    }
                    .padding(16).background(hg.card).clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .padding(.horizontal, 20)
                ForEach(Channels, id: \.0) { cate, name in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(name).font(.hgTitle(20)).foregroundStyle(hg.ink)
                            Spacer()
                            Button("全部") { channel(cate, name) }.font(.subheadline).foregroundStyle(hg.muted)
                        }
                        .padding(.horizontal, 20)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                let list = rows[cate] ?? []
                                if list.isEmpty { Text("加载中").foregroundStyle(hg.faint).padding(.vertical, 28) }
                                ForEach(list) { item in
                                    Button { open(list.map(\.id), list.firstIndex(of: item) ?? 0) } label: {
                                        VStack(alignment: .leading) {
                                            CoverView(url: item.cover).frame(width: 112, height: 150).clipShape(RoundedRectangle(cornerRadius: 14))
                                            Text(item.title).font(.caption).foregroundStyle(hg.ink).lineLimit(2).frame(width: 112, alignment: .leading)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }
                Button { posts() } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("黄果吃瓜").font(.hgTitle(20)).foregroundStyle(hg.ink)
                            Text("圈内更新").font(.caption).foregroundStyle(hg.muted)
                        }
                        Spacer()
                        Text("进入").foregroundStyle(hg.accent)
                    }
                    .padding(16).background(hg.soft).clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .padding(.horizontal, 20)
            }
        }
        .background(hg.paper)
        .task {
            for (cate, _) in Channels where rows[cate] == nil {
                if let (list, _) = try? await model.api.category(cate, page: 1, size: 8) {
                    Library.shared.put(list)
                    rows[cate] = list
                }
            }
        }
    }
}

struct ChannelScreen: View {
    let cate: String
    let name: String
    var back: () -> Void
    var open: ([Int], Int) -> Void
    @EnvironmentObject private var model: AppModel
    @Environment(\.hg) private var hg
    @State private var items: [VideoCard] = []
    @State private var page = 1
    @State private var pages = 1
    @State private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: name, back: back)
            if items.isEmpty && error.isEmpty { Spacer(); ProgressView(); Spacer() }
            else if items.isEmpty {
                Spacer(); Text(error).foregroundStyle(hg.muted); Button("重试") { Task { await load(1) } }; Spacer()
            } else {
                List {
                    ForEach(items) { item in
                        Button { open(items.map(\.id), items.firstIndex(of: item) ?? 0) } label: { VideoLine(item: item) }
                    }
                    if page < pages { Button("更多") { Task { await load(page + 1) } }.foregroundStyle(hg.accent) }
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
            }
        }
        .background(hg.paper)
        .task { await load(1) }
    }

    private func load(_ next: Int) async {
        do {
            let (list, info) = try await model.api.category(cate, page: next)
            Library.shared.put(list)
            items = next == 1 ? list : items + list.filter { card in !items.contains(card) }
            page = next
            pages = info.pages
        } catch let failure {
            error = failure.localizedDescription
        }
    }
}

struct RankScreen: View {
    var back: () -> Void
    var open: (Int) -> Void
    @EnvironmentObject private var model: AppModel
    @Environment(\.hg) private var hg
    @State private var kind = "hot"
    @State private var items: [RankItem] = []
    @State private var error = ""
    private let kinds = [("hot", "热播"), ("recommend", "推荐"), ("potential", "潜力")]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PageHeader(title: "排行榜", back: back)
            HStack {
                ForEach(kinds, id: \.0) { key, label in
                    Button(label) { kind = key }
                        .font(.subheadline)
                        .foregroundStyle(kind == key ? hg.onAccent : hg.ink)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(kind == key ? hg.accent : hg.card)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 20)
            if items.isEmpty && error.isEmpty { Spacer(); ProgressView(); Spacer() }
            else if items.isEmpty { Spacer(); Text(error).foregroundStyle(hg.muted); Spacer() }
            else {
                List(items) { item in
                    Button { open(item.videoId) } label: {
                        HStack(spacing: 12) {
                            CoverView(url: item.cover).frame(width: 64, height: 86).clipShape(RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(.hgTitle(16)).foregroundStyle(hg.ink).lineLimit(2)
                                Text("\(item.rank)  ·  \(item.metric)").font(.caption).foregroundStyle(hg.muted)
                            }
                        }
                    }
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
            }
        }
        .background(hg.paper)
        .task(id: kind) {
            error = ""
            items = []
            do { items = try await model.api.rank(kind) } catch let failure { error = failure.localizedDescription }
        }
    }
}

struct PostsScreen: View {
    var back: () -> Void
    var open: (Int) -> Void
    @EnvironmentObject private var model: AppModel
    @Environment(\.hg) private var hg
    @State private var items: [PostItem] = []
    @State private var page = 1
    @State private var pages = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "吃瓜", sub: "每日更新", back: back)
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(items) { post in
                        Button { open(post.id) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                CoverView(url: post.cover).frame(height: 120).clipShape(RoundedRectangle(cornerRadius: 12))
                                Text(post.title).font(.subheadline).foregroundStyle(hg.ink).lineLimit(2)
                            }
                            .padding(8).background(hg.card).clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
                .padding(16)
                if page < pages {
                    Button("更多") { Task { await load(page + 1) } }.foregroundStyle(hg.accent).padding(.bottom, 20)
                }
            }
        }
        .background(hg.paper)
        .task { await load(1) }
    }

    private func load(_ next: Int) async {
        guard let (list, info) = try? await model.api.posts(page: next) else { return }
        items = next == 1 ? list : items + list.filter { post in !items.contains(post) }
        page = next
        pages = info.pages
    }
}

struct PostScreen: View {
    let id: Int
    var back: () -> Void
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var proxy: MediaProxy
    @Environment(\.hg) private var hg
    @State private var post: PostItem?
    @State private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: post?.title ?? "正文", back: back)
            if let post {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        CoverView(url: post.cover).frame(height: 190).clipShape(RoundedRectangle(cornerRadius: 16))
                        if !post.videoUrl.isEmpty, let local = proxy.wrap(post.videoUrl) {
                            InlinePlayer(url: local).frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        Text(plain(post.content.isEmpty ? post.desc : post.content))
                            .foregroundStyle(hg.ink).font(.body)
                    }
                    .padding(20)
                }
            } else if error.isEmpty {
                Spacer(); ProgressView(); Spacer()
            } else {
                Spacer(); Text(error).foregroundStyle(hg.muted); Spacer()
            }
        }
        .background(hg.paper)
        .task {
            do { post = try await model.api.post(id) } catch let failure { error = failure.localizedDescription }
        }
    }

    private func plain(_ html: String) -> String {
        var text = html
        if let regex = try? NSRegularExpression(pattern: "(?is)<(script|style).*?>.*?</\\1>") {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        }
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return text.replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct PageHeader: View {
    let title: String
    var sub: String? = nil
    var back: (() -> Void)? = nil
    @Environment(\.hg) private var hg
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let back {
                Button(action: back) { Image(systemName: "chevron.left").foregroundStyle(hg.ink).frame(width: 40, height: 40) }
            }
            Text(title).font(.hgTitle(32)).foregroundStyle(hg.ink)
            if let sub { Text(sub).font(.subheadline).foregroundStyle(hg.muted) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}

struct VideoLine: View {
    let item: VideoCard
    @Environment(\.hg) private var hg
    var body: some View {
        HStack(spacing: 12) {
            CoverView(url: item.cover).frame(width: 72, height: 96).clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title).font(.hgTitle(16)).foregroundStyle(hg.ink).lineLimit(2)
                Text(meta).font(.caption).foregroundStyle(hg.muted).lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
    private var meta: String {
        [item.episodeCount > 0 ? "\(item.episodeCount) 集" : "", item.hot > 0 ? "热度 \(fmtCount(item.hot))" : "", item.author]
            .filter { !$0.isEmpty }.joined(separator: "  ·  ")
    }
}

struct CoverView: View {
    let url: String
    @EnvironmentObject private var model: AppModel
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            Rectangle().fill(Color.gray.opacity(0.12))
            if let image { Image(uiImage: image).resizable().scaledToFill() }
        }
        .clipped()
        .task(id: url) { image = await Covers.load(url, api: model.api) }
    }
}

struct InlinePlayer: View {
    let url: URL
    @StateObject private var box = PlayerBox()
    var body: some View {
        PlayerSurface(player: box.player).onAppear { box.open(url, muted: true) }
    }
}
