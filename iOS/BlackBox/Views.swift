import SwiftUI
import WebKit
import UIKit
import BlackBoxCore

struct RootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var rdc: RDCSession
    @ObservedObject var audio: AudioController
    var body: some View {
        TabView {
            ConversationView(m: model, rdc: rdc, audio: audio).tabItem { Label("Conversation", systemImage: "bubble.left.and.bubble.right") }
            ComputerView(m: model, rdc: rdc).tabItem { Label("Computer", systemImage: "desktopcomputer") }
            ActivityView(m: model).tabItem { Label("Activity", systemImage: "waveform.path") }
            SettingsView(m: model, rdc: rdc, audio: audio).tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
        .alert("Black_Box", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .sheet(isPresented: Binding(get: { model.reviewTool != nil }, set: { if !$0 { model.confirmReview(false) } })) {
            NavigationStack {
                Form {
                    Section("Review action") {
                        Text(model.reviewTool?.name.replacingOccurrences(of: "_", with: " ") ?? "")
                        Text(model.reviewTool?.arguments.text() ?? "").font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        Text("Computer: \(model.reviewTool?.deviceID ?? "none")").font(.caption)
                    }
                    Button("Approve this action") { model.confirmReview(true) }.disabled(!model.busy)
                    Button("Decline", role: .cancel) { model.confirmReview(false) }
                }.navigationTitle("Review")
            }.presentationDetents([.medium, .large])
        }
    }
}

struct ConversationView: View {
    @ObservedObject var m: AppModel
    @ObservedObject var rdc: RDCSession
    @ObservedObject var audio: AudioController
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "cube.transparent.fill").font(.title2).foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("BLACK_BOX").font(.system(.caption, design: .monospaced).weight(.semibold)).tracking(3)
                        Text(m.busy ? "Working" : audio.speaking ? "Speaking" : audio.listening ? "Listening" : "Ready for a request").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Circle().fill(m.selected?.online == true ? Color.green : Color.gray).frame(width: 7, height: 7)
                    Text(m.selected?.online == true ? "PC online" : "PC unavailable").font(.caption2).foregroundStyle(.secondary)
                }.padding().background(Color.blue.opacity(0.055))
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            if m.messages.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("What needs doing?").font(.title2.weight(.medium))
                                    Text("Conversation and public research work independently of your computer. Connect your providers in Settings to begin.").foregroundStyle(.secondary)
                                }.padding(.vertical, 50)
                            }
                            ForEach(m.messages) { message in
                                MessageView(message: message)
                            }
                            if m.busy {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label("Working", systemImage: "circle.dotted").font(.caption).foregroundStyle(.blue)
                                    Text(m.streamingText.isEmpty ? "Thinking…" : m.streamingText).foregroundStyle(.secondary)
                                }.id("streaming")
                            }
                            Color.clear.frame(height: 1).id("end")
                        }.padding()
                    }.onChange(of: m.messages.count) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
                }
                VStack(spacing: 10) {
                    if !audio.caption.isEmpty { Text(audio.caption).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                    HStack(spacing: 14) {
                        Button { audio.stopSpeech() } label: { Image(systemName: "stop.circle").font(.title3).frame(width: 44, height: 44) }.accessibilityLabel("Stop speech")
                        Button { if let last = m.messages.last(where: { $0.role == "model" }) { m.perform { try m.speak(last.text) } } } label: { Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44) }.accessibilityLabel("Replay last answer")
                        Button { m.settings.mute.toggle(); if m.settings.mute { audio.stopSpeech() }; m.perform { try m.saveSettings() } } label: { Image(systemName: m.settings.mute ? "speaker.slash" : "speaker.wave.2").frame(width: 44, height: 44) }.accessibilityLabel(m.settings.mute ? "Unmute replies" : "Mute replies")
                        Spacer()
                        if m.busy { Button("Cancel task", role: .destructive) { m.cancelTask() }.font(.callout) }
                    }
                    HStack(alignment: .bottom, spacing: 10) {
                        TextField("Ask Black_Box", text: $m.draft, axis: .vertical).lineLimit(1...5).padding(12).background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16)).disabled(m.busy)
                        Button {
                            if audio.listening { audio.end() } else { m.perform { try await audio.begin() } }
                        } label: { Image(systemName: audio.listening ? "stop.fill" : "mic.fill").frame(width: 44, height: 44).background(audio.listening ? Color.red.opacity(0.3) : Color.blue.opacity(0.15), in: Circle()) }
                        .disabled(m.busy).accessibilityLabel(audio.listening ? "Finish speaking" : "Start push to talk")
                        Button { m.send() } label: { Image(systemName: "arrow.up").fontWeight(.bold).frame(width: 44, height: 44).background(.blue, in: Circle()).foregroundStyle(.white) }.disabled(m.busy || m.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("Send")
                    }
                }.padding().background(.ultraThinMaterial)
            }.navigationBarHidden(true)
        }
    }
}
struct MessageView: View {
    let message: ChatMessage
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message.role == "user" ? "YOU" : "BLACK_BOX").font(.system(.caption2, design: .monospaced).weight(.semibold)).foregroundStyle(message.role == "user" ? Color.secondary : Color.blue)
            Text(.init(message.text)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            if !message.sources.isEmpty {
                ForEach(Array(message.sources.enumerated()), id: \.element.id) { index, source in
                    if let url = URL(string: source.url), GeminiClient.safeWebURL(source.url) {
                        Link(destination: url) { Label("\(index + 1). \(source.title)", systemImage: "link").font(.caption).lineLimit(2).padding(.vertical, 5) }
                    }
                }
            }
            ForEach(Array(message.attributionHTML.enumerated()), id: \.offset) { _, html in
                SearchAttribution(html: html).frame(height: 200).accessibilityLabel("Google Search attribution and suggestions")
            }
        }.padding(16).background(message.role == "user" ? Color.white.opacity(0.065) : Color.blue.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
    }
}

struct ComputerView: View {
    @ObservedObject var m: AppModel
    @ObservedObject var rdc: RDCSession
    @State private var aliasName = ""
    @State private var aliasPath = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Remote Desktop Commander") {
                    Label(rdc.status, systemImage: "network")
                    Text("PC access needs an awake computer and a running paired RDC agent. Public research and chat remain independent.").font(.caption).foregroundStyle(.secondary)
                    Button("Refresh paired devices") { m.perform { try await rdc.refreshDevices() } }.disabled(m.busy)
                    ForEach(rdc.devices) { d in
                        Button { m.perform { try m.select(d.id) } } label: {
                            HStack { Image(systemName: "desktopcomputer"); VStack(alignment: .leading) { Text(d.name); Text(d.online ? "Online" : "Offline").font(.caption).foregroundStyle(.secondary) }; Spacer(); if m.settings.selectedDeviceID == d.id { Image(systemName: "checkmark.circle.fill") } }
                        }.disabled(m.busy)
                    }
                    if rdc.devices.isEmpty { Text("No device selection has been verified.").foregroundStyle(.secondary) }
                }
                Section("Common actions") {
                    Button("Open YouTube") { m.draft = "Open https://www.youtube.com on my selected desktop. Report only what is observed."; m.send() }
                    Button("What's using my RAM?") { m.draft = "Measure current RAM use on my selected desktop. Include measurement time, units and top processes."; m.send() }
                    Button("Pause media") { m.draft = "Send the pause media command on my selected desktop."; m.send() }
                    Text(m.helperStatus).font(.caption).foregroundStyle(.secondary)
                }.disabled(m.busy || !m.helperVerified)
                Section("Named folders for selected PC") {
                    ForEach(m.aliases.filter { $0.deviceID == m.settings.selectedDeviceID }) { alias in
                        VStack(alignment: .leading) { Text(alias.name); Text(alias.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                    }.onDelete { indices in
                        let list = m.aliases.filter { $0.deviceID == m.settings.selectedDeviceID }
                        m.perform { for i in indices { try m.deleteAlias(list[i].id) } }
                    }
                    TextField("Name: projects, school, downloads", text: $aliasName).textInputAutocapitalization(.never)
                    TextField("Absolute Windows path", text: $aliasPath).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Save folder") { m.perform { try m.saveAlias(name: aliasName, path: aliasPath); aliasName = ""; aliasPath = "" } }.disabled(m.busy)
                }
            }.navigationTitle("Computer")
        }
    }
}
struct ActivityView: View {
    @ObservedObject var m: AppModel
    var body: some View {
        NavigationStack {
            List {
                if m.tasks.isEmpty { Text("Tasks and observed results will appear here.").foregroundStyle(.secondary) }
                ForEach(m.tasks) { task in
                    NavigationLink {
                        List {
                            Section("Task") {
                                Text(task.input); Text(task.state.rawValue).foregroundStyle(.blue); Text(task.detail).font(.callout)
                                Text(task.date.formatted()).font(.caption)
                                Text("Device: \(task.deviceID ?? "none")").font(.caption).textSelection(.enabled)
                                Text("Reported tokens: \(task.tokens)").font(.caption)
                            }
                            Section("Observed actions") {
                                ForEach(m.actions.filter { $0.taskID == task.id }) { action in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(action.name).font(.headline); Text(action.state.rawValue).foregroundStyle(.secondary)
                                        Text(action.date.formatted()).font(.caption)
                                        Text(action.arguments.text()).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                        if let result = action.result { Text(String(result.text().prefix(16000))).font(.caption).textSelection(.enabled) }
                                        if action.state == .unknown { Button("Retrieve existing remote call") { m.perform { try await m.reconcile(action) } }.disabled(action.remoteCallID == nil || m.busy) }
                                    }.padding(.vertical, 6)
                                }
                            }
                            if [.failed, .blocked, .cancelled].contains(task.state), !m.actions.contains(where: { $0.taskID == task.id && $0.state == .unknown }) {
                                Button("Retry as a new request") { m.draft = task.input; m.send() }.disabled(m.busy)
                            }
                            if task.state == .unknown || m.actions.contains(where: { $0.taskID == task.id && $0.state == .unknown }) { Text("Outcome uncertain. Inspect the computer or retrieve the existing call before issuing a fresh request. Nothing is replayed automatically.").foregroundStyle(.orange) }
                        }.navigationTitle("Task details")
                    } label: {
                        VStack(alignment: .leading, spacing: 5) { Text(task.input).lineLimit(2); Text(task.state.rawValue + " · " + task.date.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }.navigationTitle("Activity")
        }
    }
}
struct SettingsView: View {
    @ObservedObject var m: AppModel
    @ObservedObject var rdc: RDCSession
    @ObservedObject var audio: AudioController
    @State private var geminiKey = ""
    @State private var voiceKey = ""
    @State private var publicClientID = ""
    @State private var newMemory = ""
    @State private var editingMemory: Memory?
    var body: some View {
        NavigationStack {
            Form {
                Section("Gemini") {
                    Text(m.hasGeminiKey ? "API key ••••••••" : "No API key stored").font(.caption).foregroundStyle(.secondary)
                    SecureField("Enter replacement API key", text: $geminiKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Save and check key") { m.perform { try m.saveKey(geminiKey, provider: "gemini"); geminiKey = "" } }
                        .disabled(geminiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    TextField("Model ID", text: $m.settings.model).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onChange(of: m.settings.model) { _, value in m.geminiModelChanged(value) }
                    if m.geminiState.isChecking {
                        ProgressView("Checking Gemini…")
                        Button("Cancel connection check", role: .cancel) { m.cancelGeminiValidation() }
                    } else {
                        Button("Check connection") { m.validateGemini() }.disabled(!m.hasGeminiKey)
                    }
                    Text(m.geminiState.message).font(.callout)
                        .foregroundStyle(m.geminiState.phase == .failed ? Color.orange : Color.secondary)
                        .textSelection(.enabled).accessibilityIdentifier("gemini.connection.status")
                    if !m.geminiState.models.isEmpty {
                        Picker("Google models", selection: $m.settings.model) {
                            if !m.geminiState.models.contains(m.settings.model) { Text("Choose a model").tag(m.settings.model) }
                            ForEach(m.geminiState.models, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    Button("Delete Gemini key", role: .destructive) { m.perform { try m.deleteKey("gemini") } }
                }
                Section("ElevenLabs voice") {
                    Text(m.hasVoiceKey ? "API key ••••••••" : "No API key stored").font(.caption).foregroundStyle(.secondary)
                    SecureField("Enter replacement API key", text: $voiceKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Save and check key") { m.perform { try m.saveKey(voiceKey, provider: "elevenlabs"); voiceKey = "" } }
                        .disabled(voiceKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    TextField("Voice ID", text: $m.settings.voiceID).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onChange(of: m.settings.voiceID) { _, value in m.voiceIDChanged(value) }
                        .onSubmit { m.validateVoice() }
                    TextField("Speech model ID", text: $m.settings.speechModel).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onChange(of: m.settings.speechModel) { _, value in m.speechModelChanged(value) }
                        .onSubmit { m.validateVoice() }
                    if m.voiceState.isChecking {
                        ProgressView("Checking ElevenLabs…")
                        Button("Cancel voice check", role: .cancel) { m.cancelVoiceValidation() }
                    } else {
                        Button("Check voice and model") { m.validateVoice() }.disabled(!m.hasVoiceKey)
                    }
                    Text(m.voiceState.message).font(.callout)
                        .foregroundStyle(m.voiceState.phase == .failed ? Color.orange : Color.secondary)
                        .textSelection(.enabled).accessibilityIdentifier("elevenlabs.connection.status")
                    if !m.voiceState.models.isEmpty {
                        Picker("Speech models", selection: $m.settings.speechModel) {
                            if !m.voiceState.models.contains(where: { $0.id == m.settings.speechModel }) { Text("Choose a model").tag(m.settings.speechModel) }
                            ForEach(m.voiceState.models) { model in Text(model.name + " · " + model.id).tag(model.id) }
                        }
                    }
                    Button("Test voice (uses API quota)") { m.perform { try m.testVoice() } }
                        .disabled(!m.hasVoiceKey || m.settings.voiceID.isEmpty || m.voiceState.isChecking || audio.speaking)
                    if audio.speaking { Button("Stop test speech") { audio.stopSpeech() } }
                    Text(audio.status).font(.caption).textSelection(.enabled)
                    Button("Delete ElevenLabs key", role: .destructive) { m.perform { try m.deleteKey("elevenlabs") } }
                    Text("Use an accessible authorized voice ID from ElevenLabs. Voice creation and verification are separate from app setup.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Independent RDC sign-in") {
                    Text(rdc.diagnostic).font(.caption).foregroundStyle(.secondary)
                    TextField("RDC-issued public client ID (if provided)", text: $publicClientID).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Sign in with PKCE") { m.perform { try await rdc.signIn(publicClientID: publicClientID); m.recordCheck("PASS · independent RDC sign-in and device listing") } }
                    Button("Revoke server grant") { m.perform { try await rdc.revoke() } }
                    Link("Open RDC dashboard", destination: URL(string: "https://mcp.desktopcommander.app")!)
                    Button("Remove local RDC credentials", role: .destructive) { m.perform { try await rdc.removeLocal() } }
                }
                Section("Windows helper") {
                    TextField("Full path to BlackBoxHelper.ps1", text: $m.settings.helperPath).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Check installed helper") { m.perform { try await m.verifyHelper() } }
                    Text(m.helperStatus).font(.caption).foregroundStyle(.secondary)
                }
                Section("Local memory") {
                    ForEach(m.memories) { memory in Button { editingMemory = memory } label: { Text(memory.text).foregroundStyle(.primary).lineLimit(3) } }
                    .onDelete { indices in m.perform { for i in indices { try m.deleteMemory(m.memories[i].id) } } }
                    TextField("New memory", text: $newMemory, axis: .vertical)
                    Button("Add memory") { m.perform { try m.saveMemory(Memory(text: newMemory)); newMemory = "" } }.disabled(newMemory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section("Limits and usage") {
                    Stepper("Steps: \(m.settings.maxSteps)", value: $m.settings.maxSteps, in: 1...16)
                    Stepper("Dispatch window: \(m.settings.maxSeconds)s", value: $m.settings.maxSeconds, in: 30...300, step: 30)
                    Stepper("Reported token budget: \(m.settings.maxTokens)", value: $m.settings.maxTokens, in: 4000...64000, step: 4000)
                    Stepper("Spoken reply cap: \(m.settings.maxSpeechCharacters)", value: $m.settings.maxSpeechCharacters, in: 500...5000, step: 500)
                    Text("Usage is reported tokens across saved tasks, not an invoice: \(m.tasks.reduce(0) { $0 + $1.tokens }). Provider charges and account limits remain authoritative.").font(.caption).foregroundStyle(.secondary)
                    Button("Save configuration") { m.perform { try m.saveSettings() } }
                }
                Section("Native feasibility harness") {
                    Text("\(m.hardwareIdentifier) · \(UIDevice.current.model) · \(ProcessInfo.processInfo.operatingSystemVersionString)").font(.caption)
                    Button("1 · Check RDC discovery") { m.perform { try await rdc.probe(); m.recordCheck("PASS · live RDC discovery. Public registration remains a separate gate.") } }
                    Button("2 · Test Gemini response (uses API quota)") { m.perform { try await m.testGemini() } }
                    Button("3 · Test ElevenLabs playback (uses API quota)") { m.perform { try m.testVoice() } }
                    Text(audio.status).font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(m.checks.enumerated()), id: \.offset) { _, check in Text(check).font(.caption).textSelection(.enabled) }
                }
                Section("Permissions and operation") {
                    Text("Microphone and Apple speech recognition are requested on first use. Recognition may use Apple's servers when on-device support is unavailable. Desktop commands use final transcripts only. Black_Box works in the foreground; suspension stops dispatch and audio.").font(.caption).foregroundStyle(.secondary)
                    Button("Open iPhone settings") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }
                }
            }.navigationTitle("Settings").disabled(m.busy)
                .task { m.checkSavedGeminiKey(); m.checkSavedVoiceKey() }
                .sheet(item: $editingMemory) { memory in MemoryEditor(memory: memory, save: { value in m.perform { try m.saveMemory(value) } }) }
        }
    }
}
struct MemoryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var memory: Memory
    let save: (Memory) -> Void
    var body: some View { NavigationStack { Form { TextEditor(text: $memory.text).frame(minHeight: 180); Button("Save") { save(memory); dismiss() } }.navigationTitle("Edit memory") } }
}

/// Google's required rendered attribution is displayed without JavaScript or native tool bridges.
struct SearchAttribution: UIViewRepresentable {
    let html: String
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration(); config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config); view.navigationDelegate = context.coordinator
        view.isOpaque = false; view.backgroundColor = .clear; return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard context.coordinator.loaded != html else { return }; context.coordinator.loaded = html
        uiView.loadHTMLString(html, baseURL: URL(string: "https://www.google.com"))
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var loaded = ""
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated {
                if let u = navigationAction.request.url, GeminiClient.safeWebURL(u.absoluteString) { UIApplication.shared.open(u) }
                decisionHandler(.cancel)
            } else if navigationAction.request.url?.scheme == "about" { decisionHandler(.allow) }
            else { decisionHandler(.cancel) }
        }
    }
}
