import 'package:dawn_mesh/core/internet/internet_audio_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('公网音频按网络类型选择安全的默认档位', () {
    expect(
      InternetAudioProfileDetails.recommended(metered: false),
      InternetAudioProfile.clarity,
    );
    expect(
      InternetAudioProfileDetails.recommended(metered: true),
      InternetAudioProfile.dataSaver,
    );
  });

  test('所有档位在计费网络下都降低码率', () {
    for (final profile in InternetAudioProfile.values) {
      expect(
        profile.bitrateFor(metered: true),
        lessThan(profile.bitrateFor(metered: false)),
      );
    }
    expect(InternetAudioProfile.dataSaver.bitrateFor(metered: true), 12000);
  });
}
