import sys
import time
import math
from PySide6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QHBoxLayout, QVBoxLayout,
    QSplitter, QGroupBox, QLabel, QLineEdit, QPushButton, QSlider,
    QListWidget, QRadioButton, QButtonGroup, QFrame
)
from PySide6.QtGui import QPainter, QColor, QPen, QFont, QImage, QPixmap
from PySide6.QtCore import Qt, QPoint, QTimer, Slot, Signal

from calibration import CalibrationSystem
from simulator import RotatingFloorSimulator
from video_pipeline import VideoPipelineThread

class VideoCanvas(QWidget):
    crosshair_changed = Signal(float, float, float, float)  # screen_x, screen_y, world_x, world_y

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setMinimumSize(640, 480)
        self.current_frame = None
        self.is_simulator = True
        
        # Reference sizes and parameters
        self.camera_radius = 150.0
        self.simulator = RotatingFloorSimulator(camera_radius=self.camera_radius)
        self.calibration_system = CalibrationSystem(camera_radius=self.camera_radius)
        
        self.camera_angle = 0.0
        self.fps = 0.0
        self.frame_count = 0
        
        # Draggable Crosshair state
        self.crosshair_x = None
        self.crosshair_y = None
        self.crosshair_ratio_x = 0.5  # default to center
        self.crosshair_ratio_y = 0.5
        self.crosshair_moved = False
        self.dragging_crosshair = False
        self.dragging_rotation = False
        self.hovering_crosshair = False
        self.drag_offset_x = 0.0
        self.drag_offset_y = 0.0
        self.setMouseTracking(True)
        
        # For mouse drag rotation
        self.drag_start_x = 0
        
        # Telemetry timer for Simulator mode FPS
        self.sim_timer = QTimer(self)
        self.sim_timer.timeout.connect(self.update_sim_frame)
        self.sim_timer.start(33)  # ~30 FPS
        
        self.last_fps_time = time.time()
        self.fps_frame_count = 0

    def update_sim_frame(self):
        if self.is_simulator:
            self.frame_count += 1
            self.fps_frame_count += 1
            
            curr_time = time.time()
            elapsed = curr_time - self.last_fps_time
            if elapsed >= 1.0:
                self.fps = self.fps_frame_count / elapsed
                self.fps_frame_count = 0
                self.last_fps_time = curr_time
                
            self.update()

    def set_mode(self, is_simulator):
        self.is_simulator = is_simulator
        if is_simulator:
            self.sim_timer.start(33)
        else:
            self.sim_timer.stop()
            self.current_frame = None
        self.update()

    def update_frame(self, q_img):
        self.current_frame = q_img
        self.update()

    def update_metrics(self, fps, frame_count):
        if not self.is_simulator:
            self.fps = fps
            self.frame_count = frame_count

    def set_angle(self, angle):
        self.camera_angle = angle
        self.emit_crosshair_coordinates()
        self.update()

    def emit_crosshair_coordinates(self):
        if self.crosshair_x is None or self.crosshair_y is None:
            self.crosshair_x = self.width() / 2.0
            self.crosshair_y = self.height() / 2.0
        
        w_x, w_y = self.calibration_system.screen_to_world(
            self.crosshair_x, self.crosshair_y, self.camera_angle, self.width(), self.height()
        )
        self.crosshair_changed.emit(self.crosshair_x, self.crosshair_y, w_x, w_y)

    def reset_crosshair(self):
        self.crosshair_x = self.width() / 2.0
        self.crosshair_y = self.height() / 2.0
        self.crosshair_ratio_x = 0.5
        self.crosshair_ratio_y = 0.5
        self.crosshair_moved = False
        self.emit_crosshair_coordinates()
        self.update()

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self.crosshair_x = self.crosshair_ratio_x * self.width()
        self.crosshair_y = self.crosshair_ratio_y * self.height()
        self.emit_crosshair_coordinates()

    # Mouse Drag Gestures to Rotate Object or Drag Crosshair
    def mousePressEvent(self, event):
        if event.button() == Qt.MouseButton.LeftButton:
            pos = event.position()
            if self.crosshair_x is None or self.crosshair_y is None:
                self.crosshair_x = self.width() / 2.0
                self.crosshair_y = self.height() / 2.0
                
            dx = pos.x() - self.crosshair_x
            dy = pos.y() - self.crosshair_y
            
            # Detect click close to crosshair (25-pixel active region)
            if math.hypot(dx, dy) < 25.0:
                self.dragging_crosshair = True
                self.dragging_rotation = False
                self.drag_offset_x = dx
                self.drag_offset_y = dy
                self.crosshair_moved = True
                self.setCursor(Qt.CursorShape.ClosedHandCursor)
            else:
                self.dragging_crosshair = False
                self.dragging_rotation = True
                self.drag_start_x = pos.x()
                self.setCursor(Qt.CursorShape.SizeHorCursor)

    def mouseMoveEvent(self, event):
        pos = event.position()
        if self.dragging_crosshair:
            self.crosshair_x = max(0.0, min(float(self.width()), pos.x() - self.drag_offset_x))
            self.crosshair_y = max(0.0, min(float(self.height()), pos.y() - self.drag_offset_y))
            self.crosshair_ratio_x = self.crosshair_x / max(1.0, float(self.width()))
            self.crosshair_ratio_y = self.crosshair_y / max(1.0, float(self.height()))
            self.emit_crosshair_coordinates()
            self.update()
        elif self.dragging_rotation:
            current_x = pos.x()
            delta_x = current_x - self.drag_start_x
            self.drag_start_x = current_x
            
            new_angle = (self.camera_angle - delta_x * 0.5) % 360.0
            if new_angle < 0:
                new_angle += 360.0
                
            self.parentWidget().parentWidget().rotate_from_canvas(new_angle)
            self.emit_crosshair_coordinates()
        else:
            if self.crosshair_x is None or self.crosshair_y is None:
                self.crosshair_x = self.width() / 2.0
                self.crosshair_y = self.height() / 2.0
                
            dx = pos.x() - self.crosshair_x
            dy = pos.y() - self.crosshair_y
            if math.hypot(dx, dy) < 25.0:
                if not self.hovering_crosshair:
                    self.hovering_crosshair = True
                    self.update()
                self.setCursor(Qt.CursorShape.OpenHandCursor)
            else:
                if self.hovering_crosshair:
                    self.hovering_crosshair = False
                    self.update()
                self.setCursor(Qt.CursorShape.ArrowCursor)

    def mouseReleaseEvent(self, event):
        self.dragging_crosshair = False
        self.dragging_rotation = False
        pos = event.position()
        if self.crosshair_x is not None and self.crosshair_y is not None:
            dx = pos.x() - self.crosshair_x
            dy = pos.y() - self.crosshair_y
            if math.hypot(dx, dy) < 25.0:
                self.setCursor(Qt.CursorShape.OpenHandCursor)
                self.hovering_crosshair = True
            else:
                self.setCursor(Qt.CursorShape.ArrowCursor)
                self.hovering_crosshair = False
        else:
            self.setCursor(Qt.CursorShape.ArrowCursor)
        self.update()

    def paintEvent(self, event):
        painter = QPainter(self)
        W, H = self.width(), self.height()
        
        # 1. Render Video Feed or Simulator Background
        if self.is_simulator:
            self.simulator.paint_simulation(painter, W, H, self.camera_angle)
        else:
            if self.current_frame is not None:
                # Scale the image keeping aspect ratio
                scaled_img = self.current_frame.scaled(
                    self.size(),
                    Qt.AspectRatioMode.KeepAspectRatio,
                    Qt.TransformationMode.SmoothTransformation
                )
                # Center the image in the widget
                x_pos = (W - scaled_img.width()) // 2
                y_pos = (H - scaled_img.height()) // 2
                painter.fillRect(0, 0, W, H, QColor("#090B0D"))
                painter.drawImage(x_pos, y_pos, scaled_img)
            else:
                # Idle/Connecting screen
                painter.fillRect(0, 0, W, H, QColor("#090B0D"))
                painter.setPen(QPen(QColor("#00FF66"), 1))
                font = QFont("Consolas", 12, QFont.Weight.Bold)
                painter.setFont(font)
                painter.drawText(
                    self.rect(),
                    Qt.AlignmentFlag.AlignCenter,
                    "WAITING FOR RTSP VIDEO FEED..."
                )
        
        # Save painter state for overlays
        painter.save()
        painter.setRenderHint(QPainter.RenderHint.Antialiasing, True)
        
        # 2. Draw HUD Overlay (Grid alignment helper)
        hud_pen = QPen(QColor(255, 255, 255, 10), 1)
        painter.setPen(hud_pen)
        # Horizontal and Vertical center lines
        painter.drawLine(0, H // 2, W, H // 2)
        painter.drawLine(W // 2, 0, W // 2, H)
        
        # 3. Draw Draggable Targeting Reticle
        if self.crosshair_x is None or self.crosshair_y is None:
            self.crosshair_x = W / 2.0
            self.crosshair_y = H / 2.0
            
        cx, cy = self.crosshair_x, self.crosshair_y
        
        # Color & thickness based on interaction state
        if self.dragging_crosshair:
            box_color = QColor("#00FF66")  # Dragging: Green
            pen_width = 2
        elif self.hovering_crosshair:
            box_color = QColor("#00FFFF")  # Hover: Cyan
            pen_width = 2
        else:
            box_color = QColor("#FFCC00")  # Idle: Yellow
            pen_width = 1.5
            
        box_pen = QPen(box_color, pen_width)
        painter.setPen(box_pen)
        box_size = 40
        painter.drawRect(int(cx - box_size // 2), int(cy - box_size // 2), box_size, box_size)
        
        # Red center crosshair
        red_pen = QPen(QColor("#FF3B30"), 2)
        painter.setPen(red_pen)
        ch_len = 12
        painter.drawLine(int(cx - ch_len), int(cy), int(cx + ch_len), int(cy))  # Horizontal
        painter.drawLine(int(cx), int(cy - ch_len), int(cx), int(cy + ch_len))  # Vertical
        
        # Draw coordinates next to crosshair
        font_coords = QFont("Consolas", 8)
        painter.setFont(font_coords)
        if self.hovering_crosshair or self.dragging_crosshair:
            painter.setPen(QPen(QColor("#00FFFF"), 1))
        else:
            painter.setPen(QPen(QColor("#CCCCCC"), 1))
        
        w_x, w_y = self.calibration_system.screen_to_world(cx, cy, self.camera_angle, W, H)
        painter.drawText(int(cx) + 25, int(cy) + 15, f"Scr: ({int(cx)}, {int(cy)})\nWorld: ({w_x:.1f}, {w_y:.1f})")
        
        # 4. Draw Logged Readings (Cyan dots)
        for idx, reading in enumerate(self.calibration_system.readings):
            rx, ry = self.calibration_system.world_to_screen(
                reading["world_x"], reading["world_y"], self.camera_angle, W, H
            )
            
            # Point marker
            painter.setPen(QPen(QColor("#00FFFF"), 2))
            painter.setBrush(QColor("#00FFFF"))
            painter.drawEllipse(QPoint(int(rx), int(ry)), 3, 3)
            
            # Label
            font_lbl = QFont("Consolas", 8, QFont.Weight.Bold)
            painter.setFont(font_lbl)
            painter.setPen(QColor("#00FFFF"))
            painter.drawText(int(rx) + 6, int(ry) - 4, f"P{idx+1}")
            
        # 5. Draw Dynamic Calibrated Centroid Crosshair (Green)
        if self.calibration_system.centroid is not None:
            c_x, c_y = self.calibration_system.centroid
            # Project world coordinate back to screen
            scr_x, scr_y = self.calibration_system.world_to_screen(c_x, c_y, self.camera_angle, W, H)
            
            green_pen = QPen(QColor("#00FF66"), 2)
            painter.setPen(green_pen)
            
            # Draw circle target with dot
            painter.setBrush(Qt.BrushStyle.NoBrush)
            painter.drawEllipse(QPoint(int(scr_x), int(scr_y)), 15, 15)
            painter.setBrush(QColor("#00FF66"))
            painter.drawEllipse(QPoint(int(scr_x), int(scr_y)), 2, 2)
            
            # Draw outer cross lines
            painter.drawLine(int(scr_x) - 22, int(scr_y), int(scr_x) - 10, int(scr_y))
            painter.drawLine(int(scr_x) + 10, int(scr_y), int(scr_x) + 22, int(scr_y))
            painter.drawLine(int(scr_x), int(scr_y) - 22, int(scr_x), int(scr_y) - 10)
            painter.drawLine(int(scr_x), int(scr_y) + 10, int(scr_x), int(scr_y) + 22)
            
            # Label
            font = QFont("Consolas", 8, QFont.Weight.Bold)
            painter.setFont(font)
            painter.setPen(QColor("#00FF66"))
            painter.drawText(int(scr_x) + 18, int(scr_y) - 8, f"CALIB_ZERO ({c_x:.1f}, {c_y:.1f})")
            
        # 5. Display Telemetry Overlay text in corners
        font = QFont("Consolas", 9)
        painter.setFont(font)
        
        # Top-Left: Rec source
        painter.setPen(QColor("#FF3B30"))
        mode_text = "SIMULATOR_MODE" if self.is_simulator else "LIVE_RTSP_FEED"
        painter.drawText(15, 25, f"● REC [{mode_text}]")
        
        # Top-Right: FOV and Angle
        painter.setPen(QColor("#00FF66"))
        painter.drawText(W - 200, 25, f"AZ: {self.camera_angle:.1f}° | EL: 0.0°")
        
        # Bottom-Left: FPS and Frame metrics
        painter.setPen(QColor("#888888"))
        metrics_text = f"SYS: STABLE  |  FPS: {self.fps:.1f}  |  FRAMES: {self.frame_count}"
        painter.drawText(15, H - 25, metrics_text)
        
        # Bottom-Right: Time stamp
        time_str = time.strftime("SYS_TIME: %H:%M:%S")
        painter.drawText(W - 180, H - 25, time_str)
        
        painter.restore()


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("360° Desktop Calibration System")
        self.resize(1100, 700)
        
        # Application Stylesheet (Tactical Glass/Dark Theme)
        self.setStyleSheet("""
            QMainWindow {
                background-color: #0F1216;
            }
            QWidget#sidebar {
                background-color: #1E222B;
                border-left: 1px solid #2D333F;
            }
            QGroupBox {
                border: 1px solid #2D333F;
                border-radius: 6px;
                margin-top: 1.2em;
                font-weight: bold;
                color: #A0AABF;
                font-size: 11px;
                padding-top: 8px;
            }
            QGroupBox::title {
                subcontrol-origin: margin;
                left: 10px;
                padding: 0 4px 0 4px;
            }
            QLabel {
                color: #CCCCCC;
                font-size: 11px;
            }
            QLabel#lbl_title {
                font-weight: bold;
                font-size: 14px;
                color: #FFFFFF;
                letter-spacing: 1px;
            }
            QLabel#lbl_readings_count {
                font-size: 20px;
                font-weight: bold;
                color: #00FF66;
                font-family: 'Consolas', monospace;
            }
            QPushButton {
                background-color: #2D333F;
                color: #FFFFFF;
                border: 1px solid #444E60;
                border-radius: 4px;
                padding: 8px;
                font-weight: bold;
                font-size: 11px;
            }
            QPushButton:hover {
                background-color: #3B4555;
                border: 1px solid #5C6A80;
            }
            QPushButton:disabled {
                background-color: #14181F;
                color: #555555;
                border: 1px solid #222833;
            }
            QPushButton#btn_take_reading {
                background-color: #005A2B;
                border: 1px solid #00994D;
                color: #FFFFFF;
            }
            QPushButton#btn_take_reading:hover {
                background-color: #008040;
            }
            QPushButton#btn_calculate {
                background-color: #004C80;
                border: 1px solid #0073C2;
                color: #FFFFFF;
            }
            QPushButton#btn_calculate:hover {
                background-color: #0066AD;
            }
            QPushButton#btn_clear {
                background-color: #801414;
                border: 1px solid #B31C1C;
                color: #FFFFFF;
            }
            QPushButton#btn_clear:hover {
                background-color: #B31C1C;
            }
            QPushButton#btn_reset_crosshair {
                background-color: #1A1F26;
                border: 1px solid #3A4454;
                color: #A0AABF;
            }
            QPushButton#btn_reset_crosshair:hover {
                background-color: #232A34;
                border: 1px solid #00FFFF;
                color: #FFFFFF;
            }
            QLineEdit {
                background-color: #0F1216;
                border: 1px solid #2D333F;
                border-radius: 4px;
                padding: 5px;
                color: #FFFFFF;
                font-family: 'Consolas', monospace;
                font-size: 11px;
            }
            QLineEdit:focus {
                border: 1px solid #00FF66;
            }
            QSlider::groove:horizontal {
                border: 1px solid #2D333F;
                height: 6px;
                background: #0F1216;
                border-radius: 3px;
            }
            QSlider::handle:horizontal {
                background: #00FF66;
                border: 1px solid #00B347;
                width: 14px;
                margin: -4px 0;
                border-radius: 7px;
            }
            QListWidget {
                background-color: #0F1216;
                border: 1px solid #2D333F;
                border-radius: 4px;
                color: #00FF66;
                font-family: 'Consolas', monospace;
                font-size: 10px;
            }
            QRadioButton {
                color: #CCCCCC;
                font-size: 11px;
            }
            QRadioButton::indicator {
                width: 10px;
                height: 10px;
            }
        """)
        
        self.video_thread = None
        self.setup_ui()

    def setup_ui(self):
        # Base Splitter Layout
        splitter = QSplitter(Qt.Orientation.Horizontal)
        self.setCentralWidget(splitter)
        
        # Left Side: Video Canvas
        self.canvas = VideoCanvas(self)
        self.canvas.crosshair_changed.connect(self.update_crosshair_ui)
        splitter.addWidget(self.canvas)
        
        # Right Side: Sidebar Panel
        sidebar = QWidget()
        sidebar.setObjectName("sidebar")
        sidebar_layout = QVBoxLayout(sidebar)
        sidebar_layout.setContentsMargins(15, 15, 15, 15)
        
        # Title Header
        lbl_title = QLabel("360° RANGE CALIBRATION PANEL")
        lbl_title.setObjectName("lbl_title")
        lbl_subtitle = QLabel("TACTICAL PIVOT POSITIONING SYSTEM")
        lbl_subtitle.setStyleSheet("color: #666666; font-size: 9px; letter-spacing: 0.5px;")
        
        sidebar_layout.addWidget(lbl_title)
        sidebar_layout.addWidget(lbl_subtitle)
        
        # Group 1: Pipeline Mode Selection
        grp_mode = QGroupBox("OPERATION MODE")
        mode_layout = QHBoxLayout(grp_mode)
        self.rad_sim = QRadioButton("Virtual Simulator")
        self.rad_rtsp = QRadioButton("Live RTSP Feed")
        self.rad_sim.setChecked(True)
        
        self.mode_group = QButtonGroup(self)
        self.mode_group.addButton(self.rad_sim)
        self.mode_group.addButton(self.rad_rtsp)
        self.mode_group.buttonClicked.connect(self.mode_changed)
        
        mode_layout.addWidget(self.rad_sim)
        mode_layout.addWidget(self.rad_rtsp)
        sidebar_layout.addWidget(grp_mode)
        
        # Group 2: Live RTSP Stream Settings
        self.grp_rtsp = QGroupBox("RTSP CONNECTION")
        rtsp_layout = QVBoxLayout(self.grp_rtsp)
        
        self.txt_rtsp_url = QLineEdit("rtsp://192.168.1.141:1945/")
        self.btn_connect = QPushButton("Connect Stream")
        self.btn_connect.clicked.connect(self.toggle_stream)
        
        rtsp_layout.addWidget(QLabel("Stream Address String:"))
        rtsp_layout.addWidget(self.txt_rtsp_url)
        rtsp_layout.addWidget(self.btn_connect)
        sidebar_layout.addWidget(self.grp_rtsp)
        self.grp_rtsp.setEnabled(False)  # Simulator default
        
        # Group 3: Angle Controller (0 - 360)
        grp_angle = QGroupBox("CAMERA ROTATION (360° YAW)")
        angle_layout = QVBoxLayout(grp_angle)
        
        self.lbl_angle_val = QLabel("ANGLE: 0.0°")
        self.lbl_angle_val.setStyleSheet("font-family: 'Consolas'; font-size: 12px; font-weight: bold; color: #00FF66;")
        
        self.slider_angle = QSlider(Qt.Orientation.Horizontal)
        self.slider_angle.setRange(0, 3600)  # Multiplied by 10 for 0.1 deg precision
        self.slider_angle.setValue(0)
        self.slider_angle.valueChanged.connect(self.slider_changed)
        
        angle_layout.addWidget(self.lbl_angle_val)
        angle_layout.addWidget(self.slider_angle)
        sidebar_layout.addWidget(grp_angle)

        # Group 3.5: Interactive Crosshair Controls
        grp_crosshair = QGroupBox("INTERACTIVE CROSSHAIR")
        crosshair_layout = QVBoxLayout(grp_crosshair)
        
        self.lbl_crosshair_scr = QLabel("Screen: X=000, Y=000")
        self.lbl_crosshair_scr.setStyleSheet("font-family: 'Consolas'; font-size: 11px; color: #CCCCCC;")
        
        self.lbl_crosshair_world = QLabel("World:  X=+00.0, Y=+00.0")
        self.lbl_crosshair_world.setStyleSheet("font-family: 'Consolas'; font-size: 11px; color: #00FF66;")
        
        self.btn_reset_crosshair = QPushButton("Reset Crosshair to Center")
        self.btn_reset_crosshair.setObjectName("btn_reset_crosshair")
        self.btn_reset_crosshair.clicked.connect(self.canvas.reset_crosshair)
        
        crosshair_layout.addWidget(self.lbl_crosshair_scr)
        crosshair_layout.addWidget(self.lbl_crosshair_world)
        crosshair_layout.addWidget(self.btn_reset_crosshair)
        sidebar_layout.addWidget(grp_crosshair)
        
        # Group 4: Logged Calibration Readings
        grp_readings = QGroupBox("CALIBRATION LOG")
        readings_layout = QVBoxLayout(grp_readings)
        
        self.lbl_readings = QLabel("READINGS: 0")
        self.lbl_readings.setObjectName("lbl_readings_count")
        
        self.lst_readings = QListWidget()
        self.lst_readings.setMinimumHeight(150)
        
        readings_layout.addWidget(self.lbl_readings)
        readings_layout.addWidget(self.lst_readings)
        sidebar_layout.addWidget(grp_readings)
        
        # Group 5: Control Actions
        grp_actions = QGroupBox("ACTIONS")
        actions_layout = QVBoxLayout(grp_actions)
        
        self.btn_take_reading = QPushButton("Take Reading")
        self.btn_take_reading.setObjectName("btn_take_reading")
        self.btn_take_reading.clicked.connect(self.take_reading)
        
        self.btn_calculate = QPushButton("Calculate Center")
        self.btn_calculate.setObjectName("btn_calculate")
        self.btn_calculate.setEnabled(False)
        self.btn_calculate.clicked.connect(self.calculate_center)
        
        self.btn_clear = QPushButton("Clear All Readings")
        self.btn_clear.setObjectName("btn_clear")
        self.btn_clear.clicked.connect(self.clear_readings)
        
        actions_layout.addWidget(self.btn_take_reading)
        actions_layout.addWidget(self.btn_calculate)
        actions_layout.addWidget(self.btn_clear)
        sidebar_layout.addWidget(grp_actions)
        
        # Add Stretch at bottom
        sidebar_layout.addStretch()
        
        # Set sidebar width constraint
        sidebar.setMinimumWidth(320)
        sidebar.setMaximumWidth(400)
        
        splitter.addWidget(sidebar)
        splitter.setSizes([750, 350])

    @Slot(float, float, float, float)
    def update_crosshair_ui(self, screen_x, screen_y, world_x, world_y):
        self.lbl_crosshair_scr.setText(f"Screen: X={int(screen_x):03d}, Y={int(screen_y):03d}")
        self.lbl_crosshair_world.setText(f"World:  X={world_x:+.1f}, Y={world_y:+.1f}")

    def mode_changed(self, button):
        is_sim = (button == self.rad_sim)
        self.canvas.set_mode(is_sim)
        self.grp_rtsp.setEnabled(not is_sim)
        if is_sim:
            self.stop_rtsp_thread()
            self.btn_connect.setText("Connect Stream")
        else:
            self.canvas.update_frame(None)

    def rotate_from_canvas(self, angle_deg):
        self.slider_angle.blockSignals(True)
        self.slider_angle.setValue(int(angle_deg * 10))
        self.slider_angle.blockSignals(False)
        self.lbl_angle_val.setText(f"ANGLE: {angle_deg:.1f}°")
        self.canvas.set_angle(angle_deg)

    def slider_changed(self, val):
        angle = val / 10.0
        self.lbl_angle_val.setText(f"ANGLE: {angle:.1f}°")
        self.canvas.set_angle(angle)

    def take_reading(self):
        # We align features under the draggable crosshair
        if self.canvas.crosshair_x is None or self.canvas.crosshair_y is None:
            cx, cy = self.canvas.width() / 2.0, self.canvas.height() / 2.0
        else:
            cx, cy = self.canvas.crosshair_x, self.canvas.crosshair_y
            
        angle = self.canvas.camera_angle
        
        reading = self.canvas.calibration_system.add_reading(
            angle, cx, cy, self.canvas.width(), self.canvas.height()
        )
        
        count = len(self.canvas.calibration_system.readings)
        self.lbl_readings.setText(f"READINGS: {count}")
        
        item_text = f"#{count} | AZ: {reading['angle']:.1f}° | Scr: ({int(cx)}, {int(cy)}) | World: ({reading['world_x']:.1f}, {reading['world_y']:.1f})"
        self.lst_readings.addItem(item_text)
        
        # Validation rule: Enable Calculate Center only if n >= 4
        if count >= 4:
            self.btn_calculate.setEnabled(True)
            self.btn_calculate.setStyleSheet("background-color: #0073C2; border: 1px solid #00FF66; color: #FFFFFF;")
        else:
            self.btn_calculate.setEnabled(False)

    def calculate_center(self):
        centroid = self.canvas.calibration_system.calculate_centroid()
        if centroid is not None:
            # Clear logged marks (readings) but keep the calculated centroid
            self.canvas.calibration_system.readings.clear()
            self.lbl_readings.setText("READINGS: 0")
            self.btn_calculate.setEnabled(False)
            self.btn_calculate.setStyleSheet("")
            
            self.canvas.update()
            # Log center details in the list
            self.lst_readings.addItem(f"--- RESOLVED PIVOT CENTER ---")
            self.lst_readings.addItem(f"X_c: {centroid[0]:.2f} units")
            self.lst_readings.addItem(f"Y_c: {centroid[1]:.2f} units")
            self.lst_readings.scrollToBottom()

    def clear_readings(self):
        self.canvas.calibration_system.clear()
        self.lbl_readings.setText("READINGS: 0")
        self.lst_readings.clear()
        self.btn_calculate.setEnabled(False)
        self.btn_calculate.setStyleSheet("")
        self.canvas.update()

    def toggle_stream(self):
        if self.video_thread and self.video_thread.isRunning():
            self.stop_rtsp_thread()
            self.btn_connect.setText("Connect Stream")
            self.canvas.update_frame(None)
        else:
            url = self.txt_rtsp_url.text().strip()
            self.video_thread = VideoPipelineThread(url)
            self.video_thread.frame_ready.connect(self.canvas.update_frame)
            self.video_thread.metrics_updated.connect(self.canvas.update_metrics)
            self.video_thread.status_changed.connect(self.stream_status_changed)
            self.video_thread.start()
            self.btn_connect.setText("Disconnect Stream")

    def stream_status_changed(self, status):
        # We can update the connect button or show status bar text
        if status == "error":
            self.btn_connect.setText("Connect Stream (Error!)")
            self.stop_rtsp_thread()

    def stop_rtsp_thread(self):
        if self.video_thread:
            self.video_thread.stop()
            self.video_thread = None

    def closeEvent(self, event):
        self.stop_rtsp_thread()
        super().closeEvent(event)

if __name__ == "__main__":
    app = QApplication(sys.argv)
    window = MainWindow()
    window.show()
    sys.exit(app.exec())
