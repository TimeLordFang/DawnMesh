import 'package:flutter/material.dart';

/// App-wide typed bilingual strings.
class AppStrings {
  final bool isEn;

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
  String get wifiDescription =>
      isEn
          ? 'Talk freely and send messages over Wi-Fi, a hotspot or a direct connection'
          : '用 Wi-Fi、热点或设备直连，开口就能聊，也能发消息';
  String get bluetoothRoom => isEn ? 'Bluetooth room' : '蓝牙房间';
  String get bluetoothDescription =>
      isEn
          ? 'Connect over Bluetooth with push-to-talk or automatic voice and messages'
          : '用蓝牙连接，可选按住对讲或自动通话，也能发消息';
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
  String get debugLoggingDescription =>
      isEn
          ? 'App events plus readable Android hardware and runtime state'
          : '记录应用事件及 Android 可读取的硬件与运行状态';
  String get debugLogDisabledHint =>
      isEn
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
  String get debugLogPrivacyNote =>
      isEn
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
  String get audioTuningLowDescription =>
      isEn
          ? 'About 40 ms Bluetooth prebuffer and 20 ms app playback buffer. Stale voice is dropped to stay live; speech may skip on weak links.'
          : '蓝牙预缓冲约 40 ms、应用播放缓冲约 20 ms；积压语音会被丢弃以追上实时，弱链路下可能跳音。';
  String get audioTuningBalancedDescription =>
      isEn
          ? 'About 120 ms Bluetooth prebuffer and 80 ms app playback buffer. Recommended for most devices.'
          : '蓝牙预缓冲约 120 ms、应用播放缓冲约 80 ms；适合大多数设备，建议优先使用。';
  String get audioTuningStableDescription =>
      isEn
          ? 'About 200 ms Bluetooth prebuffer and 120 ms app playback buffer. Better resistance to radio bursts.'
          : '蓝牙预缓冲约 200 ms、应用播放缓冲约 120 ms；更能抵抗无线突发阻塞。';
  String get audioTuningApplied =>
      isEn
          ? 'Audio profile applied. Active audio may rebuffer briefly.'
          : '音频档位已应用，当前通话可能会短暂重新缓冲。';
  String get audioTuningSaveFailed =>
      isEn ? 'Could not save the audio profile' : '无法保存音频档位';
  String get audioAdvancedButton => isEn ? 'Advanced controls' : '高级参数控制';
  String get audioAdvancedTitle => isEn ? 'Bluetooth audio lab' : '蓝牙音频实验室';
  String get audioAdvancedDescription =>
      isEn
          ? 'Saved on this phone and applied to an active room immediately. Change one variable at a time for comparable logs.'
          : '参数保存在本机，并立即应用到当前房间。建议每次只改一项，方便对比日志。';
  String get audioHeadsetBitrate =>
      isEn ? 'Headset coexistence bitrate' : '耳机共存码率';
  String get audioL2capCoalesce =>
      isEn ? 'L2CAP batching window' : 'L2CAP 合并窗口';
  String get audioFlushEveryWrite =>
      isEn ? 'Flush every socket write' : '每次写入后刷新';
  String get audioFlushEveryWriteHint =>
      isEn
          ? 'Legacy behavior. Disable it to test asynchronous batched writes.'
          : '旧版行为；关闭后可测试异步批量写入。';
  String get audioDropStale => isEn ? 'Drop stale outgoing voice' : '丢弃过期待发语音';
  String get audioDropStaleHint =>
      isEn
          ? 'Keeps current speech when the local writer queue grows.'
          : '本机发送队列拥塞时优先保留最新话音。';
  String get audioStaleDeadline =>
      isEn ? 'Outgoing voice deadline' : '待发语音截止时间';
  String get audioPrebuffer => isEn ? 'Jitter prebuffer' : '接收预缓冲';
  String get audioMaximumBuffer => isEn ? 'Jitter hard limit' : '接收缓冲硬上限';
  String get audioAdaptiveBuffer =>
      isEn ? 'Adaptive jitter ceiling' : '自适应缓冲上限';
  String get audioStableDecay =>
      isEn ? 'Adaptive decay interval' : '自适应缓冲回落周期';
  String get audioLiveQueue => isEn ? 'Maximum playout backlog' : '最大待播积压';
  String get audioPlcLimit => isEn ? 'Packet-loss concealment limit' : '丢包隐藏上限';
  String get audioTrackBuffer =>
      isEn ? 'AudioTrack buffer request' : 'AudioTrack 缓冲请求';
  String get audioResetProfile => isEn ? 'Reset preset' : '恢复当前档默认值';
  String get audioApplyParameters => isEn ? 'Save and apply' : '保存并应用';
  String get audioParametersApplied =>
      isEn
          ? 'Parameters saved and applied to the active pipeline.'
          : '参数已保存，并应用到当前音频管线。';

  // Host Election & Transfer
  String get transferHost => isEn ? 'Change host' : '更换房主';
  String get selectNewHost => isEn ? 'Who will take over?' : '交给谁来接着聊';
  String get transferHostTip =>
      isEn ? 'Choose someone to take over the chat' : '选一位成员，接手这场聊天';
  String get bluetoothTransferUnsupported =>
      isEn
          ? 'Changing hosts is not yet supported in Bluetooth room'
          : '蓝牙对讲暂时不能更换房主';
  String transferTo(String name) => isEn ? 'Make host' : '设为房主';
  String transferHostConfirm(String name) =>
      isEn ? 'Let $name take over as host?' : '把房主交给$name？';
  String get hostTag => isEn ? 'Host' : '房主';
  String get memberTag => isEn ? 'Member' : '成员';
  String get cancel => isEn ? 'Cancel' : '取消';
  String get confirm => isEn ? 'Confirm' : '确定';

  // Status & Notifications
  String roomOnlineCount(int count) =>
      isEn ? '$count people here' : '$count 人在这里';
  String get roomConnected => isEn ? 'Connected' : '已连接';
  String get roomReconnecting =>
      isEn
          ? 'Reconnecting automatically · up to 10 min'
          : '连接中断 · 自动恢复中（最长 10 分钟）';
  String get roomDisconnected =>
      isEn ? 'Could not restore the room connection' : '房间连接暂未恢复';
  String get speaking => isEn ? 'Speaking' : '正在说话';
  String get muted => isEn ? 'Muted' : '已静音';

  // About & Updates
  String get aboutTitle => isEn ? 'About DawnMesh' : '关于曙光之声';
  String get aboutProduct =>
      isEn ? 'DawnMesh · Chat with people nearby' : '曙光之声 · 和身边的人聊聊';
  String currentVersion(String ver) =>
      isEn ? 'Current version: $ver' : '当前版本：$ver';
  String get updateNetworkNote =>
      isEn
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
  String get updateCheckFailed =>
      isEn
          ? 'Could not check for updates. Please try again later.'
          : '这次没查到更新，稍后再试一次';
  String get changelogTitle => isEn ? 'Recent changes' : '最近的变化';
  String get changelogBody =>
      isEn
          ? '1.0.0-beta.2\nThe invitation now follows the current host and disappears from the previous host after handover.\nMember avatars keep a stable order while roles, speaking state, and media connections change.'
          : '1.0.0-beta.2\n房主移交后，邀请码会跟随新房主，并立即从原房主界面移除。\n房主身份、发言状态和媒体连接变化时，成员头像保持稳定顺序。';
  String get licenseTitle => isEn ? 'Open source license' : '开源许可';
  String get licenseBody =>
      isEn
          ? 'Apache License 2.0\nDawnMesh is based on its original upstream project, under Apache License 2.0.\nhttps://www.apache.org/licenses/LICENSE-2.0'
          : 'Apache License 2.0\n曙光之声基于原始上游项目开发，采用 Apache License 2.0 开源许可证。\nhttps://www.apache.org/licenses/LICENSE-2.0';
  String get privacyTitle => isEn ? 'Messages & privacy' : '关于消息与隐私';
  String get privacyBody =>
      isEn
          ? 'Voice and text travel between devices in the chat over local Wi-Fi or Bluetooth.\nMessages are kept only in memory. Leaving clears the chat history on your device; other members may still have messages from this chat.\nChecking for updates connects to GitHub.'
          : '声音和文字通过本地 Wi-Fi 或蓝牙，在参与聊天的设备之间传递。\n文字消息只放在内存里。离开后，你这台设备上的聊天记录会清除，其他成员那里仍可能留有本次聊天的消息。\n检查更新时，会连接 GitHub。';

  // Theme
  String themeDescription(String current) =>
      isEn ? 'Current theme: $current' : '现在是$current';
  String get themeLight => isEn ? 'Dawn glow' : '晨曦微光';
  String get themeDark => isEn ? 'Moonlit sea' : '月色入海';

  // Home & Stage
  String get appSubheading => isEn ? 'Never Meant.' : '越过地平线，看海洋辽阔的延绵。';
  String get defaultNickname => isEn ? 'Explorer' : '探索者';
  String get nicknameValidationEmpty =>
      isEn ? 'Leave a nickname first' : '先留个称呼吧';
  String get emptyRoomListHint =>
      isEn
          ? 'No chats nearby yet\nStart one and wait for someone nearby to join'
          : '附近还没有聊天室\n先开一个，等身边的人来聊';
  String get nearFieldDirect => isEn ? 'Wi-Fi device connection' : 'Wi-Fi 设备直连';
  String get nearbyWifiRoom => isEn ? 'Nearby Wi-Fi room' : '附近的 Wi-Fi 畅聊';
  String get directP2PExplanation =>
      isEn
          ? 'Connect directly over Wi-Fi, without a router'
          : '用 Wi-Fi 直接连上对方，不用路由器';
  String get scanRooms => isEn ? 'Look nearby' : '看看附近';
  String get nearbyRoomsTitle => isEn ? 'Chats nearby' : '附近的聊天室';
  String get detectingRooms => scanning;
  String get noRoomsDiscoveredHint =>
      isEn
          ? 'No one found nearby yet\nOnce they start a chat, look again'
          : '还没找到附近的人\n等对方开好聊天，再找一次';
  String get wifiRoomChipSubtitle =>
      isEn ? 'Talk freely, send messages' : '开口就能聊，也能发消息';
  String get bleRoomChipSubtitle =>
      isEn ? 'Push-to-talk or automatic voice' : '按住对讲 / 自动通话';
  String get nearbyDevice => isEn ? 'Nearby device' : '附近的设备';
  String connectingTo(String target) =>
      isEn ? 'Connecting to "$target"…' : '正在连上「$target」…';
  String get directConnectFailed =>
      isEn
          ? 'Wi-Fi Direct did not connect. Move closer and try again.'
          : 'Wi-Fi 直连没连上，靠近对方再试一次';
  String get directConnectPermissionFailed =>
      isEn
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
  String get tooltipLeaveRoom => leaveRoom;
  String get tooltipDiagnostics =>
      isEn ? 'View connection and audio' : '查看连接与音质';
  String get hostBroadcastingStatus =>
      isEn ? 'Host · Chat started' : '房主 · 聊天已开始';
  String get memberConnectedStatus => isEn ? 'You are connected' : '已经连上了';

  // Room Audio State
  String get micMutedStatus => isEn ? 'Microphone is off' : '麦克风已关闭';
  String get speakingStatus => speaking;
  String get inCallStatus => isEn ? 'In call' : '通话中';
  String get pttHoldingToTalk => speaking;
  String get pttHoldToTalk => isEn ? 'Hold to talk' : '按住说话';
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
  String get chatInputPlaceholder => isEn ? 'Say something…' : '说点什么…';
  String get chatSend => isEn ? 'Send' : '发送';
  String get chatEmptyHint => isEn ? 'No one has said hello yet' : '还没人说第一句';
  String get chatMessageTooLong =>
      isEn
          ? 'This message is a little long. Split it into a few messages.'
          : '这条有点长，分成几条发吧';
  String get chatSendFailed =>
      isEn
          ? 'Something went wrong sending this message. Check the connection and try again.'
          : '这条消息发送时出了点问题，检查连接后再试一次';
  String get chatSending => isEn ? 'Sending message' : '消息正在发送';
  String get chatRecallFailed =>
      isEn
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
