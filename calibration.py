import math

class CalibrationSystem:
    def __init__(self, camera_radius=150.0):
        """
        Initialize the calibration system.
        :param camera_radius: Distance R from the center of rotation to the camera center (in pixels).
        """
        self.R = camera_radius
        self.readings = []  # List of dicts: {"angle": float, "screen_x": float, "screen_y": float, "world_x": float, "world_y": float}
        self.centroid = None  # Tuple: (X_centroid, Y_centroid) in world coordinates

    def add_reading(self, angle_deg, screen_x, screen_y, W, H):
        """
        Calculate the absolute world coordinate of the point under the screen coordinate (screen_x, screen_y)
        at the current camera angle and store it.
        """
        # Convert screen to world coordinate
        x_w, y_w = self.screen_to_world(screen_x, screen_y, angle_deg, W, H)
        
        reading = {
            "angle": angle_deg,
            "screen_x": screen_x,
            "screen_y": screen_y,
            "world_x": x_w,
            "world_y": y_w
        }
        self.readings.append(reading)
        return reading

    def calculate_centroid(self):
        """
        Compute the centroid (geometric mean) of all logged world points.
        $$X_{centroid} = \\frac{1}{n}\\sum x_i, \\quad Y_{centroid} = \\frac{1}{n}\\sum y_i$$
        """
        if len(self.readings) < 4:
            self.centroid = None
            return None

        n = len(self.readings)
        sum_x = sum(r["world_x"] for r in self.readings)
        sum_y = sum(r["world_y"] for r in self.readings)
        
        self.centroid = (sum_x / n, sum_y / n)
        return self.centroid

    def clear(self):
        """Reset the calibration state."""
        self.readings.clear()
        self.centroid = None

    def screen_to_world(self, screen_x, screen_y, angle_deg, W, H):
        """
        Transform screen coordinates (pixel) to world coordinates (floor) relative to the pivot.
        """
        x_local = screen_x - W / 2.0
        y_local = screen_y - H / 2.0
        
        theta = math.radians(angle_deg)
        
        # Transformation:
        x_w = self.R * math.cos(theta) + x_local * math.cos(theta) - y_local * math.sin(theta)
        y_w = self.R * math.sin(theta) + x_local * math.sin(theta) + y_local * math.cos(theta)
        return x_w, y_w

    def world_to_screen(self, world_x, world_y, angle_deg, W, H):
        """
        Project world coordinates (floor) back to camera screen coordinates (pixel) at the given angle.
        """
        theta = math.radians(angle_deg)
        
        # Inverse Transformation:
        x_local = world_x * math.cos(theta) + world_y * math.sin(theta) - self.R
        y_local = -world_x * math.sin(theta) + world_y * math.cos(theta)
        
        screen_x = W / 2.0 + x_local
        screen_y = H / 2.0 + y_local
        return screen_x, screen_y
