import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var scanner = ScannerService()
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            switch scanner.state {
            case .idle:
                idleView
            case .scanning(let scanned, let total):
                scanningView(scanned: scanned, total: total)
            case .results:
                resultsView
            }
        }
        .frame(minWidth: 480, minHeight: 400)
        .background(.background)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
            return true
        }
    }

    // MARK: - Idle View

    private var idleView: some View {
        VStack(spacing: 16) {
            Spacer()

            // Logo
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

            Text("Footage Calculator")
                .font(.title.bold())

            // Drop zone
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 2.5, dash: [10, 6])
                    )
                    .foregroundStyle(isTargeted ? .blue : .secondary.opacity(0.5))
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isTargeted ? Color.blue.opacity(0.06) : Color.clear)
                    )

                VStack(spacing: 14) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 36, weight: .thin))
                        .foregroundStyle(.secondary)

                    Text("Drop a folder or files here")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    Button("Browse...") {
                        browseForFolder()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.vertical, 24)
            }
            .frame(maxHeight: 180)
            .padding(.horizontal, 32)

            Toggle("Include subfolders", isOn: $scanner.includeSubfolders)
                .toggleStyle(.checkbox)
                .padding(.bottom, 8)

            Spacer()
        }
        .padding()
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }

    // MARK: - Scanning View

    private func scanningView(scanned: Int, total: Int) -> some View {
        VStack(spacing: 20) {
            Spacer()

            ProgressView(value: total > 0 ? Double(scanned) / Double(total) : 0) {
                Text("Scanning \(scanned) of \(total) files...")
                    .font(.headline)
            }
            .progressViewStyle(.linear)
            .padding(.horizontal, 60)

            Button("Cancel") {
                scanner.cancel()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Spacer()
        }
        .padding()
    }

    // MARK: - Results View

    private var resultsView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    let r = scanner.results
                    let totalFiles = r.videoCount + r.audioCount + r.imageCount + r.otherCount

                    if totalFiles == 0 {
                        Text("No files found.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)
                    } else {
                        categoryCard(
                            icon: "film",
                            title: "Video",
                            count: r.videoCount,
                            duration: r.videoDuration,
                            unknown: r.videoUnknown,
                            color: .blue
                        )

                        categoryCard(
                            icon: "waveform",
                            title: "Audio",
                            count: r.audioCount,
                            duration: r.audioDuration,
                            unknown: r.audioUnknown,
                            color: .purple
                        )

                        categoryCard(
                            icon: "photo",
                            title: "Images",
                            count: r.imageCount,
                            duration: nil,
                            unknown: 0,
                            color: .green
                        )

                        categoryCard(
                            icon: "doc",
                            title: "Other",
                            count: r.otherCount,
                            duration: nil,
                            unknown: 0,
                            color: .gray
                        )
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                Text("Drop another folder to scan again")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button("Scan Another") {
                    scanner.reset()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Category Card

    private func categoryCard(
        icon: String,
        title: String,
        count: Int,
        duration: TimeInterval?,
        unknown: Int,
        color: Color
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)

                if count == 0 {
                    Text("No files")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 12) {
                        Text("\(count) file\(count == 1 ? "" : "s")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let duration {
                            Text(formatDuration(duration))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.primary)
                        }

                        if unknown > 0 {
                            Text("\(unknown) unknown")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Actions

    private func browseForFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Select a folder or files to scan"

        guard panel.runModal() == .OK else { return }
        scanner.scan(urls: panel.urls)
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                defer { group.leave() }
                guard let data = data as? Data,
                      let path = String(data: data, encoding: .utf8),
                      let url = URL(string: path)
                else { return }
                urls.append(url)
            }
        }

        group.notify(queue: .main) {
            if !urls.isEmpty {
                scanner.scan(urls: urls)
            }
        }
    }
}

#Preview {
    ContentView()
}
