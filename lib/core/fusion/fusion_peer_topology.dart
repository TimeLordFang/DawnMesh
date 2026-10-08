/// A ring among admitted members stays connected after one member disappears.
/// Bootstrap/host links remain as extra paths, without dialing a full clique.
abstract final class FusionPeerTopology {
  static Set<int> dialTargets(int selfId, Iterable<int> memberIds) {
    final peers = memberIds.where((id) => id != 1).toSet().toList()..sort();
    final index = peers.indexOf(selfId);
    if (index < 0 || peers.length < 2) return {};
    return {
      peers[(index + peers.length - 1) % peers.length],
      peers[(index + 1) % peers.length],
    }.where((id) => selfId < id).toSet();
  }
}
