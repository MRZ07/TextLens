import SwiftUI
import TextLensCore

struct CaptureHistoryView: View {
    @ObservedObject var model: CaptureViewModel
    @State private var selection: CapturedText.ID?
    @State private var confirmingClear = false

    private var selectedCapture: CapturedText? {
        model.filteredHistory.first { $0.id == selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.phase != .idle || model.feedback.tone != .neutral {
                feedbackBanner
                Divider()
            }
            historyContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 620, minHeight: 380)
        .background(Color(nsColor: .windowBackgroundColor))
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search captures")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: model.capture) {
                    Label("Capture Text", systemImage: "viewfinder")
                }
                .disabled(model.isWorking)

                Button(action: model.chooseImage) {
                    Label("Read Text from Image", systemImage: "photo")
                }
                .disabled(model.isWorking)

                Button(role: .destructive) {
                    confirmingClear = true
                } label: {
                    Label("Clear History", systemImage: "trash")
                }
                .disabled(model.history.isEmpty || model.isWorking)
            }
        }
        .onChange(of: model.filteredHistory.map(\.id), initial: true) { _, current in
            if selectedCapture == nil {
                selection = current.first
            }
        }
        .onChange(of: model.history.first?.id) { _, latest in
            if model.filteredHistory.first?.id == latest {
                selection = latest
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
            Text("This permanently removes saved text from this Mac.")
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        if let error = model.historyLoadError {
            ContentUnavailableView {
                Label("History unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Reload History", action: model.reloadHistory)
            }
        } else if model.history.isEmpty {
            ContentUnavailableView {
                Label("No captures yet", systemImage: "text.viewfinder")
            } description: {
                Text("Select a region on screen or read text from an image.")
            } actions: {
                Button("Capture Text", action: model.capture)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isWorking)
                Button("Open Image…", action: model.chooseImage)
                    .disabled(model.isWorking)
            }
        } else if model.filteredHistory.isEmpty {
            ContentUnavailableView.search(text: model.searchText)
        } else {
            HSplitView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.searchText.isEmpty ? "Recent captures" : "Search results")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .padding(.bottom, 6)
                        .accessibilityAddTraits(.isHeader)

                    List(model.filteredHistory, selection: $selection) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.text)
                                .lineLimit(2)
                            Text(item.capturedAt, format: .dateTime.month().day().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 5)
                        .tag(item.id)
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                }
                .background(.regularMaterial)
                .frame(minWidth: 210, idealWidth: 245, maxWidth: 275)

                if let selectedCapture {
                    captureDetail(selectedCapture)
                } else {
                    ContentUnavailableView("Select a capture", systemImage: "text.alignleft")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func captureDetail(_ item: CapturedText) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Captured text")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                    Text(item.capturedAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.copyAgain(item)
                } label: {
                    Label("Copy Text", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isWorking)
            }
            .padding(20)

            Divider()
            ScrollView {
                Text(item.text)
                    .font(.body)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .id(item.id)
        }
        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
    }

    private var feedbackBanner: some View {
        HStack(alignment: .center, spacing: 11) {
            Group {
                if model.phase.isWorking {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: model.feedback.symbol)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(feedbackColor)
                }
            }
            .frame(width: 20)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(model.feedback.title)
                    .font(.subheadline.weight(.semibold))
                Text(model.feedback.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            if model.feedback.needsScreenRecordingAccess {
                Button("Open Screen Recording Settings", action: CaptureViewModel.openScreenRecordingSettings)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(feedbackColor.opacity(0.08))
    }

    private var feedbackColor: Color {
        switch model.feedback.tone {
        case .neutral: .accentColor
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }
}
