# HGhubX 整合复核记录（2026-11-14）

本次复核对应用户确认的目标：采用 HGhubX 的界面、频道、搜索及全部 CI，同时适配保留本地缓存、独立观看进度、CIDR 与安全修复。

上游基线固定为 `zxsos/HGhubX@66a2cbb3656cbcffa26f8a9efbb73fa41918470f`，不是对后续提交的自动背书。原 play 为 `8b622d82c359efa15a4ffd6fd14985ebf78b5425`，保留在本地 `backup/play-before-hghubx-20261113`。整合保留双方 Git 历史，供最终 PR 按 HGhubX 基线审阅新增功能；没有推送、创建 PR 或发布安装包。

原始审查报告已恢复为 [hghubx-audit-20261113.md](hghubx-audit-20261113.md)。此前聊天链接含有错误的路径前缀，报告文件本身仍在聊天工作目录中。现在使用仓库文档路径并纳入版本控制，避免依赖临时目录。原报告保留迁移前的结论和暂停状态，不能将其末尾“尚未修改”当成当前状态。

## 目标逐项核对

| 目标 | 实施与证据 |
| --- | --- |
| HGhubX 界面、频道、搜索 | App、Home、Category、Discover、Search、User、README、品牌和 Tauri 主配置与指定 HGhubX 基线一致。Feed、Settings、播放器、store 仅适配新增功能；保留它的 HEVC、频道分页排序、视频/帖子搜索、独立栏目搜索、清屏和移动布局。 |
| HGhubX 全部 CI | 保留其 `ci.yml`、`playback.yml`、`release.yml`、`build-ios.yml` 四个工作流，移除原 play 的独立 checks/native/Linux/macOS 工作流；不是把原 CI 改名继续运行。三个上游工作流追加了必要安全修复或新增功能回归，因此不再声称 YAML 与上游逐字相同。 |
| 磁盘缓存 | 迁入 media_cache/media_download/playbackCache，以及 HLS 音轨、字幕、Key 和 MP4 分块缓存。保持默认 256 MiB、可设 0/128–4096 MiB、清理、前台播放优先、取消、部分块恢复与去重。见 [播放缓存](playback-cache.md)。 |
| Linux 媒体通道 | 使用 HGhubX 的回环 HTTP/GStreamer 架构，将请求 Range 传到同一缓存后端，保留 206、Content-Range、Content-Length、HEAD 语义。HTTP 请求头限制 16 KiB，并发上限 32，校验 Host 与网页 Origin，拒绝外站 Fetch Metadata；可信应用 Origin 即便被标成 cross-site 仍可工作。 |
| 独立观看进度 | useWatchProgress 与独立 progress 映射迁入新版 Feed/store。旧数据迁移、超过 80 条历史仍保留进度、失活/退出写入、旧 writer 拒绝、清空防回写、片尾回拖、自动续集保留旧集直到新集实际播放均有回归。 |
| 画质切换与进度交接 | 新增 sourceKey 区分同集的 HEVC/标准源，重建播放器时保留当前位置；不会因切换画质将独立进度归零。 |
| CIDR | 保留 IPv4/IPv6 例外配置、验证、规范化、落盘及失败保持原配置；应用到 URL 与 DNS 答案检查，设置页可读取和保存。 |
| 严格模式与代理 | 保留 HGhubX 的系统代理识别及 AliDNS 媒体回退；严格模式仍检查本地 DNS 答案，避免全局代理开关掩盖 NO_PROXY 直连。网络策略代数隔离缓存，过期/切换后重新检查。Range 媒体也接入 DNS 回退。 |
| 账号与导航安全 | 凭据只信任固定业务来源，不随镜像发现或 CIDR 例外扩大；关闭传输层自动重定向，凭据请求不重放。恢复 Unix 数据目录 0700、会话文件 0600，以及独立导航守卫，拒绝 data/file/javascript 等地址。HTML 清洗、媒体清单 URI 改写与日志脱敏继续保留。 |
| 移动客户端 | 按已确认的 HGhubX 方案使用 Tauri Android/iOS，独立 native/android、native/ios 不进入目标提交；原生实现专属的 Keystore/Keychain、SIGPIPE 等代码不适用于这个已移除的实现，不声称已对新移动安装包完成同等真机验证。 |

## 复核补齐的遗漏

1. 字幕后端与设置开关已有，但播放器快捷控制未完整接回；已恢复桌面、移动 Feed 与帖播放器的控制，以及原生轨道变化事件。
2. 新版相邻集预热改变了测试前提：最后一个播放地址请求可能属于预热；旧失败注入也可能命中已预热地址。测试改为观察实际 HLS 源，失败在预热之前注入，继续验证真实失败与旧回调，未关闭预热功能。
3. 原播放回归的“画质切换”定位会命中多个预渲染卡片；已限定实际包含 video 的 section。应用的双向画质切换与重新进入均保持集数和位置。
4. Range 下载原先尚未接入 HGhubX 的 DNS 回退；已补齐。
5. 仅保留上游 CI 会漏跑本地新增回归；已将缓存/安全/字幕/进度/画质回归接入它的 frontend job，将本地 HTTP 和真实 Rust 缓存浏览器回归接入 rust job，没有另建旧版 CI。
6. 原审查记录中的发布风险不能因采用上游 CI 而忽略：手动 tag 改为经环境变量传递，不直接插入 shell；版本脚本校验合法版本与 Android versionCode 范围；发布说明 tag 拒绝路径/换行；APK 密钥文件设 0600 并用 EXIT trap 清理；默认 contents:read，仅 Publish job 授予 contents:write。

## 验证结果

- 应用与测试 TypeScript 检查、Vite 生产构建通过；只有既有的大 JS 包体积提示。
- `cargo check --locked --offline --all-targets` 与 Rust 单元测试通过：55 passed，11 ignored。默认忽略项包括真实联网测试、四个回环测试和专用浏览器 fixture。
- 四个回环测试分别运行并通过：Linux 实际 socket 的 Range/206/HEAD/CORS、范围缓存复用、前台优先与部分块恢复、在途缓存变更。
- 缓存调度 23 项、安全 HTML/设置 70 项通过。
- 上游频道分页 3 项、API 加载 2 组、移动端布局 16 项、诊断复制 7 组通过。
- 上游原有五个播放场景通过。完整本地套件的 16 个场景均已验证；完整运行先有 15 项通过，画质项因按钮定位歧义失败，定位修正后该项单独复跑通过。包括真实 Rust HLS 缓存续播、MP4 解码/Range/跳转/重开复用、字幕、自动续集、片尾回拖、进度和存储错误；storage 场景内含 13 项用例。没有把未通过的首次运行隐藏为一次性全绿。
- 发布脚本用实际 workflow shell 片段检查：合法版本可用，shell/换行载荷未执行且被拒绝；模拟签名器返回失败后，测试密钥已删除。四份 YAML 与 shell 语法检查通过，Git 空白检查通过。

测试输出位于本地 `test-results/`，该目录按上游约定不提交。此次本机回归拦截外网业务请求，不发送真实账号或发布密钥。

## 剩余验证边界

- 尚未推送到 GitHub，不能声称云端 Actions 全绿；action 可用性、仓库密钥配置、分支保护和发布权限仍需服务端实际运行。
- 本机 Linux，没有完成 macOS、Windows、Android、iOS 安装包构建或真机测试。Chromium 中的 MMS/iOS 行为模拟不能代替 WebKit/GStreamer/真机验证。
- 会话仍是当前应用用户可读的文件；Unix 权限收紧不等于移动端 Keychain/Keystore 加密。采用 HGhubX 的应用 identifier 后，不自动导入旧应用数据目录或凭据。
- 可信代理的远端解析与最终连接地址无法靠本地 DNS 检查证明；本机同用户进程仍可调用回环服务。回环边界加固不声称隔离恶意本地进程。
- 上游 Actions 使用版本标签，未额外固定到提交 SHA；第三方依赖、线上服务与已发布二进制不在本次源码结论的完整验证范围内。

复核未发现新增的主观恶意证据。上述边界属于未执行的平台/云端验证或信任范围，不能混同为已经证明安全，也不能隐去。
