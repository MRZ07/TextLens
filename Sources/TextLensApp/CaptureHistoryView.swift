import SwiftUI
import TextLensCore

struct CaptureHistoryView: View {
    @ObservedObject var model: CaptureViewModel
    @State private var confirmingClear = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                feedbackSummary
                historyContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Capture History")
            .searchable(text: $model.searchText, prompt: "Search captures")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        confirmingClear = true
                    } label: {
                        Label("Clear History", systemImage: "trash")
                    }
                    .disabled(model.history.isEmpty || model.isWorking)
                }
            }
        }
        .confirmationDialog(
            "Clear all captures?",
            isPresented: $confirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                guard !model.isWorking else { return }
                model.clearHistory()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes saved text from this Mac. It can't be undone.")
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        if let error = model.historyLoadError {
            ContentUnavailableView {
                Label("History unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text("TextLens couldn't read its local history. \(error)")
            } actions: {
                Button("Try Again") {
                    model.reloadHistory()
                }
            }
        } else if model.history.isEmpty {
            ContentUnavailableView(
                "No captures yet",
                systemImage: "text.viewfinder",
                description: Text("Text you capture will be saved here for quick access.")
            )
        } else if model.filteredHistory.isEmpty {
            ContentUnavailableView(
                "No matches",
                systemImage: "magnifyingglass",
                description: Text("Try another word or clear your search.")
            )
        } else {
            List {
                Section("\(model.filteredHistory.count) \(model.filteredHistory.count == 1 ? "capture" : "captures")") {
                    ForEach(model.filteredHistory) { item in
                        HistoryRow(item: item, isWorking: model.isWorking) {
                            model.copyAgain(item)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private var feedbackSummary: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: feedbackSymbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(feedbackColor)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(model.feedback.title)
                    .font(.system(.subheadline, weight: .semibold))
                Text(model.feedback.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(feedbackColor.opacity(0.08))
        .accessibilityElement(children: .combine)
    }

    private var feedbackColor: Color {
        switch model.feedback.tone {
        case .neutral: Color.accentColor
        case .success: Color.green
        case .warning: Color.orange
        case .error: Color.red
        }
    }

    private var feedbackSymbol: String {
        switch model.phase {
        case .idle: "info.circle"
        case .capturing: "viewfinder"
        case .recognizing: "text.viewfinder"
        case .recognized: "text.viewfinder"
        case .copied: model.feedback.tone == .warning ? "exclamationmark.triangle" : "checkmark.circle"
        case .failed: "exclamationmark.circle"
        }
    }
}

private struct HistoryRow: View {
    let item: CapturedText
    let isWorking: Bool
    let copy: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(item.text)
                    .font(.body)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(item.capturedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(action: copy) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .disabled(isWorking)
            .help("Copy this capture again")
            .accessibilityLabel("Copy capture from \(item.capturedAt.formatted(date: .abbreviated, time: .shortened)) again")
        }
        .padding(.vertical, 5)
    }
}
