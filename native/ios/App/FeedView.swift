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

/// 系统 UISlider：拖动时圆点跟手，播放时按屏幕刷新往前走。
struct NativeScrubber: UIViewRepresentable {
    let player: AVPlayer
    var accent: UIColor
    var onLabel: (String?) -> Void

    func makeUIView(context: Context) -> ScrubberBar {
        let bar = ScrubberBar()
        bar.onLabel = onLabel
        bar.player = player
        bar.apply(accent: accent)
        return bar
    }

    func updateUIView(_ uiView: ScrubberBar, context: Context) {
        uiView.onLabel = onLabel
        uiView.player = player
        uiView.apply(accent: accent)
    }

    static func dismantleUIView(_ uiView: ScrubberBar, coordinator: ()) {
        uiView.stop()
    }
}

final class ScrubberBar: UIView {
    let slider = ThickSlider()
    var onLabel: ((String?) -> Void)?
    weak var player: AVPlayer?
    private var link: CADisplayLink?
    private var lastSeek: CFTimeInterval = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.isContinuous = true
        slider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(slider)
        NSLayoutConstraint.activate([
            slider.leadingAnchor.constraint(equalTo: leadingAnchor),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor),
            slider.centerYAnchor.constraint(equalTo: centerYAnchor),
            slider.heightAnchor.constraint(equalToConstant: 40),
        ])
        slider.addTarget(self, action: #selector(changed), for: .valueChanged)
        slider.addTarget(self, action: #selector(ended), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    required init?(coder: NSCoder) { nil }

    private var appliedAccent: UIColor?

    func apply(accent: UIColor) {
        if appliedAccent?.isEqual(accent) == true { return }
        appliedAccent = accent
        slider.minimumTrackTintColor = accent
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.35)
        slider.setThumbImage(ScrubberBar.thumb, for: .normal)
        slider.setMinimumTrackImage(ScrubberBar.track(accent), for: .normal)
        slider.setMaximumTrackImage(ScrubberBar.track(UIColor.white.withAlphaComponent(0.35)), for: .normal)
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    deinit { stop() }

    @objc private func tick() {
        guard !slider.isTracking, let item = player?.currentItem else { return }
        let duration = item.duration.seconds
        let position = player?.currentTime().seconds ?? 0
        guard duration.isFinite, duration > 0, position.isFinite else { return }
        slider.setValue(Float(min(max(position / duration, 0), 1)), animated: false)
    }

    @objc private func changed() {
        guard slider.isTracking else { return }
        seek(exact: false)
    }

    @objc private func ended() {
        seek(exact: true)
        onLabel?(nil)
    }

    private func seek(exact: Bool) {
        guard let player, let item = player.currentItem else { return }
        let duration = item.duration.seconds
        guard duration.isFinite, duration > 0 else { return }
        let seconds = Double(slider.value) * duration
        onLabel?(fmtClock(seconds))
        let now = CACurrentMediaTime()
        if !exact && now - lastSeek < 0.05 { return }
        lastSeek = now
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        if exact {
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            player.seek(to: time, toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity)
        }
    }

    private static let thumb: UIImage = {
        let side: CGFloat = 24
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { _ in
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: side, height: side)).fill()
        }
    }()

    private static func track(_ color: UIColor) -> UIImage {
        let height: CGFloat = 10
        let width: CGFloat = 12
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { _ in
            color.setFill()
            UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: height), cornerRadius: height / 2).fill()
        }
        return image.resizableImage(withCapInsets: UIEdgeInsets(top: 0, left: 5, bottom: 0, right: 5), resizingMode: .stretch)
    }
}

final class ThickSlider: UISlider {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -8, dy: -16).contains(point)
    }
}

struct FeedScreen: View {
    let ids: [Int]
    let start: Int
    var startEp: Int = 1
    var startTime: Double = 0
    var showsBack: Bool = true
    /// 为真时上下滑切换的是这一部的集，而不是下一部剧。
    var episodePaging = false
    var onBack: () -> Void = {}
    var onNearEnd: () -> Void = {}
    var onEnterSeries: ((Int, Int, Double) -> Void)? = nil
    /// 历史滑动时，每部剧回到自己记下的集数和进度。
    var progressFor: (Int) -> (ep: Int, time: Double)? = { _ in nil }

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
    @State private var chrome = true
    @State private var hideChrome: Task<Void, Never>?
    @State private var scrubLabel: String?
    @State private var hevcAvailable = false
    @State private var qualityKnown = false
    @State private var playTask: Task<Void, Never>?
    @State private var picked = false
    @State private var commentExtra = 0
    @State private var lastEnded = 0.0
    @State private var switching = false
    @State private var lineAttempt = 0
    @State private var lineFor = ""
    @State private var waitSince: Date?

    private let speeds: [Float] = [1, 1.25, 1.5, 2]

    var body: some View {
        let id = ids.indices.contains(index) ? ids[index] : 0
        GeometryReader { _ in
            ZStack {
                Color.black
                if fullscreen {
                    PlayerSurface(player: box.player, fill: false).ignoresSafeArea()
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { toggleChrome() }
                        .gesture(episodeSwipe)
                    if chrome {
                        VStack(spacing: 0) {
                            topBar
                            Spacer()
                            progress.padding(.horizontal, 12)
                            episodeBar(id, pickHere: true)
                                .padding(.horizontal, 16)
                                .padding(.top, 6)
                                .padding(.bottom, 16)
                        }
                    }
                    playbackStatus
                } else {
                    PlayerSurface(player: box.player, fill: true)
                        .ignoresSafeArea()
                    LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if box.player.timeControlStatus == .playing { box.player.pause() } else { box.player.play() }
                        }
                        .gesture(episodeSwipe)
                    VStack(spacing: 0) {
                        topBar
                        Spacer()
                        HStack {
                            Spacer()
                            rail(id)
                                .padding(.trailing, 10)
                                .padding(.bottom, 12)
                        }
                        Button {
                            chrome = true
                            fullscreen = true
                        } label: {
                            Label("全屏观看", systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(.black.opacity(0.45))
                                .clipShape(Capsule())
                        }
                        .padding(.bottom, 12)
                        if !episodePaging {
                            caption(id)
                                .padding(.horizontal, 16)
                                .padding(.trailing, 64)
                                .padding(.bottom, 6)
                        }
                        progress.padding(.horizontal, 12)
                        episodeBar(id)
                            .padding(.horizontal, 12)
                            .padding(.top, 6)
                            .padding(.bottom, 8)
                    }
                    playbackStatus
                }
            }
        }
        .background(Color.black)
        .onAppear {
            index = min(max(start, 0), max(ids.count - 1, 0))
            ep = max(startEp, 1)
            resume = startTime
            box.player.isMuted = model.muted
            queuePlayback()
        }
        .onChange(of: index) { newIndex in
            commentExtra = 0
            if !episodePaging, ids.count - newIndex <= 3 { onNearEnd() }
            queuePlayback()
        }
        .onChange(of: ep) { value in
            queuePlayback()
            let current = ids.indices.contains(index) ? ids[index] : 0
            guard current > 0, episodePaging || picked else { return }
            let prev = model.history.first { $0.id == current }
            let t = prev?.ep == value ? (prev?.t ?? 0) : 0
            model.saveWatch(id: current, ep: value, t: t, dur: prev?.dur ?? box.dur)
        }
        .onChange(of: ticket) { _ in queuePlayback() }
        .onChange(of: model.base) { _ in queuePlayback() }
        .onChange(of: model.preferHevc) { _ in queuePlayback() }
        .onDisappear {
            playTask?.cancel()
            hideChrome?.cancel()
        }
        .onChange(of: model.muted) { on in box.player.isMuted = on }
        .onChange(of: box.failed) { msg in
            guard !msg.isEmpty else { return }
            if model.preferHevc, hevcAvailable {
                resume = max(box.pos, resume)
                box.failed = ""
                box.player.replaceCurrentItem(with: nil)
                model.setPreferHevc(false)
                model.show("高清暂时播不了，已切回标准")
                return
            }
            let all = playbackOrigins(model.base)
            guard lineAttempt < all.count - 1 else { return }
            lineAttempt += 1
            box.failed = ""
            model.show("当前线路拥挤，正在换线路")
            queuePlayback()
        }
        .onChange(of: fullscreen) { on in
            model.immersive = on
            OrientationLock.apply(fullscreen: on)
            chrome = true
            if on { armChromeHide() } else { hideChrome?.cancel() }
        }
        .onChange(of: scrubLabel) { value in
            if value != nil { hideChrome?.cancel() } else { armChromeHide() }
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
                model.saveWatch(id: id, ep: ep, t: box.pos, dur: box.dur, keepFurther: !episodePaging && !picked)
            }
            if box.pos > 0.5 { waitSince = nil }
            if box.failed.isEmpty, (switching || box.waiting), box.pos < 0.5, let waitSince, Date().timeIntervalSince(waitSince) > 9 {
                self.waitSince = nil
                let all = playbackOrigins(model.base)
                if lineAttempt < all.count - 1 {
                    lineAttempt += 1
                    model.show("当前线路拥挤，正在换线路")
                    queuePlayback()
                }
            }
            if resume > 0.4, box.dur > resume {
                box.player.seek(to: CMTime(seconds: resume, preferredTimescale: 600))
                resume = 0
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
            guard let item = note.object as? AVPlayerItem, item == box.player.currentItem else { return }
            let now = Date().timeIntervalSince1970
            guard now - lastEnded > 0.7 else { return }
            lastEnded = now
            let current = ids.indices.contains(index) ? ids[index] : 0
            let total = episodeCount(current)
            if ep < total {
                resume = 0
                if episodePaging {
                    step(1)
                } else {
                    picked = true
                    ep += 1
                }
            } else {
                resume = 0
                box.player.seek(to: .zero)
                box.player.play()
            }
        }
    }

    private var topBar: some View {
        HStack {
            if fullscreen || showsBack {
                Button {
                    if fullscreen { fullscreen = false } else { onBack() }
                } label: {
                    Image(systemName: "chevron.left").foregroundStyle(.white).padding(8)
                }
                if episodePaging || fullscreen {
                    Text("第 \(ep) 集").font(.hgTitle(18)).foregroundStyle(.white)
                }
            } else {
                Text("HGhub").font(.hgTitle(22)).foregroundStyle(.white).padding(.leading, 8)
            }
            Spacer()
            Menu {
                let playingHevc = model.preferHevc && (hevcAvailable || !qualityKnown)
                Button {
                    guard model.preferHevc else { return }
                    resume = box.pos
                    model.setPreferHevc(false)
                    armChromeHide()
                } label: {
                    Text(playingHevc ? "标准" : "标准  ✓")
                }
                Button {
                    if qualityKnown, !hevcAvailable {
                        model.show("这一集没有高清")
                        return
                    }
                    guard !model.preferHevc else { return }
                    resume = box.pos
                    model.setPreferHevc(true)
                    armChromeHide()
                } label: {
                    if qualityKnown, !hevcAvailable {
                        Text("高清（这一集没有）")
                    } else {
                        Text(playingHevc ? "高清  ✓" : "高清")
                    }
                }
            } label: {
                let playingHevc = model.preferHevc && (hevcAvailable || !qualityKnown)
                Text(playingHevc ? "高清" : "标准")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.black.opacity(0.35))
                    .clipShape(Capsule())
            }
            Button {
                fullscreen.toggle()
            } label: {
                Image(systemName: fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .foregroundStyle(.white)
                    .padding(8)
            }
            Button("\(speedText)x") {
                if let i = speeds.firstIndex(of: speed) {
                    speed = speeds[(i + 1) % speeds.count]
                } else { speed = 1 }
                box.player.rate = speed
                armChromeHide()
            }
            .font(.subheadline).foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.black.opacity(0.35)).clipShape(Capsule())
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
            railButton("text.bubble", .white, detail == nil && commentExtra == 0 ? "评论" : fmtCount((detail?.comment ?? 0) + commentExtra)) {
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

    private var episodeSwipe: some Gesture {
        DragGesture(minimumDistance: 36).onEnded { value in
            let dy = value.translation.height
            guard abs(dy) > abs(value.translation.width), abs(dy) > 64 else { return }
            step(dy < 0 ? 1 : -1)
        }
    }

    private var progress: some View {
        VStack(spacing: 2) {
            NativeScrubber(player: box.player, accent: UIColor(hg.accent)) { scrubLabel = $0 }
                .frame(height: 36)
                .overlay(alignment: .top) {
                    if let scrubLabel {
                        Text(scrubLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .offset(y: -16)
                    }
                }
            Text("\(scrubLabel ?? fmtClock(box.pos)) / \(fmtClock(box.dur))")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity)
        }
        .frame(height: 58)
    }

    private func toggleChrome() {
        chrome.toggle()
        if chrome { armChromeHide() } else { hideChrome?.cancel() }
    }

    private func armChromeHide() {
        hideChrome?.cancel()
        guard fullscreen, chrome else { return }
        hideChrome = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            chrome = false
        }
    }

    @ViewBuilder
    private var playbackStatus: some View {
        if (switching || box.waiting) && box.failed.isEmpty {
            VStack(spacing: 8) {
                ProgressView().tint(hg.accent)
                Text("加载中").font(.caption).foregroundStyle(.white)
            }
        }
        if box.paused && box.failed.isEmpty {
            Button { box.player.play() } label: {
                Image(systemName: "play.fill").font(.system(size: 42)).foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        if !box.failed.isEmpty {
            VStack(spacing: 12) {
                Text(box.failed).foregroundStyle(.white).font(.subheadline).multilineTextAlignment(.center)
                Button("重试") {
                    lineAttempt = 0
                    lineFor = ""
                    ticket += 1
                }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(hg.accent).foregroundStyle(hg.onAccent).clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24)
        }
    }

    private func episodeCount(_ id: Int) -> Int {
        if let detail, detail.id == id, !detail.episodes.isEmpty { return detail.episodes.count }
        if let count = Library.shared.get(id)?.episodeCount, count > 0 { return count }
        return max(ep, 1)
    }

    private func episodeBar(_ id: Int, pickHere: Bool = false) -> some View {
        let count = episodeCount(id)
        let title = (episodePaging || pickHere) ? "选集 · 第 \(ep) 集 · 全 \(count) 集" : "选集 · 全 \(count) 集"
        return Button {
            if pickHere || episodePaging || onEnterSeries == nil {
                sheet = .episodes
            } else {
                onEnterSeries?(id, ep, box.pos)
            }
            armChromeHide()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.rectangle.on.rectangle")
                Text(title).lineLimit(1)
                Spacer()
                Image(systemName: (episodePaging || fullscreen) ? "chevron.up" : "chevron.right")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
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
                                picked = true
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
                                commentExtra += 1
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
        if episodePaging {
            let id = ids.indices.contains(index) ? ids[index] : 0
            let total = episodeCount(id)
            let next = ep + delta
            let ceiling = detail?.id == id && !(detail?.episodes.isEmpty ?? true) ? total : max(total, ep + 1)
            guard next >= 1, next <= ceiling else { return }
            resume = 0
            ep = next
        } else {
            let next = index + delta
            guard ids.indices.contains(next) else { return }
            index = next
            picked = false
            detail = nil
            if let saved = progressFor(ids[next]) {
                ep = max(saved.ep, 1)
                resume = saved.time
            } else {
                ep = 1
                resume = 0
            }
        }
    }

    /// 连续快滑时只播放停下来的那一集，避免把上一个请求的失败当成当前集的错误。
    private func queuePlayback() {
        playTask?.cancel()
        let id = ids.indices.contains(index) ? ids[index] : 0
        let episode = ep
        let marker = "\(id):\(episode)"
        if lineFor != marker {
            lineFor = marker
            lineAttempt = 0
        }
        switching = true
        box.failed = ""
        waitSince = Date()
        playTask = Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            await load(id, episode: episode)
        }
    }

    private func load(_ id: Int, episode: Int) async {
        guard id > 0 else { return }
        guard !Task.isCancelled else { return }
        switching = true
        do {
            let loaded = try? await model.api.video(id)
            guard !Task.isCancelled, self.ep == episode, (ids.indices.contains(index) ? ids[index] : 0) == id else { return }
            if let loaded { detail = loaded }
            if episodePaging, let loaded, !loaded.episodes.isEmpty, episode > loaded.episodes.count {
                ep = loaded.episodes.count
                return
            }
            if let loaded {
                if loaded.liked && !model.isLiked(id) { model.toggleLike(id) }
                if loaded.collected && !model.isFav(id) { model.toggleFav(id) }
            }
            let lines = Array(playbackOrigins(model.base).dropFirst(lineAttempt))
            var play: PlayInfo?
            var used = ""
            var last = "没有可播放的地址"
            for origin in lines {
                if Task.isCancelled || self.ep != episode { return }
                do {
                    let info = try await model.api.play(id, ep: episode, origin: origin)
                    let candidate = (model.preferHevc && !info.hevcUrl.isEmpty) ? info.hevcUrl : info.videoUrl
                    if !candidate.isEmpty || !info.videoUrl.isEmpty {
                        play = info
                        used = origin
                        break
                    }
                } catch is CancellationError {
                    return
                } catch {
                    last = error.localizedDescription
                }
            }
            guard !Task.isCancelled, self.ep == episode else { return }
            guard let play, !used.isEmpty else {
                box.failed = last
                box.waiting = false
                switching = false
                return
            }
            hevcAvailable = !play.hevcUrl.isEmpty
            qualityKnown = true
            let standard = play.videoUrl.isEmpty ? (detail?.videoUrl ?? "") : play.videoUrl
            let remote = (model.preferHevc && !play.hevcUrl.isEmpty) ? play.hevcUrl : standard
            guard !remote.isEmpty else {
                box.failed = "没有可播放的地址"
                box.waiting = false
                switching = false
                return
            }
            proxy.updateReferer(used + "/")
            guard let local = proxy.wrap(remote) else {
                box.failed = "没有可播放的地址"
                box.waiting = false
                switching = false
                return
            }
            box.open(local, muted: model.muted)
            if speed != 1 { box.player.rate = speed }
            switching = false
        }
    }

    private func playbackOrigins(_ current: String) -> [String] {
        let fixed = ["https://huangguoai.com", "https://huangguoai.ai"]
        var all: [String] = []
        for raw in [current] + fixed {
            let url = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if url.hasPrefix("https://") && !all.contains(url) { all.append(url) }
        }
        return all
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
    var openSeries: (Int, Int, Double) -> Void = { _, _, _ in }
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
                    if !done && !loading { Task { await load(page + 1, reset: false) } }
                }, onEnterSeries: openSeries)
            }
        }
        .task { if items.isEmpty { await load(1, reset: true) } }
    }

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
