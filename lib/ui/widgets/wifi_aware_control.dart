import 'package:flutter/material.dart';

import '../../core/transport/wifi_aware_link.dart';
import '../../l10n/app_strings.dart';

class WifiAwareControl extends StatefulWidget {
  const WifiAwareControl({super.key, required this.link});
  final WifiAwareLink link;
  @override
  State<WifiAwareControl> createState() => _WifiAwareControlState();
}

class _WifiAwareControlState extends State<WifiAwareControl> {
  final _pin = TextEditingController();
  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.link,
    builder: (context, _) {
      final link = widget.link;
      final en = AppStrings.of(context).isEn;
      return ExpansionTile(
        leading: const Icon(Icons.wifi_tethering),
        title: Text(
          en ? 'Optional Wi-Fi Aware acceleration' : '可选 Wi-Fi Aware 加速',
        ),
        subtitle: Text(link.status),
        onExpansionChanged: (expanded) {
          if (expanded && link.capability == null) link.inspect();
        },
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text(
            en
                ? 'Both devices must support standard pairing. In this fusion room, start on the host and a member, then pair them. Setup failure keeps existing connections. This mode may use more battery.'
                : '双方设备都需支持标准配对。在本融合房的房主和成员上启用后，再进行配对。失败时继续使用原连接；加速可能增加耗电。',
          ),
          const SizedBox(height: 8),
          if (link.capability?['reason'] case final String reason) Text(reason),
          if (link.displayedPin case final pin?) ...[
            const SizedBox(height: 12),
            SelectableText(
              '${en ? "Pairing code" : "配对码"}：$pin',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
          if (link.active &&
              link.capability?['systemPairingUi'] != true &&
              !link.isHost()) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _pin,
              keyboardType: TextInputType.number,
              maxLength: 12,
              decoration: InputDecoration(
                labelText: en ? 'Code shown by the host' : '房主显示的配对码',
              ),
            ),
          ],
          Wrap(
            spacing: 8,
            children: [
              if (!link.active)
                FilledButton(
                  onPressed: link.busy || link.capability?['supported'] == false
                      ? null
                      : link.start,
                  child: Text(en ? 'Try acceleration' : '尝试启用'),
                ),
              if (link.active)
                OutlinedButton(
                  onPressed: link.busy
                      ? null
                      : () => link.pair(pin: _pin.text.trim()),
                  child: Text(en ? 'Pair devices' : '配对设备'),
                ),
              if (link.active)
                TextButton(
                  onPressed: link.busy ? null : link.stop,
                  child: Text(en ? 'Disable acceleration' : '关闭加速'),
                ),
            ],
          ),
        ],
      );
    },
  );
}
