# Repository instructions / 仓库指令

- Only publish project source, synthetic tests, build/check scripts, and reviewed public documentation. 仅发布项目源码、虚构数据测试、构建/检查脚本与公开文档。
- Never read personal data merely to prepare a commit. Never stage or upload personal tasks, notes, browsing records, window inventories, screenshots, recordings, logs, snapshots, or runtime state. Do not copy data from the sibling `Thread_kevin` directory into this repository. 不得为准备提交而读取个人数据；不得提交或上传个人任务、笔记及任何运行记录。
- The local `验证`, `设计`, `dist`, `.build` directories and historical root planning/report documents are not public deliverables. Keep them ignored. 本机验收、设计样例、构建产物与历史报告保持忽略。
- Before every commit/push, inspect the staged paths AND contents; run `python3 scripts/check-repository.py` before committing and `python3 scripts/check-repository.py --all-history` before pushing. Install hooks with `git config core.hooksPath .githooks`. Do not bypass checks. 每次更新必须审查路径及内容并执行检查。
- When adding public files, review the allowlists in both `.gitignore` and the checker. An allowed path does not make personal content publishable. 新增公开文件须同步审查允许范围。
- Use isolated temporary test data. Version format is `x.y`; increment `y` for a delivered modification and consult the owner before changing `x`. Document actual validation and remaining limits. 测试使用隔离数据；小版本递增，大版本先对齐。
