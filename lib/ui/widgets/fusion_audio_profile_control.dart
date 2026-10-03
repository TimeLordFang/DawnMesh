import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/fusion/fusion_audio_settings.dart';
import '../../core/internet/internet_audio_profile.dart';

class FusionAudioProfileControl extends StatelessWidget {
  const FusionAudioProfileControl({super.key, required this.settings});
  final FusionAudioSettings settings;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: settings,
    builder: (context, _) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '语音质量 · ${settings.bitrate ~/ 1000} kbps',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final profile in InternetAudioProfile.values)
                ChoiceChip(
                  key: ValueKey('fusion-audio-${profile.name}'),
                  label: Text(profile.label),
                  selected: settings.profile == profile,
                  onSelected: (_) => unawaited(settings.select(profile)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '只调整本机发送的语音。省流档降低编码码率，双线同时传输仍会使用公网流量。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}
