import 'package:flutter/material.dart';

import '../../core/audio/noise_reduction.dart';

class NoiseReductionControl extends StatelessWidget {
  const NoiseReductionControl({super.key, required this.isNight});
  final bool isNight;

  @override
  Widget build(BuildContext context) {
    final english = Localizations.localeOf(context).languageCode == 'en';
    final labels = english ? ['Off', 'Standard', 'Strong'] : ['关闭', '标准', '强力'];
    return ValueListenableBuilder<NoiseReductionLevel>(
      valueListenable: NoiseReductionSettings.level,
      builder: (context, level, _) => PopupMenuButton<NoiseReductionLevel>(
        key: const ValueKey('noise-reduction-control'),
        tooltip:
            '${english ? 'Microphone noise reduction' : '麦克风降噪'}：${labels[level.index]}',
        constraints: const BoxConstraints(minWidth: 152, maxWidth: 180),
        menuPadding: const EdgeInsets.symmetric(vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
              height: 40,
              child: Row(
                children: [
                  Icon(
                    value == level ? Icons.check_rounded : Icons.remove_rounded,
                    size: 17,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    labels[value.index],
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
        ],
        child: Semantics(
          button: true,
          label: '${english ? 'Noise reduction' : '降噪'}：${labels[level.index]}',
          child: SizedBox(
            width: 48,
            height: 48,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.record_voice_over_rounded,
                    size: 21,
                    color: isNight ? Colors.white70 : const Color(0xFF7E3947),
                  ),
                  Text(
                    english ? 'Noise' : '降噪',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: isNight ? Colors.white70 : const Color(0xFF7E3947),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
