import 'dart:math';

/// Generates a friendly local identity when the user has not chosen one yet.
///
/// The generated value is persisted by the nickname store, so it remains stable
/// across launches instead of changing every time a room is opened.
class GeneratedNickname {
  const GeneratedNickname._();

  static const _placeholders = {'探索者', 'explorer'};

  static const _zhFirst = ['晨风', '微光', '远山', '星河', '晴岚', '晚潮', '青空', '流云'];
  static const _zhSecond = ['旅人', '雨燕', '信使', '灯塔', '纸鸢', '山雀', '舟子', '萤火'];
  static const _enFirst = [
    'Dawn',
    'Misty',
    'River',
    'Starlit',
    'Cloud',
    'Harbor',
    'Meadow',
    'Ember',
  ];
  static const _enSecond = [
    'Finch',
    'Rider',
    'Beacon',
    'Swift',
    'Sparrow',
    'Voyager',
    'Kite',
    'Firefly',
  ];

  static bool needsGeneration(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return true;
    return _placeholders.contains(normalized.toLowerCase());
  }

  static String generate({required bool isEnglish, Random? random}) {
    final source = random ?? Random.secure();
    final number = 100 + source.nextInt(900);
    if (isEnglish) {
      return '${_enFirst[source.nextInt(_enFirst.length)]} '
          '${_enSecond[source.nextInt(_enSecond.length)]} $number';
    }
    return '${_zhFirst[source.nextInt(_zhFirst.length)]}'
        '${_zhSecond[source.nextInt(_zhSecond.length)]}$number';
  }
}
