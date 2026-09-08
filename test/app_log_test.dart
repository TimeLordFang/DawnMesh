import 'package:flutter_test/flutter_test.dart';
import 'package:dawn_mesh/core/diagnostics/app_log.dart';

void main() {
  setUp(() {
    AppLog.setEnabled(false);
    AppLog.clear();
  });

  tearDown(() {
    AppLog.setEnabled(false);
    AppLog.clear();
  });

  test('logging is opt-in and disabling clears retained entries', () async {
    AppLog.info('测试', '关闭时不应记录');
    expect(AppLog.recent, isEmpty);

    final emitted = AppLog.stream.first;
    AppLog.setEnabled(true);
    AppLog.warn('蓝牙', '测试链路波动');

    expect((await emitted).message, '测试链路波动');
    expect(AppLog.recent.single.tag, '蓝牙');

    AppLog.setEnabled(false);
    AppLog.error('音频', '关闭后也不应记录');
    expect(AppLog.recent, isEmpty);
  });

  test('retains only the newest bounded set of entries', () {
    AppLog.setEnabled(true);
    for (var index = 0; index < AppLog.maxRetained + 5; index++) {
      AppLog.debug('容量', '记录 $index');
    }

    expect(AppLog.recent, hasLength(AppLog.maxRetained));
    expect(AppLog.recent.first.message, '记录 ${AppLog.maxRetained + 4}');
    expect(AppLog.recent.last.message, '记录 5');
  });
}
