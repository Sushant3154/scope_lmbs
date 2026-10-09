import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'calibration_system.dart';

/// Lets external widgets (e.g. a sidebar joystick) drive the crosshair
/// inside a [CalibrationCanvas] imperatively, without lifting its position
/// state up into the parent. Attach one instance per canvas.
class CrosshairController {
  void Function(double dx, double dy)? _onNudge;
  VoidCallback? _onResetToCenter;

  void _attach(void Function(double dx, double dy) onNudge,
      VoidCallback onResetToCenter) {
    _onNudge = onNudge;
    _onResetToCenter = onResetToCenter;
  }

  void _detach() {
    _onNudge = null;
    _onResetToCenter = null;
  }

  /// Moves the crosshair by (dx, dy) screen pixels.
  void nudge(double dx, double dy) => _onNudge?.call(dx, dy);

  /// Snaps the crosshair back to the center of the canvas.
  void resetToCenter() => _onResetToCenter?.call();
}

class CalibrationCanvas extends StatefulWidget {
  final double angle;
  final CalibrationSystem calibrationSystem;

  /// media_kit VideoController — null when not connected
  final VideoController? videoController;
  final Function(double) onAngleChanged;
  // screenX, screenY, worldX, worldY, canvasWidth, canvasHeight
  final Function(double, double, double, double, double, double)
      onCrosshairChanged;
  final CrosshairController? controller;

  const CalibrationCanvas({
    super.key,
    required this.angle,
    required this.calibrationSystem,
    required this.videoController,
    required this.onAngleChanged,
    required this.onCrosshairChanged,
    this.controller,
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

  // Tracks the last canvas size we reported up to the parent, so it can be
  // re-reported (with a fresh world-coordinate) on first layout and on any
  // later resize/orientation change — not just when the crosshair is dragged.
  double? _lastReportedW;
  double? _lastReportedH;

  // Drag hit threshold (larger for touch screens to make it easy)
  final double _hitBoxThreshold = 35.0;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(_nudgeCrosshair, _resetCrosshairToCenter);
  }

  @override
  void didUpdateWidget(covariant CalibrationCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach();
      widget.controller?._attach(_nudgeCrosshair, _resetCrosshairToCenter);
    }
  }

  @override
  void dispose() {
    widget.controller?._detach();
    super.dispose();
  }

  void _nudgeCrosshair(double dx, double dy) {
    // Locked once a centroid has been resolved, matching the draggable
    // reticle being hidden at that point.
    if (widget.calibrationSystem.centroid != null) return;
    final w = _lastReportedW;
    final h = _lastReportedH;
    if (w == null || h == null || _cx == null || _cy == null) return;
    _updateCrosshairPosition(_cx! + dx, _cy! + dy, w, h);
  }

  void _resetCrosshairToCenter() {
    if (widget.calibrationSystem.centroid != null) return;
    final w = _lastReportedW;
    final h = _lastReportedH;
    if (w == null || h == null) return;
    _updateCrosshairPosition(w / 2.0, h / 2.0, w, h);
  }

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
    widget.onCrosshairChanged(_cx!, _cy!, worldPt.dx, worldPt.dy, W, H);
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

        // Report position/canvas-size on first layout and on any later
        // resize (rotation, tablet size change) — not just when the user
        // drags the crosshair — so "Take Reading" never uses a stale or
        // default screen position.
        if (_lastReportedW != W || _lastReportedH != H) {
          _lastReportedW = W;
          _lastReportedH = H;
          final reportCx = currentCx;
          final reportCy = currentCy;
          final reportAngle = widget.angle;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final worldPt = widget.calibrationSystem
                .screenToWorld(reportCx, reportCy, reportAngle, W, H);
            widget.onCrosshairChanged(
                reportCx, reportCy, worldPt.dx, worldPt.dy, W, H);
          });
        }

        final bool locked = widget.calibrationSystem.centroid != null;

        return GestureDetector(
          onPanStart: locked
              ? null
              : (details) {
                  final touchPt = details.localPosition;
                  final distance = math.sqrt(
                      math.pow(touchPt.dx - currentCx, 2) +
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

              // Rotate viewport relative to touch movement, wrapped to the
              // -180..180 range instead of 0..360.
              final double newAngle =
                  ((widget.angle - deltaX * 0.5 + 180.0) % 360.0) - 180.0;
              widget.onAngleChanged(newAngle);

              // Recalculate coordinates under crosshair
              final worldPt = widget.calibrationSystem
                  .screenToWorld(currentCx, currentCy, newAngle, W, H);
              widget.onCrosshairChanged(
                  currentCx, currentCy, worldPt.dx, worldPt.dy, W, H);
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
              // 1. Background — media_kit Video, or an idle placeholder
              if (widget.videoController != null)
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
                  alignment: Alignment.center,
                  child: const Text(
                    'NOT CONNECTED',
                    style: TextStyle(
                      color: Color(0xFF444444),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      letterSpacing: 1.0,
                    ),
                  ),
                ),

              // 2. Custom Painter Overlays (HUD, crosshairs, centroid)
              Positioned.fill(
                child: CustomPaint(
                  painter: CalibrationPainter(
                    isConnected: widget.videoController != null,
                    angle: widget.angle,
                    crosshairX: currentCx,
                    crosshairY: currentCy,
                    calibrationSystem: widget.calibrationSystem,
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
  final bool isConnected;
  final double angle;
  final double crosshairX;
  final double crosshairY;
  final CalibrationSystem calibrationSystem;
  final bool draggingCrosshair;

  CalibrationPainter({
    required this.isConnected,
    required this.angle,
    required this.crosshairX,
    required this.crosshairY,
    required this.calibrationSystem,
    required this.draggingCrosshair,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double W = size.width;
    final double H = size.height;
    final double cx = W / 2.0;
    final double cy = H / 2.0;

    // --- 1. RENDER STATIC CENTRAL HUD GUIDELINES ---
    final hudPaint = Paint()
      ..color = const Color(0x10FFFFFF)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(0, cy), Offset(W, cy), hudPaint);
    canvas.drawLine(Offset(cx, 0), Offset(cx, H), hudPaint);

    // --- 2. RENDER LOGGED CALIBRATION READINGS (Cyan dots) ---
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

    // --- 3. RENDER CALIBRATED PIVOT CENTROID (thin plus-sign, no label) ---
    if (calibrationSystem.centroid != null) {
      final centroidWorld = calibrationSystem.centroid!;
      final centroidScreen = calibrationSystem.worldToScreen(
          centroidWorld.dx, centroidWorld.dy, angle, W, H);

      final greenPaint = Paint()
        ..color = const Color(0xFF00FF66)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;

      const double armLen = 14.0;
      canvas.drawLine(
          Offset(centroidScreen.dx - armLen, centroidScreen.dy),
          Offset(centroidScreen.dx + armLen, centroidScreen.dy),
          greenPaint);
      canvas.drawLine(
          Offset(centroidScreen.dx, centroidScreen.dy - armLen),
          Offset(centroidScreen.dx, centroidScreen.dy + armLen),
          greenPaint);
    }

    // --- 4. RENDER ACTIVE TARGETING RETICLE (Draggable crosshair) ---
    // Hidden once a centroid has been resolved — only the plus-sign
    // marker above should remain on screen at that point.
    if (calibrationSystem.centroid == null) {
      final Color boxColor = draggingCrosshair
          ? const Color(0xFF00FF66)
          : const Color(0xFFFFCC00);
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
    }

    // --- 5. TELEMETRY CORNER OVERLAYS ---
    // Top-Left: REC / connection state
    final modeText = isConnected ? "● REC [LIVE]" : "○ NOT CONNECTED";
    final modePainter = TextPainter(
      text: TextSpan(
        text: modeText,
        style: TextStyle(
            color: isConnected
                ? const Color(0xFFFF3B30)
                : const Color(0xFF666666),
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
    return oldDelegate.isConnected != isConnected ||
        oldDelegate.angle != angle ||
        oldDelegate.crosshairX != crosshairX ||
        oldDelegate.crosshairY != crosshairY ||
        oldDelegate.draggingCrosshair != draggingCrosshair ||
        oldDelegate.calibrationSystem.readings.length !=
            calibrationSystem.readings.length ||
        oldDelegate.calibrationSystem.centroid != calibrationSystem.centroid;
  }
}
