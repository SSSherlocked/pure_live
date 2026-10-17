# 播放内核：范围、分层与改动规则

本文定义「播放内核」包含哪些代码，一次开播要经过哪些决策层，以及为什么对它的改动必须单独立项。
规则本身写在 [CLAUDE.md](../CLAUDE.md) 的「播放内核」一节；本文是它的参考。

## 为什么要把内核圈出来

2026-10-11 到 10-17 之间，B 站播放问题改了六版（见下文「修复谱系」），每一版都在某一层加一个判断或一个定时器，
结果是：冷启动 40 s 黑屏 → 有声无画 → 有声无画 4 s 后重开。原因不是某一处写错，而是同一次开播有九层代码各自做决定，
每层都能「重开」或「换线」，而且几项 mpv 调参偏离了 FFmpeg/mpv 的默认值。任何一层改一个数字，其他层的行为都会变。

对比 Simple Live：它用 media_kit 直接 `open(Playlist(urls))`，不改 mpv 的探测参数，除 Android 上 `force-seekable=yes`
和 vo/hwdec 外不设任何 mpv 属性；出错或流结束时同一条线重试 2 次，然后换下一条；没有预检、没有本地中转、
没有逐线验证、没有门面层看门狗。它遇到过同一个 Android Surface 附着时 seek 被拒的问题，解法与我们一样。
它的播放不如我们「聪明」，但决策者只有一个。

## 内核包含的文件

普通的功能、界面、文案、设置改动不得触及下面任何一处；需要改时按 CLAUDE.md「播放内核」一节单独立项。

### media_core 分叉（`../media_core`，`pure-live` 分支）

- `packages/media_core_live/`：`live_playback_controller.dart`、`live_playback_sweep.dart`（引擎 × 线路逐条验证）、
  `live_watchdogs.dart`、`live_watchdog_arms.dart`、`live_playback_pipeline.dart`
- `packages/media_core_media_kit/`：`media_kit_player_adapter.dart`、`mpv_error_gate.dart`（哪些 mpv 错误行算线路失败）
- `packages/media_core_ingest/`：HLS/FLV 本地中转
- `packages/media_core_ijk_player/`、`packages/media_core_better_player/`：Android 备用引擎

### media-kit 分叉（`../media-kit`，`pure-live` 分支）

- `media_kit_video/PURELIVE_PATCH.md` 描述的 Android Surface 补丁及 `android_video_controller/real.dart`

### pure_live

- `lib/core/player/kernel/`：全部。其中 `media_kit_live_properties.dart` 是 mpv 属性表（探测、缓存、超时、重连、解码），
  `player_kernel_service.dart` 组装内核与引擎，`stream_replay_detector.dart` 读 mpv 日志判回放
- `lib/core/stream/`：全部（FLV 分帧、HLS 主清单选择、上游代理路由）
- `lib/domains/live/data/stream/`：全部（`line_preflight.dart` 预检、`ingest_source_interceptor.dart`、
  `playback_source_transport.dart` 直连/中转决策、`flv_legacy_hevc_relay.dart`、`flv_splice_relay.dart`、
  `playback_manifest_probe.dart`、`playback_ingest_needs.dart`、`live_stream_ingest.dart`）
- `lib/domains/live/domain/`：`live_player_facade.dart`（无画面/回放/卡顿看门狗、换线、重开）、
  `playback_source_interceptor.dart`、`stream_replay_policy.dart`、`playback_source_refresh.dart`、`global_player_service.dart`
- `lib/domains/live/presentation/playback/controllers/live_play_controller.dart` 中的重连梯（`_reconnect*`、`onPlaybackNetworkError`）
- 各站点 `resolvePlayUrlsRaw` / `getPlayUrls` 返回的线路顺序与 `LiveStreamFacts` 声明（`lib/shared/platforms/*/*_site.dart`）：
  线路顺序决定内核先开哪条，`format`/`codec` 事实决定是否走中转。改请求参数（如 B 站的 `protocol`/`format`/`codec`）也算内核改动
- `lib/domains/live/data/playback_header_resolver.dart`：发给 CDN 的请求头

### 对应测试

`test/core/player/`、`test/domains/live/` 下带 `line_preflight`、`ingest_source_interceptor`、`playback_ingest_needs`、
`playback_manifest_probe`、`media_kit_source_properties`、`media_kit_refused_seek`、`stream_replay`、`flv_video_declared`、
`loopback_relay_session_cookie` 的测试。

## 一次开播经过的决策层（2026-10-17 现状）

按时间顺序，每层括号里是它自己的定时器或阈值。改任何一个数字前先看这张表，因为下一层的窗口是按上一层算的。

1. **站点解析**（`bilibili_site.dart` 等）：请求 `protocol=0,1 format=0,1,2 codec=0`，按「请求的清晰度 → http_stream → flv → avc → 非 mcdn」排序，
   同时为每条线声明 `LiveStreamFacts`（format、codec）。
2. **预检** `LinePreflight`（每条线 1.5 s，并行；结果记 5 min）：对每条线的主机做 TCP 连接。全部地址不通的线移到最后；
   仅第一个地址不通（IPv6 黑洞）的线保持位置但标记 `firstAddressDead`，交给 Dart 中转。平台首条是 FLV 时，活着的 FLV 排在 HLS 前。
3. **拦截与传输** `IngestSourceInterceptor` → `PlaybackSourceTransport`：决定第一条线是直连、Dart FLV 透传中转（改 FLV 头的视频标志、
   重写 codec-id-12 HEVC 标签）、Dart HLS 中转（所有 HLS 线都走它，预取分片）还是 FFmpeg 重封装。
4. **内核 sweep**（`media_core_live`，每条线 `sourceReadyTimeout` = 10 s，由门面传入）：引擎 × 线路逐个打开并验证，
   位置前进即通过；验证期间任一 adapter 错误事件让这条线失败；所有线失败后换引擎（Android：mpv → ijkplayer → ExoPlayer）。
5. **适配层错误门** `MpvErrorGate`（非终结错误观察 1.2 s）：media_kit 把 `file`/`vd`/`ad`/`cplayer`/`stream` 前缀的 mpv 错误日志行都当错误抛出；
   门把它们分成「立即终结」和「观察 1.2 s，有进度就丢弃」。`Cannot seek` 在 adapter 里单独忽略。
6. **mpv 属性表** `MediaKitLiveProperties`（约 25 项偏离默认值）：`demuxer-lavf-analyzeduration=1`、`demuxer-lavf-probesize=1 MiB`、
   `network-timeout=8`、`cache-pause=yes`/`cache-pause-wait=1`、`demuxer-readahead-secs=8`、`cache-secs=30`、`framedrop=decoder+vo`、
   `hwdec-software-fallback=1`、Android `initial-audio-sync=no`、低端机 `lowres=1`/2 线程；按源设置 `force-seekable`（FLV yes、HLS no）
   和 ffmpeg 的 `reconnect*` 选项。
7. **门面看门狗** `LivePlayerFacade`：有声无画 4 s 且位置已过 1 s → 经中转重开一次；mpv 报音频 PTS 回跳 2–60 s 且开播 ≥ 5 s → 换同类线路（20 s 内一次）；
   位置不动 → 卡顿提示 / 长卡顿事件。
8. **内核 watchdogs**：buffering 12 s、position 15 s 无进展 → recovery（向宿主要新线路再重开）。
9. **房间控制器重连梯** `LivePlayController`：网络类失败后 2/5/10/20/30/60 s 重试，最长 30 min，网络恢复时立刻重试。

## B 站有声无画：根因

- FLV 头第 5 字节的标志位声明有哪些轨道。FFmpeg 的 `flv_read_header` 把它记到 `missing_streams`；`avformat_find_stream_info`
  在三种情况下结束探测：所有已知轨道参数齐全且 `missing_streams == 0`（"All info found"）、读够 `probesize`、或流时间戳超过 `analyzeduration`。
- mpv 只在探测结束时建轨并选轨；之后 FFmpeg 再发现新轨（`flv_read_packet` 里 `create_stream`），mpv 的 `add_stream_track`
  只把它登记进轨道列表，**不会自动选中**（`player/loadfile.c`）。所以探测时没看到视频，这次连接就永远无画。
- B 站某些边缘节点开头只发音频：头声明 audio-only，第一个视频标签要等到下一个关键帧。10-17 的日志是「探测在 23 627 字节后结束，只有 aid=1」：
  这个字节数约等于 1.4 s 的 AAC，与我们自己设的 `analyzeduration=1 s` 吻合，也与 audio-only 头让 `missing_streams` 清零吻合——两条路都在 1 s 左右结束探测。
  FFmpeg 默认 `analyzeduration` 是 5 s，覆盖一个 GOP，这就是 Simple Live 不出现此问题的直接原因。
- 10-11 把探测从 2 MiB/2 s 改成 1 MiB/1 s（为了 B 站首帧 1.8 s → 0.7 s）是这个问题的引入点。首帧变快的真正来源是 FFmpeg 对不可靠时间基（FLV）的
  帧率分析要攒 20 帧视频；把 `analyzeduration` 压到 1 s 等于用「截断探测」换首帧，副作用就是把晚到的视频一起截掉。
- 10-17 的修复（中转里把头的视频标志置 1，并在无画面时经中转重开）只堵住 `missing_streams` 这条路：视频若在 1 s 之后才到，探测仍被 `analyzeduration` 截断，
  重开后依旧无画，而 `_noPictureReopened` 只允许重开一次。它是补丁，不是根治。

### 一步到位的方向（待单独立项验证）

1. `demuxer-lavf-analyzeduration` 和 `demuxer-lavf-probesize` 回到 mpv/FFmpeg 默认值（5 s / 5 MB），
   改用 `demuxer-lavf-o=fpsprobesize=0` 砍掉 20 帧的帧率分析：两轨参数齐全即结束探测，正常流首帧不变慢，音频先到的流最多等到下一个关键帧。
   需要用 `playback-timing firstFrame` 日志在 Android 上对比确认。
2. 验证通过后撤掉 `withVideoDeclared` 和「无画面经中转重开」这两层补丁，以及对应测试；保留 Dart 中转只为 IPv6 黑洞和 HEVC 标签重写。
3. 不再新增独立的「重开」决策者。需要新的恢复行为时，加到内核 sweep/watchdogs 这一层，由它统一执行。

## 冷启动 40 s 黑屏：根因（已修，记录以免回退）

- 内核逐线验证 10 s，Android 五条 B 站线 + 三个引擎；media_kit 在 Surface 附着时 seek 到当前位置，直播流拒绝该 seek，
  mpv 打一条 `cplayer` 错误行，media_kit 把它当错误抛出，adapter 上报，sweep 把这条健康的线判死。于是每条线各烧 10 s（ac35d28cc）。
- 手机上 getaddrinfo 先返回 IPv6 地址，而某些网络到 B 站 CDN 的 IPv6 是黑洞；ffmpeg/ijkplayer 在第一个地址上等满超时（e01197bff、7cf7008a1、9099ba002）。
- 两件事叠加才到 40 s。前者现在由 adapter 忽略 `Cannot seek`、`MpvErrorGate` 分级、`force-seekable=yes`（FLV）和 media-kit 分叉的 Surface 补丁共同兜住；
  后者由预检 + Dart 中转兜住。它们之间的耦合是：预检的 1.5 s、门的 1.2 s、`network-timeout` 8 s 都必须小于 sweep 的 10 s 窗口。

## 修复谱系（2026-10）

| 日期 | 提交 | 改了哪一层 | 效果与副作用 |
| --- | --- | --- | --- |
| 10-11 | 4a2b6ca39 | 第 6 层：探测 2 MiB/2 s → 1 MiB/1 s | 首帧快 1.1 s；埋下有声无画 |
| 10-13 | aa81fb054 | 第 4、6 层：sourceReady 18 → 8 s，network-timeout 15 → 8 | 死线早放弃 |
| 10-14 | ac35d28cc | 第 6 层：FLV 回到 force-seekable=yes | 冷启动不再烧光所有线 |
| 10-14 | e01197bff / 7cf7008a1 / 9099ba002 | 新增第 2 层预检；第 3 层加 firstAddressDead 中转 | IPv6 黑洞下仍能 2 s 开播；多了一层 |
| 10-16 | 659d9b657 | 第 7 层：无画面重开要等位置过 1 s | 修 10-16 自己引入的误重开 |
| 10-16 | 5aa540f81 | 第 2 层：死 FLV 线让位给活 FLV 线而非 HLS | 虎牙 HLS 卡顿 |
| 10-17 | f70fb00aa | 第 3、7 层：中转改 FLV 头标志；无画面经中转重开 | 1 s 内到视频的流恢复画面；1 s 后到的仍无画 |

## 改动规则

见 CLAUDE.md「播放内核」。要点：内核改动单独一次提交、一次推送，提交信息写清改的是上表哪一层、动了哪个阈值、
与相邻层窗口的关系；先在本文更新分层表，再改代码；不在门面层新增看门狗。
