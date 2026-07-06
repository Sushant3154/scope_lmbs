import math
from PySide6.QtGui import QPainter, QColor, QPen, QFont, QBrush
from PySide6.QtCore import Qt, QPointF, QRectF

class RotatingFloorSimulator:
    def __init__(self, camera_radius=150.0):
        self.R = camera_radius
        
        # True offset of the pivot in the world (adds a realistic calibration offset)
        self.true_pivot_x = 12.0
        self.true_pivot_y = -8.0
        
        # Features on the floor in world coordinates (relative to the true pivot)
        # We place them at the camera radius so they will align perfectly at specific angles.
        self.features = [
            {"name": "TILE_CORNER_N", "x": 0.0, "y": -self.R},
            {"name": "TILE_CORNER_E", "x": self.R, "y": 0.0},
            {"name": "TILE_CORNER_S", "x": 0.0, "y": self.R},
            {"name": "TILE_CORNER_W", "x": -self.R, "y": 0.0},
            # Some other clutter features
            {"name": "ANCHOR_POINT_A", "x": 100.0, "y": 100.0},
            {"name": "ANCHOR_POINT_B", "x": -80.0, "y": -120.0},
        ]

    def paint_simulation(self, painter: QPainter, width: int, height: int, camera_angle_deg: float):
        """
        Draws the simulated rotating floor on the canvas using a QPainter.
        """
        cx = width / 2.0
        cy = height / 2.0
        
        # Draw background
        painter.fillRect(0, 0, width, height, QColor("#090B0D"))
        
        # Save painter state
        painter.save()
        
        # Enable antialiasing
        painter.setRenderHint(QPainter.RenderHint.Antialiasing, True)
        
        # Map world coordinates (x_w, y_w) to camera sensor coordinates (x_local, y_local)
        # and then to screen.
        theta = math.radians(camera_angle_deg)
        cos_t = math.cos(theta)
        sin_t = math.sin(theta)
        
        # --- Draw Rotating Grid ---
        # To draw a grid, we can project grid lines into the camera frame.
        grid_size = 80
        grid_pen = QPen(QColor(255, 255, 255, 12), 1, Qt.PenStyle.DashLine)
        painter.setPen(grid_pen)
        
        # Draw floor grid lines in world coordinates:
        # For simplicity, we draw lines in world coordinates from -600 to 600
        for g in range(-480, 481, grid_size):
            # Horizontal lines (constant y_w)
            # We draw them as series of line segments or just project start and end points
            pt_start_h = self.world_to_screen(-640, g, cos_t, sin_t, cx, cy)
            pt_end_h = self.world_to_screen(640, g, cos_t, sin_t, cx, cy)
            painter.drawLine(pt_start_h, pt_end_h)
            
            # Vertical lines (constant x_w)
            pt_start_v = self.world_to_screen(g, -480, cos_t, sin_t, cx, cy)
            pt_end_v = self.world_to_screen(g, 480, cos_t, sin_t, cx, cy)
            painter.drawLine(pt_start_v, pt_end_v)
            
        # Draw the true pivot indicator (just for verification, very faint, or hidden)
        pivot_screen = self.world_to_screen(self.true_pivot_x, self.true_pivot_y, cos_t, sin_t, cx, cy)
        painter.setPen(QPen(QColor("#00FF66", 25), 1))
        painter.setBrush(Qt.BrushStyle.NoBrush)
        painter.drawCircle(pivot_screen, 4)
        
        # --- Draw Floor Features ---
        font = QFont("Consolas", 8)
        painter.setFont(font)
        
        for feature in self.features:
            # Feature world position is relative to true pivot
            world_x = self.true_pivot_x + feature["x"]
            world_y = self.true_pivot_y + feature["y"]
            
            screen_pos = self.world_to_screen(world_x, world_y, cos_t, sin_t, cx, cy)
            
            # Skip drawing if feature is far off-screen
            if not (0 <= screen_pos.x() <= width and 0 <= screen_pos.y() <= height):
                continue
                
            # Draw feature point marker (orange cross / dot)
            painter.setPen(QPen(QColor("#FF9900", 180), 2))
            # Draw + shape
            painter.drawLine(screen_pos.x() - 6, screen_pos.y(), screen_pos.x() + 6, screen_pos.y())
            painter.drawLine(screen_pos.x(), screen_pos.y() - 6, screen_pos.x(), screen_pos.y() + 6)
            
            # Label
            painter.setPen(QColor("#CCCCCC"))
            painter.drawText(screen_pos.x() + 8, screen_pos.y() + 4, f"{feature['name']}")
            
        # Restore painter state
        painter.restore()

    def world_to_screen(self, world_x: float, world_y: float, cos_t: float, sin_t: float, cx: float, cy: float) -> QPointF:
        """Helper to transform world coordinates to screen coordinate points."""
        x_local = world_x * cos_t + world_y * sin_t - self.R
        y_local = -world_x * sin_t + world_y * cos_t
        return QPointF(cx + x_local, cy + y_local)
