import SwiftUI
import NearbyConnections
import CoreLocation

@main
struct NearbyProbeApp: App {
    @StateObject private var model = ProbeModel()
    var body: some Scene {
        WindowGroup {
            NavigationView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("独立 Nearby 原型；不加入正式融合房。双方需核对配对码。")
                        Text(model.status).textSelection(.enabled)
                        if model.hotspotBuild {
                            Toggle("允许为高速连接切换 Wi-Fi", isOn: $model.allowHotspot)
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
    private var active = false
    private var pending = Set<String>()
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
    private var mediums: Set<Medium> {
        var values: Set<Medium> = [.ble, .wifiLAN, .awdl]
        if hotspotBuild && allowHotspot { values.insert(.wifiHotspot) }
        return values
    }
    private func permitted(_ action: @escaping () -> Void) {
        if !hotspotBuild || !allowHotspot { action(); return }
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
    func advertise() { permitted { [weak self] in
        guard let self = self else { return }; self.stop(); self.active = true
        self.advertiser.startAdvertising(using: Data("iOS Probe".utf8), mediums: self.mediums) { [weak self] error in
            guard let self = self, self.active else { return }
            self.status = error == nil ? "正在发布；等待另一台设备选择" : "发布失败：\(error!)"
        }
    } }
    func discover() { permitted { [weak self] in
        guard let self = self else { return }; self.stop(); self.active = true
        self.discoverer.startDiscovery(mediums: self.mediums) { [weak self] error in
            guard let self = self, self.active else { return }
            self.status = error == nil ? "正在发现；请选择设备" : "发现失败：\(error!)"
        }
    } }
    func connect(_ endpoint: String) {
        guard active, remote == nil, pending.isEmpty else { return }
        pending.insert(endpoint)
        discoverer.requestConnection(to: endpoint, using: Data("iOS Probe".utf8), mediums: mediums) { [weak self] error in
            guard let self = self, self.active else { return }
            if let error = error, self.pending.remove(endpoint) != nil { self.status = "连接失败：\(error)" }
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
    func discoverer(_ discoverer: Discoverer, didLose endpointID: EndpointID) { found.removeValue(forKey: endpointID) }
    func connectionManager(_ connectionManager: ConnectionManager, didReceive verificationCode: String,
                           from endpointID: EndpointID, verificationHandler: @escaping (Bool) -> Void) {
        guard active, pending.contains(endpointID), verification == nil && remote == nil else { verificationHandler(false); return }
        verification = verificationHandler; challenge = Challenge(id: endpointID, code: verificationCode)
    }
    func verify(_ accepted: Bool) { let action = verification; verification = nil; challenge = nil; action?(accepted) }
    func connectionManager(_ connectionManager: ConnectionManager, didChangeTo state: ConnectionState, for endpointID: EndpointID) {
        switch state {
        case .connected:
            guard active, pending.remove(endpointID) != nil else { manager.disconnect(from: endpointID); return }
            remote = endpointID; discoverer.stopDiscovery(); status = "已配对；实际介质由 SDK 选择。"
        case .disconnected, .rejected:
            let wasPending = pending.remove(endpointID) != nil
            if challenge?.id == endpointID { verify(false) }
            if remote == endpointID || wasPending {
                if remote == endpointID { remote = nil }
                cancelProbe(); if active { status = "连接已断开或被拒绝" }
            }
        case .connecting: if active && pending.contains(endpointID) { status = "正在连接，等待双方确认" }
        }
    }
    func probe() {
        guard remote != nil, !testing else { return }
        token = UInt32.random(in: 0...UInt32.max); chunk = 0
        testing = true; started = Date(); maxRTT = 0; next()
    }
    private func next() {
        guard let endpoint = remote, chunk >= 0 else { return }
        var bytes: [UInt8] = [68, 77, 80, 49, 1, UInt8(chunk >> 8), UInt8(chunk & 255)]
        bytes += [UInt8((token >> 24) & 255), UInt8((token >> 16) & 255), UInt8((token >> 8) & 255), UInt8(token & 255)]
        bytes += (0..<1024).map { UInt8(($0 + chunk) % 251) }
        sentAt = Date()
        let expected = token; let sequence = chunk
        let timer = DispatchWorkItem { [weak self] in
            guard let self = self, self.token == expected, self.chunk == sequence else { return }
            self.cancelProbe(); self.status = "等待回包超时"
        }
        watchdog = timer; DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timer)
        _ = manager.send(Data(bytes), to: [endpoint]) { [weak self] error in
            if error != nil { self?.cancelProbe(); self?.status = "发送失败" }
        }
    }
    func connectionManager(_ connectionManager: ConnectionManager, didReceive data: Data, withID payloadID: PayloadID, from endpointID: EndpointID) {
        guard endpointID == remote, data.count == 1035 else { return }
        var bytes = [UInt8](data)
        guard Array(bytes[0..<4]) == [68, 77, 80, 49] else { return }
        let index = Int(bytes[5]) * 256 + Int(bytes[6])
        guard (0..<32).contains(index) else { return }
        if bytes[4] == 1 { bytes[4] = 2; _ = manager.send(Data(bytes), to: [endpointID]); return }
        let receivedToken = bytes[7..<11].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard testing, bytes[4] == 2, index == chunk, receivedToken == token else { return }
        guard (11..<bytes.count).allSatisfy({ bytes[$0] == UInt8(($0 - 11 + chunk) % 251) }) else {
            cancelProbe(); status = "数据完整性校验失败"; return
        }
        maxRTT = max(maxRTT, Date().timeIntervalSince(sentAt) * 1000)
        watchdog?.cancel(); watchdog = nil; chunk += 1
        if chunk == 32 {
            let elapsed = max(0.001, Date().timeIntervalSince(started))
            status = String(format: "32 KiB 双向完整性通过；%.0f ms；最大 RTT %.0f ms；往返有效速率 %.1f KiB/s。此数值不证明使用了 Wi-Fi。", elapsed * 1000, maxRTT, 64 / elapsed)
            cancelProbe()
        } else { next() }
    }
    private func cancelProbe() { watchdog?.cancel(); watchdog = nil; chunk = -1; testing = false }
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
        if case .failure = update, endpointID == remote { cancelProbe(); status = "传输失败，请重试" }
    }
    func stop() {
        active = false; permissionAction = nil; verify(false); cancelProbe()
        advertiser.stopAdvertising(); discoverer.stopDiscovery()
        var connections = pending
        if let endpoint = remote { connections.insert(endpoint) }
        pending.removeAll()
        for endpoint in connections { manager.disconnect(from: endpoint) }
        remote = nil; found.removeAll(); status = "已停止"
    }
}
