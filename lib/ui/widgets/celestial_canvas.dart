import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Dynamic Canvas Painter for Dawn Sun / Moonlit Night & Water Wave Ripples.
class CelestialCanvas extends StatefulWidget {
  final bool isNight;
  final double waveIntensity; // 0.0 ~ 1.0 (audio activity)

  /// 画布高度。进房转场时由 [SessionStage] 在首页高度与房间高度之间插值。
  final double height;

  /// 日轮/月轮圆心的横向位置，取值为宽度的比例。
  final double celestialCenterFactorX;

  /// 日轮/月轮圆心的纵向位置，取值为高度的比例。
  final double celestialCenterFactorY;

  /// 日轮/月轮半径（逻辑像素）。
  final double celestialRadius;

  /// 水面波纹起始线的纵向位置，取值为高度的比例。
  final double waterLineFactor;

  const CelestialCanvas({
    super.key,
    required this.isNight,
    this.waveIntensity = 0.0,
    this.height = 260,
    this.celestialCenterFactorX = 0.5,
    this.celestialCenterFactorY = 0.42,
    this.celestialRadius = 52,
    this.waterLineFactor = 0.76,
  });

  @override
  State<CelestialCanvas> createState() => _CelestialCanvasState();
}

class _CelestialCanvasState extends State<CelestialCanvas>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return CustomPaint(
          size: Size(double.infinity, widget.height),
          painter: _CelestialPainter(
            isNight: widget.isNight,
            wavePhase: _animController.value * 2 * math.pi,
            waveIntensity: widget.waveIntensity,
            celestialCenterFactorX: widget.celestialCenterFactorX,
            celestialCenterFactorY: widget.celestialCenterFactorY,
            celestialRadius: widget.celestialRadius,
            waterLineFactor: widget.waterLineFactor,
          ),
        );
      },
    );
  }
}

class _CelestialPainter extends CustomPainter {
  final bool isNight;
  final double wavePhase;
  final double waveIntensity;
  final double celestialCenterFactorX;
  final double celestialCenterFactorY;
  final double celestialRadius;
  final double waterLineFactor;

  _CelestialPainter({
    required this.isNight,
    required this.wavePhase,
    required this.waveIntensity,
    required this.celestialCenterFactorX,
    required this.celestialCenterFactorY,
    required this.celestialRadius,
    required this.waterLineFactor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // 1. Sky Gradient
    final skyColors = isNight
        ? [AppTheme.brandIndigo, AppTheme.brandNavy, AppTheme.darkBg]
        : [
            const Color(0xFF1A2757),
            const Color(0xFF424B80),
            const Color(0xFFCC8C98),
            const Color(0xFFFFB687),
            const Color(0xFFFFE4AD),
            AppTheme.lightBg,
          ];

    final skyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: skyColors,
        stops: isNight ? null : const [0, 0.25, 0.44, 0.62, 0.80, 1],
      ).createShader(rect);

    canvas.drawRect(rect, skyPaint);

    // 2. Sun / Moon (Celestial Body)
    final celestialCenter = Offset(
      size.width * celestialCenterFactorX,
      size.height * celestialCenterFactorY,
    );
    final radius = celestialRadius;

    final celestialColor = AppTheme.brandGold;

    // Outer Glow: GPU RadialGradient shader instead of expensive MaskFilter.blur
    final glowRadius = radius + 26;
    final glowPaint = Paint()
      ..shader =
          RadialGradient(
            colors: [
              celestialColor.withValues(
                alpha: 0.38 + 0.12 * math.sin(wavePhase),
              ),
              celestialColor.withValues(alpha: 0.0),
            ],
            stops: const [0.55, 1.0],
          ).createShader(
            Rect.fromCircle(center: celestialCenter, radius: glowRadius),
          );
    canvas.drawCircle(celestialCenter, glowRadius, glowPaint);

    // Main Circle
    final mainPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppTheme.warmWhite, AppTheme.brandGold, AppTheme.brandOrange],
      ).createShader(Rect.fromCircle(center: celestialCenter, radius: radius));
    canvas.drawCircle(celestialCenter, radius, mainPaint);

    // Both appearances share the same animated horizon ripples.
    final waterY = size.height * waterLineFactor;
    final horizonPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = AppTheme.warmWhite.withValues(alpha: 0.42);
    for (var i = 0; i < 2; i++) {
      final path = Path();
      for (double x = 0; x <= size.width; x += 4) {
        final y =
            waterY +
            i * 15 +
            math.sin(x / size.width * math.pi * 2 + wavePhase + i * 0.7) *
                (9 + waveIntensity * 6);
        if (x == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, horizonPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CelestialPainter oldDelegate) {
    return oldDelegate.isNight != isNight ||
        oldDelegate.wavePhase != wavePhase ||
        oldDelegate.waveIntensity != waveIntensity ||
        oldDelegate.celestialCenterFactorX != celestialCenterFactorX ||
        oldDelegate.celestialCenterFactorY != celestialCenterFactorY ||
        oldDelegate.celestialRadius != celestialRadius ||
        oldDelegate.waterLineFactor != waterLineFactor;
  }
}
