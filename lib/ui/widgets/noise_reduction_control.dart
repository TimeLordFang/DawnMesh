import 'package:flutter/material.dart';

import '../../core/audio/noise_reduction.dart';

class NoiseReductionControl extends StatelessWidget {
  const NoiseReductionControl({super.key, required this.isNight});
  final bool isNight;

  @override
  Widget build(BuildContext context) {
    final english = Localizations.localeOf(context).languageCode == 'en';
    final labels = english ? ['Off', 'Standard', 'Strong'] : ['关闭', '标准', '强力'];
    final descriptions = english
        ? [
            'System audio processing only',
            'Offline voice enhancement',
            'Extra wind and background reduction; softer speech may be affected',
          ]
        : ['仅保留系统音频处理', '本地人声增强，兼顾清晰与自然', '进一步压低风噪与背景声，轻声可能受影响'];
    return ValueListenableBuilder<NoiseReductionLevel>(
      valueListenable: NoiseReductionSettings.level,
      builder: (context, level, _) => PopupMenuButton<NoiseReductionLevel>(
        key: const ValueKey('noise-reduction-control'),
        tooltip: english ? 'Microphone noise reduction' : '麦克风降噪',
        initialValue: level,
        onSelected: (value) async {
          try {
            await NoiseReductionSettings.setLevel(value);
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    english ? 'Could not change noise reduction' : '降噪切换失败，请重试',
                  ),
                ),
              );
            }
          }
        },
        itemBuilder: (_) => [
          for (final value in NoiseReductionLevel.values)
            PopupMenuItem(
              value: value,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  value == level
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                ),
                title: Text(labels[value.index]),
                subtitle: Text(descriptions[value.index]),
              ),
            ),
        ],
        child: Semantics(
          button: true,
          label: '${english ? 'Noise reduction' : '降噪'}：${labels[level.index]}',
          child: SizedBox(
            width: 62,
            height: 34 + MediaQuery.textScalerOf(context).scale(14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.record_voice_over_rounded,
                  size: 21,
                  color: isNight ? Colors.white70 : const Color(0xFF7E3947),
                ),
                Text(
                  '${english ? 'NS' : '降噪'}·${english && level == NoiseReductionLevel.standard ? 'Std' : labels[level.index]}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
