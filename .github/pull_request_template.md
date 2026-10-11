<!-- pr-maintenance-markers: bug-provenance; semantic-audit; impact-matrix; evidence-layered; rollback -->

## 变更摘要

- 目的：
- 关联 Issue：
- 目标平台：Android / Windows / 社区验证平台 / 公共逻辑

## Bug 来源与根因

- 来源分类：`upstream-existing` / `fork-regression` / `integration-conflict` / `external-drift` / `environment-or-data` / `not-reproduced` / 不适用
- 冻结的维护分支 SHA：
- 最短复现与最后正常版本：
- 第一个错误状态、调用链或事件时序：
- 根本原因：

## 方案与兼容

- 处置：直接复用 / `adapt` / 兼容层 / `rewrite` / `drop` / `defer`
- 选用理由及未选方案：
- 修改前行为、修改后行为：
- 对本分支定制功能和产品不变量的影响：

较大或跨模块改动另需逐项记录 `semantic_change_ledger`（语义变更）、`fork_feature_impact`（对本仓库定制功能的影响）、`quality_assessment`（实现质量）与每项 `disposition`。

## 影响矩阵

- [ ] Android 首次进入 / 竖屏
- [ ] Android 横屏 / 全屏 / 返回
- [ ] Android 系统画中画 / 应用小窗
- [ ] 音频与视频切换 / 前后台恢复
- [ ] 弹幕列表 / 画面弹幕 / 设置实时同步
- [ ] 清晰度 / 线路 / 房间切换
- [ ] 首页 / 关注 / 搜索 / 排行 / 平台接口
- [ ] Windows 普通窗口 / 全屏 / 小窗 / 滚轮
- [ ] 设置、旧配置、备份恢复和升级迁移
- [ ] Timer / Stream / Worker / Controller / 纹理 / 缓存释放与上限
- 不适用或未覆盖项说明：

## 验证证据

按实际执行填写，不把一个证据层外推到其他层：

- 代码审查 / 静态检查：
- 受影响自动化测试：
- Analyze（修改稳定后一次）：
- 目标平台构建：
- 设备采样或 Windows 运行验证：
- 外部接口探测与时间：
- 截图 / 录屏：
- 未覆盖平台与剩余风险：

## 数据、性能与回滚

- 配置默认值与旧版本迁移：
- 数据目录、备份与降级影响：
- CPU、内存、帧耗时或网络请求基线（如适用）：
- 回滚提交、开关或恢复步骤：

## 提交前检查

- [ ] 修改遵循 `MAINTENANCE_POLICY.md` 和 `BUILD_POLICY.md` 的适用部分
- [ ] 未包含账号、Cookie、密钥、签名材料、私有直播源或个人备份
- [ ] 文档、版本号、更新源和发布说明已按需更新
- [ ] 分支已同步最新 `master`，且最终差异通过 `git diff --check`
- [ ] 结论明确区分代码、测试、构建、设备和接口证据，没有使用绝对化完成声明
