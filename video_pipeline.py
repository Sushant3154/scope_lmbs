import time
import cv2
from PySide6.QtCore import QThread, Signal, Qt
from PySide6.QtGui import QImage

class VideoPipelineThread(QThread):
    # Signals to communicate with the main thread
    frame_ready = Signal(QImage)
    status_changed = Signal(str)  # "connecting", "connected", "disconnected", "error"
    metrics_updated = Signal(float, int)  # fps, frame_count

    def __init__(self, rtsp_url="rtsp://192.168.1.141:1945/"):
        super().__init__()
        self.rtsp_url = rtsp_url
        self.running = False
        self.frame_count = 0
        self.fps = 0.0

    def run(self):
        self.running = True
        self.status_changed.emit("connecting")
        
        cap = cv2.VideoCapture(self.rtsp_url)
        
        # Set buffer size and timeout properties if supported
        cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
        
        if not cap.isOpened():
            self.status_changed.emit("error")
            self.running = False
            return

        self.status_changed.emit("connected")
        
        last_time = time.time()
        fps_frame_count = 0
        
        while self.running:
            ret, frame = cap.read()
            if not ret:
                self.status_changed.emit("disconnected")
                # Try to reconnect
                cap.release()
                time.sleep(2)
                cap = cv2.VideoCapture(self.rtsp_url)
                if not cap.isOpened():
                    self.status_changed.emit("error")
                    break
                self.status_changed.emit("connected")
                continue
                
            self.frame_count += 1
            fps_frame_count += 1
            
            # Calculate FPS every 1 second
            current_time = time.time()
            elapsed = current_time - last_time
            if elapsed >= 1.0:
                self.fps = fps_frame_count / elapsed
                fps_frame_count = 0
                last_time = current_time
                self.metrics_updated.emit(self.fps, self.frame_count)
            
            # Convert OpenCV BGR frame to RGB QImage
            height, width, channel = frame.shape
            bytes_per_line = channel * width
            q_img = QImage(frame.data, width, height, bytes_per_line, QImage.Format_BGR888)
            # Need to copy the image because frame buffer is reused by opencv
            q_img_copy = q_img.copy()
            
            self.frame_ready.emit(q_img_copy)
            
            # Yield CPU execution
            self.msleep(10)

        cap.release()
        self.status_changed.emit("disconnected")

    def stop(self):
        self.running = False
        self.wait()
