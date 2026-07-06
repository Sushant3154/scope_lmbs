import 'dart:math' as math;
import 'package:flutter/painting.dart';

class CalibrationReading {
  final double angle;
  final double screenX;
  final double screenY;
  final double worldX;
  final double worldY;

  CalibrationReading({
    required this.angle,
    required this.screenX,
    required this.screenY,
    required this.worldX,
    required this.worldY,
  });

  Map<String, dynamic> toMap() {
    return {
      'angle': angle,
      'screen_x': screenX,
      'screen_y': screenY,
      'world_x': worldX,
      'world_y': worldY,
    };
  }
}

class CalibrationSystem {
  double cameraRadius;
  final List<CalibrationReading> readings = [];
  Offset? centroid;

  CalibrationSystem({this.cameraRadius = 150.0});

  /// Calculate the absolute world coordinate of the point under the screen coordinate (screenX, screenY)
  /// at the current camera angle and store it.
  CalibrationReading addReading(double angleDeg, double screenX, double screenY, double W, double H) {
    final worldPt = screenToWorld(screenX, screenY, angleDeg, W, H);
    
    final reading = CalibrationReading(
      angle: angleDeg,
      screenX: screenX,
      screenY: screenY,
      worldX: worldPt.dx,
      worldY: worldPt.dy,
    );
    
    readings.add(reading);
    return reading;
  }

  /// Compute the centroid (geometric mean) of all logged world points.
  Offset? calculateCentroid() {
    if (readings.length < 4) {
      centroid = null;
      return null;
    }

    double sumX = 0;
    double sumY = 0;
    for (var r in readings) {
      sumX += r.worldX;
      sumY += r.worldY;
    }

    centroid = Offset(sumX / readings.length, sumY / readings.length);
    return centroid;
  }

  /// Reset the calibration state.
  void clear() {
    readings.clear();
    centroid = null;
  }

  /// Transform screen coordinates (pixel) to world coordinates (floor) relative to the pivot.
  Offset screenToWorld(double screenX, double screenY, double angleDeg, double W, double H) {
    final double xLocal = screenX - W / 2.0;
    final double yLocal = screenY - H / 2.0;
    
    final double theta = angleDeg * math.pi / 180.0;
    
    // Transformation:
    final double worldX = cameraRadius * math.cos(theta) + xLocal * math.cos(theta) - yLocal * math.sin(theta);
    final double worldY = cameraRadius * math.sin(theta) + xLocal * math.sin(theta) + yLocal * math.cos(theta);
    return Offset(worldX, worldY);
  }

  /// Project world coordinates (floor) back to camera screen coordinates (pixel) at the given angle.
  Offset worldToScreen(double worldX, double worldY, double angleDeg, double W, double H) {
    final double theta = angleDeg * math.pi / 180.0;
    
    // Inverse Transformation:
    final double xLocal = worldX * math.cos(theta) + worldY * math.sin(theta) - cameraRadius;
    final double yLocal = -worldX * math.sin(theta) + worldY * math.cos(theta);
    
    final double screenX = W / 2.0 + xLocal;
    final double screenY = H / 2.0 + yLocal;
    return Offset(screenX, screenY);
  }
}
