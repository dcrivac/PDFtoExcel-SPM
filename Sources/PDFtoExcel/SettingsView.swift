//
//  SettingsView.swift
//  PDFtoExcel
//
//  Created by David Kenji Crivac on 10/15/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("settings.outputFormat") private var outputFormat: String = "csv"
    @AppStorage("settings.accuracy") private var accuracy: String = "accurate"
    @AppStorage("settings.separateByPage") private var separateByPage: Bool = true
    @AppStorage("settings.includeConfidence") private var includeConfidence: Bool = true
    @AppStorage("settings.outputDirectory") private var outputDirectoryBookmark: Data?
    
    @State private var selectedTab: SettingTab = .general
    @State private var outputDirectory: URL?
    @State private var showingDirectoryPicker = false
    
    enum SettingTab: String, CaseIterable {
        case general = "General"
        case output = "Output"
        case advanced = "Advanced"
        
        var icon: String {
            switch self {
            case .general: return "gearshape.fill"
            case .output: return "folder.fill"
            case .advanced: return "slider.horizontal.3"
            }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "gearshape.2.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue.gradient)
                    
                    Text("Settings")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                .padding(.vertical, 24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)
                
                // Tab selection
                VStack(spacing: 4) {
                    ForEach(SettingTab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation(.spring(response: 0.4)) {
                                selectedTab = tab
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: tab.icon)
                                    .font(.title3)
                                    .frame(width: 24)
                                
                                Text(tab.rawValue)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Spacer()
                            }
                            .foregroundColor(selectedTab == tab ? .white : .primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background {
                                if selectedTab == tab {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(.blue.gradient)
                                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                                } else {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(.clear)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 24)
                
                Spacer()
            }
            .frame(minWidth: 200)
            .background(.ultraThinMaterial)
        } detail: {
            // Main content
            ScrollView {
                VStack(spacing: 24) {
                    switch selectedTab {
                    case .general:
                        GeneralSettingsView(
                            outputFormat: $outputFormat,
                            accuracy: $accuracy
                        )
                    case .output:
                        OutputSettingsView(
                            separateByPage: $separateByPage,
                            includeConfidence: $includeConfidence,
                            outputDirectory: $outputDirectory,
                            showingDirectoryPicker: $showingDirectoryPicker
                        )
                    case .advanced:
                        AdvancedSettingsView()
                    }
                }
                .padding(32)
            }
            .background(.ultraThinMaterial)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: 700, height: 500)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .fileImporter(
            isPresented: $showingDirectoryPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleDirectorySelection(result)
        }
        .onAppear {
            loadOutputDirectory()
        }
    }
    
    private func loadOutputDirectory() {
        guard let bookmarkData = outputDirectoryBookmark else { return }
        
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmarkData,
                            options: .withSecurityScope,
                            relativeTo: nil,
                            bookmarkDataIsStale: &isStale)
            if !isStale {
                outputDirectory = url
            }
        } catch {
            print("Failed to resolve bookmark: \(error)")
        }
    }
    
    private func handleDirectorySelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            outputDirectory = url
            
            // Create security-scoped bookmark
            do {
                let bookmarkData = try url.bookmarkData(options: .withSecurityScope,
                                                      includingResourceValuesForKeys: nil,
                                                      relativeTo: nil)
                outputDirectoryBookmark = bookmarkData
            } catch {
                print("Failed to create bookmark: \(error)")
            }
            
        case .failure(let error):
            print("Directory selection failed: \(error)")
        }
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @Binding var outputFormat: String
    @Binding var accuracy: String
    
    var body: some View {
        SettingsSection(title: "Output Format", icon: "doc.fill") {
            VStack(spacing: 16) {
                SettingsPicker(
                    title: "File Format",
                    selection: $outputFormat,
                    options: [
                        ("csv", "CSV", "Comma-separated values format"),
                        ("xlsx", "Excel", "Microsoft Excel format (placeholder)")
                    ]
                )
                
                SettingsPicker(
                    title: "Recognition Accuracy",
                    selection: $accuracy,
                    options: [
                        ("fast", "Fast", "Quick processing with good accuracy"),
                        ("accurate", "Accurate", "Slower processing with highest accuracy")
                    ]
                )
            }
        }
    }
}

// MARK: - Output Settings

struct OutputSettingsView: View {
    @Binding var separateByPage: Bool
    @Binding var includeConfidence: Bool
    @Binding var outputDirectory: URL?
    @Binding var showingDirectoryPicker: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            SettingsSection(title: "File Organization", icon: "folder.fill") {
                VStack(spacing: 16) {
                    SettingsToggle(
                        title: "Separate by Page",
                        subtitle: "Add page breaks between tables from different pages",
                        isOn: $separateByPage
                    )
                    
                    SettingsToggle(
                        title: "Include Confidence Scores",
                        subtitle: "Show recognition confidence in the output",
                        isOn: $includeConfidence
                    )
                }
            }
            
            SettingsSection(title: "Output Location", icon: "location.fill") {
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Save Location")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            if let directory = outputDirectory {
                                Text(directory.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            } else {
                                Text("Documents/PDFtoExcel (default)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Button("Choose...") {
                            showingDirectoryPicker = true
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .background(Color(.quaternarySystemFill), in: .rect(cornerRadius: 12))
                    
                    if outputDirectory != nil {
                        Button("Reset to Default") {
                            withAnimation(.spring()) {
                                outputDirectory = nil
                            }
                        }
                        .buttonStyle(.bordered)
                        .foregroundStyle(.red)
                    }
                }
            }
        }
    }
}

// MARK: - Advanced Settings

struct AdvancedSettingsView: View {
    @AppStorage("settings.enableLogging") private var enableLogging: Bool = false
    @AppStorage("settings.useOptimizedProcessor") private var useOptimizedProcessor: Bool = false
    @AppStorage("settings.maxConcurrentJobs") private var maxConcurrentJobs: Double = 4
    @AppStorage("settings.minimumTableSize") private var minimumTableSize: Double = 2
    
    var body: some View {
        VStack(spacing: 24) {
            SettingsSection(title: "Performance", icon: "speedometer") {
                VStack(spacing: 16) {
                    SettingsToggle(
                        title: "Use Optimized Processor",
                        subtitle: "Chunked, memory-aware engine with data type detection. Always writes CSV, ignoring the output format setting.",
                        isOn: $useOptimizedProcessor
                    )
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Maximum Concurrent Jobs: \(Int(maxConcurrentJobs))")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Slider(value: $maxConcurrentJobs, in: 1...8, step: 1) {
                            Text("Concurrent Jobs")
                        }
                        .accentColor(.blue)
                        
                        Text("Higher values may improve speed but use more system resources")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color(.quaternarySystemFill), in: .rect(cornerRadius: 12))
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Minimum Table Size: \(Int(minimumTableSize)) rows")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Slider(value: $minimumTableSize, in: 1...10, step: 1) {
                            Text("Minimum Rows")
                        }
                        .accentColor(.blue)
                        
                        Text("Tables with fewer rows will be ignored")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color(.quaternarySystemFill), in: .rect(cornerRadius: 12))
                }
            }
            
            SettingsSection(title: "Debug", icon: "ladybug.fill") {
                VStack(spacing: 16) {
                    SettingsToggle(
                        title: "Enable Debug Logging",
                        subtitle: "Log detailed processing information for troubleshooting",
                        isOn: $enableLogging
                    )
                }
            }
            
            SettingsSection(title: "About", icon: "info.circle.fill") {
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("PDF to Excel Converter")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            Text("Version 1.0.0 (Build 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "doc.richtext.fill")
                            .font(.title)
                            .foregroundStyle(.blue.gradient)
                    }
                    .padding()
                    .background(Color(.quaternarySystemFill), in: .rect(cornerRadius: 12))
                }
            }
        }
    }
}

// MARK: - Helper Views

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 24)
                
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            
            content
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct SettingsPicker: View {
    let title: String
    @Binding var selection: String
    let options: [(value: String, title: String, subtitle: String)]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            
            VStack(spacing: 8) {
                ForEach(options, id: \.value) { option in
                    Button {
                        withAnimation(.spring()) {
                            selection = option.value
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.title)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Text(option.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            if selection == option.value {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .foregroundColor(.primary)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selection == option.value ? Color.blue.opacity(0.1) : Color(.quaternarySystemFill))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(selection == option.value ? .blue : .clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct SettingsToggle: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.blue)
        }
        .padding()
        .background(Color(.quaternarySystemFill), in: .rect(cornerRadius: 12))
    }
}

#Preview {
    SettingsView()
}
