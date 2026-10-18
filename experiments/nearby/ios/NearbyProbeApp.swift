import Foundation

struct ProbeLedger {
    private struct Request: Equatable { let run: UInt32; let sequence: Int }
    private var requests = [Int64: Request]()
    mutating func sent(_ id: Int64, run: UInt32, sequence: Int) { requests[id] = Request(run: run, sequence: sequence) }
    mutating func settled(_ id: Int64) { requests.removeValue(forKey: id) }
    mutating func acknowledged(run: UInt32, sequence: Int) {
        requests = requests.filter { $0.value != Request(run: run, sequence: sequence) }
    }
    mutating func failed(_ id: Int64, run: UInt32, sequence: Int) -> Bool {
        requests.removeValue(forKey: id) == Request(run: run, sequence: sequence)
    }
    mutating func clear() { requests.removeAll() }
}

#if !PROBE_REGRESSION
import SwiftUI
import NearbyConnections
import NearbyCoreAdapter
import CoreLocation
import UIKit

@main
struct NearbyProbeApp: App {
    @StateObject private var model = ProbeModel()
    var body: some Scene {
        WindowGroup {
            NavigationView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("独立 Nearby 原型；不加入正式融合房。双方需核对配对码。")
                        Text("原型 0.1.2")
                        Text(model.status).textSelection(.enabled)
                        Toggle("BLE 基线模式：仅测试蓝牙，不升级 Wi-Fi", isOn: Binding(
                            get: { model.bleBaseline },
                            set: { model.bleBaseline = $0; if $0 { model.allowHotspot = false } }
                        )).disabled(model.active)
                        if model.hotspotBuild {
                            Toggle("允许为高速连接切换 Wi-Fi", isOn: $model.allowHotspot)
                                .disabled(model.active || model.bleBaseline)
                        } else {
                            Text("此构建测试蓝牙、同网 Wi-Fi 与苹果点对点；热点升级需另用匹配的签名能力构建。")
                                .font(.footnote)
                        }
                        Button("发布此设备", action: model.advertise)
                        Button("发现附近设备", action: model.discover)
                        ForEach(model.found.keys.sorted(), id: \.self) { id in
                            Button(model.found[id] ?? "附近设备") { model.connect(id) }
                        }
                        Button("测试 32 KiB 双向完整性与往返速率", action: model.probe)
                            .disabled(model.remote == nil || model.testing)
                        Button("停止并断开", role: .destructive, action: model.stop)
                        Button("复制诊断") { UIPasteboard.general.string = "Nearby Probe 0.1.2\n" + model.diagnostics }
                        Text(model.diagnostics).font(.footnote).textSelection(.enabled)
                    }.padding()
                }.navigationTitle("Nearby Probe")
            }
            .alert(item: $model.challenge) { item in
                Alert(title: Text("核对双方配对码"),
                      message: Text("\(item.code)\n仅当另一台设备显示相同代码时确认。"),
                      primaryButton: .default(Text("一致，连接")) { model.verify(true) },
                      secondaryButton: .cancel(Text("拒绝")) { model.verify(false) })
            }
        }
    }
}

final class ProbeModel: NSObject, ObservableObject, ConnectionManagerDelegate, AdvertiserDelegate, DiscovererDelegate, CLLocationManagerDelegate {
    struct Challenge: Identifiable { let id: String; let code: String }
    static let service = "dev.dawnmesh.nearby.probe.v1"
    @Published var status = "等待操作"
    @Published var found = [String: String]()
    @Published var challenge: Challenge?
    @Published var remote: String?
    @Published var testing = false
    @Published var allowHotspot = false
    @Published var bleBaseline = true
    @Published var diagnostics = ""
    #if DAWNMESH_NEARBY_HOTSPOT
    let hotspotBuild = true
    #else
    let hotspotBuild = false
    #endif
    private let manager = ConnectionManager(serviceID: service, strategy: .pointToPoint)
    private lazy var advertiser = Advertiser(connectionManager: manager)
    private lazy var discoverer = Discoverer(connectionManager: manager)
    private let location = CLLocationManager()
    private var permissionAction: (() -> Void)?
    private var verification: ((Bool) -> Void)?
    @Published private(set) var active = false
    private var pending = Set<String>()
    private var epoch: UInt64 = 0
    private var ledger = ProbeLedger()
    private var notes = [String]()
    private var teardown = DispatchGroup()
    private var resetFailure: Error?
    private var sessionMediums: Set<Medium> = [.ble]
    private let appStarted = ProcessInfo.processInfo.systemUptime
    private var connectedAt: TimeInterval = 0
    private var lastDataAt: TimeInterval = 0
    private var chunk = -1
    private var token: UInt32 = 0
    private var started = Date()
    private var sentAt = Date()
    private var maxRTT: Double = 0
    private var watchdog: DispatchWorkItem?

    override init() {
        super.init()
        manager.delegate = self; advertiser.delegate = self; discoverer.delegate = self
        location.delegate = self
    }
    private func note(_ message: String, severity: String = "信息") {
        let age = Int(ProcessInfo.processInfo.systemUptime - appStarted)
        notes.append("[\(severity)] +\(age)s " + String(message.prefix(220)))
        if notes.count > 60 { notes.removeFirst() }
        diagnostics = notes.joined(separator: "\n")
    }
    private func failure(_ operation: String, _ error: Error) {
        let value = error as NSError
        let description = "\(operation)：\(value.domain) / \(value.code)"
        status = description; note(description, severity: "错误")
    }
    private var mediums: Set<Medium> {
        if bleBaseline { return [.ble] }
        var values: Set<Medium> = [.ble, .wifiLAN, .awdl]
        if hotspotBuild && allowHotspot { values.insert(.wifiHotspot) }
        return values
    }
    private func permitted(_ action: @escaping () -> Void) {
        if bleBaseline || !hotspotBuild || !allowHotspot { action(); return }
        switch location.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: action()
        case .notDetermined: permissionAction = action; location.requestWhenInUseAuthorization()
        default: status = "热点升级需要位置授权；也可关闭热点选项测试其他路径。"
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let action = permissionAction, manager.authorizationStatus != .notDetermined else { return }
        permissionAction = nil
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways { action() }
        else { status = "位置授权未授予；热点升级未启动。" }
    }
    func advertise() { permitted { [weak self] in self?.restart(advertise: true) } }
    func discover() { permitted { [weak self] in self?.restart(advertise: false) } }
    private func restart(advertise: Bool) {
        stop(); let run = epoch
        sessionMediums = mediums
        note("开始\(advertise ? "发布" : "发现")；BLE基线=\(bleBaseline)")
        status = "正在等待上一会话清理完成…"
        teardown.notify(queue: .main) { [weak self] in
            guard let self = self, self.epoch == run else { return }
            if let error = self.resetFailure { self.failure("清理上一会话", error); return }
            self.active = true
            let completion: (Error?) -> Void = { [weak self] error in
                DispatchQueue.main.async {
                    guard let self = self, self.active, self.epoch == run else { return }
                    if let error = error { self.failure(advertise ? "发布" : "发现", error) }
                    else { self.status = advertise ? "正在发布；等待另一台设备选择" : "正在发现；请选择设备" }
                }
            }
            if advertise { self.advertiser.startAdvertising(using: Data("iOS Probe".utf8), mediums: self.sessionMediums, completionHandler: completion) }
            else { self.discoverer.startDiscovery(mediums: self.sessionMediums, completionHandler: completion) }
        }
    }
    func connect(_ endpoint: String) {
        guard active, remote == nil, pending.isEmpty else { return }
        pending.insert(endpoint)
        let run = epoch
        discoverer.requestConnection(to: endpoint, using: Data("iOS Probe".utf8), mediums: sessionMediums) { [weak self] error in
            guard let self = self, self.active, self.epoch == run else { return }
            if let error = error, self.pending.remove(endpoint) != nil { self.failure("连接", error) }
        }
    }
    func advertiser(_ advertiser: Advertiser, didReceiveConnectionRequestFrom endpointID: EndpointID,
                    with context: Data, connectionRequestHandler: @escaping (Bool) -> Void) {
        let accepted = active && remote == nil && verification == nil && pending.isEmpty
        if accepted { pending.insert(endpointID) }
        connectionRequestHandler(accepted)
    }
    func discoverer(_ discoverer: Discoverer, didFind endpointID: EndpointID, with context: Data) {
        guard active, found.count < 32, context.count <= 131 else { return }
        found[endpointID] = String((String(data: context, encoding: .utf8) ?? "附近设备").prefix(48))
    }
    func discoverer(_ discoverer: Discoverer, didLose endpointID: EndpointID) { if active { found.removeValue(forKey: endpointID) } }
    func connectionManager(_ connectionManager: ConnectionManager, didReceive verificationCode: String,
                           from endpointID: EndpointID, verificationHandler: @escaping (Bool) -> Void) {
        guard active, pending.contains(endpointID), verification == nil && remote == nil else { verificationHandler(false); return }
        verification = verificationHandler; challenge = Challenge(id: endpointID, code: verificationCode)
    }
    func verify(_ accepted: Bool) { let action = verification; verification = nil; challenge = nil; action?(accepted) }
    func connectionManager(_ connectionManager: ConnectionManager, didChangeTo state: ConnectionState, for endpointID: EndpointID) {
        guard active else { return }
        switch state {
        case .connected:
            if remote == endpointID { return }
            guard active, pending.remove(endpointID) != nil else { manager.disconnect(from: endpointID); return }
            remote = endpointID; connectedAt = ProcessInfo.processInfo.systemUptime; lastDataAt = connectedAt
            discoverer.stopDiscovery()
            // stopAdvertising also removes the SDK's BLE listening service.
            // Keep that service alive until full session teardown instead.
            status = "已配对；可测试稳定性。"; note("已连接；停止发现，保留发布服务")
        case .disconnected, .rejected:
            let wasPending = pending.remove(endpointID) != nil
            if challenge?.id == endpointID { verify(false) }
            if remote == endpointID || wasPending {
                let now = ProcessInfo.processInfo.systemUptime
                let age = remote == endpointID ? Int((now - connectedAt) * 1000) : 0
                let idle = remote == endpointID ? Int((now - lastDataAt) * 1000) : 0
                note("SDK连接断开或拒绝；连接\(age)ms；数据空闲\(idle)ms；未提供具体原因", severity: "事件")
                stop(); status = "SDK 报告连接断开或拒绝，未提供具体原因；请重新发布或发现"
            }
        case .connecting: if active && pending.contains(endpointID) { status = "正在连接，等待双方确认" }
        }
    }
    func probe() {
        guard remote != nil, !testing else { return }
        ledger.clear()
        token = UInt32.random(in: 0...UInt32.max); chunk = 0
        testing = true; started = Date(); maxRTT = 0; next()
    }
    private func next() {
        guard let endpoint = remote, chunk >= 0 else { return }
        var bytes: [UInt8] = [68, 77, 80, 49, 1, UInt8(chunk >> 8), UInt8(chunk & 255)]
        bytes += [UInt8((token >> 24) & 255), UInt8((token >> 16) & 255), UInt8((token >> 8) & 255), UInt8(token & 255)]
        bytes += (0..<1024).map { UInt8(($0 + chunk) % 251) }
        sentAt = Date()
        let expected = token; let sequence = chunk; let run = epoch
        let timer = DispatchWorkItem { [weak self] in
            guard let self = self, self.active, self.epoch == run, self.token == expected, self.chunk == sequence else { return }
            self.cancelProbe(); self.status = "等待回包超时"
        }
        watchdog = timer; DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timer)
        let payloadID = Int64.random(in: Int64.min...Int64.max)
        ledger.sent(payloadID, run: expected, sequence: sequence)
        _ = manager.send(Data(bytes), to: [endpoint], id: payloadID) { [weak self] error in
            guard let self = self, self.active, self.epoch == run else { return }
            if let error = error, self.testing, self.ledger.failed(payloadID, run: self.token, sequence: self.chunk) {
                self.cancelProbe(); self.failure("发送", error)
            }
        }
    }
    func connectionManager(_ connectionManager: ConnectionManager, didReceive data: Data, withID payloadID: PayloadID, from endpointID: EndpointID) {
        guard active, endpointID == remote, data.count == 1035 else { return }
        var bytes = [UInt8](data)
        guard Array(bytes[0..<4]) == [68, 77, 80, 49] else { return }
        lastDataAt = ProcessInfo.processInfo.systemUptime
        let index = Int(bytes[5]) * 256 + Int(bytes[6])
        guard (0..<32).contains(index) else { return }
        if bytes[4] == 1 {
            bytes[4] = 2; let run = epoch
            _ = manager.send(Data(bytes), to: [endpointID]) { [weak self] error in
                guard let self = self, self.active, self.epoch == run, let error = error else { return }
                let value = error as NSError; self.note("Echo send: \(value.domain) / \(value.code)")
            }
            return
        }
        let receivedToken = bytes[7..<11].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard testing, bytes[4] == 2, index == chunk, receivedToken == token else { return }
        guard (11..<bytes.count).allSatisfy({ bytes[$0] == UInt8(($0 - 11 + chunk) % 251) }) else {
            cancelProbe(); status = "数据完整性校验失败"; return
        }
        ledger.acknowledged(run: token, sequence: chunk)
        maxRTT = max(maxRTT, Date().timeIntervalSince(sentAt) * 1000)
        watchdog?.cancel(); watchdog = nil; chunk += 1
        if chunk == 32 {
            let elapsed = max(0.001, Date().timeIntervalSince(started))
            status = String(format: "32 KiB 双向完整性通过；%.0f ms；最大 RTT %.0f ms；往返有效速率 %.1f KiB/s。此数值不证明使用了 Wi-Fi。", elapsed * 1000, maxRTT, 64 / elapsed)
            note(String(format: "Probe passed: %.0f ms; max RTT %.0f ms", elapsed * 1000, maxRTT))
            cancelProbe()
        } else { next() }
    }
    private func cancelProbe() { watchdog?.cancel(); watchdog = nil; chunk = -1; testing = false; ledger.clear() }
    func connectionManager(_ connectionManager: ConnectionManager, didReceive stream: InputStream,
                           withID payloadID: PayloadID, from endpointID: EndpointID, cancellationToken token: CancellationToken) {
        token.cancel(); stream.close()
    }
    func connectionManager(_ connectionManager: ConnectionManager, didStartReceivingResourceWithID payloadID: PayloadID,
                           from endpointID: EndpointID, at localURL: URL, withName name: String, cancellationToken token: CancellationToken) {
        token.cancel()
    }
    func connectionManager(_ connectionManager: ConnectionManager, didReceiveTransferUpdate update: TransferUpdate,
                           from endpointID: EndpointID, forPayload payloadID: PayloadID) {
        guard active, endpointID == remote else { return }
        switch update {
        case .success: ledger.settled(payloadID)
        case .failure, .canceled:
            let relevant = testing && ledger.failed(payloadID, run: token, sequence: chunk)
            note("Payload failed/canceled; active request=\(relevant); seq=\(chunk)", severity: relevant ? "错误" : "信息")
            if relevant { cancelProbe(); status = "本轮请求传输失败；可重试或停止后重新连接" }
        case .progress: break
        }
    }
    func stop() {
        if active { note("本机清理会话与缓存端点") }
        epoch &+= 1; active = false; permissionAction = nil; verify(false); cancelProbe()
        pending.removeAll()
        remote = nil; found.removeAll(); status = "已停止"
        // Wait for both stop callbacks and clear SDK endpoint/strategy state.
        // Serialize repeated stops so an older stop cannot kill a new session.
        let previous = teardown; let barrier = DispatchGroup()
        barrier.enter(); teardown = barrier
        previous.notify(queue: .main) { [weak self] in
            guard let self = self else { barrier.leave(); return }
            let stops = DispatchGroup()
            stops.enter(); self.advertiser.stopAdvertising { _ in stops.leave() }
            stops.enter(); self.discoverer.stopDiscovery { _ in stops.leave() }
            stops.notify(queue: .main) {
                GNCCoreAdapter.shared.stopAllEndpoints { [weak self] error in
                    DispatchQueue.main.async { self?.resetFailure = error; barrier.leave() }
                }
            }
        }
    }
}
#endif
