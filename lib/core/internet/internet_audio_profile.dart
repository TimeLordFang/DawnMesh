enum InternetAudioProfile { clarity, balanced, dataSaver }

extension InternetAudioProfileDetails on InternetAudioProfile {
  String get label => switch (this) {
    InternetAudioProfile.clarity => '清晰',
    InternetAudioProfile.balanced => '平衡',
    InternetAudioProfile.dataSaver => '省流',
  };

  String get description => switch (this) {
    InternetAudioProfile.clarity => 'Wi-Fi 优先提升话音细节',
    InternetAudioProfile.balanced => '兼顾清晰度与流量',
    InternetAudioProfile.dataSaver => '最低可懂语音码率，静音段 DTX',
  };

  int bitrateFor({required bool metered}) => switch ((this, metered)) {
    (InternetAudioProfile.clarity, false) => 32000,
    (InternetAudioProfile.clarity, true) => 20000,
    (InternetAudioProfile.balanced, false) => 24000,
    (InternetAudioProfile.balanced, true) => 16000,
    (InternetAudioProfile.dataSaver, false) => 16000,
    (InternetAudioProfile.dataSaver, true) => 12000,
  };

  static InternetAudioProfile recommended({required bool metered}) =>
      metered ? InternetAudioProfile.dataSaver : InternetAudioProfile.clarity;
}
