import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'calibration_system.dart';
import 'rotating_floor_simulator.dart';

class CalibrationCanvas extends StatefulWidget {
  final bool isSimulator;
  final double angle;
  final CalibrationSystem calibrationSystem;
  final RotatingFloorSimulator simulator;

  /// media_kit VideoController — null when not connected
  final VideoController? videoController;
  final Function(double) onAngleChanged;
  final Function(double, double, double, double) onCrosshairChanged;

  const CalibrationCanvas({
    super.key,
    required this.isSimulator,
    required this.angle,
    required this.calibrationSystem,
    required this.simulator,
    required this.videoController,
    required this.onAngleChanged,
    required this.onCrosshairChanged,
  });

  @override
  State<CalibrationCanvas> createState() => _CalibrationCanvasState();
}

class _CalibrationCanvasState extends State<CalibrationCanvas> {
  double? _cx;
  double? _cy;
  double _ratioX = 0.5;
  double _ratioY = 0.5;

  bool _draggingCrosshair = false;
  bool _draggingRotation = false;
  double _dragStartLocalX = 0.0;

  // Drag hit threshold (larger for touch screens to make it easy)
  final double _hitBoxThreshold = 35.0;

  void _updateCrosshairPosition(
      double screenX, double screenY, double W, double H) {
    setState(() {
      _cx = screenX.clamp(0.0, W);
      _cy = screenY.clamp(0.0, H);
      _ratioX = _cx! / (W > 0 ? W : 1.0);
      _ratioY = _cy! / (H > 0 ? H : 1.0);
    });

    final worldPt =
        widget.calibrationSystem.screenToWorld(_cx!, _cy!, widget.angle, W, H);
    widget.onCrosshairChanged(_cx!, _cy!, worldPt.dx, worldPt.dy);
  }

  void _resetCrosshair(double W, double H) {
    _updateCrosshairPosition(W / 2.0, H / 2.0, W, H);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final W = constraints.maxWidth;
        final H = constraints.maxHeight;

        // Initialize crosshair at center if null
        if (_cx == null || _cy == null) {
          _cx = _ratioX * W;
          _cy = _ratioY * H;
        }

        // Keep crosshair responsive during resize
        final currentCx = _ratioX * W;
        final currentCy = _ratioY * H;

        return GestureDetector(
          onPanStart: (details) {
            final touchPt = details.localPosition;
            final distance = math.sqrt(math.pow(touchPt.dx - currentCx, 2) +
                math.pow(touchPt.dy - currentCy, 2));

            if (distance < _hitBoxThreshold) {
              setState(() {
                _draggingCrosshair = true;
                _draggingRotation = false;
              });
            } else {
              setState(() {
                _draggingCrosshair = false;
                _draggingRotation = true;
                _dragStartLocalX = touchPt.dx;
              });
            }
          },
          onPanUpdate: (details) {
            if (_draggingCrosshair) {
              _updateCrosshairPosition(
                  details.localPosition.dx, details.localPosition.dy, W, H);
            } else if (_draggingRotation) {
              final double currentX = details.localPosition.dx;
              final double deltaX = currentX - _dragStartLocalX;
              _dragStartLocalX = currentX;

              // Rotate viewport relative to touch movement
              double newAngle = (widget.angle - deltaX * 0.5) % 360.0;
              if (newAngle < 0) {
                newAngle += 360.0;
              }
              widget.onAngleChanged(newAngle);

              // Recalculate coordinates under crosshair
              final worldPt = widget.calibrationSystem
                  .screenToWorld(currentCx, currentCy, newAngle, W, H);
              widget.onCrosshairChanged(
                  currentCx, currentCy, worldPt.dx, worldPt.dy);
            }
          },
          onPanEnd: (_) {
            setState(() {
              _draggingCrosshair = false;
              _draggingRotation = false;
            });
          },
          onPanCancel: () {
            setState(() {
              _draggingCrosshair = false;
              _draggingRotation = false;
            });
          },
          child: Stack(
            children: [
              // 1. Background — media_kit Video or dark fallback
              if (!widget.isSimulator && widget.videoController != null)
                SizedBox(
                  width: W,
                  height: H,
                  child: Video(
                    controller: widget.videoController!,
                    // Disable built-in controls; we draw our own HUD overlay
                    controls: NoVideoControls,
                    fill: const Color(0xFF090B0D),
                  ),
                )
              else
                Container(
                  color: const Color(0xFF090B0D),
                  width: W,
                  height: H,
                ),

              // 2. Custom Painter Overlays (Simulator rotating grid, HUD, crosshairs, centroids)
              Positioned.fill(
                child: CustomPaint(
                  painter: CalibrationPainter(
                    isSimulator: widget.isSimulator,
                    angle: widget.angle,
                    crosshairX: currentCx,
                    crosshairY: currentCy,
                    calibrationSystem: widget.calibrationSystem,
                    simulator: widget.simulator,
                    draggingCrosshair: _draggingCrosshair,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class CalibrationPainter extends CustomPainter {
  final bool isSimulator;
  final double angle;
  final double crosshairX;
  final double crosshairY;
  final CalibrationSystem calibrationSystem;
  final RotatingFloorSimulator simulator;
  final bool draggingCrosshair;

  CalibrationPainter({
    required this.isSimulator,
    required this.angle,
    required this.crosshairX,
    required this.crosshairY,
    required this.calibrationSystem,
    required this.simulator,
    required this.draggingCrosshair,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double W = size.width;
    final double H = size.height;
    final double cx = W / 2.0;
    final double cy = H / 2.0;

    final paint = Paint()..isAntiAlias = true;

    // --- 1. RENDER SIMULATOR FLOOR GRID AND FEATURES ---
    if (isSimulator) {
      final double theta = angle * math.pi / 180.0;
      final double cosT = math.cos(theta);
      final double sinT = math.sin(theta);

      // Rotating grid lines
      final gridPaint = Paint()
        ..color = const Color(0x15FFFFFF)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;

      const double gridInterval = 80.0;
      for (double g = -480; g <= 480; g += gridInterval) {
        // Horizontal lines (constant y_w)
        final ptStartH = simulator.worldToScreen(-640, g, cosT, sinT, cx, cy);
        final ptEndH = simulator.worldToScreen(640, g, cosT, sinT, cx, cy);
        canvas.drawLine(ptStartH, ptEndH, gridPaint);

        // Vertical lines (constant x_w)
        final ptStartV = simulator.worldToScreen(g, -480, cosT, sinT, cx, cy);
        final ptEndV = simulator.worldToScreen(g, 480, cosT, sinT, cx, cy);
        canvas.drawLine(ptStartV, ptEndV, gridPaint);
      }

      // Draw true pivot marker
      final truePivotScreen = simulator.getProjectedPivot(angle, W, H);
      final truePivotPaint = Paint()
        ..color = const Color(0x3500FF66)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(truePivotScreen, 6.0, truePivotPaint);

      // Draw simulator floor features
      final features = simulator.getProjectedFeatures(angle, W, H);
      for (var f in features) {
        if (!f['isOnScreen']) continue;
        final Offset screenPos = f['position'];

        // Faint orange marker
        final featurePaint = Paint()
          ..color = const Color(0xB0FF9900)
          ..strokeWidth = 2.0;

        canvas.drawLine(Offset(screenPos.dx - 6, screenPos.dy),
            Offset(screenPos.dx + 6, screenPos.dy), featurePaint);
        canvas.drawLine(Offset(screenPos.dx, screenPos.dy - 6),
            Offset(screenPos.dx, screenPos.dy + 6), featurePaint);

        // Draw feature name label
        final textPainter = TextPainter(
          text: TextSpan(
            text: f['name'],
            style: const TextStyle(
                color: Color(0xFFCCCCCC),
                fontSize: 9.0,
                fontFamily: 'monospace'),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(canvas, Offset(screenPos.dx + 8, screenPos.dy - 5));
      }
    }

    // --- 2. RENDER STATIC CENTRAL HUD GUIDELINES ---
    final hudPaint = Paint()
      ..color = const Color(0x10FFFFFF)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(0, cy), Offset(W, cy), hudPaint);
    canvas.drawLine(Offset(cx, 0), Offset(cx, H), hudPaint);

    // --- 3. RENDER LOGGED CALIBRATION READINGS (Cyan dots) ---
    for (int i = 0; i < calibrationSystem.readings.length; i++) {
      final reading = calibrationSystem.readings[i];
      final rxry = calibrationSystem.worldToScreen(
          reading.worldX, reading.worldY, angle, W, H);

      // Cyan circular point marker
      final pointPaint = Paint()
        ..color = const Color(0xFF00FFFF)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(rxry, 3.5, pointPaint);

      // Label
      final textPainter = TextPainter(
        text: TextSpan(
          text: "P${i + 1}",
          style: const TextStyle(
              color: Color(0xFF00FFFF),
              fontSize: 9.0,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace'),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(rxry.dx + 6, rxry.dy - 12));
    }

    // --- 4. RENDER CALIBRATED PIVOT CENTROID OVERLAY (Green target) ---
    if (calibrationSystem.centroid != null) {
      final centroidWorld = calibrationSystem.centroid!;
      final centroidScreen = calibrationSystem.worldToScreen(
          centroidWorld.dx, centroidWorld.dy, angle, W, H);

      final greenPaint = Paint()
        ..color = const Color(0xFF00FF66)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

      canvas.drawCircle(centroidScreen, 15.0, greenPaint);
      canvas.drawCircle(
          centroidScreen,
          2.0,
          Paint()
            ..color = const Color(0xFF00FF66)
            ..style = PaintingStyle.fill);

      // Outer targeting tick lines
      canvas.drawLine(Offset(centroidScreen.dx - 22, centroidScreen.dy),
          Offset(centroidScreen.dx - 10, centroidScreen.dy), greenPaint);
      canvas.drawLine(Offset(centroidScreen.dx + 10, centroidScreen.dy),
          Offset(centroidScreen.dx + 22, centroidScreen.dy), greenPaint);
      canvas.drawLine(Offset(centroidScreen.dx, centroidScreen.dy - 22),
          Offset(centroidScreen.dx, centroidScreen.dy - 10), greenPaint);
      canvas.drawLine(Offset(centroidScreen.dx, centroidScreen.dy + 10),
          Offset(centroidScreen.dx, centroidScreen.dy + 22), greenPaint);

      // Text label details
      final textPainter = TextPainter(
        text: TextSpan(
          text:
              "CALIB_ZERO (${centroidWorld.dx.toStringAsFixed(1)}, ${centroidWorld.dy.toStringAsFixed(1)})",
          style: const TextStyle(
              color: Color(0xFF00FF66),
              fontSize: 9.0,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace'),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
          canvas, Offset(centroidScreen.dx + 18, centroidScreen.dy - 12));
    }

    // --- 5. RENDER ACTIVE TARGETING RETICLE (Draggable crosshair) ---
    final Color boxColor =
        draggingCrosshair ? const Color(0xFF00FF66) : const Color(0xFFFFCC00);
    final boxPaint = Paint()
      ..color = boxColor
      ..strokeWidth = draggingCrosshair ? 2.0 : 1.5
      ..style = PaintingStyle.stroke;

    const double boxSize = 40.0;
    canvas.drawRect(
      Rect.fromCenter(
          center: Offset(crosshairX, crosshairY),
          width: boxSize,
          height: boxSize),
      boxPaint,
    );

    // Inner red crosshairs
    final redPaint = Paint()
      ..color = const Color(0xFFFF3B30)
      ..strokeWidth = 2.0;
    const double chLen = 12.0;
    canvas.drawLine(Offset(crosshairX - chLen, crosshairY),
        Offset(crosshairX + chLen, crosshairY), redPaint);
    canvas.drawLine(Offset(crosshairX, crosshairY - chLen),
        Offset(crosshairX, crosshairY + chLen), redPaint);

    // Render coordinates beside reticle
    final worldPt =
        calibrationSystem.screenToWorld(crosshairX, crosshairY, angle, W, H);
    final textPainter = TextPainter(
      text: TextSpan(
        text:
            "Scr: (${crosshairX.toInt()}, ${crosshairY.toInt()})\nWorld: (${worldPt.dx.toStringAsFixed(1)}, ${worldPt.dy.toStringAsFixed(1)})",
        style: TextStyle(
          color: draggingCrosshair
              ? const Color(0xFF00FFFF)
              : const Color(0xFFCCCCCC),
          fontSize: 9.0,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, Offset(crosshairX + 25, crosshairY - 10));

    // --- 6. TELEMETRY CORNER OVERLAYS ---
    // Top-Left: REC mode label
    final modeText =
        isSimulator ? "● REC [SIMULATOR_MODE]" : "● REC [LIVE_RTSP_FEED]";
    final modePainter = TextPainter(
      text: TextSpan(
        text: modeText,
        style: const TextStyle(
            color: Color(0xFFFF3B30),
            fontSize: 10.0,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace'),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    modePainter.paint(canvas, const Offset(15, 25));

    // Top-Right: Yaw Rotation angle
    final anglePainter = TextPainter(
      text: TextSpan(
        text: "AZ: ${angle.toStringAsFixed(1)}° | EL: 0.0°",
        style: const TextStyle(
            color: Color(0xFF00FF66),
            fontSize: 10.0,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace'),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    anglePainter.paint(canvas, Offset(W - anglePainter.width - 15, 25));

    // Bottom-Left: System health & state
    final statePainter = TextPainter(
      text: TextSpan(
        text: "SYS: STABLE  |  READINGS: ${calibrationSystem.readings.length}",
        style: const TextStyle(
            color: Color(0xFF888888), fontSize: 10.0, fontFamily: 'monospace'),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    statePainter.paint(canvas, Offset(15, H - 25));

    // Bottom-Right: Current Time
    final now = DateTime.now();
    final timeStr =
        "SYS_TIME: ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
    final timePainter = TextPainter(
      text: TextSpan(
        text: timeStr,
        style: const TextStyle(
            color: Color(0xFF888888), fontSize: 10.0, fontFamily: 'monospace'),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    timePainter.paint(canvas, Offset(W - timePainter.width - 15, H - 25));
  }

  @override
  bool shouldRepaint(covariant CalibrationPainter oldDelegate) {
    return oldDelegate.isSimulator != isSimulator ||
        oldDelegate.angle != angle ||
        oldDelegate.crosshairX != crosshairX ||
        oldDelegate.crosshairY != crosshairY ||
        oldDelegate.draggingCrosshair != draggingCrosshair ||
        oldDelegate.calibrationSystem.readings.length !=
            calibrationSystem.readings.length ||
        oldDelegate.calibrationSystem.centroid != calibrationSystem.centroid;
  }
}
