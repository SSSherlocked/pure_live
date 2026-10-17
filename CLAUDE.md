# Claude Code 指引

本仓库是 [SSSherlocked/pure_live](https://github.com/SSSherlocked/pure_live)，从 liuchuancong/pure_live 分叉后独立维护，不接受外部 Issue 或贡献。本文件描述这个分叉的实际流程；`docs/` 只放仍在使用的参考文档（入口见 [docs/README.md](docs/README.md)），与这里冲突时以本文件为准。

## 沟通

- 所有回复、进度和总结都用简体中文；代码、注释、提交信息用英文。

## 环境：本机不跑 Flutter

- 这台 Mac 没有安装 Flutter、Dart、Android SDK，也不要安装。所有分析、测试、编译、打包、发布都在 GitHub Actions 上完成。
- 没有 WSL，也不用 Windows PowerShell 工具链、本地打包或设备测试；原项目的这些脚本和文档已删除，不要再加回来。
- 本机能跑的只有 Python 工具。用一个装了 `pyyaml` 的虚拟环境运行：
  - `tool/audit_repository.py`：仓库审计
  - `tool/validate_architecture.py`：分层规则（应为 0 条未批准违规）
  - `tool/check_text_styles.py`：禁止写死字号
  - `tool/check_settings_width.py`：设置页必须限宽
  - `tool/release_version.py check`：版本号与更新源一致
  - `python -m unittest discover -s tool/tests -p 'test_*.py'`
- `tool/emoji/` 下是抓取各平台表情包、生成 `assets/emo/` 的脚本，需要更新表情时再运行。
- 因为不能本地编译，改 Dart 代码时要逐行核对类型、import 和调用方，推送后以 CI 的 `flutter analyze`、`flutter test` 和 Android 编译为准；改 Kotlin 时核对 `package com.mystyle.purelive`（目录名是 `pure_live`）。

## 依赖

- media_core 用本项目自己的分叉 [SSSherlocked/media_core](https://github.com/SSSherlocked/media_core) 的 `pure-live` 分支，本地克隆在 `../media_core`。修播放内核（线路切换、各播放器适配层）的问题时直接在分叉里改：每项修复单独提交并推送，再把 `pubspec.yaml` 里所有 media_core 子包的 `ref` 和 `pubspec.lock` 的 `resolved-ref` 一起改成新提交。分叉不跟随上游自动更新，需要上游的改动时手工合并。
- 可下载字体来自本项目的字体仓库 [SSSherlocked/fonts](https://github.com/SSSherlocked/fonts)（fork 自 SlotSun/fonts）。`assets/fonts/fonts-manifest.json` 是 app 实际使用的可下载列表，按它的顺序显示，与该仓库的 `fonts-manifest.json` 保持一致。苹方（6 个字重，`ping-fang/`）按用户决定排在第一位。
- media_kit / media_kit_video 来自本项目的分叉 [SSSherlocked/media-kit](https://github.com/SSSherlocked/media-kit) 的 `pure-live` 分支（基于 Predidit/media-kit，本地克隆在 `../media-kit`），由 media_core 分叉里的 `media_core_media_kit/pubspec.yaml` 钉住提交。补丁写在分叉的 `media_kit_video/PURELIVE_PATCH.md`。改 media_kit 时：分叉提交并推送 → media_core 分叉更新 `ref` 和锁文件 → pure_live 更新 media_core 的 `ref` 以及锁文件里 media_kit 的 `resolved-ref`。
- 其余 2 个外部依赖仍指向 liuchuancong：floating、flv_lzc。
- `pubspec.lock` 由 CI 用 `flutter pub get --enforce-lockfile` 校验，改依赖时要手工同步锁文件。

## 分支、提交与推送

- 只有 `master` 一个分支。验证过的改动直接提交并推送到 `origin/master`。
- 临时分支 `next/3.6.0`：放 3.6.0 的内容（HLS 线路用系统播放器、Mac 的 AVPlayer 后端），master 继续发 3.5.x。3.5.x 的修复照常进 master，并合并进这个分支；3.6 的改动只进这个分支，更新说明写在分支上 `RELEASE_NOTES.md` 的 v3.6.0 一节。用户决定发布第一个 3.6 版本时：把 `next/3.6.0` 合并进 master（普通合并，不改写历史），删除分支里 `ci.yml` 对它的触发，推送后删除本地和远端的 `next/3.6.0`，并删掉本条。
- 提交身份：`SSSherlocked <35389477+SSSherlocked@users.noreply.github.com>`（已在本仓库的 git 配置里设置）。不要用任何个人邮箱提交，也不要把用户邮箱写进代码或安装包元数据。
- 提交信息末尾加上 Claude 的 `Co-Authored-By` 署名行。
- 不要强制推送或改写历史，除非用户明确要求；推送被拒时先 `git fetch` 并变基，不要覆盖远端。
- 连续的小改动合并成一次推送，避免每改一处就推送一次、等一次 CI。一项改动做完、检查过就先在本地提交，攒到一组完整的改动（或用户要验证、要发布时）再推送；CI 正在跑时不要为了一个小改动再推一次，等它跑完再推。只改文档、更新说明的提交可以随下一次代码推送一起推。

## CI 与发布

- `.github/workflows/ci.yml` 在每次推送时运行：先检测改动（与上一次通过检查的提交比较；只改文档时跳过 Flutter 检查），然后并行跑 Analyze 和 Test；Android 编译（debug APK，检查 Kotlin/Java）只在 `android/`、`plugins/`、`pubspec.yaml`/`pubspec.lock`、`.env`、`build.yaml` 或工作流本身有改动时才跑；另有仓库审计和工具测试。
- 推送不会取消正在跑的 CI：新的运行排队等前一次跑完（GitHub 只保留最新一个排队的运行，中间的排队运行会被丢弃），排到的那次会把之前没检查到的改动一起检查。确认结果时看最新一次运行；不要把 `cancel-in-progress` 改回对推送生效。
- 查看 CI 结果：GitHub 匿名 API 每小时只有 60 次配额，容易被限流；优先打开 Actions 网页（`https://github.com/SSSherlocked/pure_live/actions/workflows/ci.yml`）读取运行状态，不要高频轮询 API。
- 发布用手动触发的 `build_pure_live_release.yml`，输入版本号（如 `3.2.2`）。`RELEASE_NOTES.md` 里最好先写好这个版本的中文更新说明；没写时发布不会被阻止，会按上次发布以来的提交自动生成一节（提交标题，英文）。发布完成后，工作流会把 `RELEASE_NOTES.md`、`pubspec.yaml`、`assets/version.json`、`releases.json` 提交回 master。
- 应用内更新：启动后和「关于 › 检查更新」读取 master 上的 `assets/version.json`（最新版本与更新说明）和 `assets/releases.json`（各平台的下载文件，按文件名里的平台关键词挑选），关于 › 历史也读取后者。两个文件都由发布工作流写回，不要手工提前修改，否则用户会收到不存在的更新。

## 播放内核

- 「播放内核」指 [docs/PLAYBACK_CORE.md](docs/PLAYBACK_CORE.md) 列出的文件：media_core 分叉的 `media_core_live`、`media_core_media_kit`、`media_core_ingest`，media-kit 分叉的 Android Surface 补丁，以及本仓库的 `lib/core/player/kernel/`、`lib/core/stream/`、`lib/domains/live/data/stream/`、`live_player_facade.dart`、`live_play_controller.dart` 的重连梯、各站点的线路顺序与 `LiveStreamFacts` 声明、`playback_header_resolver.dart`。
- 普通改动（功能、界面、文案、设置、站点目录/弹幕/搜索）不得触及内核文件，也不得改 mpv 属性、超时、窗口、重试次数这类数字。顺手改一行也不行：同一次开播有九层代码各自做决定，一层的数字是按相邻层的窗口算的（见该文档的分层表）。
- 内核改动单独立项：单独一次提交、一次推送，不与其他改动合并；提交信息写明改的是分层表的哪一层、动了哪个阈值、与相邻层窗口的关系；改代码前先更新 `docs/PLAYBACK_CORE.md` 的分层表和修复谱系。
- 不在门面层（`live_player_facade.dart`）新增看门狗或「重开」逻辑；新的恢复行为加到 media_core_live 的 sweep/watchdogs，由它统一执行。先问「去掉哪一层能解决」，再问「加哪一层」。
- 偏离 mpv/FFmpeg 默认值的属性，每一项都要在 `media_kit_live_properties.dart` 的注释里写清测得的收益和已知代价；没有数据支撑的调参回到默认值。

## 代码约定

- 分层：`app -> core, shared, domains, features`；`core` 不依赖上层；`domains/X` 只依赖 `core`、`shared` 和自身。由 `tool/validate_architecture.py` 检查。
- 文字：只用 `AppText` 的六个角色（pageTitle、sectionTitle、listPrimary、body、secondary、tag）或主题字号，不写死字号。密集区域（直播间信息页、全屏面板、播放器菜单）包在 `CompactText` 里，整体小一级。
- 应用外壳：页面外面的所有包裹层都在 `lib/app/shell/app_shell.dart`。每一层在整个运行期间必须保持同一种结构，状态变化只能改画什么，不能增减或替换层，否则路由会被重建（曾导致全屏时多推一个直播间页面）。
- 设置页：页面主体包在 `SettingsContentWidth` 里（固定内容宽度，两侧空白可滚动）。由 `tool/check_settings_width.py` 检查（CI 也跑）；设置目录以外、从设置进入的页面要加进脚本的 `SETTINGS_FILES`。设置行右侧的取值（「原画」「已启用」）一律用 `context.buildTileValue`，不自己写 `Text`，同一脚本检查。
- 新增的用户设置必须进入备份：在对应控制器的 `toJson`、`parseConfig`、`fromJson`、`extractConfig` 四处同时加上，默认值与 `hiveBool`/`hiveString` 等声明一致。只与本机有关的状态（路径、任务列表、缓存、设备 ID、迁移标记）不同步。
- 文案：新键同时追加到 `assets/translations/zh.json` 和 `en.json` 末尾，两份的键集合必须一致（测试会检查）；删除功能时一并删除不再使用的键。
- 删除功能时连同不再被调用的代码、资源和测试一起删掉，不留死代码。
