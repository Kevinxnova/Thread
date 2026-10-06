# 留绪 · Thread

**Pick up where you left off.**

*留住思路，随时继续。*

English · [简体中文](README.md)

Thread is a native macOS app that connects application windows and web pages with goals and notes. Leave a numbered marker on your work, then click it later to return to the right window or page and continue your train of thought.

Current version: **0.8**. This source publication builds on the locally validated 0.7 feature set and adds bilingual documentation and repository privacy checks. The application UI is currently primarily in Chinese.

## Features

- **Keep your context** — Choose a window or page, enter a goal, and get a numbered, automatically saved Markdown note. Multiple goals can share the same source.
- **Resume with a click** — A numbered marker brings back its source window or page, opens its note, and promotes its live mirror above older mirrors.
- **Optional always-on-top mirrors** — Keep content visible with SIP enabled. Newly pinned mirrors take priority; unpinning preserves your task and notes.
- **Lightweight notes** — Move and resize note panels. Closing a source window does not complete the task.
- **Manage ongoing work** — A three-icon floating toolbar opens source selection, work items, and the full overview. Search, star, reorder, complete, and undo completion. The three most recent completed items appear in gray; deletion requires confirmation.
- **A readable overview** — Render the local Markdown overview with four columns: ID, goal, current page/application, and notes, plus a note sidebar. “All open” lists windows currently available to enumeration.
- **Native macOS design** — AppKit, SwiftUI, system typography, and light/dark appearance.

> Thread keeps its own live mirror panels on top; it does not persistently change the stacking level of another application's original window. The source app keeps running. Click and scroll forwarding are experimental; use the original window for keyboard input and complex interactions. Up to six source windows can be mirrored at once.

## Build and run

Requires macOS, Swift 5.9 or later, and a working macOS SDK. The deployment target is macOS 13; full local workflow validation was performed on **macOS 15.6 / Apple Silicon**. Other environments have not been comprehensively validated. No third-party package dependencies.

```sh
git clone https://github.com/Kevinxnova/Thread.git
cd Thread
python3 scripts/check-repository.py --all-history
swift test
./scripts/build.sh
open dist/Thread.app
```

The build script creates an app for the host architecture and applies an ad-hoc signature. It does not provide Developer ID signing or Apple notarization. This repository contains source, not application bundles, build caches, or personal data.

Grant Screen Recording and Accessibility permissions when requested. Browser page discovery and navigation may also require Automation permission. SIP can remain enabled.

1. Click the toolbar's marker icon, choose a source, and enter a goal.
2. Click a desktop numbered marker to resume the source and its note.
3. Use work items to reorder, star, complete, or restore tasks; open the third toolbar icon for the full overview.

## Your data stays local

The default data directory is `~/Thread_kevin/` under the current user's home directory, separate from the repository:

| File | Purpose |
| --- | --- |
| `总览.md` | A readable four-column Markdown overview |
| `笔记/000001.md` | Numbered task metadata and note body |
| `.thread/store.json` | ID high-water mark that prevents number reuse |
| `.thread/conflicts/` | Preserved copies when external edits conflict |

No account or cloud service is required. Mirror frames are processed in memory rather than saved as recordings. The app has no task or note upload feature. Resuming a web page delegates navigation to its browser. Runtime diagnostics may appear in terminal output; `THREAD_MIRROR_LOG` optionally writes a local log. Review diagnostics before sharing them.

When editing a numbered note externally, edit only the body after the second `---` separator and retain its metadata and ID state. If the overview changes externally, the app pauses automatic overwriting and offers to back it up before rebuilding it.

Set `THREAD_DATA_DIR` to an isolated directory for development. **Never commit personal tasks, browsing records, notes, or validation logs.** See the [contribution and publication checklist](CONTRIBUTING.md).

## Validation and limitations

- Version 0.7 passed 64 automated tests on the environment above, plus local workflow checks for native windows, Chrome pages, marker recovery, shared mirrors, note persistence, and light/dark appearance. Raw logs remain local and are excluded from this repository.
- Standard `swift test` skips the real Trash integration test. Run `THREAD_TEST_REAL_TRASH=1 swift test` to enable it; it uses disposable generated notes only.
- Web mirrors capture the browser window. A page change clears the mirror and blocks forwarded input until the source matches again. This is not an independent background-tab renderer; checks have a short detection delay.
- Safari, Edge, and Brave have discovery code paths, but lack the same scope of live validation as Chrome. Other macOS versions, Intel, multiple physical displays, fullscreen/Spaces combinations, protected content, long-term power use, and full VoiceOver workflows still need validation.
- Input forwarding uses an undocumented system interface and may break after OS updates. This version does not claim App Store compatibility.

[Requirements and approach](docs/REQUIREMENTS.md) · [Changelog](CHANGELOG.md) · [Contributing](CONTRIBUTING.md)
