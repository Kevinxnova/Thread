# 版本记录 / Changelog

## 0.8 — 2026-10-06

- 首次整理并发布完整项目源码，保留仓库原有历史；增加中英文介绍、贡献指南与公开需求说明。
- 增加默认排除规则、暂存区及历史检查、提交/推送钩子和 CI，个人任务、笔记、验收日志及构建产物不上传。
- 应用版本标识更新为 0.8；工作管理和镜像功能沿用 0.7，数据格式未变。
- 验证：本机 64 项应用测试通过（包含真实废纸篓临时数据测试），9 项发布保护测试通过；发布构建和临时签名验证通过，39 个公开文件的暂存区审查通过。原始日志保持本地；云端结果见 CI。

- Initial full source publication, preserving the repository's existing history; bilingual introduction, contribution guide, and public requirements.
- Added default-deny ignore rules, staged/history checks, commit/push hooks, and CI. Personal tasks, notes, validation logs, and build output stay local.
- Updated application version labels to 0.8. Work-management and mirror behavior retain the 0.7 implementation; no data-format change.
- Validation: 64 local app tests passed, including the real Trash test on disposable data; all nine publication-safeguard tests passed. The release build, ad-hoc signature verification, and staged review of 39 public files passed. Raw logs stay local; see CI for cloud results.

## 0.7 — 2026-10-06

将实时镜像与任务、目标、编号笔记和完成/撤回/删除接通；点击标签恢复来源并提升镜像。64 项自动测试及 macOS 15.6 / Apple Silicon 上的原生窗口与 Chrome 工作流验收通过。受验证环境和权限条件限制，不代表任意应用和所有显示器/Spaces 组合均兼容。

Integrated live mirrors with goals, numbered notes, and task completion/restore/deletion. Markers resume the source and promote its mirror. Passed 64 automated tests plus native-window and Chrome workflow checks on macOS 15.6 / Apple Silicon. Results are limited to the tested environment and permissions, not universal application or display/Spaces compatibility.
