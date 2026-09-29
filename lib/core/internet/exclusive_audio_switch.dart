/// Native audio calls must be awaited in this order. If silencing the old
/// output fails, never enable the other output and risk two audible streams.
Future<void> switchExclusiveAudio({
  required bool direct,
  required Future<void> Function(bool enabled) cloudPlayback,
  required Future<void> Function(bool enabled) directPlayback,
}) async {
  if (direct) {
    await cloudPlayback(false);
    await directPlayback(true);
  } else {
    await directPlayback(false);
    await cloudPlayback(true);
  }
}
