import SwiftUI
import AppKit
import ThreadCore

struct OverviewView: View {
    @ObservedObject var model: AppModel
    @State private var document: OverviewDocument?
    @State private var notes: [String: WorkItem] = [:]
    @State private var noteErrors: [String: String] = [:]
    @State private var warning: String?
    @State private var filter = OverviewDocument.Filter.all
    @State private var query = ""
    @State private var selectedID: String?
    @State private var showInspector = true
    @State private var narrowInspector = false
    @State private var documentMode = false
    @State private var externalOverview = false
    private var rows: [OverviewDocument.Row] { document?.filtered(filter, query: query, notes: notes.mapValues(\.note)) ?? [] }
    private var selected: OverviewDocument.Row? { rows.first { $0.id == selectedID } }
    private var readOnly: Bool { model.store.overviewConflict || externalOverview }
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 1000
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("完整总览").font(.headline)
                    TextField("搜索编号、目标、来源或笔记", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 350).disabled(document == nil || documentMode)
                    Spacer(minLength: 0)
                    Button { if wide { showInspector.toggle() } else { narrowInspector.toggle() } } label: { Image(systemName: "sidebar.right") }.help("显示或隐藏笔记侧栏").accessibilityLabel("显示或隐藏笔记侧栏").disabled(document == nil || documentMode)
                    Button("打开 MD") { NSWorkspace.shared.open(model.store.overviewURL) }
                    Menu {
                        Button(documentMode ? "表格阅读" : "文档阅读") { documentMode.toggle() }.disabled(document == nil)
                        Button("数据文件夹") { NSWorkspace.shared.open(model.store.root) }
                        Button("刷新") { _ = model.store.reload(); model.sync(); reload() }
                    } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("总览更多操作")
                }.padding(14)
                if readOnly {
                    HStack { Image(systemName: "exclamationmark.triangle"); Text("总览有外部修改，自动更新已暂停。当前按文件原文阅读。").font(.caption); Spacer(); Button("备份并重新生成") { model.perform { try model.store.refreshOverview(force: true) }; reload() } }.padding(10).background(Color.orange.opacity(0.12))
                }
                if let warning { Text(warning).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(10) }
                Divider()
                if document == nil || documentMode { OverviewWeb(model: model, revision: model.overviewRevision) }
                else {
                    HStack(spacing: 0) {
                        if geometry.size.width >= 1100 { sidebar.frame(width: 145); Divider() }
                        VStack(spacing: 0) {
                            HStack {
                                if geometry.size.width < 1100 { Picker("记录范围", selection: $filter) { ForEach(OverviewDocument.Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 130) }
                                else { Text(filter.rawValue).font(.subheadline.weight(.medium)) }
                                Text("\(rows.count) 条").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                if !wide && narrowInspector { Button("返回表格") { narrowInspector = false }.buttonStyle(.borderless) }
                            }.padding(.horizontal, 14).padding(.vertical, 10)
                            if !wide && narrowInspector { Divider(); inspector }
                            else { table }
                        }
                        if wide && showInspector { Divider(); inspector.frame(width: 300) }
                    }
                }
                Divider()
                HStack { Text("总览.md"); Spacer(); Text(document == nil ? "文档阅读 · 原文保留" : "\(document?.rows.count ?? 0) 个条项 · 笔记按编号保存") }.font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.vertical, 8)
            }.background(Color(nsColor: .windowBackgroundColor))
        }.frame(minWidth: 760, minHeight: 480)
            .onAppear(perform: reload).onChange(of: model.overviewRevision) { _ in reload() }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("工作记录").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.vertical, 12)
            ForEach(OverviewDocument.Filter.allCases, id: \.self) { value in
                Button { filter = value } label: {
                    HStack { Image(systemName: symbol(value)).frame(width: 18).accessibilityHidden(true); Text(value.rawValue); Spacer(minLength: 2); Text("\(document?.filtered(value, query: "").count ?? 0)").font(.caption).monospacedDigit() }
                        .font(.system(size: 12)).padding(.horizontal, 8).padding(.vertical, 9).contentShape(Rectangle())
                        .background(filter == value ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain).accessibilityLabel(value.rawValue).accessibilityAddTraits(filter == value ? .isSelected : [])
            }
            Spacer()
            Text("留绪 · Thread").font(.caption).foregroundStyle(.secondary).padding(10)
        }.padding(.horizontal, 8)
    }
    private func symbol(_ value: OverviewDocument.Filter) -> String {
        switch value { case .all: return "tray.full"; case .active: return "circle.dotted"; case .starred: return "star"; case .completed: return "checkmark.circle" }
    }
    private var table: some View {
        GeometryReader { tableGeometry in
        let available = max(360, tableGeometry.size.width - 155)
        Table(rows, selection: $selectedID) {
            TableColumn("编号") { row in Text(row.id).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).padding(.vertical, 8) }.width(62)
            TableColumn("目标") { row in
                HStack(spacing: 5) { if row.starred { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.orange) }; if row.completed { Image(systemName: "checkmark.circle").foregroundStyle(.secondary).accessibilityLabel("已完成") }; Text(row.goal).font(.system(size: 13, weight: .medium)).lineLimit(2).foregroundStyle(row.completed ? .secondary : .primary) }.help(row.goal)
            }.width(available * 0.38)
            TableColumn("当前打开网页/应用") { row in Text(row.source).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2).help(row.source) }.width(available * 0.34)
            TableColumn("笔记") { row in
                Button { selectedID = row.id; if let _ = notes[row.id] { model.coordinator.openNote(row.id) } } label: { Text(noteErrors[row.id] != nil ? "笔记无法读取" : (notes[row.id]?.note.isEmpty == false ? notes[row.id]!.note.replacingOccurrences(of: "\n", with: " ") : "记下下一步…")).font(.system(size: 12)).lineLimit(2) }.buttonStyle(.borderless).disabled(!canAct(row)).accessibilityLabel("打开笔记 \(row.id)")
            }.width(available * 0.28)
        }.id(Int(tableGeometry.size.width)).overlay { if rows.isEmpty { VStack(spacing: 8) { Image(systemName: "tray").font(.largeTitle).foregroundStyle(.tertiary); Text(query.isEmpty ? "这里还没有条项" : "没有匹配的条项").foregroundStyle(.secondary); if document?.rows.isEmpty == true { Text("从悬浮条添加一个标记，留住下一步。").font(.caption).foregroundStyle(.secondary) } }.allowsHitTesting(false) } }
    }
    }
    private var inspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let row = selected {
                HStack { Text(row.id).font(.caption.monospacedDigit()).foregroundStyle(.secondary); Spacer(); Text(row.completed ? "已完成" : "进行中").font(.caption).foregroundStyle(.secondary); Button { model.toggleStar(row.id) } label: { Image(systemName: row.starred ? "star.fill" : "star").foregroundStyle(row.starred ? Color.orange : Color.secondary) }.buttonStyle(.plain).disabled(!canAct(row)).accessibilityLabel("星标 \(row.id)") }.padding(16)
                Text(row.goal).font(.system(size: 17, weight: .semibold)).textSelection(.enabled).lineLimit(5).padding(.horizontal, 16).help(row.goal)
                Text(row.source).font(.caption).foregroundStyle(.secondary).lineLimit(3).padding(.horizontal, 16).padding(.top, 8).help(row.source)
                if let url = row.sourceURL { Text(url).font(.caption2).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled).padding(.horizontal, 16).padding(.top, 4).help(url) }
                HStack { Button("回到来源") { if let item = model.store.item(row.id) { model.focus(item) } }; Button("独立打开") { model.coordinator.openNote(row.id) } }.controlSize(.small).disabled(!canAct(row)).padding(16)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("笔记").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        if let error = noteErrors[row.id] { Text(error).foregroundStyle(.orange) }
                        else { Text(notes[row.id]?.note.isEmpty == false ? notes[row.id]!.note : "还没有笔记。点击“独立打开”，记下下一步。").textSelection(.enabled).font(.system(size: 14)).lineSpacing(5).frame(maxWidth: .infinity, alignment: .leading) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                }
                Divider()
                HStack {
                    Button(row.completed ? "撤回完成" : "完成") { if row.completed { model.restore(row.id) } else { model.complete(row.id) } }
                    Spacer()
                    Menu {
                        Button("编辑目标与关联") { model.coordinator.showDetail(row.id) }
                        if query.isEmpty && (filter == .all || filter == .active || filter == .completed) {
                            Button("上移") { model.perform { try model.store.nudge(row.id, delta: -1) } }
                            Button("下移") { model.perform { try model.store.nudge(row.id, delta: 1) } }
                        }
                        Divider(); Button("删除…", role: .destructive) { model.delete(row.id) }
                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("条项更多操作")
                }.disabled(!canAct(row)).padding(16)
                if readOnly { Text("外部修改阅读模式：恢复自动总览后可在这里操作条项。").font(.caption).foregroundStyle(.secondary).padding([.horizontal, .bottom], 16) }
            } else {
                Spacer(); VStack(spacing: 12) { Image(systemName: "note.text").font(.largeTitle).foregroundStyle(.tertiary); Text("选择一个条项").font(.headline); Text("在这里查看目标和完整笔记").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity); Spacer()
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(nsColor: .textBackgroundColor))
    }
    private func canAct(_ row: OverviewDocument.Row) -> Bool {
        guard !readOnly, let note = notes[row.id], let current = model.store.item(row.id) else { return false }
        return note == current && row.goal == current.goal && row.starred == current.starred && row.completed == (current.status == "completed")
    }
    private func reload() {
        do {
            let data = try Data(contentsOf: model.store.overviewURL)
            externalOverview = (try? Data(contentsOf: model.store.root.appendingPathComponent(".thread/overview-baseline.md"))) != data
            guard let text = String(data: data, encoding: .utf8) else { throw ThreadError.message("总览不是有效的 UTF-8 文本。") }
            let parsed = try OverviewDocument(markdown: text)
            var loaded: [String: WorkItem] = [:], errors: [String: String] = [:]
            for row in parsed.rows {
                do { loaded[row.id] = try OverviewDocument.readNote(id: row.id, root: model.store.root) }
                catch { errors[row.id] = error.localizedDescription }
            }
            document = parsed; notes = loaded; noteErrors = errors; warning = nil
        } catch { document = nil; notes = [:]; noteErrors = [:]; warning = error.localizedDescription }
    }
}
