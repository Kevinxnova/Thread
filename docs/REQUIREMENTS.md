# 项目需求与方案 / Requirements and approach

版本 / Version: **0.8**。这里是软件项目需求，不是个人工作清单。 / These are software requirements, not personal work items.

以下功能基于 0.7 本机验收范围。0.8 主要增加仓库发布保护和公开文档，不扩大兼容性承诺。原始本机记录不公开。 / Features retain the locally validated 0.7 baseline. Version 0.8 adds publication safeguards and documentation, without expanding compatibility claims. Raw local records are not published.

| REQ编号 / ID | REQ / Requirement | 方案 / Approach | 开发 / Implementation | 验证 / Validation |
| --- | --- | --- | --- | --- |
| REQ-001 | 可选置顶，新开启优先 / Optional pinning, newest first | SIP 开启；实时镜像 / Live mirrors with SIP enabled | 已实现，上限 6 来源 / Implemented, six sources | 本机层级与开关验收 / Local stacking and toggle checks |
| REQ-002 | 可拖动悬浮条 / Draggable toolbar | 三图标、屏幕约束 / Three icons, screen bounds | 已实现 / Implemented | 本机与几何回归 / Local and geometry checks |
| REQ-003 | 新建时必填目标 / Required goal on creation | 独立编号、持久化后置顶 / Unique ID, save then pin | 已实现 / Implemented | 创建、取消和必填 / Create, cancel, required input |
| REQ-004 | 点击标签打开笔记 / Marker opens notes | 自动保存、拖动缩放 / Autosave, move and resize | 已实现 / Implemented | 本机保存与位置恢复 / Local save and frame recovery |
| REQ-005 | 页面或应用关联，可多个目标 / Page or app association, multiple goals | URL 与应用标识 / URL and bundle identity | 已实现，共享捕获 / Implemented, shared capture | Chrome 页面切换保护 / Chrome page-change guard |
| REQ-006 | 四列 Markdown 总览 / Four-column Markdown overview | 编号、目标、来源、笔记 / ID, goal, source, notes | 已实现 / Implemented | 格式、冲突回归 / Format and conflict tests |
| REQ-007 | 所有进行中条项 / All active work items | 列表、搜索与笔记入口 / List, search, notes | 已实现 / Implemented | 本机列表与筛选 / Local list and filters |
| REQ-008 | 最近完成三条及撤回 / Three recent completions and undo | 灰色展示，历史保留 / Gray entries, retained history | 已实现 / Implemented | 完成/恢复和边界回归 / Completion, restore, boundary tests |
| REQ-009 | 排序与星标 / Reorder and star | 手动顺序持久化 / Persist manual order | 已实现 / Implemented | 本机与存储回归 / Local and persistence tests |
| REQ-010 | 完成/删除联动、删除确认 / Lifecycle and confirmed deletion | 共享镜像引用，笔记进废纸篓 / Shared ownership, Trash | 已实现 / Implemented | 共享生命周期与废纸篓测试 / Ownership and Trash tests |
| REQ-011 | 关闭来源不完成任务，重启保留 / Closing source preserves tasks | 持久化与来源重定位 / Persistence and source recovery | 已实现 / Implemented | 原生和 Chrome 恢复 / Native and Chrome recovery |
| REQ-012 | 五列需求表，x.y 版本 / Five-column requirements, x.y versions | 小改递增，大版本对齐 / Increment minor, discuss major | 已实现 / Implemented | 文档和版本一致性 / Documentation and version checks |
| REQ-013 | 编号笔记文件 / Numbered note files | 用户主目录内独立数据 / Separate data under user home | 已实现 / Implemented | 编号、事务及冲突回归 / IDs, transactions, conflict tests |
| REQ-014 | 全部打开，默认已标记 / All open, marked by default | 系统可枚举窗口 / System-enumerable windows | 已实现 / Implemented | 本机分组；不保证全部 Spaces / Local grouping, limited Spaces coverage |
| REQ-015 | 第三图标渲染总览 / Third icon renders overview | 读取实际 MD、笔记侧栏 / Actual Markdown and note sidebar | 已实现 / Implemented | 解析及本机界面 / Parsing and local UI |
| REQ-016 | 苹果设计风格 / Native Apple styling | 系统组件、语义色、浅深色 / System controls and appearance | 已实现 / Implemented | 本机浅深色；完整 VoiceOver 待验 / Local appearance, full VoiceOver pending |
| REQ-017 | 标签展示关联来源并前置 / Marker resumes and brings forward | 定位来源、提升镜像、打开笔记 / Locate source, promote mirror, open note | 已实现 / Implemented | 原生与具体网页恢复 / Native and exact-page recovery |
| REQ-018 | 中英文仓库，仅发布项目内容 / Bilingual repository, project content only | 允许范围、内容检查、钩子、CI / Allowlists, content checks, hooks, CI | 已实现 / Implemented | 暂存区/历史审查与拦截回归 / Index/history review and rejection tests |

兼容性与权限条件见 [中文介绍](../README.md) 或 [English README](../README.en.md)。 / See the README for compatibility and permission requirements.
