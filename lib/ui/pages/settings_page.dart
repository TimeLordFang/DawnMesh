import 'package:flutter/material.dart';

import '../../core/session/room_session.dart';
import '../../l10n/app_strings.dart';
import '../theme/app_appearance.dart';
import '../widgets/noise_reduction_control.dart';
import 'about_page.dart';
import 'courier_page.dart';
import 'debug_log_page.dart';
import 'server_settings_page.dart';

/// Shared settings destination for the home screen and every room type.
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    this.roomItems,
    this.listenable,
    this.session,
    this.lockedServerId,
  });
  final List<Widget> Function(BuildContext)? roomItems;
  final Listenable? listenable;
  final RoomSession? session;
  final String? lockedServerId;

  @override
  Widget build(BuildContext context) => listenable == null
      ? _content(context)
      : ListenableBuilder(
          listenable: listenable!,
          builder: (context, _) => _content(context),
        );

  Widget _content(BuildContext context) {
    final s = AppStrings.of(context);
    final night = Theme.of(context).brightness == Brightness.dark;
    final appearance = AppAppearance.maybeOf(context);
    String tr(String zh, String en) => s.isEn ? en : zh;
    void open(Widget page) =>
        Navigator.push<void>(context, MaterialPageRoute(builder: (_) => page));
    final room = roomItems?.call(context) ?? const <Widget>[];
    return Scaffold(
      appBar: AppBar(title: Text(tr('设置', 'Settings'))),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (appearance != null)
              _section(context, tr('外观', 'Appearance'), [
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: Text(tr('主题', 'Theme')),
                  subtitle: Text(
                    tr(
                      '选择浅色、深色或跟随系统',
                      'Choose light, dark, or follow your device',
                    ),
                  ),
                  trailing: DropdownButton<ThemeMode>(
                    key: const ValueKey('appearance-mode'),
                    value: appearance.mode,
                    underline: const SizedBox.shrink(),
                    items: [
                      DropdownMenuItem(
                        value: ThemeMode.system,
                        child: Text(tr('跟随系统', 'System')),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.light,
                        child: Text(tr('浅色', 'Light')),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.dark,
                        child: Text(tr('深色', 'Dark')),
                      ),
                    ],
                    onChanged: (mode) {
                      if (mode != null) appearance.onChanged(mode);
                    },
                  ),
                ),
              ]),
            _section(context, tr('语音与消息', 'Voice and messages'), [
              ListTile(
                leading: const Icon(Icons.mic_none_rounded),
                title: Text(tr('麦克风降噪', 'Microphone noise reduction')),
                subtitle: Text(
                  tr('只影响本机发出的语音', 'Only affects your outgoing voice'),
                ),
                trailing: NoiseReductionControl(isNight: night),
              ),
              ListTile(
                key: const ValueKey('settings-courier'),
                leading: const Icon(Icons.move_to_inbox_outlined),
                title: Text(tr('离线转交', 'Offline forwarding')),
                subtitle: Text(
                  tr(
                    '管理密封留言、联系人与转交开关',
                    'Manage sealed messages, contacts and forwarding',
                  ),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => open(CourierPage(session: session)),
              ),
            ]),
            _section(context, tr('连接', 'Connections'), [
              ListTile(
                key: const ValueKey('settings-servers'),
                leading: const Icon(Icons.dns_outlined),
                title: Text(tr('服务器', 'Servers')),
                subtitle: Text(
                  tr(
                    '统一管理公网房与融合房的服务器',
                    'Manage servers for public and fusion rooms',
                  ),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () =>
                    open(ServerSettingsPage(lockedServerId: lockedServerId)),
              ),
            ]),
            if (room.isNotEmpty)
              _section(context, tr('当前房间', 'Current room'), room),
            _section(context, tr('高级与帮助', 'Advanced and help'), [
              ListTile(
                key: const ValueKey('settings-debug'),
                leading: const Icon(Icons.tune_rounded),
                title: Text(tr('调试与音频调校', 'Diagnostics and audio tuning')),
                subtitle: Text(
                  tr(
                    '日志、音频参数和故障排查',
                    'Logs, audio parameters and troubleshooting',
                  ),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => open(DebugLogPage(isNight: night)),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: Text(s.tooltipInfoAndUpdates),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => open(AboutPage(isNight: night)),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> items) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Text(title, style: Theme.of(context).textTheme.titleSmall),
            ),
            Card(
              clipBehavior: Clip.antiAlias,
              margin: EdgeInsets.zero,
              child: Column(children: items),
            ),
          ],
        ),
      );
}
