import SwiftUI

enum Route: Hashable {
    case feed(ids: [Int], index: Int, ep: Int, time: Double)
    case channel(String, String)
    case ranks
    case posts
    case post(Int)
    case settings
}

struct ShellView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.hg) private var hg
    @State private var tab = 0
    @State private var stack: [Route] = []

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let top = stack.last {
                    route(top)
                } else {
                    switch tab {
                    case 0: HomeFeed()
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
                        open: { id, ep, time in stack.append(.feed(ids: [id], index: 0, ep: ep, time: time)) }
                    )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .background((stack.last == nil && tab == 0) || isFeed ? Color.black : hg.paper)
        .safeAreaInset(edge: .bottom) { if stack.isEmpty && !model.immersive { tabBar } }
        .sheet(isPresented: $model.loginOpen) { LoginSheet().environment(\.hg, hg) }
    }

    private var isFeed: Bool {
        if case .feed = stack.last { return true }
        return false
    }

    @ViewBuilder
    private func route(_ top: Route) -> some View {
        switch top {
        case let .feed(ids, index, ep, time):
            FeedScreen(ids: ids, start: index, startEp: ep, startTime: time, onBack: pop)
        case let .channel(cate, name):
            ChannelScreen(cate: cate, name: name, back: pop, open: pushFeed)
        case .ranks:
            RankScreen(back: pop) { stack.append(.feed(ids: [$0], index: 0, ep: 1, time: 0)) }
        case .posts:
            PostsScreen(back: pop) { stack.append(.post($0)) }
        case let .post(id):
            PostScreen(id: id, back: pop)
        case .settings:
            SettingsScreen(back: pop)
        }
    }

    private func pop() { if !stack.isEmpty { stack.removeLast() } }

    private func pushFeed(_ ids: [Int], _ index: Int) {
        stack.append(.feed(ids: ids, index: index, ep: 1, time: 0))
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
