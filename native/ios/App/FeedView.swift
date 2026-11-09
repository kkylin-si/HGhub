import AVFoundation
import SwiftUI
import UIKit

final class PlayerBox: ObservableObject {
    let player = AVPlayer()
    @Published var pos = 0.0
    @Published var dur = 0.0
    @Published var waiting = true
    @Published var paused = false
    @Published var failed = ""
    private var observer: Any?

    init() {
        player.isMuted = true
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.4, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self else { return }
            self.pos = time.seconds.isFinite ? time.seconds : 0
            let d = self.player.currentItem?.duration.seconds ?? 0
            self.dur = d.isFinite ? d : 0
            self.paused = self.player.timeControlStatus != .playing && self.player.currentItem?.status == .readyToPlay
            self.waiting = self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            if self.player.currentItem?.status == .failed {
                self.failed = "这一集暂时播不了，可换线路或重试"
                self.waiting = false
            }
        }
    }

    deinit {
        if let observer { player.removeTimeObserver(observer) }
    }

    func open(_ url: URL, muted: Bool) {
        failed = ""
        waiting = true
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.isMuted = muted
        player.play()
    }
}

struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    var fill = true
    func makeUIView(context: Context) -> PlayerHost {
        let view = PlayerHost()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        view.backgroundColor = .black
        return view
    }
    func updateUIView(_ uiView: PlayerHost, context: Context) {
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
    }
}

final class PlayerHost: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct FeedScreen: View {
    let ids: [Int]
    let start: Int
    var startEp: Int = 1
    var startTime: Double = 0
    var showsBack: Bool = true
    var onBack: () -> Void = {}
    var onNearEnd: () -> Void = {}

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var proxy: MediaProxy
    @Environment(\.hg) private var hg
    @StateObject private var box = PlayerBox()
    @State private var index = 0
    @State private var ep = 1
    @State private var detail: Detail?
    @State private var comments: [CommentItem] = []
    @State private var sheet: Sheet?
    @State private var draft = ""
    @State private var speed: Float = 1
    @State private var ticket = 0
    @State private var resume = 0.0
    @State private var fullscreen = false
    @State private var hevcAvailable = false

    private let speeds: [Float] = [1, 1.25, 1.5, 2]

    var body: some View {
        let id = ids.indices.contains(index) ? ids[index] : 0
        ZStack {
            Color.black.ignoresSafeArea()
            PlayerSurface(player: box.player, fill: !fullscreen).ignoresSafeArea()
            LinearGradient(colors: [.clear, .black.opacity(fullscreen ? 0.35 : 0.72)], startPoint: .center, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(spacing: 0) {
                topBar
                Spacer()
                progress
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                if !fullscreen {
                    HStack(alignment: .bottom) {
                        caption(id)
                        rail(id)
                    }
                    .padding(.horizontal, 16)
                }
                Color.clear.frame(height: fullscreen ? 64 : 48)
            }
            if box.waiting && box.failed.isEmpty {
                ProgressView().tint(hg.accent)
            }
            if box.paused && box.failed.isEmpty {
                Image(systemName: "play.fill").font(.system(size: 42)).foregroundStyle(.white)
            }
            if !box.failed.isEmpty {
                VStack(spacing: 12) {
                    Text(box.failed).foregroundStyle(.white).font(.subheadline)
                    Button("重试") { ticket += 1 }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(hg.accent).foregroundStyle(hg.onAccent).clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if box.player.timeControlStatus == .playing { box.player.pause() } else { box.player.play() }
        }
        .gesture(DragGesture(minimumDistance: 24).onEnded { value in
            if value.translation.height < -70 { step(1) }
            if value.translation.height > 70 { step(-1) }
        })
        .onAppear {
            index = min(max(start, 0), max(ids.count - 1, 0))
            ep = max(startEp, 1)
            resume = startTime
            box.player.isMuted = model.muted
        }
        .task(id: "\(id)-\(ep)-\(model.base)-\(ticket)-\(model.preferHevc)") { await load(id) }
        .onChange(of: index) { _ in onNearEnd() }
        .onChange(of: model.muted) { on in box.player.isMuted = on }
        .onChange(of: box.failed) { msg in
            guard !msg.isEmpty, model.preferHevc, hevcAvailable else { return }
            resume = max(box.pos, resume)
            box.failed = ""
            box.player.replaceCurrentItem(with: nil)
            model.setPreferHevc(false)
            model.show("高清暂时播不了，已切回标准")
        }
        .onChange(of: fullscreen) { on in
            model.immersive = on
            OrientationLock.apply(fullscreen: on)
        }
        .onDisappear {
            if fullscreen || model.immersive {
                fullscreen = false
                model.immersive = false
                OrientationLock.apply(fullscreen: false)
            }
        }
        .sheet(item: $sheet) { kind in
            sheetBody(kind, id: id).presentationDetents([.medium, .large])
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            if id > 0, box.dur > 0, box.pos > 0.8 {
                model.saveWatch(id: id, ep: ep, t: box.pos, dur: box.dur)
            }
            if resume > 0.4, box.dur > resume {
                box.player.seek(to: CMTime(seconds: resume, preferredTimescale: 600))
                resume = 0
            }
        }
    }

    private var topBar: some View {
        HStack {
            if showsBack {
                Button(action: onBack) { Image(systemName: "chevron.left").foregroundStyle(.white).padding(8) }
            } else {
                Text("HGhub").font(.hgTitle(22)).foregroundStyle(.white).padding(.leading, 8)
            }
            Spacer()
            if hevcAvailable {
                Button(model.preferHevc ? "高清" : "标准") {
                    resume = box.pos
                    model.setPreferHevc(!model.preferHevc)
                }
                .font(.subheadline).foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.black.opacity(0.35)).clipShape(Capsule())
            }
            Button {
                fullscreen.toggle()
            } label: {
                Image(systemName: fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .foregroundStyle(.white)
                    .padding(8)
            }
            if !fullscreen {
            Button("\(speedText)x") {
                if let i = speeds.firstIndex(of: speed) {
                    speed = speeds[(i + 1) % speeds.count]
                } else { speed = 1 }
                box.player.rate = speed
            }
            .font(.subheadline).foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.black.opacity(0.35)).clipShape(Capsule())
            }
            Button { model.setMuted(!model.muted) } label: {
                Image(systemName: model.muted ? "speaker.slash" : "speaker.wave.2").foregroundStyle(.white).padding(8)
            }
        }
        .padding(.top, 8)
    }

    private var speedText: String { speed == floor(speed) ? String(Int(speed)) : String(speed) }

    private func caption(_ id: Int) -> some View {
        let card = Library.shared.get(id)
        let title = detail?.title ?? card?.title ?? ""
        let tags = detail?.tags ?? card?.tags ?? []
        let desc = detail?.desc ?? card?.desc ?? ""
        return VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.hgTitle(22)).foregroundStyle(.white).lineLimit(2)
            if !tags.isEmpty { Text(tags.prefix(3).joined(separator: "  ·  ")).font(.caption).foregroundStyle(Color(red: 0.91, green: 0.82, blue: 0.78)) }
            if !desc.isEmpty { Text(desc.replacingOccurrences(of: "\n", with: " ")).font(.subheadline).foregroundStyle(.white.opacity(0.85)).lineLimit(2) }
            Text("第 \(ep) 集   \(fmtClock(box.pos)) / \(fmtClock(box.dur))").font(.caption).foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rail(_ id: Int) -> some View {
        VStack(spacing: 16) {
            railButton(model.isLiked(id) ? "heart.fill" : "heart", model.isLiked(id) ? hg.accent : .white, fmtCount(detail?.like ?? Library.shared.get(id)?.likeCount ?? 0)) {
                let on = model.toggleLike(id)
                guard model.loggedIn else { return }
                Task { try? await model.api.like(id, ep: ep, on: on) }
            }
            railButton(model.isFav(id) ? "star.fill" : "star", model.isFav(id) ? hg.accent : .white, "收藏") {
                let on = model.toggleFav(id)
                model.show(on ? "已收藏" : "已取消收藏")
                guard model.loggedIn else { return }
                Task { try? await model.api.collect(id, on: on) }
            }
            railButton("list.bullet", .white, "选集") { sheet = .episodes }
            railButton("text.bubble", .white, "评论") {
                sheet = .comments
                Task { comments = (try? await model.api.comments(id, ep: ep)) ?? [] }
            }
        }
    }

    private func railButton(_ name: String, _ color: Color, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: name).font(.title3).foregroundStyle(color)
                Text(label).font(.caption2).foregroundStyle(.white)
            }
        }
    }

    private var progress: some View {
        GeometryReader { geo in
            let frac = box.dur > 0 ? min(max(box.pos / box.dur, 0), 1) : 0
            ZStack(alignment: .leading) {
                Rectangle().fill(.white.opacity(0.28))
                Rectangle().fill(hg.accent).frame(width: geo.size.width * frac)
            }
            .frame(height: 3)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 0).onEnded { value in
                guard box.dur > 0 else { return }
                let x = min(max(value.location.x, 0), geo.size.width)
                box.player.seek(to: CMTime(seconds: Double(x / geo.size.width) * box.dur, preferredTimescale: 600))
            })
        }
        .frame(height: 22)
    }

    @ViewBuilder
    private func sheetBody(_ kind: Sheet, id: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(kind == .episodes ? (detail?.title ?? "选集") : "评论").font(.hgTitle(24)).foregroundStyle(hg.ink)
            if kind == .episodes {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(detail?.episodes ?? []) { item in
                            Button {
                                resume = 0
                                ep = item.ep
                                sheet = nil
                            } label: {
                                HStack {
                                    Text(item.ep == ep ? "正在播放" : "第 \(item.ep) 集").foregroundStyle(item.ep == ep ? hg.accent : hg.muted).frame(width: 72, alignment: .leading)
                                    Text(item.title).foregroundStyle(hg.ink)
                                    Spacer()
                                }
                                .padding(.vertical, 12)
                            }
                        }
                    }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if comments.isEmpty { Text("还没有评论").foregroundStyle(hg.muted) }
                        ForEach(comments) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.nickname).font(.subheadline.weight(.semibold)).foregroundStyle(hg.ink)
                                Text(item.text).foregroundStyle(hg.ink)
                                Text(item.time).font(.caption2).foregroundStyle(hg.faint)
                            }
                        }
                    }
                }
                HStack {
                    TextField("说点什么", text: $draft).textFieldStyle(.roundedBorder)
                    Button("发送") {
                        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return }
                        guard model.loggedIn else { model.show("登录后才能评论"); return }
                        Task {
                            do {
                                try await model.api.sendComment(id, ep: ep, text: text)
                                draft = ""
                                model.show("已发送")
                                comments = (try? await model.api.comments(id, ep: ep)) ?? comments
                            } catch {
                                model.show(error.localizedDescription)
                            }
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(hg.accent).foregroundStyle(hg.onAccent).clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(20)
        .background(hg.paper)
    }

    private func step(_ delta: Int) {
        let next = index + delta
        guard ids.indices.contains(next) else { return }
        index = next
        ep = 1
        resume = 0
        detail = nil
    }

    private func load(_ id: Int) async {
        guard id > 0 else { return }
        do {
            async let d = model.api.video(id)
            async let p = model.api.play(id, ep: ep)
            let (detail, play) = try await (d, p)
            self.detail = detail
            if detail.liked && !model.isLiked(id) { model.toggleLike(id) }
            if detail.collected && !model.isFav(id) { model.toggleFav(id) }
            let hevc = play.hevcUrl
            hevcAvailable = !hevc.isEmpty
            let standard = play.videoUrl.isEmpty ? detail.videoUrl : play.videoUrl
            let remote = (model.preferHevc && !hevc.isEmpty) ? hevc : standard
            guard !remote.isEmpty, let local = proxy.wrap(remote) else {
                box.failed = "没有可播放的地址"
                box.waiting = false
                return
            }
            box.open(local, muted: model.muted)
            if speed != 1 { box.player.rate = speed }
        } catch {
            box.failed = error.localizedDescription
            box.waiting = false
        }
    }
}

enum Sheet: Identifiable {
    case episodes, comments
    var id: Int { self == .episodes ? 0 : 1 }
}

@MainActor
final class Library {
    static let shared = Library()
    private var cards: [Int: VideoCard] = [:]
    func put(_ items: [VideoCard]) { items.forEach { cards[$0.id] = $0 } }
    func get(_ id: Int) -> VideoCard? { cards[id] }
}

struct HomeFeed: View {
    @EnvironmentObject private var model: AppModel
    @State private var items: [VideoCard] = []
    @State private var page = 1
    @State private var done = false
    @State private var error = ""
    @State private var loading = false

    var body: some View {
        Group {
            if items.isEmpty && loading { ProgressView().tint(HgPalette.light.accent) }
            else if items.isEmpty {
                VStack(spacing: 10) {
                    Text("首页加载失败").font(.hgTitle(22))
                    Text(error.isEmpty ? "请检查网络或切换线路" : error).font(.subheadline).foregroundStyle(.secondary)
                    Button("重试") { Task { await load(1, reset: true) } }
                }
            } else {
                FeedScreen(ids: items.map(\.id), start: 0, showsBack: false, onNearEnd: {
                    if !done && !loading && indexNearEnd { Task { await load(page + 1, reset: false) } }
                })
            }
        }
        .task { if items.isEmpty { await load(1, reset: true) } }
    }

    private var indexNearEnd: Bool { true }

    private func load(_ next: Int, reset: Bool) async {
        if loading || (done && !reset) { return }
        loading = true
        defer { loading = false }
        do {
            let (list, info) = try await model.api.feed(page: next)
            Library.shared.put(list)
            items = next == 1 ? list : unique(items + list)
            page = next
            done = list.isEmpty || next >= info.pages
            error = ""
        } catch let failure {
            error = failure.localizedDescription
            if items.isEmpty { model.show(failure.localizedDescription) }
        }
    }

    private func unique(_ list: [VideoCard]) -> [VideoCard] {
        var seen = Set<Int>()
        return list.filter { seen.insert($0.id).inserted }
    }
}
