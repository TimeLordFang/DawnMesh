/// Supported binary frame types in DawnMesh protocol.
enum FrameType {
  audio(0x01),
  joinReq(0x02),
  roster(0x03),
  pttState(0x04),
  heartbeat(0x05),
  leave(0x06),
  hostHandover(0x07),
  hostAnnounce(0x08),
  handshakeHello(0x09),
  handshakeConfirm(0x0a),
  sealed(0x0b),
  chat(0x0c),
  chatSync(0x0d),
  chatDelete(0x0e),
  chatImage(0x0f),
  admission(0x10),
  nicknameUpdate(0x11),
  fusionState(0x12),
  controlFragment(0x13),
  chatControl(0x14),
  memberKeys(0x15),
  voiceNote(0x16),
  voiceNoteStart(0x17),
  courierControl(0x18),
  courierBundle(0x19);

  final int value;
  const FrameType(this.value);

  bool get isBulk =>
      this == chatImage || this == voiceNote || this == voiceNoteStart;

  bool get isHostCommand =>
      this == roster ||
      this == hostHandover ||
      this == hostAnnounce ||
      this == chatSync ||
      this == memberKeys ||
      this == admission;

  static FrameType? fromValue(int value) {
    for (final type in FrameType.values) {
      if (type.value == value) return type;
    }
    return null;
  }
}
