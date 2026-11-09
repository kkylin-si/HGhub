import SwiftUI

enum Route: Hashable {
    case feed(ids: [Int], index: Int, ep: Int, time: Double)
    case series(id: Int, ep: Int, time: Double)
    case channel(String, String)
    case ranks
    case posts
    case post(Int)
    case library(String)
    case settings
}

private enum PlaySlot: Hashable {
    case home
    case feed(ids: [Int], index: Int, ep: Int, time: Double)
    case series(id: Int, ep: Int, time: Double)
}

struct ShellView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.hg) private var hg
    @State private var tab = 0
    @State private var stack: [Route] = []
    @State private var mini = false
    @State private var parked: PlaySlot?
    @State private var miniOffset = CGSize.zero
    @State private var miniDragProxy = CGSize.zero

    private var live: PlaySlot? {
        if mini { return parked }
        if let top = stack.last {
            switch top {
            case let .feed(ids, index, ep, time):
                return .feed(ids: ids, index: index, ep: ep, time: time)
            case let .series(id, ep, time):
                return .series(id: id, ep: ep, time: time)
            default:
                return nil
            }
        }
        return tab == 0 ? .home : nil
    }

    private var fullPlayer: Bool { live != nil && !mini }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if !fullPlayer {
                ZStack {
                    if let top = stack.last {
                        route(top)
                    } else {
                        switch tab {
                        case 0:
                            if mini, case .home = parked {
                                Text("正在小窗播放").font(.hgTitle(18)).foregroundStyle(hg.ink)
                            } else if live == nil || mini {
                                HomeFeed(openSeries: { id, ep, time in enterSeries(id, ep, time) })
                            }
                        case 1: SearchScreen(open: pushFeed, ranks: { stack.append(.ranks) })
                        case 2: CategoryScreen(
                            channel: { stack.append(.channel($0, $1)) },
                            ranks: { stack.append(.ranks) },
                            posts: { stack.append(.posts) },
                            open: pushFeed
                        )
                        default: ProfileScreen(
                            settings: { stack.append(.settings) },
                            login: { model.loginOpen = true },
                            library: { stack.append(.library($0)) }
                        )
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let slot = live {
                player(slot)
                    .id(slotID(slot))
                    .frame(maxWidth: mini ? 132 : .infinity, maxHeight: mini ? 210 : .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: mini ? 14 : 0, style: .continuous))
                    .padding(.trailing, mini ? 12 : 0)
                    .padding(.bottom, mini ? 12 : 0)
                    .offset(x: mini ? miniOffset.width + miniDragProxy.width : 0, y: mini ? miniOffset.height + miniDragProxy.height : 0)
                    .overlay {
                        if mini {
                            Color.clear
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            miniDragProxy = value.translation
                                        }
                                        .onEnded { value in
                                            let far = hypot(value.translation.width, value.translation.height)
                                            miniDragProxy = .zero
                                            if far < 12 {
                                                expandMini()
                                            } else {
                                                miniOffset.width += value.translation.width
                                                miniOffset.height += value.translation.height
                                            }
                                        }
                                )
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if mini {
                            Button { closeMini() } label: {
                                Image(systemName: "xmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 26, height: 26)
                                    .background(.black.opacity(0.72))
                                    .clipShape(Circle())
                            }
                            .padding(6)
                        }
                    }
            }
            if let toast = model.toast {
                Text(toast)
                    .font(.subheadline)
                    .foregroundStyle(hg.onAccent)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(hg.accent)
                    .clipShape(Capsule())
                    .padding(.bottom, stack.isEmpty ? 72 : 24)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                            if model.toast == toast { model.toast = nil }
                        }
                    }
            }
        }
        .background((stack.last == nil && tab == 0) || fullPlayer ? Color.black : hg.paper)
        .safeAreaInset(edge: .bottom) { if stack.isEmpty && !model.immersive { tabBar } }
        .sheet(isPresented: $model.loginOpen) { LoginSheet().environment(\.hg, hg) }
    }

    @ViewBuilder
    private func player(_ slot: PlaySlot) -> some View {
        switch slot {
        case .home:
            HomeFeed(
                openSeries: { id, ep, time in enterSeries(id, ep, time) },
                mini: mini,
                onMini: { _, _, _ in enterMini() }
            )
        case let .feed(ids, index, ep, time):
            FeedScreen(
                ids: ids, start: index, startEp: ep, startTime: time,
                onBack: pop,
                onEnterSeries: { id, ep, time in enterSeries(id, ep, time) },
                mini: mini,
                onMini: { _, _, _ in enterMini() }
            )
        case let .series(id, ep, time):
            FeedScreen(
                ids: [id], start: 0, startEp: ep, startTime: time,
                episodePaging: true, onBack: pop,
                mini: mini,
                onMini: { _, _, _ in enterMini() }
            )
        }
    }

    private func slotID(_ slot: PlaySlot) -> String {
        switch slot {
        case .home: return "home"
        case let .feed(ids, index, ep, _): return "feed-\(ids.count)-\(index)-\(ep)-\(ids.first ?? 0)"
        case let .series(id, ep, _): return "series-\(id)-\(ep)"
        }
    }

    private func enterMini() {
        guard let slot = live, !mini else { return }
        parked = slot
        miniOffset = .zero
        if isFeed { pop() }
        mini = true
    }

    private func expandMini() {
        guard let slot = parked else { return }
        mini = false
        parked = nil
        miniOffset = .zero
        switch slot {
        case .home:
            tab = 0
        case let .feed(ids, index, ep, time):
            stack.append(.feed(ids: ids, index: index, ep: ep, time: time))
        case let .series(id, ep, time):
            stack.append(.series(id: id, ep: ep, time: time))
        }
    }

    private func closeMini() {
        mini = false
        parked = nil
        miniOffset = .zero
    }

    private func floatSeries(_ id: Int, _ ep: Int, _ time: Double) {
        parked = .series(id: id, ep: max(ep, 1), time: time)
        miniOffset = .zero
        mini = true
    }

    private var isFeed: Bool {
        if case .feed = stack.last { return true }
        if case .series = stack.last { return true }
        return false
    }

    @ViewBuilder
    private func route(_ top: Route) -> some View {
        switch top {
        case let .feed(ids, index, ep, time):
            FeedScreen(ids: ids, start: index, startEp: ep, startTime: time, onBack: pop, onEnterSeries: { id, ep, time in
                enterSeries(id, ep, time)
            })
        case let .series(id, ep, time):
            FeedScreen(ids: [id], start: 0, startEp: ep, startTime: time, episodePaging: true, onBack: pop)
                .id("series-\(id)-\(ep)")
        case let .channel(cate, name):
            ChannelScreen(cate: cate, name: name, back: pop, open: pushFeed)
        case .ranks:
            RankScreen(back: pop) { stack.append(.feed(ids: [$0], index: 0, ep: 1, time: 0)) }
        case .posts:
            PostsScreen(back: pop) { stack.append(.post($0)) }
        case let .post(id):
            PostScreen(id: id, back: pop)
        case let .library(kind):
            LibraryScreen(
                kind: kind,
                back: pop,
                open: { id, ep, time in enterSeries(id, ep, time) },
                series: { id, ep, time in enterSeries(id, ep, time) },
                float: { id, ep, time in floatSeries(id, ep, time) }
            )
        case .settings:
            SettingsScreen(back: pop)
        }
    }

    private func pop() { if !stack.isEmpty { stack.removeLast() } }

    private func pushFeed(_ ids: [Int], _ index: Int) {
        closeMini()
        stack.append(.feed(ids: ids, index: index, ep: 1, time: 0))
    }

    private func enterSeries(_ id: Int, _ ep: Int, _ time: Double = 0) {
        closeMini()
        stack.append(.series(id: id, ep: max(ep, 1), time: time))
    }

    private var tabBar: some View {
        HStack {
            tabItem("首页", "house", 0)
            tabItem("搜索", "magnifyingglass", 1)
            tabItem("分类", "square.grid.2x2", 2)
            tabItem("我的", "person", 3)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(hg.paper)
    }

    private func tabItem(_ title: String, _ icon: String, _ value: Int) -> some View {
        Button { tab = value } label: {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.body.weight(tab == value ? .semibold : .regular))
                Text(title).font(.caption2.weight(tab == value ? .semibold : .regular))
            }
            .foregroundStyle(tab == value ? hg.accent : hg.faint)
            .frame(maxWidth: .infinity)
        }
    }
}
