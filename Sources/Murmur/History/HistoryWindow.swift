import AppKit
import SwiftUI

/// Native SwiftUI history window — much nicer than the Python version's
/// render-HTML-to-temp-file-and-open-browser dance.
///
/// Features:
/// * Search field filters on `text` + `model`.
/// * Per-row Copy button (clipboard).
/// * Error rows rendered with a red leading strip.
/// * Shows paste state (✓ pasted vs ⎘ copy-only vs ⚠ error).
@MainActor
struct HistoryView: View {
    let store: HistoryStore
    @State private var items: [Transcript] = []
    @State private var query: String = ""
    @State private var refreshKey: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            list
        }
        .frame(minWidth: 460, minHeight: 320)
        .onAppear(perform: reload)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search transcripts…", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button(action: { query = "" }) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(filtered.count) item\(filtered.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(action: reload) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Reload")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var list: some View {
        List(filtered) { row in
            HistoryRow(item: row)
                .listRowSeparator(.visible)
        }
        .listStyle(.inset)
    }

    private var filtered: [Transcript] {
        guard !query.isEmpty else { return items }
        let q = query.lowercased()
        return items.filter { t in
            t.text.lowercased().contains(q) || t.model.lowercased().contains(q)
        }
    }

    private func reload() {
        items = store.recent(limit: 500)
        refreshKey &+= 1
    }
}

/// One transcript row. Note: no @Observable here — we rebuild the list on
/// reload, so local transient state (copied? flash) is all that matters.
private struct HistoryRow: View {
    let item: Transcript
    @State private var justCopied = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            leadingStrip
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.timestamp, style: .date)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(item.timestamp, style: .time)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(item.model)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let d = item.durationS {
                        Text(String(format: "%.1fs", d))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    pasteBadge
                }
                if let error = item.error {
                    Text("error: \(error)")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                } else {
                    Text(item.text.isEmpty ? "(empty)" : item.text)
                        .font(.callout)
                        .textSelection(.enabled)
                        .lineLimit(6)
                }
            }
            Button(action: copy) {
                Label(justCopied ? "Copied" : "Copy",
                      systemImage: justCopied ? "checkmark" : "doc.on.doc")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Copy transcript")
            .disabled(item.text.isEmpty)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var leadingStrip: some View {
        Rectangle()
            .fill(item.error != nil ? Color.red : Color.accentColor.opacity(0.35))
            .frame(width: 3)
    }

    @ViewBuilder
    private var pasteBadge: some View {
        if item.error != nil {
            Label("error", systemImage: "exclamationmark.triangle.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(.red)
        } else if item.pasted {
            Label("pasted", systemImage: "checkmark.circle.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(.green)
        } else {
            Label("not pasted", systemImage: "doc.on.clipboard")
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
        }
    }

    private func copy() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(item.text, forType: .string)
        justCopied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            justCopied = false
        }
    }
}
