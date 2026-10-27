import 'dart:math' as math;

import 'package:dawn_mesh/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (math.max(x, y) + .05) / (math.min(x, y) + .05);
}

void main() {
  test('brand colors keep text readable in both appearances', () {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      final colors = theme.colorScheme;
      expect(
        contrast(colors.primary, colors.onPrimary),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(colors.secondary, colors.onSecondary),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(colors.surface, colors.onSurface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(colors.surface, colors.onSurfaceVariant),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(theme.scaffoldBackgroundColor, colors.primary),
        greaterThanOrEqualTo(4.5),
      );
    }
  });
}
