import AppKit
import SwiftUI

enum DisplayMode: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case windowed = "Windowed"
    case fullscreen = "Fullscreen"
    var id: String { rawValue }
}

enum FpsCap: String, CaseIterable, Identifiable {
    case uncapped = "Uncapped"
    case fps60 = "60"
    case fps72 = "72"
    case fps120 = "120"
    case fps144 = "144"
    var id: String { rawValue }
}

@MainActor
final class LauncherViewModel: ObservableObject {
    @Published var useLegacyNtdll = true
    @Published var metalHud = false
    @Published var x87Accel = true
    @Published var smoothMouse = true
    @Published var fpsCap: FpsCap = .uncapped
    @Published var displayMode: DisplayMode = .auto

    @Published var gameDir: String = ""
    @Published var detectedGameLabel: String = "NO GAME FOLDER SELECTED"
    @Published var isRunning = false
    @Published var statusLine = "READY // NTDLL=legacy • x87sidecar • DXMT"

    private var activeProcess: Process?
    private let gameDirKey = "PlutoniumGameDir"

    private var runtimeDir: String {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("runtime").path,
           FileManager.default.fileExists(atPath: "\(bundled)/launch.sh") {
            return bundled
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/plutonium-on-mac").path
    }

    private var isStandalone: Bool {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("runtime").path,
           FileManager.default.fileExists(atPath: "\(bundled)/launch.sh") {
            return true
        }
        return false
    }

    private var prefixDir: String {
        if isStandalone {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/PlutoniumOnMac/prefix").path
        }
        return "\(runtimeDir)/prefix"
    }

    private var logsDir: String {
        if isStandalone {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/PlutoniumOnMac/logs").path
        }
        return "\(runtimeDir)/logs"
    }

    var wineZPath: String {
        guard !gameDir.isEmpty else { return "" }
        return "Z:" + gameDir.replacingOccurrences(of: "/", with: "\\")
    }

    init() {
        detectGameFolder()
    }

    private func classifyGameFolder(_ path: String) -> String? {
        let fm = FileManager.default
        let bo2Markers = ["t6mp.exe", "t6zm.exe", "games/t6mp.exe", "games/t6zm.exe", "t6r"]
        if bo2Markers.contains(where: { fm.fileExists(atPath: "\(path)/\($0)") }) {
            return "BO2"
        }
        let bo1Markers = ["BlackOps.exe", "BlackOpsMP.exe"]
        if bo1Markers.contains(where: { fm.fileExists(atPath: "\(path)/\($0)") }) {
            return "BO1"
        }
        if fm.fileExists(atPath: "\(path)/iw5mp.exe") || fm.fileExists(atPath: "\(path)/games/iw5mp.exe") {
            return "MW3"
        }
        if fm.fileExists(atPath: "\(path)/CoDWaW.exe") || fm.fileExists(atPath: "\(path)/CoDWaWmp.exe") {
            return "WaW"
        }
        return nil
    }

    func detectGameFolder() {
        let bundleParent = Bundle.main.bundleURL.deletingLastPathComponent().path
        if let kind = classifyGameFolder(bundleParent) {
            gameDir = bundleParent
            detectedGameLabel = "\(kind) DETECTED IN APP FOLDER"
            UserDefaults.standard.set(bundleParent, forKey: gameDirKey)
            return
        }
        if let saved = UserDefaults.standard.string(forKey: gameDirKey),
           FileManager.default.fileExists(atPath: saved),
           let kind = classifyGameFolder(saved) {
            gameDir = saved
            detectedGameLabel = "\(kind) // \(URL(fileURLWithPath: saved).lastPathComponent)"
            return
        }
        let downloadsBO2 = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/Black Ops 2").path
        if let kind = classifyGameFolder(downloadsBO2) {
            gameDir = downloadsBO2
            detectedGameLabel = "\(kind) // Downloads/Black Ops 2"
            return
        }
        gameDir = ""
        detectedGameLabel = "DROP APP IN GAME FOLDER OR BROWSE"
    }

    func browseGameFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select your Call of Duty game folder (BO1, BO2, WaW, or MW3)"
        if panel.runModal() == .OK, let url = panel.url {
            gameDir = url.path
            UserDefaults.standard.set(url.path, forKey: gameDirKey)
            if let kind = classifyGameFolder(url.path) {
                detectedGameLabel = "\(kind) // \(url.lastPathComponent)"
            } else {
                detectedGameLabel = "CUSTOM // \(url.lastPathComponent)"
            }
            statusLine = "GAME FOLDER SET: \(url.lastPathComponent)"
        }
    }

    func copyWinePath() {
        guard !wineZPath.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(wineZPath, forType: .string)
        statusLine = "COPIED: \(wineZPath)"
    }

    private func clearBrokenWineTemp() {
        let tmp = NSTemporaryDirectory()
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: tmp) else { return }
        for item in items where item.hasPrefix("winetemp-") {
            let dir = (tmp as NSString).appendingPathComponent(item)
            let ntdll = (dir as NSString).appendingPathComponent("ntdll.so")
            if let target = try? fm.destinationOfSymbolicLink(atPath: ntdll),
               !fm.fileExists(atPath: target) {
                try? fm.removeItem(atPath: dir)
            }
        }
    }

    func launch() {
        guard !isRunning else { return }
        isRunning = true
        clearBrokenWineTemp()

        try? FileManager.default.createDirectory(
            atPath: (prefixDir as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(atPath: logsDir, withIntermediateDirectories: true)

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
        env["WINEPREFIX"] = prefixDir
        env["AIO_LOGS"] = logsDir
        env["NTDLL"] = useLegacyNtdll ? "legacy" : "fixed"
        env["HUD"] = metalHud ? "1" : "0"
        env["X87"] = x87Accel ? "1" : "0"
        env["MOUSE_COALESCING"] = smoothMouse ? "1" : "0"
        if fpsCap != .uncapped {
            env["MAXFPS"] = fpsCap.rawValue
        } else {
            env.removeValue(forKey: "MAXFPS")
        }
        switch displayMode {
        case .auto:
            env.removeValue(forKey: "WINDOWED")
            env.removeValue(forKey: "FULLSCREEN")
        case .windowed:
            env["WINDOWED"] = "1"
            env.removeValue(forKey: "FULLSCREEN")
        case .fullscreen:
            env["FULLSCREEN"] = "1"
            env.removeValue(forKey: "WINDOWED")
        }
        if !gameDir.isEmpty {
            let kind = classifyGameFolder(gameDir)
            if kind == "BO1" { env["BO1_DIR"] = gameDir }
            else { env["BO2_DIR"] = gameDir }
        }

        let needsSetup = !FileManager.default.fileExists(atPath: "\(prefixDir)/system.reg")
            || !FileManager.default.fileExists(atPath: "\(prefixDir)/drive_c/users/crossover/AppData/Local/Plutonium/bin/plutonium-launcher-win32.exe")

        let script = needsSetup
            ? "./setup.sh && ./launch.sh"
            : "./launch.sh"

        statusLine = needsSetup ? "FIRST-TIME SETUP + LOGIN..." : "STARTING PLUTONIUM..."

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = ["-c", script]
        proc.currentDirectoryURL = URL(fileURLWithPath: runtimeDir)
        proc.environment = env
        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        proc.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self else { return }
                self.isRunning = false
                self.activeProcess = nil
                if process.terminationStatus == 0 {
                    self.statusLine = "SESSION ENDED CLEANLY (EXIT 0)"
                } else {
                    self.statusLine = "EXITED WITH CODE \(process.terminationStatus) (CHECK LOG)"
                }
            }
        }

        do {
            try proc.run()
            activeProcess = proc
            if !needsSetup {
                let fpsLabel = fpsCap != .uncapped ? " • \(fpsCap.rawValue)FPS" : ""
                statusLine = "RUNNING // \(useLegacyNtdll ? "NTDLL=legacy" : "NTDLL=fixed")\(fpsLabel)\(metalHud ? " • HUD" : "")"
            }
        } catch {
            isRunning = false
            statusLine = "FAILED TO START: \(error.localizedDescription)"
        }
    }

    func killPrefix() {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = ["./launch.sh", "kill"]
        proc.currentDirectoryURL = URL(fileURLWithPath: runtimeDir)
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
        env["WINEPREFIX"] = prefixDir
        env["AIO_LOGS"] = logsDir
        proc.environment = env
        try? proc.run()
        proc.waitUntilExit()
        isRunning = false
        activeProcess = nil
        statusLine = "PREFIX STOPPED"
    }

    func openLog() {
        let logURL = URL(fileURLWithPath: logsDir).appendingPathComponent("last-run.log")
        if FileManager.default.fileExists(atPath: logURL.path) {
            NSWorkspace.shared.open(logURL)
        } else {
            statusLine = "NO LOG FILE YET"
        }
    }
}

struct TacticalSegmentedPicker<T: Hashable & Identifiable & RawRepresentable>: View where T.RawValue == String {
    let options: [T]
    @Binding var selection: T

    private let accent = Color(red: 0.95, green: 0.42, blue: 0.11)
    private let border = Color(red: 0.16, green: 0.19, blue: 0.25)

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let selected = selection == option
                Button {
                    selection = option
                } label: {
                    Text(option.rawValue)
                        .font(.system(size: 10.5, weight: selected ? .bold : .medium, design: .monospaced))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(selected ? accent : Color.black.opacity(0.35))
                        .foregroundColor(selected ? .black : Color(white: 0.78))
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.black.opacity(0.45))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(border, lineWidth: 1))
        .frame(width: 272)
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct TacticalToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(white: 0.92))
                Text(subtitle)
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundColor(Color(white: 0.55))
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(Color(red: 0.95, green: 0.42, blue: 0.11))
        }
    }
}

struct ContentView: View {
    @StateObject private var vm = LauncherViewModel()

    private let bg = Color(red: 0.04, green: 0.05, blue: 0.07)
    private let card = Color(red: 0.08, green: 0.10, blue: 0.13)
    private let border = Color(red: 0.16, green: 0.19, blue: 0.25)
    private let accent = Color(red: 0.95, green: 0.42, blue: 0.11)

    var body: some View {
        VStack(spacing: 13) {
            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(accent)
                            .frame(width: 4, height: 20)
                        Text("PLUTONIUM")
                            .font(.system(size: 20, weight: .heavy, design: .monospaced))
                            .tracking(2.5)
                            .foregroundColor(.white)
                    }
                    Text("APPLE SILICON // DXMT + DXVK + X87")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(1.2)
                        .foregroundColor(Color(white: 0.55))
                        .padding(.leading, 12)
                }
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(vm.isRunning ? Color.green : accent)
                        .frame(width: 7, height: 7)
                    Text(vm.isRunning ? "ACTIVE" : "READY")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(vm.isRunning ? .green : accent)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(card)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(border, lineWidth: 1))
            }

            // Game Folder Card
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(vm.detectedGameLabel)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(vm.gameDir.isEmpty ? Color(white: 0.6) : accent)
                        .lineLimit(1)
                    Spacer()
                    Button("BROWSE", action: vm.browseGameFolder)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.4))
                        .foregroundColor(.white)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(border, lineWidth: 1))
                }
                if !vm.wineZPath.isEmpty {
                    HStack {
                        Text(vm.wineZPath)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color(white: 0.6))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("COPY Z:\\", action: vm.copyWinePath)
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .buttonStyle(.plain)
                            .foregroundColor(accent)
                    }
                }
            }
            .padding(11)
            .background(card)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(border, lineWidth: 1))

            // Options Panel
            VStack(spacing: 11) {
                TacticalToggleRow(
                    title: "LEGACY NTDLL",
                    subtitle: "Fixes Loading fastfile hang (recommended)",
                    isOn: $vm.useLegacyNtdll
                )
                Divider().background(border)
                TacticalToggleRow(
                    title: "X87 ACCELERATION",
                    subtitle: "Rosetta 2 x87 sidecar for physics & FPS",
                    isOn: $vm.x87Accel
                )
                Divider().background(border)
                TacticalToggleRow(
                    title: "METAL HUD",
                    subtitle: "Show Apple FPS & frame time overlay",
                    isOn: $vm.metalHud
                )
                Divider().background(border)
                TacticalToggleRow(
                    title: "SMOOTH MOUSE",
                    subtitle: "Coalesce mouse events to reduce jitter (recommended)",
                    isOn: $vm.smoothMouse
                )
                Divider().background(border)

                HStack {
                    Text("FPS CAP")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(white: 0.92))
                    Spacer()
                    TacticalSegmentedPicker(options: Array(FpsCap.allCases), selection: $vm.fpsCap)
                }

                HStack {
                    Text("DISPLAY")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(white: 0.92))
                    Spacer()
                    TacticalSegmentedPicker(options: Array(DisplayMode.allCases), selection: $vm.displayMode)
                }
            }
            .padding(14)
            .background(card)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(border, lineWidth: 1))
            .cornerRadius(6)

            // Launch Button
            Button(action: vm.launch) {
                HStack(spacing: 8) {
                    Image(systemName: vm.isRunning ? "bolt.horizontal.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text(vm.isRunning ? "PLUTONIUM RUNNING..." : "LAUNCH PLUTONIUM")
                        .font(.system(size: 14, weight: .heavy, design: .monospaced))
                        .tracking(1.8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(vm.isRunning ? accent.opacity(0.45) : accent)
                .foregroundColor(.black)
                .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .disabled(vm.isRunning)

            // Utility Row + Status
            HStack(spacing: 10) {
                Button(action: vm.killPrefix) {
                    Label("KILL PREFIX", systemImage: "xmark.octagon")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(card)
                        .foregroundColor(Color(white: 0.85))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(border, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button(action: vm.openLog) {
                    Label("OPEN LOG", systemImage: "doc.text")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(card)
                        .foregroundColor(Color(white: 0.85))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            HStack {
                Text("> \(vm.statusLine)")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(white: 0.65))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.45))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(border, lineWidth: 1))
        }
        .padding(18)
        .frame(width: 430)
        .background(bg)
        .preferredColorScheme(.dark)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct PlutoniumLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
