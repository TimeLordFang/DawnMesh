import 'package:flutter/material.dart';

/// App-wide typed bilingual strings.
class AppStrings {
  final bool isEn;
  String get textOnlyStatus =>
      !isEn ? '蓝牙备用连接 · 仅文字' : 'Bluetooth fallback · text only';
  String get textOnlyHint => !isEn
      ? '当前连接支持文字聊天。重新连接后将再次尝试语音通道。'
      : 'Text chat is available. Reconnect to retry the voice link.';
  String get textOnlyLabel => !isEn ? '仅文字' : 'Text only';

  String get memberSafetyNumbers => isEn ? 'Member safety numbers' : '成员安全号码';
  String get safetyNumberHint => isEn
      ? 'Compare the full number for the same member on both phones in person or through a trusted channel. Nicknames and short device codes do not verify identity. Reinstalling or clearing secure storage may change this number.'
      : '面对面或通过可信渠道，核对双方手机上同一成员的完整号码。昵称和三位编号不能验证身份；重装或清除安全存储后号码可能变化。';
  String get measurementUnavailable => isEn ? 'Not measured' : '尚未测量';
  String get transportQueued => isEn ? 'Queued packets' : '等待发送的数据包';
  String get transportHighWater =>
      isEn ? 'Largest queue on one link' : '单条链路队列峰值';
  String get transportDroppedAudio =>
      isEn ? 'Expired or congested audio packets' : '过期或拥塞丢弃的语音包';
  String get transportSentBytes =>
      isEn ? 'Sent bytes (all links)' : '累计发送字节（所有链路）';
  String get transportLinks => isEn ? 'Active links' : '当前链路数';

  String get retainVoiceNotes =>
      isEn ? 'Keep my PTT as voice notes' : '将我的按键通话保留为留言';
  String get retainVoiceNotesHint => isEn
      ? 'Off by default. Up to 15 seconds per press, kept in this room only. Live speech continues beyond the limit. Notes can be recalled.'
      : '默认关闭。每次按键最多保留 15 秒，仅在本房间暂存；超出仍可继续通话。已留存的留言可撤回。';
  String get playVoiceNote => isEn ? 'Play voice note' : '播放语音留言';
  String get stopVoiceNote => isEn ? 'Stop playback' : '停止播放';
  String get cancelVoiceNote => isEn ? 'Discard this note' : '取消本次留言';
  String get voiceNotePending =>
      isEn ? 'Voice note · waiting for completion' : '语音留言 · 等待补全';
  String voiceNoteDuration(String seconds) =>
      isEn ? 'Voice note · $seconds s' : '语音留言 · $seconds 秒';
  String get voiceNotePlaybackFailed => isEn
      ? 'Release PTT or mute before playback. If it still fails, the note cannot be played.'
      : '请先松开对讲或静音再播放；若仍失败，该留言暂时无法播放。';

  String chatDeliveryLabel(String state) => switch (state) {
    'pending' => isEn ? 'Sent · awaiting confirmation' : '已发送 · 等待确认',
    'delivered' => isEn ? 'Confirmed by recipients' : '收件成员已确认',
    'failed' => isEn ? 'Delivery unconfirmed' : '尚未确认送达',
    _ => isEn ? 'Sent' : '已发送',
  };

  const AppStrings({this.isEn = false});

  static const AppStrings zh = AppStrings(isEn: false);
  static const AppStrings en = AppStrings(isEn: true);

  static AppStrings of(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context);
    if (locale == null) return zh;
    return locale.languageCode == 'en' ? en : zh;
  }

  // App & Branding
  String get appName => isEn ? 'DawnMesh' : '曙光之声';
  String get tagline => isEn ? 'Chat with people nearby' : '和身边的人聊聊';
  String get nicknameLabel => isEn ? 'What should we call you?' : '怎么称呼你';
  String get nicknamePlaceholder => isEn ? 'Your nickname' : '留个称呼';

  // Modes & Descriptions
  String get wifiRoom => isEn ? 'Wi-Fi room' : 'Wi-Fi 房间';
  String get wifiDirect => isEn ? 'Wi-Fi Direct' : 'Wi-Fi 直连';
  String get wifiDescription => isEn
      ? 'Share Wi-Fi or a hotspot with iPhone; Android devices also support Wi-Fi Direct'
      : '与 iPhone 互通请连接同一 Wi-Fi 或热点；安卓设备间也支持 Wi-Fi Direct';
  String get bluetoothRoom => isEn ? 'Bluetooth room' : '蓝牙房间';
  String get bluetoothDescription => isEn
      ? 'Bluetooth voice and messages. With Bluetooth headsets, prefer a Wi-Fi room.'
      : '用蓝牙对讲和发消息；同时戴蓝牙耳机时，建议优先用 Wi-Fi 房间';
  String get fullDuplex => isEn ? 'Talk freely' : '自由交谈';
  String get pttMode => isEn ? 'Hold to talk' : '按住说话';

  // Actions & Buttons
  String get createRoom => isEn ? 'Create room' : '创建房间';
  String get createWifiRoom => isEn ? 'Create Wi-Fi room' : '创建 Wi-Fi 房间';
  String get createBleRoom => isEn ? 'Create Bluetooth room' : '创建蓝牙房间';
  String get joinRoom => isEn ? 'Join room' : '加入房间';
  String get scanning => isEn ? 'Looking nearby…' : '正在看看附近…';
  String get scanAgain => isEn ? 'Look again' : '再找一次';
  String get checkMicrophone =>
      isEn ? 'Check microphone and headset' : '检查麦克风与耳机';
  String get backHome => isEn ? 'Back to home' : '回到首页';
  String get leaveRoom => isEn ? 'Leave chat' : '离开聊天';
  String get hangUp => isEn ? 'Hang up' : '挂断';
  String get mute => isEn ? 'Turn off microphone' : '关闭麦克风';
  String get unmute => isEn ? 'Turn on microphone' : '开启麦克风';
  String get micOn => isEn ? 'Microphone is on' : '麦克风已开启';
  String get speaker => isEn ? 'Speaker' : '扬声器';
  String get earpiece => isEn ? 'Earpiece' : '听筒';
  String get phoneMic => isEn ? 'Phone microphone' : '手机麦克风';
  String get headsetMic => isEn ? 'Headset microphone' : '耳机麦克风';

  // Diagnostics & Quality
  String get diagnosticsTitle => isEn ? 'Connection & audio' : '连接与音质';
  String get exportDiagnostics => isEn ? 'Export diagnostic report' : '导出诊断报告';
  String get copyReport => isEn ? 'Copy report' : '复制报告';
  String get reportCopied => isEn ? 'Report copied' : '报告已复制';
  String get qualityGood => isEn ? 'Good' : '良好';
  String get qualityFair => isEn ? 'Fair' : '一般';
  String get qualityPoor => isEn ? 'Poor' : '较差';

  // Debug Logs
  String get debugLogsTitle => isEn ? 'Debug logs' : '调试日志';
  String get tooltipDebugLogs => isEn ? 'Open debug logs' : '查看调试日志';
  String get debugLoggingSwitch => isEn ? 'Capture debug logs' : '记录调试日志';
  String get debugLoggingEnabled => isEn ? 'On' : '已开启';
  String get debugLoggingDisabled => isEn ? 'Off' : '已关闭';
  String get debugLoggingDescription => isEn
      ? 'App events plus readable Android hardware and runtime state'
      : '记录应用事件及 Android 可读取的硬件与运行状态';
  String get debugLogDisabledHint => isEn
      ? 'Turn logging on before reproducing a problem'
      : '遇到问题前先开启，随后重新操作一次';
  String get debugLogEmpty => isEn ? 'Waiting for logs' : '正在等待日志';
  String get debugLogEmptyHint =>
      isEn ? 'Use the app and new events will appear here' : '继续操作应用，新事件会显示在这里';
  String get searchDebugLogs => isEn ? 'Search tag or message' : '搜索模块或日志内容';
  String get clearSearch => isEn ? 'Clear search' : '清除搜索';
  String get copyDebugLogs => isEn ? 'Copy visible logs' : '复制当前日志';
  String get clearDebugLogs => isEn ? 'Clear logs' : '清空日志';
  String get captureSystemSnapshot =>
      isEn ? 'Capture system snapshot' : '刷新系统快照';
  String get debugLogsCopied =>
      isEn ? 'Logs copied with private addresses redacted' : '日志已复制，地址和长令牌已隐藏';
  String get debugLogsCleared => isEn ? 'Logs cleared' : '日志已清空';
  String get debugLogSaveFailed =>
      isEn ? 'Could not save the logging setting' : '无法保存调试日志开关';
  String get debugLogPrivacyNote => isEn
      ? 'Memory only. Android does not expose full system logcat to normal apps. Review before sharing.'
      : '仅存内存。普通应用无法读取完整系统 Logcat；对外发送前请检查内容。';
  String get debugLogAll => isEn ? 'All' : '全部';
  String get debugLogDebug => 'DEBUG';
  String get debugLogInfo => 'INFO';
  String get debugLogWarning => 'WARN';
  String get debugLogError => 'ERROR';
  String debugLogCount(int count) => isEn ? '$count entries' : '$count 条日志';
  String get audioTuningTitle => isEn ? 'Audio latency' : '音频延迟';
  String get audioTuningLow => isEn ? 'Fast' : '低延迟';
  String get audioTuningBalanced => isEn ? 'Balanced' : '平衡';
  String get audioTuningStable => isEn ? 'Stable' : '稳定';
  String get audioTuningLowDescription => isEn
      ? 'About 40 ms Bluetooth prebuffer and 20 ms app playback buffer. Stale voice is dropped to stay live; speech may skip on weak links.'
      : '蓝牙预缓冲约 40 ms、应用播放缓冲约 20 ms；积压语音会被丢弃以追上实时，弱链路下可能跳音。';
  String get audioTuningBalancedDescription => isEn
      ? 'About 120 ms Bluetooth prebuffer and 80 ms app playback buffer. Recommended for most devices.'
      : '蓝牙预缓冲约 120 ms、应用播放缓冲约 80 ms；适合大多数设备，建议优先使用。';
  String get audioTuningStableDescription => isEn
      ? 'About 200 ms Bluetooth prebuffer and 120 ms app playback buffer. Better resistance to radio bursts.'
      : '蓝牙预缓冲约 200 ms、应用播放缓冲约 120 ms；更能抵抗无线突发阻塞。';
  String get audioTuningApplied => isEn
      ? 'Audio profile applied. Active audio may rebuffer briefly.'
      : '音频档位已应用，当前通话可能会短暂重新缓冲。';
  String get audioTuningSaveFailed =>
      isEn ? 'Could not save the audio profile' : '无法保存音频档位';
  String get audioAdvancedButton => isEn ? 'Advanced controls' : '高级参数控制';
  String get audioAdvancedTitle => isEn ? 'Bluetooth audio lab' : '蓝牙音频实验室';
  String get audioAdvancedDescription => isEn
      ? 'Saved on this phone and applied to an active room immediately. Change one variable at a time for comparable logs.'
      : '参数保存在本机，并立即应用到当前房间。建议每次只改一项，方便对比日志。';
  String get audioHeadsetBitrate =>
      isEn ? 'Headset coexistence bitrate' : '耳机共存码率';
  String get audioL2capCoalesce =>
      isEn ? 'L2CAP batching window' : 'L2CAP 合并窗口';
  String get audioFlushEveryWrite =>
      isEn ? 'Flush every socket write' : '每次写入后刷新';
  String get audioFlushEveryWriteHint => isEn
      ? 'Legacy behavior. Disable it to test asynchronous batched writes.'
      : '旧版行为；关闭后可测试异步批量写入。';
  String get audioDropStale => isEn ? 'Drop stale outgoing voice' : '丢弃过期待发语音';
  String get audioDropStaleHint => isEn
      ? 'Keeps current speech when the local writer queue grows.'
      : '本机发送队列拥塞时优先保留最新话音。';
  String get audioStaleDeadline =>
      isEn ? 'Outgoing voice deadline' : '待发语音截止时间';
  String get audioPrebuffer => isEn ? 'Jitter prebuffer' : '接收预缓冲';
  String get audioMaximumBuffer => isEn ? 'Jitter hard limit' : '接收缓冲硬上限';
  String get audioAdaptiveBuffer =>
      isEn ? 'Adaptive jitter ceiling' : '自适应缓冲上限';
  String get audioStableDecay => isEn ? 'Adaptive decay interval' : '自适应缓冲回落周期';
  String get audioLiveQueue => isEn ? 'Maximum playout backlog' : '最大待播积压';
  String get audioPlcLimit => isEn ? 'Packet-loss concealment limit' : '丢包隐藏上限';
  String get audioTrackBuffer =>
      isEn ? 'AudioTrack buffer request' : 'AudioTrack 缓冲请求';
  String get audioResetProfile => isEn ? 'Reset preset' : '恢复当前档默认值';
  String get audioApplyParameters => isEn ? 'Save and apply' : '保存并应用';
  String get audioParametersApplied => isEn
      ? 'Parameters saved and applied to the active pipeline.'
      : '参数已保存，并应用到当前音频管线。';

  // Host Election & Transfer
  String get transferHost => isEn ? 'Change host' : '更换房主';
  String get selectNewHost => isEn ? 'Who will take over?' : '交给谁来接着聊';
  String get transferHostTip =>
      isEn ? 'Choose someone to take over the chat' : '选一位成员，接手这场聊天';
  String get bluetoothTransferUnsupported => isEn
      ? 'Changing hosts is not yet supported in Bluetooth room'
      : '蓝牙对讲暂时不能更换房主';
  String transferTo(String name) => isEn ? 'Make host' : '设为房主';
  String transferHostConfirm(String name) =>
      isEn ? 'Let $name take over as host?' : '把房主交给$name？';
  String get hostTag => isEn ? 'Host' : '房主';
  String get memberTag => isEn ? 'Member' : '成员';
  String get cancel => isEn ? 'Cancel' : '取消';
  String get confirm => isEn ? 'Confirm' : '确定';
  String get leaveRoomTitle => isEn ? 'Leave this room?' : '退出房间？';
  String get leaveRoomConfirmation => isEn
      ? 'You will stop receiving audio and messages from this room.'
      : '退出后将停止接收这个房间的语音和消息。';
  String get leaveRoomAction => isEn ? 'Leave room' : '退出房间';
  String get dissolveRoomTitle => isEn ? 'Dissolve this room?' : '解散房间？';
  String get dissolveRoomConfirmation => isEn
      ? 'The call will end for everyone in the room. This cannot be undone.'
      : '房间内所有人的通话都会结束，此操作无法撤销。';
  String get dissolveRoomAction => isEn ? 'Dissolve room' : '解散房间';

  // Status & Notifications
  String roomOnlineCount(int count) =>
      isEn ? '$count people here' : '$count 人在这里';
  String get roomConnected => isEn ? 'Connected' : '已连接';
  String get roomReconnecting => isEn
      ? 'Reconnecting automatically · up to 30 min'
      : '连接中断 · 自动恢复中（最长 30 分钟）';
  String get roomDisconnected =>
      isEn ? 'Could not restore the room connection' : '房间连接暂未恢复';
  String get activeRoomKept =>
      isEn ? 'In call · tap to return' : '通话保持中 · 点按返回';
  String get speaking => isEn ? 'Speaking' : '正在说话';
  String get muted => isEn ? 'Muted' : '已静音';

  // About & Updates
  String get aboutTitle => isEn ? 'About DawnMesh' : '关于曙光之声';
  String get aboutProduct =>
      isEn ? 'DawnMesh · Chat with people nearby' : '曙光之声 · 和身边的人聊聊';
  String currentVersion(String ver) =>
      isEn ? 'Current version: $ver' : '当前版本：$ver';
  String get updateNetworkNote => isEn
      ? 'Chat over local Wi-Fi or Bluetooth without internet access. Checking for updates connects to GitHub.'
      : '用本地 Wi-Fi 或蓝牙就能聊，不需要接入互联网。检查更新时，会连接 GitHub。';
  String get checkUpdate => isEn ? 'Check for updates' : '看看有没有更新';
  String get updateIdle => isEn ? 'No update check yet' : '还没检查过更新';
  String get updateChecking =>
      isEn ? 'Looking for a new version…' : '正在看看有没有新版本…';
  String get updateCurrent => isEn ? 'You are up to date' : '已经是最新版本了';
  String updateAvailable(String ver) =>
      isEn ? 'A new version is here: $ver' : '新版本来了：$ver';
  String get openGithubRelease =>
      isEn ? 'Open GitHub Releases' : '前往 GitHub 下载';
  String get openReleaseFailed =>
      isEn ? 'Could not open GitHub Releases' : '无法打开 GitHub Releases';
  String updateFailed(String msg) =>
      isEn ? 'Could not check for updates: $msg' : '这次没查到更新：$msg';
  String get updateCheckFailed => isEn
      ? 'Could not check for updates. Please try again later.'
      : '这次没查到更新，稍后再试一次';
  String get changelogTitle => isEn ? 'Recent changes' : '最近的变化';
  String get changelogBody => isEn
      ? '1.2.4\nUnifies room creation and other dialog actions across Android and iOS, improves small-screen input, and consolidates release and development guides.\n\n1.2.3\nUnifies dawn colors and settings, refines sun placement and animated ripples, improves Android icon resources and default iOS signing compatibility, and strengthens release checks.\n\n1.2.2\nImproves room joining and reconnection when admission messages are delayed or lost.\n\n1.2.1\nImproves busy fusion-room handshakes, shared concurrent connections and cancellation after timeout or exit.\n\n1.2.0\nUnifies icons and versions. Adds reliable text repair, independent member signatures and rekeying, Bluetooth text fallback, optional voice notes, optional Wi-Fi Aware acceleration and opt-in sealed offline forwarding. All nearby-room members must upgrade; radio interoperability and lock-screen behavior require device acceptance.\n\n1.1.9\nKeeps fusion entry in one flow, with same-network Android/iOS discovery, native same-platform peer Wi-Fi and server fallback. Removes experimental Nearby pairing and prototypes. Cross-platform offline peer networking is deferred.\n\n1.1.7\nAdds standard Bonjour/NSD discovery between Android and iOS on shared Wi-Fi or a hotspot, including real service ports and discovery recovery. Apple peer Wi-Fi and Android Wi-Fi Direct remain separate transports.\n\n1.1.6\nHandles asynchronous UDP discovery failures when no broadcast route is available, retaining the room and continuing discovery after network recovery.\n\n1.1.5\nProvides full Bluetooth room names for iOS discovery and preserves fresh names when joining. Recovers missing room titles from the authenticated host and clears stale names when rooms change. Pair with iOS 1.0.4.\n\n1.1.4\nDiscovers and joins iOS 1.0.3 Bluetooth hosts through GATT metadata while retaining legacy Android discovery. Updates fallback icons to match the shared DawnMesh branding.\n\n1.1.3\nUpdates shared RNNoise model loading checks and C declarations, improves Android backup rules, accessibility and launcher resources, and removes redundant platform checks.\n\n1.1.2\nPreserves replay protection across reconnects, handles foreground service failures and audio focus changes, and adds accessible start/stop controls for push-to-talk.\n\n1.1.1\nUpdated stable audio and networking dependencies and the Android build toolchain. Retains Android, iOS and Web protocol compatibility.\n\n1.1.0\nWi-Fi and fusion rooms now support up to 16 members, with encrypted fragmentation for long rosters and fewer redundant fusion paths. Includes voice quality presets, noise reduction, stable device identities, offline fusion communication and 30-minute recovery. Update all clients and Server to 0.3.0. Actual Wi-Fi Direct group capacity depends on the phones; Bluetooth remains limited to 6 members.'
      : '1.2.4\n统一两端建房及其他弹窗的按钮样式，改善小屏输入，并合并发布、开发与验证说明。\n\n1.2.3\n统一晨光配色和设置入口，调整太阳位置及动态波纹，改进安卓图标资源与 iOS 默认签名配置，并加强发布校验。\n\n1.2.2\n改善繁忙房间中认证报文延迟或丢失导致的入房和重连等待。\n\n1.2.1\n改善繁忙融合房的握手等待、并发连接结果及超时或退出后的连接清理。\n\n1.2.0\n统一两端图标与版本。新增文字确认补齐、成员独立签名和退出换钥、蓝牙文字备用通道、可选语音留言、可选 Wi-Fi Aware 加速与默认关闭的离线密封转交。近场房间要求所有成员升级；无线互通与锁屏表现仍需按设备验收。\n\n1.1.9\n融合房一次点击即可输入邀请码并继续连接；保留安卓与 iOS 同网互通、同系统原生 Wi-Fi 直连及公网兜底，补齐本地认证停滞时的备用入口。移除 Nearby 实验配对和原型，跨系统无共同网络直连暂缓。\n\n1.1.7\n补齐安卓与 iOS 同一 Wi-Fi/热点下的 Bonjour/NSD 双向发现，采用实际服务端口并完善发现恢复。苹果点对点 Wi-Fi 与安卓 Wi-Fi Direct 仍为不同链路。\n\n1.1.6\n处理无广播路由时异步上报的 UDP 发现错误，保留房间，并在网络恢复后继续发现附近设备。\n\n1.1.5\n补齐供 iOS 读取的完整蓝牙房名，入房采用最新名称；缺名时从已认证房主补全标题，换房时清理旧名称。配套 iOS 1.0.4。\n\n1.1.4\n通过 GATT 房间信息发现并加入 iOS 1.0.3 蓝牙房，保留旧安卓发现方式；统一备用启动图标。\n\n1.1.3\n同步 RNNoise 模型文件边界检查和标准 C 声明，规范备份规则、无障碍及启动图标资源，清理冗余系统版本判断。\n\n1.1.2\n重连保留防重放状态，完善前台服务失败和音频焦点变化时的采集处理，对讲按钮支持无障碍开始与停止操作。\n\n1.1.1\n升级音频、网络依赖及 Android 构建工具，保持 Android、iOS 和网页的协议兼容。\n\n1.1.0\nWi-Fi 房和融合房扩至 16 人，长名单通过加密分片完整传输，融合房减少重复转发路径。包含音质档位、降噪、稳定设备身份、离线融合通话及 30 分钟重连。所有成员需更新客户端，服务端升级至 0.3.0。Wi-Fi 直连实际群组容量取决于手机，蓝牙房保持 6 人。';
  String get licenseTitle => isEn ? 'Open source license' : '开源许可';
  String get licenseBody => isEn
      ? 'Apache License 2.0\nDawnMesh is based on its original upstream project, under Apache License 2.0.\nhttps://www.apache.org/licenses/LICENSE-2.0'
      : 'Apache License 2.0\n曙光之声基于原始上游项目开发，采用 Apache License 2.0 开源许可证。\nhttps://www.apache.org/licenses/LICENSE-2.0';
  String get privacyTitle => isEn ? 'Messages & privacy' : '关于消息与隐私';
  String get privacyPolicyLink => isEn ? 'Privacy policy' : '隐私政策';
  String get openPrivacyPolicyFailed => isEn
      ? 'Could not open the privacy policy. Please try again in your browser.'
      : '无法打开隐私政策，请在浏览器中重试。';
  String get privacyBody => isEn
      ? 'Room voice and messages use nearby devices or your selected server, depending on the room. Ordinary room chat and opt-in PTT voice notes are held in memory and cleared when you leave.\nOffline forwarding is separate and off by default. Enabling it saves encrypted messages and contacts on your device. Messages expire within 24 hours and are purged when the app next runs or exchanges data; contacts remain until deleted. Messages are encrypted for the recipient, while carriers can see routing identities and expiry. Turning it off stops exchange; Clear deletes local data. Recall cannot erase already-read content or uncooperative copies.\nPersistent identity keys use device secure storage. Checking for updates connects to GitHub.'
      : '房间语音和消息按房型通过附近设备或你选择的服务器传输。普通聊天和主动保留的按键语音留言暂存在内存，离开房间后清除。\n离线转交是独立功能，默认关闭。开启后在本机保存加密消息与联系人；消息最长有效 24 小时，在应用下次运行或交换时清理，联系人保留至主动删除。正文密封给收件人，转交者可见路由身份和到期时间。关闭会停止交换；“清空”另行删除本机数据。撤回无法抹去已读内容或不合作的副本。\n持久身份密钥保存在设备安全存储。检查更新时连接 GitHub。';

  // Theme
  String themeDescription(String current) =>
      isEn ? 'Current theme: $current' : '现在是$current';
  String get themeLight => isEn ? 'Dawn glow' : '晨曦微光';
  String get themeDark => isEn ? 'Moonlit sea' : '月色入海';

  // Home & Stage
  String get appSubheading =>
      isEn ? 'Beyond the horizon, let voices meet.' : '越过地平线，让声音相遇。';
  String get defaultNickname => isEn ? 'Explorer' : '探索者';
  String get nicknameValidationEmpty =>
      isEn ? 'Leave a nickname first' : '先留个称呼吧';
  String get emptyRoomListHint => isEn
      ? 'No chats nearby yet\nStart one and wait for someone nearby to join'
      : '附近还没有聊天室\n先开一个，等身边的人来聊';
  String get nearFieldDirect => isEn ? 'Wi-Fi device connection' : 'Wi-Fi 设备直连';
  String get nearbyWifiRoom => isEn ? 'Nearby Wi-Fi room' : '附近的 Wi-Fi 畅聊';
  String get directP2PExplanation => isEn
      ? 'Connect directly over Wi-Fi, without a router'
      : '用 Wi-Fi 直接连上对方，不用路由器';
  String get scanRooms => isEn ? 'Look nearby' : '看看附近';
  String get nearbyRoomsTitle => isEn ? 'Chats nearby' : '附近的聊天室';
  String get detectingRooms => scanning;
  String get noRoomsDiscoveredHint => isEn
      ? 'No one found nearby yet\nOnce they start a chat, look again'
      : '还没找到附近的人\n等对方开好聊天，再找一次';
  String get wifiRoomChipSubtitle =>
      isEn ? 'Talk freely, send messages' : '开口就能聊，也能发消息';
  String get bleRoomChipSubtitle =>
      isEn ? 'Push-to-talk or automatic voice' : '按住对讲 / 自动通话';
  String get nearbyDevice => isEn ? 'Nearby device' : '附近的设备';
  String connectingTo(String target) =>
      isEn ? 'Connecting to "$target"…' : '正在连上「$target」…';
  String get directConnectFailed => isEn
      ? 'Wi-Fi Direct did not connect. Move closer and try again.'
      : 'Wi-Fi 直连没连上，靠近对方再试一次';
  String get directConnectPermissionFailed => isEn
      ? 'Wi-Fi Direct did not connect. Check that the other person accepted the connection.'
      : 'Wi-Fi 直连没连上，请确认对方同意了连接';
  String roomHostInfo(String host, int count, int max) =>
      isEn ? 'Host: $host · $count/$max devices' : '房主：$host · $count/$max 台设备';
  String deviceCount(int count, int max) =>
      isEn ? '$count/$max devices' : '$count/$max 台设备';
  String defaultWifiRoomTitle(String name) =>
      isEn ? "$name's chat · Wi-Fi" : '$name的聊天室 · Wi-Fi';
  String defaultBleRoomTitle(String name) =>
      isEn ? "$name's chat · Bluetooth" : '$name的聊天室 · 蓝牙';
  String get connecting => isEn ? 'Connecting…' : '正在连接…';
  String joinFailed(String msg) =>
      isEn ? 'Could not join this chat: $msg' : '没能加入这场聊天：$msg';

  // Stage Header
  String get tooltipInfoAndUpdates => aboutTitle;
  String get tooltipToggleTheme =>
      isEn ? 'Switch dawn and moonlight themes' : '切换晨曦与月夜';
  String get tooltipLeaveRoom => backHome;
  String get tooltipDiagnostics =>
      isEn ? 'View connection and audio' : '查看连接与音质';
  String get hostBroadcastingStatus =>
      isEn ? 'Host · Chat started' : '房主 · 聊天已开始';
  String get memberConnectedStatus => isEn ? 'You are connected' : '已经连上了';

  // Room Audio State
  String get micMutedStatus => isEn ? 'Microphone is off' : '麦克风已关闭';
  String get speakingStatus => speaking;
  String get inCallStatus => isEn ? 'In call' : '通话中';
  String get automaticListening =>
      isEn ? 'Automatic voice is listening' : '自动通话正在聆听';
  String get pttHoldingToTalk => speaking;
  String get pttHoldToTalk => isEn ? 'Hold to talk' : '按住说话';
  String get pttStartSpeaking => isEn ? 'Start speaking' : '开始说话';
  String get pttStopSpeaking => isEn ? 'Stop speaking' : '停止说话';
  String get pttAccessibleHint =>
      isEn ? 'Activate to start or stop speaking' : '激活按钮开始或停止说话';
  String get leave => isEn ? 'Leave' : '离开';
  String get microphone => isEn ? 'Microphone' : '麦克风';

  // Diagnostics Sheet
  String get currentOnlineMembers => isEn ? 'People here now' : '现在在线的成员';
  String get roundTripLatency => isEn ? 'Round-trip latency' : '往返延迟';
  String get packetLossRateTitle => isEn ? 'Packet loss' : '丢包率';
  String get audioCodecFormat => isEn ? 'Audio format' : '音频格式';
  String get audioCodecDescription =>
      isEn ? 'Opus · 16 kHz · Mono · 20 ms' : 'Opus · 16 kHz · 单声道 · 20 ms';

  // Room Text Chat
  String get chatTitle => isEn ? 'Messages' : '消息';
  String get recentMessages => isEn ? 'Recent messages' : '最近消息';
  String get viewAllMessages => isEn ? 'View all' : '查看全部';
  String get chatInputPlaceholder => isEn ? 'Say something…' : '说点什么…';
  String get chatSend => isEn ? 'Send' : '发送';
  String get chatEmptyHint => isEn ? 'No one has said hello yet' : '还没人说第一句';
  String get chatDockEmpty =>
      isEn ? 'New messages will appear here' : '消息会显示在这里';
  String get chatImage => isEn ? 'Image' : '图片';
  String get chatSendImage => isEn ? 'Send image' : '发送图片';
  String get chatSaveImage => isEn ? 'Save to phone' : '保存到手机';
  String get chatImageSaved =>
      isEn ? 'Image saved to your gallery' : '图片已保存到手机相册';
  String get chatImageSaveFailed => isEn
      ? 'Could not save the image. Check photo permissions and try again.'
      : '图片保存失败，请检查相册权限';
  String get chatMessageTooLong => isEn
      ? 'This message is a little long. Split it into a few messages.'
      : '这条有点长，分成几条发吧';
  String get chatSendFailed => isEn
      ? 'Something went wrong sending this message. Check the connection and try again.'
      : '这条消息发送时出了点问题，检查连接后再试一次';
  String get chatSending => isEn ? 'Sending message' : '消息正在发送';
  String get chatRecallFailed => isEn
      ? 'The recall did not finish. Please check the connection.'
      : '撤回还没完成，请检查一下连接';
  String get chatFormerMember => isEn ? 'Left the chat' : '已离开';
  String get tooltipChat => isEn ? 'Open messages' : '打开消息';
  String get chatButtonLabel => chatTitle;
  String get chatCloseSheet => isEn ? 'Close messages' : '关闭消息';
  String chatUnreadBadge(int count) =>
      isEn ? '$count unread messages' : '$count 条未读消息';
  String get chatRecall => isEn ? 'Recall' : '撤回';
  String get chatRecallConfirm =>
      isEn ? 'Would you like to recall this message?' : '要撤回这条消息吗？';
  String get chatRecalledTip => isEn ? 'Recall request submitted' : '撤回请求已提交';
  String formerNameLabel(String name) => isEn ? 'Previously $name' : '之前叫$name';
  String get hostRoleBadge => hostTag;
  String get chatSelfBadge => isEn ? 'Me' : '我';
  String get deviceCodeTooltip => isEn ? 'Device code' : '设备识别码';
}
