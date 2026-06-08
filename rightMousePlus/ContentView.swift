//
//  ContentView.swift
//  superMouse —— macOS 26 风格设置主界面
//

import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case newFile = "新建文件"
    case general = "通用设置"
    case about = "关于"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .newFile: "doc.badge.plus"
        case .general: "gearshape"
        case .about: "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .newFile: .blue
        case .general: .gray
        case .about: .pink
        }
    }
}

struct ContentView: View {
    @State private var selection: SidebarItem? = .newFile
    @EnvironmentObject private var updater: UpdateChecker
    @AppStorage("didOnboard") private var didOnboard = false
    @State private var showOnboarding = false

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                NavigationLink(value: item) {
                    Label {
                        Text(item.rawValue)
                    } icon: {
                        Image(systemName: item.icon)
                            .foregroundStyle(.white)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 22, height: 22)
                            .background(item.tint, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 210, max: 240)
            .safeAreaInset(edge: .top) {
                brandHeader
            }
        } detail: {
            Group {
                switch selection ?? .newFile {
                case .newFile: NewFileSettingsView()
                case .general: GeneralSettingsView()
                case .about: AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(minWidth: 780, minHeight: 560)
        .onOpenURL { AirDropService.handle($0) }
        .onAppear {
            updater.check()
            if !didOnboard { showOnboarding = true }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingSheet { didOnboard = true }
        }
        .sheet(item: $updater.available) { release in
            UpdateSheet(
                release: release,
                currentVersion: updater.currentVersion,
                onDownload: { updater.download(release) },
                onSkip: { updater.skip(release) },
                onLater: { updater.dismiss() }
            )
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "cursorarrow.click.2")
                .font(.system(size: 22))
                .foregroundStyle(.tint)
                .frame(width: 38, height: 38)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 1) {
                Text("RightPlus").font(.headline)
                Text("v1.0").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

#Preview {
    ContentView()
        .environmentObject(UpdateChecker())
}
