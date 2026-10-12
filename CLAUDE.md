# Claude Code 指引

本仓库是 [SSSherlocked/pure_live](https://github.com/SSSherlocked/pure_live)，从 liuchuancong/pure_live 分叉后独立维护，不接受外部 Issue 或贡献。本文件描述的是这个分叉的实际流程；[AGENTS.md](AGENTS.md)、[BUILD_POLICY.md](BUILD_POLICY.md) 和 `docs/` 里大多数构建、设备、发布说明来自原项目，与这里冲突时以本文件为准。

## 沟通

- 所有回复、进度和总结都用简体中文；代码、注释、提交信息用英文。

## 环境：本机不跑 Flutter

- 这台 Mac 没有安装 Flutter、Dart、Android SDK，也不要安装。所有分析、测试、编译、打包、发布都在 GitHub Actions 上完成。
- 没有 WSL，也不使用 Windows PowerShell 工具链。`tool/*.ps1`、`tool/flutterw.ps1`、`tool/local_ci.ps1`、本地打包和设备测试相关的文档都不适用。
- 本机能跑的只有 Python 工具。用一个装了 `pyyaml` 的虚拟环境运行：
  - `tool/audit_repository.py`：仓库审计
  - `tool/validate_architecture.py`：分层规则（目前有 1 条已知的未批准违规：`domains/recorder -> global_player_service`）
  - `tool/check_text_styles.py`：禁止写死字号
  - `PURE_LIVE_SKIP_POWERSHELL_TESTS=1 python -m unittest discover -s tool/tests -p 'test_*.py'`
- 因为不能本地编译，改 Dart 代码时要逐行核对类型、import 和调用方，推送后以 CI 的 `flutter analyze` 和 `flutter test` 为准。

## 依赖

- 4 个外部依赖仓库保持指向 liuchuancong：media_core、fonts、floating、flv_lzc。
- `pubspec.lock` 由 CI 用 `flutter pub get --enforce-lockfile` 校验，改依赖时要手工同步锁文件。

## 分支、提交与推送

- 只有 `master` 一个分支。验证过的改动直接提交并推送到 `origin/master`。
- 提交身份：`SSSherlocked <35389477+SSSherlocked@users.noreply.github.com>`（已在本仓库的 git 配置里设置）。不要用任何个人邮箱提交，也不要把用户邮箱写进代码或安装包元数据。
- 提交信息末尾加上 Claude 的 `Co-Authored-By` 署名行。
- 不要强制推送或改写历史，除非用户明确要求；推送被拒时先 `git fetch` 并变基，不要覆盖远端。
- 连续的小改动合并成一次推送，避免每改一处就推送一次、等一次 CI。

## CI 与发布

- `.github/workflows/ci.yml` 在每次推送时运行：先检测改动（只改文档时跳过 Flutter 检查），然后并行跑 Analyze 和 Test，另有仓库审计和工具测试。
- 查看 CI 结果：GitHub 匿名 API 每小时只有 60 次配额，容易被限流；优先打开 Actions 网页（`https://github.com/SSSherlocked/pure_live/actions/workflows/ci.yml`）读取运行状态，不要高频轮询 API。
- 发布用手动触发的 `build_pure_live_release.yml`，输入版本号（如 `3.2.2`）。`RELEASE_NOTES.md` 里必须先写好这个版本的更新说明。发布完成后，工作流会把 `pubspec.yaml`、`assets/version.json`、`releases.json` 提交回 master。
- 不要手工修改 `assets/version.json`：应用内的检查更新读取的就是 master 上的这个文件，提前改会让用户收到不存在的更新。

## 代码约定

- 分层：`app -> core, shared, domains, features`；`core` 不依赖上层；`domains/X` 只依赖 `core`、`shared` 和自身。由 `tool/validate_architecture.py` 检查。
- 文字：只用 `AppText` 的六个角色（pageTitle、sectionTitle、listPrimary、body、secondary、tag）或主题字号，不写死字号。密集区域（直播间侧栏、全屏面板、播放器菜单）包在 `CompactText` 里，整体小一级。
- 应用外壳：页面外面的所有包裹层都在 `lib/app/shell/app_shell.dart`。每一层在整个运行期间必须保持同一种结构，状态变化只能改画什么，不能增减或替换层，否则路由会被重建（曾导致全屏时多推一个直播间页面）。
- 设置页：页面主体包在 `SettingsContentWidth` 里（固定内容宽度，两侧空白可滚动）。
- 新增的用户设置必须进入备份：在对应控制器的 `toJson`、`parseConfig`、`fromJson`、`extractConfig` 四处同时加上，默认值与 `hiveBool`/`hiveString` 等声明一致。只与本机有关的状态（路径、任务列表、缓存、设备 ID、迁移标记）不同步。
- 文案：新键同时追加到 `assets/translations/zh.json` 和 `en.json` 末尾，两份的键集合必须一致（测试会检查）；删除功能时一并删除不再使用的键。
- 删除功能时连同不再被调用的代码、资源和测试一起删掉，不留死代码。
