import 'package:flutter/material.dart';

import '../../core/session/room_session.dart';
import '../../core/transport/ble_l2cap_transport.dart';
import '../../core/fusion/fusion_transport.dart';
import '../theme/app_theme.dart';
import '../../l10n/app_strings.dart';

/// Diagnostics & Connection Quality Sheet.
class DiagnosticsSheet extends StatelessWidget {
  final bool isNight;
  final int memberCount;
  final int? packetLossRate;
  final int? roundTripTimeMs;
  final RoomSession? session;

  const DiagnosticsSheet({
    super.key,
    required this.isNight,
    this.memberCount = 1,
    this.packetLossRate,
    this.roundTripTimeMs,
    this.session,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final transport = session?.transport;
    final metrics = <String, int>{
      if (transport is FusionTransport) ...{
        s.transportLinks: transport.activeLinks,
        s.transportQueued: transport.queuedPackets,
        s.transportHighWater: transport.queueHighWatermark,
        s.transportDroppedAudio: transport.droppedAudioPackets,
        s.transportSentBytes: transport.sentBytes,
      },
    };
    final bg = isNight ? AppTheme.darkBg : AppTheme.lightBg;
    final cardBg = isNight ? AppTheme.darkCardBg : AppTheme.lightCardBg;
    final textPrimary = isNight
        ? AppTheme.darkTextPrimary
        : AppTheme.lightTextPrimary;
    final textSecondary = isNight
        ? AppTheme.darkTextSecondary
        : AppTheme.lightTextSecondary;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    s.diagnosticsTitle,
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _MetricRow(
              title: s.currentOnlineMembers,
              value: s.deviceCount(memberCount, session?.maxMembers ?? 6),
              cardBg: cardBg,
              textPrimary: textPrimary,
            ),
            const SizedBox(height: 10),
            _MetricRow(
              title: s.roundTripLatency,
              value: roundTripTimeMs == null
                  ? s.measurementUnavailable
                  : "$roundTripTimeMs ms",
              cardBg: cardBg,
              textPrimary: textPrimary,
            ),
            const SizedBox(height: 10),
            _MetricRow(
              title: s.packetLossRateTitle,
              value: packetLossRate == null
                  ? s.measurementUnavailable
                  : "$packetLossRate%",
              cardBg: cardBg,
              textPrimary: textPrimary,
            ),
            const SizedBox(height: 10),
            _MetricRow(
              title: s.audioCodecFormat,
              value: s.audioCodecDescription,
              cardBg: cardBg,
              textPrimary: textPrimary,
            ),
            if (session?.isBluetooth == true)
              ValueListenableBuilder<bool>(
                valueListenable: BleL2capTransport.preferTextFallback,
                builder: (context, value, _) => SwitchListTile(
                  title: Text(
                    s.isEn ? 'Test Bluetooth text fallback' : '验证蓝牙文字备用通道',
                  ),
                  subtitle: Text(
                    s.isEn
                        ? 'Applies when next joining a Bluetooth room. Rejoin to test; turn off to restore voice. Resets after app restart.'
                        : '下次加入蓝牙房时生效。退房再加入可验证；关闭后重新加入可恢复语音，重启应用会重置。',
                  ),
                  value: value,
                  onChanged: (enabled) =>
                      BleL2capTransport.preferTextFallback.value = enabled,
                ),
              ),
            for (final metric in metrics.entries) ...[
              const SizedBox(height: 10),
              _MetricRow(
                title: metric.key,
                value: '${metric.value}',
                cardBg: cardBg,
                textPrimary: textPrimary,
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final String title;
  final String value;
  final Color cardBg;
  final Color textPrimary;

  const _MetricRow({
    required this.title,
    required this.value,
    required this.cardBg,
    required this.textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 16,
        runSpacing: 6,
        children: [
          Text(title, style: TextStyle(color: textPrimary, fontSize: 14)),
          Text(
            value,
            style: TextStyle(
              color: textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
