# 贡献与发布 / Contributing and publishing

## 仅发布项目代码与公开文档 / Publish code and public documentation only

本仓库只接收源代码、使用虚构数据的测试、构建及检查脚本、公开项目文档。个人任务、目标、笔记、实际浏览记录、窗口标题、截图、录屏、验收日志、数据快照和安装包均不应提交。即使文件位于允许目录，也必须审查其内容。

This repository accepts source, tests with synthetic data, build/check scripts, and public project documentation. Never commit personal tasks, goals, notes, actual browsing records, window titles, screenshots, recordings, validation logs, data snapshots, or app bundles. An allowed file path is not proof that its contents are safe.

## 本地设置 / Local setup

需要 Python 3、Git 和 macOS Swift 工具链。克隆后执行： / Requires Python 3, Git, and the macOS Swift toolchain. After cloning:

```sh
git config core.hooksPath .githooks
python3 scripts/check-repository.py --all-history
swift test
```

`.gitignore` 默认不接收新目录；公开目录中的允许文件才会显示为待提交。提交钩子检查暂存区，推送钩子检查本地所有分支和标签的可达历史。CI 执行相同的历史检查。新增公开文件需要同时审查 `.gitignore` 和检查脚本中的允许范围，不能为了提交数据而放宽规则。

The ignore rules deny new directories by default. The commit hook checks the index; the push hook checks history reachable from all local refs, including branches and tags. CI repeats the history check. Review both the ignore rules and the checker's allowlist when introducing a new public file; do not relax them to publish runtime data.

## 每次更新 / Before every update

1. 测试使用临时目录或显式的 `THREAD_DATA_DIR`，禁止对日常数据做破坏性测试。Use a temporary directory or an explicit `THREAD_DATA_DIR`; never run destructive tests on everyday data.
2. 只暂存本次审查过的文件，不使用未经检查的整目录添加。Stage only reviewed files; do not add unreviewed directory contents.
3. 检查下面的暂存区文件列表与完整差异。Review the file list and complete staged diff:

   ```sh
   git diff --cached --name-status
   git diff --cached
   python3 scripts/check-repository.py
   ```

4. 执行相关测试及构建，再提交、检查历史并推送。Run relevant tests and builds, commit, inspect history, and then push:

   ```sh
   python3 scripts/test-repository-check.py
   swift test
   ./scripts/build.sh
   python3 scripts/check-repository.py --all-history
   git push
   ```

5. 推送后确认远程提交、文件清单及 CI 结果。Verify the remote commit, file tree, and CI result after pushing.

自动检查会拒绝非允许文件、符号链接、二进制内容、过大文件、个人绝对路径和部分凭据模式；不会理解每一段文字，也无法取代人工内容审查。钩子只在配置后的克隆中生效且可被绕过，CI 在推送之后运行，因此**不能依赖 CI 阻止首次泄露**。不要使用 `--no-verify`、强制添加数据或绕过检查发布。

Automated checks reject unapproved paths, symlinks, binary content, oversized files, personal absolute paths, and selected credential patterns. They cannot interpret all prose or replace content review. Hooks require setup in each clone and can be bypassed; CI runs after a push and therefore **cannot prevent an initial disclosure**. Do not bypass the checks, force-add data, or publish with `--no-verify`.

## 版本 / Versioning

使用 `x.y`。每次形成交付的修改递增 `y`；升级 `x` 前先与项目负责人对齐。同步应用显示、诊断版本、构建信息、README 与 CHANGELOG。提交不包含本机验收原始记录，只描述实际验证的范围和限制。

Use `x.y`. Increment `y` for each delivered change; agree with the project owner before incrementing `x`. Keep the app label, diagnostics, bundle metadata, README, and changelog aligned. Summarize actual validation and its limits without publishing raw local evidence.

## 项目结构 / Layout

- `Sources/ThreadCore/` — 数据模型、Markdown 存储、布局与镜像关联 / models, Markdown persistence, layout, mirror ownership.
- `Sources/ThreadApp/` — macOS 界面、窗口定位与实时捕获 / macOS UI, window discovery, live capture.
- `Tests/` — 使用临时数据的回归测试 / regression tests using temporary data.
- `scripts/` — 构建、图标生成、仓库检查 / build, icon generation, repository checks.
- `docs/` — 经审查的公开需求 / reviewed public requirements.
