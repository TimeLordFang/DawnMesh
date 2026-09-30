/// Last authenticated roster grants at most one reconnect window of continuity.
/// No new identity or additional permission is admitted while disconnected.
class HybridOfflineLease {
  DateTime? _lostAt;
  void update({required bool authorityOnline, required DateTime now}) {
    if (authorityOnline) {
      _lostAt = null;
    } else {
      _lostAt ??= now;
    }
  }

  bool allows(DateTime now) =>
      _lostAt == null || now.difference(_lostAt!) < const Duration(minutes: 30);
}
