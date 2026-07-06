import 'dart:math' as math;
import 'package:flutter/painting.dart';

class SimulatorFeature {
  final String name;
  final double x;
  final double y;

  SimulatorFeature({
    required this.name,
    required this.x,
    required this.y,
  });
}

class RotatingFloorSimulator {
  final double cameraRadius;
  
  // True offset of the pivot in the world (adds a realistic calibration offset)
  final double truePivotX = 12.0;
  final double truePivotY = -8.0;
  
  late final List<SimulatorFeature> features;

  RotatingFloorSimulator({this.cameraRadius = 150.0}) {
    // Features on the floor in world coordinates (relative to the true pivot)
    features = [
      SimulatorFeature(name: "TILE_CORNER_N", x: 0.0, y: -cameraRadius),
      SimulatorFeature(name: "TILE_CORNER_E", x: cameraRadius, y: 0.0),
      SimulatorFeature(name: "TILE_CORNER_S", x: 0.0, y: cameraRadius),
      SimulatorFeature(name: "TILE_CORNER_W", x: -cameraRadius, y: 0.0),
      SimulatorFeature(name: "ANCHOR_POINT_A", x: 100.0, y: 100.0),
      SimulatorFeature(name: "ANCHOR_POINT_B", x: -80.0, y: -120.0),
    ];
  }

  /// Helper to transform world coordinates to screen coordinate points.
  Offset worldToScreen(double worldX, double worldY, double cosT, double sinT, double cx, double cy) {
    final double xLocal = worldX * cosT + worldY * sinT - cameraRadius;
    final double yLocal = -worldX * sinT + worldY * cosT;
    return Offset(cx + xLocal, cy + yLocal);
  }

  /// Projects all features onto the screen based on the current camera angle and dimensions.
  List<Map<String, dynamic>> getProjectedFeatures(double angleDeg, double W, double H) {
    final double cx = W / 2.0;
    final double cy = H / 2.0;
    
    final double theta = angleDeg * math.pi / 180.0;
    final double cosT = math.cos(theta);
    final double sinT = math.sin(theta);
    
    final List<Map<String, dynamic>> projected = [];
    
    for (var feature in features) {
      final double worldX = truePivotX + feature.x;
      final double worldY = truePivotY + feature.y;
      
      final screenPos = worldToScreen(worldX, worldY, cosT, sinT, cx, cy);
      
      projected.add({
        'name': feature.name,
        'position': screenPos,
        'isOnScreen': screenPos.dx >= 0 && screenPos.dx <= W && screenPos.dy >= 0 && screenPos.dy <= H,
      });
    }
    
    return projected;
  }
  
  /// Projects the true pivot point onto the screen.
  Offset getProjectedPivot(double angleDeg, double W, double H) {
    final double cx = W / 2.0;
    final double cy = H / 2.0;
    
    final double theta = angleDeg * math.pi / 180.0;
    final double cosT = math.cos(theta);
    final double sinT = math.sin(theta);
    
    return worldToScreen(truePivotX, truePivotY, cosT, sinT, cx, cy);
  }
}
