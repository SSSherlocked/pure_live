# 构建、测试与发布

所有分析、测试、编译、打包和发布都在 GitHub Actions 上完成，本机不安装 Flutter（见 [`CLAUDE.md`](../CLAUDE.md)）。Flutter 版本固定在 `.fvmrc`（`3.47.5`），`pubspec.lock`、Git 依赖提交和原生库地址都已固定，CI 用 `flutter pub get --enforce-lockfile` 校验锁文件。

## 工作流

| 工作流 | 触发 | 作用 |
|---|---|---|
| 代码检查（`ci.yml`） | 每次推送 `master` 与 PR | 检测改动（只改文档时跳过 Flutter 检查）；并行跑 `flutter analyze`、`flutter test` 和 Android debug 编译（检查原生 Kotlin/Java）；另跑仓库审计、文字样式、设置页宽度、版本一致性和工具测试 |
| 发布新版本（`build_pure_live_release.yml`） | 手动 | 按勾选的平台打包（Android 默认勾选），可选先做代码检查，可选发布 Release |
| 更新发布历史（`update_releases.yml`） | 手动 | 重新生成 `assets/releases.json` |
| 同步原生库（`mirror_native_bundles.yml`） | 手动 | 把 FFmpeg 等预编译原生库的发布复制到本仓库的 Releases |
| Claude Code（`claude.yml`） | 评论触发 | Claude Code GitHub Actions |

## 本机检查

本机只能跑 Python 工具（装有 `pyyaml` 的虚拟环境）：

```bash
python tool/audit_repository.py
python tool/validate_architecture.py
python tool/check_text_styles.py
python tool/check_settings_width.py
python tool/release_version.py check
python -m unittest discover -s tool/tests -p 'test_*.py'
```

Dart 代码推送后以 CI 的分析与测试结果为准。

## 安装包

| 平台 | 文件 |
|---|---|
| Android | `PureLive-<版本>-Android-arm64-v8a.apk` |
| Windows | `PureLive-<版本>-Windows-x64.zip`（便携版） |
| Linux | `PureLive-<版本>-Linux-x64.deb`、`.zip`、`.tar.gz` |
| macOS | `PureLive-<版本>-MacOS-AppleSilicon.zip`、`PureLive-<版本>-MacOS-Intel.zip`（从同一个 universal 构建拆分） |
| iOS | `PureLive-<版本>-iOS-Unsigned.zip`、`PureLive-<版本>-iOS-TrollStore.ipa` |

Android 用仓库 Secrets（`KEYSTORE_BASE64`、`STORE_PASSWORD`、`KEY_PASSWORD`、`KEY_ALIAS`）中的发布密钥签名，证书与原项目不同，不能覆盖安装原项目的 APK。包名固定为 `com.mystyle.purelive`。

## 版本号

版本号只有一个来源：发布工作流的 `version` 输入（例如 `3.2.2`）。其余全部由 `tool/release_version.py` 派生，不要手改：

| 派生项 | 由谁写入 |
|---|---|
| `pubspec.yaml` 的 `version: 3.2.2+<构建号>` | 每个构建任务在构建前写入自己的工作区；发布成功后由工作流提交回 `master`。版本变化时构建号自动加 1，重复构建同一版本则不变 |
| 安装包与文件名、Android versionName/Code、iOS/macOS 版本、Windows 版本 | Flutter 与打包工具读取上面写入的 `pubspec.yaml` |
| 标签与 Release 名 `v3.2.2` | 发布任务 |
| Release 正文、应用内更新说明 | `RELEASE_NOTES.md` 的 `# Pure Live v3.2.2` 一节；没有这一节时，发布任务按上次发布以来的提交自动生成（新功能、修复、其他改进），并写回 `RELEASE_NOTES.md` |
| `assets/version.json`（应用内更新源）、`assets/releases.json` | 发布成功后由工作流生成并提交。本次未构建的平台保留原来的条目，不会被提示一个不存在的安装包 |

`version` 留空时沿用 `pubspec.yaml` 当前的版本，适合只出测试包。已经发布过的版本不能再次发布。

## 发布步骤

1. 在 `RELEASE_NOTES.md` 写好新版本一节，推送到 `master`（可省略：没写时按提交记录自动生成）。
2. 运行“发布新版本”工作流：`version` 填新版本号，勾选要打包的平台和“发布到 Release 页面”。
3. 在 [Releases](https://github.com/SSSherlocked/pure_live/releases) 核对附件；工作流已把版本号和两个索引文件提交回 `master`。

## 原生库与仓库地址

- FFmpeg Kit 使用本仓库 [原生依赖资产预发布](https://github.com/SSSherlocked/pure_live/releases/tag/native-ffmpeg-9.0.2-b1) 中的 FFmpeg `n9.0.2`（不是应用版本号），各平台归档的 SHA-256 固定在 `tool/verify_ffmpeg_native.py`（`tool/prefetch_linux_native.sh` 可按它预取并校验 Linux 归档）。
- libmpv 由 media_kit 的 `media_kit/hook/native_bundles.json` 指定。media_kit 来自本项目的分叉 [SSSherlocked/media-kit](https://github.com/SSSherlocked/media-kit)，经 [SSSherlocked/media_core](https://github.com/SSSherlocked/media_core) 分叉里钉住的提交引入（更新流程见 `CLAUDE.md`）。
- GitHub 地址从 `.env` 派生：`PURELIVE_UPDATE_OWNER`/`PURELIVE_UPDATE_REPOSITORY` 是本仓库自身的发布（`assets/version.json` 的下载地址、`assets/releases.json`、`lib/gen/env.g.dart`），`PURELIVE_NATIVE_OWNER`/`PURELIVE_NATIVE_REPOSITORY` 是原生库所在仓库（`pubspec.yaml` 的 `ffmpeg_kit_extended_config`）。换仓库时改 `.env`，并在 CI 上重新生成 `env.g.dart`。

## 平台说明

- Windows：数据目录与升级见 [Windows 数据目录与升级](WINDOWS_DATA_AND_UPGRADE.md)。
- Linux：使用系统浏览器承接“继续网页搜索”；Ubuntu 24.04 构建，目标系统需提供 GTK、托盘、显卡驱动和音频运行库。
- macOS：始终用软件纹理渲染（硬件纹理会在进入直播间时崩溃），硬件解码走 `videotoolbox-copy`。

返回 [文档索引](README.md)。
