import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'calibration_system.dart';
import 'calibration_canvas.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Required by media_kit — must be called before runApp
  MediaKit.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const AITCalibrationApp());
}

class AITCalibrationApp extends StatelessWidget {
  const AITCalibrationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AIT LMBS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F1216),
        primaryColor: const Color(0xFF00FF66),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00FF66),
          secondary: Color(0xFF00FFFF),
          surface: Color(0xFF1E222B),
        ),
        textTheme: const TextTheme(
          bodyLarge:
              TextStyle(color: Color(0xFFCCCCCC), fontFamily: 'monospace'),
          bodyMedium:
              TextStyle(color: Color(0xFF888888), fontFamily: 'monospace'),
        ),
      ),
      home: const MainCalibrationScreen(),
    );
  }
}

class MainCalibrationScreen extends StatefulWidget {
  const MainCalibrationScreen({super.key});

  @override
  State<MainCalibrationScreen> createState() => _MainCalibrationScreenState();
}

class _MainCalibrationScreenState extends State<MainCalibrationScreen> {
  // Core Business Object
  final CalibrationSystem _calibrationSystem =
      CalibrationSystem(cameraRadius: 150.0);

  // RTSP Streaming States — media_kit Player + VideoController
  final TextEditingController _rtspUrlController =
      TextEditingController(text: 'rtsp://192.168.3.1/livestream');
  Player? _player;
  VideoController? _videoController;
  bool _isConnected = false;
  bool _isReconnecting = false;

  // Auto-reconnect / stall-detection state
  StreamSubscription? _errorSubscription;
  StreamSubscription? _positionSubscription;
  Timer? _watchdogTimer;
  Timer? _reconnectTimer;
  DateTime? _lastPositionUpdate;
  int _reconnectAttempts = 0;
  bool _manualDisconnect = true;
  static const Duration _stallThreshold = Duration(seconds: 8);
  static const int _maxAutoReconnectAttempts = 6;

  // Device-level network connectivity — independent of RTSP-specific
  // errors. While the device itself is offline, only a single "Device
  // Offline" notification should be shown; every other error is noise.
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isDeviceOffline = false;

  // Rotation & Coordinates
  double _cameraAngle = 0.0; // -180..180
  double _screenX = 0.0;
  double _screenY = 0.0;
  // Actual rendered size of the video canvas — must match what the
  // crosshair's screen coordinates were computed against, or "Take Reading"
  // ends up converting to world space around the wrong center point.
  double _canvasWidth = 640.0;

  // Crosshair fine-nudge joystick
  final CrosshairController _crosshairController = CrosshairController();
  int _joystickSpeed = 2; // 0 (finest) .. 5 (coarsest)
  double _canvasHeight = 480.0;

  @override
  void initState() {
    super.initState();
    _initConnectivity();
  }

  Future<void> _initConnectivity() async {
    final initial = await _connectivity.checkConnectivity();
    _handleConnectivityChange(initial);
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen(_handleConnectivityChange);
  }

  void _handleConnectivityChange(List<ConnectivityResult> results) {
    final offline =
        results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    if (offline == _isDeviceOffline) return;
    _isDeviceOffline = offline;
    if (!mounted) return;
    setState(() {});

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    if (offline) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Device Offline'),
          backgroundColor: Colors.red,
          duration: Duration(days: 1),
        ),
      );
    }
  }

  /// Shows a short, user-facing error message — suppressed entirely while
  /// the device is offline, since the "Device Offline" banner is the only
  /// notification that should be visible in that state.
  void _showError(String message) {
    if (!mounted || _isDeviceOffline) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void dispose() {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _watchdogTimer?.cancel();
    _errorSubscription?.cancel();
    _positionSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _rtspUrlController.dispose();
    _player?.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────
  // RTSP connect / disconnect / auto-reconnect
  // ──────────────────────────────────────────────────────────────

  /// Button handler — user-initiated connect/disconnect.
  Future<void> _toggleRtspStream() async {
    if (_isConnected || _isReconnecting) {
      await _disconnectStream();
    } else {
      _manualDisconnect = false;
      _reconnectAttempts = 0;
      await _connectStream();
    }
  }

  /// Tears down the current player without touching the manual/wakelock
  /// state — used both by manual disconnect and by auto-reconnect.
  Future<void> _teardownPlayer() async {
    await _errorSubscription?.cancel();
    await _positionSubscription?.cancel();
    _errorSubscription = null;
    _positionSubscription = null;
    final p = _player;
    _player = null;
    if (mounted) {
      setState(() {
        _videoController = null;
        _isConnected = false;
      });
    } else {
      _videoController = null;
      _isConnected = false;
    }
    try {
      await p?.stop();
      await p?.dispose();
    } catch (_) {
      // Player may already be in a torn-down state after a connection drop.
    }
  }

  Future<void> _disconnectStream() async {
    debugPrint("RTSP: Disconnecting stream (manual)...");
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _watchdogTimer?.cancel();
    _reconnectAttempts = 0;
    if (mounted) setState(() => _isReconnecting = false);
    await _teardownPlayer();
    await WakelockPlus.disable();
  }

  /// Called when the stream errors out or is detected as stalled.
  /// Tears down the dead player and schedules an automatic reconnect,
  /// unless the user explicitly disconnected.
  Future<void> _handleStreamDrop(String reason) async {
    if (_manualDisconnect || _isReconnecting) return;
    debugPrint("RTSP: Stream drop detected ($reason). Will auto-reconnect.");
    _watchdogTimer?.cancel();
    if (mounted) setState(() => _isReconnecting = true);
    await _teardownPlayer();
    if (_manualDisconnect) return;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_manualDisconnect) return;
    _reconnectAttempts++;

    if (_reconnectAttempts > _maxAutoReconnectAttempts) {
      // Stop hammering a camera that may have a fragile embedded RTSP
      // server — repeated rapid reconnects can wedge cheap IP cameras
      // until they're power-cycled. Hand control back to the user instead
      // of retrying forever.
      debugPrint(
          "RTSP: Giving up after $_maxAutoReconnectAttempts automatic attempts.");
      if (mounted) setState(() => _isReconnecting = false);
      _showError("Unable to connect. Check the camera, then tap Connect.");
      return;
    }

    // Gentle, growing backoff instead of a tight retry loop.
    final delaySeconds = math.min(3 * _reconnectAttempts, 20);
    debugPrint(
        "RTSP: Reconnect attempt #$_reconnectAttempts in ${delaySeconds}s...");
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (_manualDisconnect || !mounted) return;
      _connectStream();
    });
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_isConnected || _manualDisconnect || _isReconnecting) return;
      final last = _lastPositionUpdate;
      if (last != null && DateTime.now().difference(last) > _stallThreshold) {
        _handleStreamDrop(
            'no frames for ${_stallThreshold.inSeconds}s — stream stuck');
      }
    });
  }

  Future<void> _connectStream() async {
    final url = _rtspUrlController.text.trim();
    if (url.isEmpty) return;
    debugPrint("RTSP: Attempting connection to: $url");

    final player = Player();
    final controller = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );

    // Low-latency tuning for live RTSP (libmpv native properties)
    try {
      final platform = player.platform as dynamic;
      // Hardware decode (mediacodec) fails to configure on target devices
      // for this camera's stream (MediaCodec BAD_VALUE on CONFIGURING — a
      // chip/driver-level incompatibility). Software decoding is slower but
      // reliable, so use it directly instead of a guaranteed first failure.
      await platform.setProperty('hwdec', 'no');
      await platform.setProperty('rtsp_transport', 'tcp');
      await platform.setProperty('profile', 'low-latency');
      await platform.setProperty('cache', 'no');
      await platform.setProperty(
          'demuxer-max-bytes', '1048576'); // small jitter cushion
      await platform.setProperty(
          'demuxer-max-back-bytes', '0'); // free past frames immediately
      await platform.setProperty(
          'untimed', 'yes'); // decode and display frames instantly
      await platform.setProperty(
          'framedrop', 'vo'); // drop late frames to stay live
      await platform.setProperty('vd-lavc-threads',
          '1'); // single-thread decoding for lower overhead
      await platform.setProperty(
          'network-timeout', '8000'); // tolerate brief Wi-Fi hiccups
      debugPrint("RTSP: Connection properties configured successfully.");
    } catch (e) {
      debugPrint("RTSP Warning: Failed to set connection properties: $e");
    }

    _errorSubscription = player.stream.error.listen((err) {
      final errString = err.toString().toLowerCase();
      // Ignore non-fatal seek warnings for live streams
      if (errString.contains('seek') || errString.contains('seekable')) {
        debugPrint("RTSP (Ignored non-fatal warning): $err");
        return;
      }

      debugPrint("RTSP Player Stream Error: $err");
      _showError('Failed to connect — retrying...');
      _handleStreamDrop('error: $err');
    });

    _positionSubscription = player.stream.position.listen((_) {
      _lastPositionUpdate = DateTime.now();
      // player.open() resolving only means the OPEN command was accepted —
      // not that frames are actually decoding. Only a real position update
      // proves the stream is alive, so only reset the backoff here.
      if (_reconnectAttempts != 0) {
        debugPrint("RTSP: Stream confirmed stable — reconnect backoff reset.");
        _reconnectAttempts = 0;
      }
    });

    try {
      await player.open(Media(url), play: true);
      debugPrint("RTSP: Media open call executed.");
    } catch (e) {
      debugPrint("RTSP Error: Failed to open media: $e");
      await player.dispose();
      if (_reconnectAttempts == 0) _showError('Failed to connect');
      _handleStreamDrop('open failed: $e');
      return;
    }

    _lastPositionUpdate = DateTime.now();
    await WakelockPlus.enable(); // keep screen/CPU awake so Android doesn't kill the socket

    if (!mounted) return;
    setState(() {
      _player = player;
      _videoController = controller;
      _isConnected = true;
      _isReconnecting = false;
    });

    _startWatchdog();
  }

  // ──────────────────────────────────────────────────────────────
  // Calibration actions
  // ──────────────────────────────────────────────────────────────
  void _onCrosshairChanged(double screenX, double screenY, double worldX,
      double worldY, double canvasWidth, double canvasHeight) {
    setState(() {
      _screenX = screenX;
      _screenY = screenY;
      _canvasWidth = canvasWidth;
      _canvasHeight = canvasHeight;
    });
  }

  void _addReading() {
    setState(() {
      _calibrationSystem.addReading(
          _cameraAngle, _screenX, _screenY, _canvasWidth, _canvasHeight);
    });
  }

  void _calculateCenter() {
    setState(() {
      final centroid = _calibrationSystem.calculateCentroid();
      if (centroid != null) {
        // Clear the individual point markers — only the resolved centroid
        // crosshair should remain on screen.
        _calibrationSystem.readings.clear();
      }
    });
  }

  void _clearReadings() {
    setState(() {
      _calibrationSystem.clear();
    });
  }

  // ──────────────────────────────────────────────────────────────
  // UI
  // ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final sidebarWidth = (screenWidth * 0.26).clamp(260.0, 380.0);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 40,
        titleSpacing: 12,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/image.png', width: 22, height: 22),
            const SizedBox(width: 8),
            const Text(
              'AIT LMBS',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
                fontSize: 14,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E222B),
        elevation: 0,
        shape: const Border(
          bottom: BorderSide(color: Color(0xFF2D333F), width: 1),
        ),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: CalibrationCanvas(
              angle: _cameraAngle,
              calibrationSystem: _calibrationSystem,
              videoController: _videoController,
              controller: _crosshairController,
              onAngleChanged: (angle) {
                setState(() => _cameraAngle = angle);
              },
              onCrosshairChanged: _onCrosshairChanged,
            ),
          ),
          Container(width: 1, color: const Color(0xFF2D333F)),
          SizedBox(
            width: sidebarWidth,
            child: Container(
              color: const Color(0xFF1E222B),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: _buildControlSidebar(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlSidebar() {
    final readingsCount = _calibrationSystem.readings.length;
    final hasCentroid = _calibrationSystem.centroid != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // RTSP Connection
        _buildSectionHeader('RTSP CONNECTION'),
        const SizedBox(height: 8),
        TextField(
          controller: _rtspUrlController,
          style: const TextStyle(
              color: Colors.white, fontFamily: 'monospace', fontSize: 13),
          decoration: const InputDecoration(
            labelText: 'Stream Address String',
            labelStyle: TextStyle(color: Color(0xFF888888)),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF2D333F)),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF00FF66)),
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: _toggleRtspStream,
          style: ElevatedButton.styleFrom(
            backgroundColor: (_isConnected || _isReconnecting)
                ? const Color(0xFF801414)
                : const Color(0xFF2D333F),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: BorderSide(
                color: (_isConnected || _isReconnecting)
                    ? const Color(0xFFB31C1C)
                    : const Color(0xFF444E60),
              ),
            ),
          ),
          child: Text(
            _isReconnecting
                ? 'Reconnecting… (tap to cancel)'
                : (_isConnected ? 'Disconnect Stream' : 'Connect Stream'),
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
        const SizedBox(height: 16),

        // Action Buttons
        _buildSectionHeader('ACTIONS'),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: _addReading,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF005A2B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: const BorderSide(color: Color(0xFF00994D)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          child: const Text('Take Reading',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: readingsCount >= 4 ? _calculateCenter : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: readingsCount >= 4
                ? const Color(0xFF004C80)
                : const Color(0xFF14181F),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: BorderSide(
                color: readingsCount >= 4
                    ? const Color(0xFF0073C2)
                    : const Color(0xFF222833),
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          child: Text(
            'Calculate Center',
            style: TextStyle(
              color:
                  readingsCount >= 4 ? Colors.white : const Color(0xFF555555),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: _clearReadings,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF801414),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: const BorderSide(color: Color(0xFFB31C1C)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          child: const Text('Clear All Readings',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 16),

        // Yaw Angle — adjustable by dragging on the video canvas itself;
        // the slider bar UI was removed here at the user's request, but the
        // underlying angle state/logic is untouched.
        _buildSectionHeader('CAMERA ROTATION (360° YAW)'),
        const SizedBox(height: 16),

        // Crosshair fine-nudge joystick
        _buildSectionHeader('CROSSHAIR NUDGE'),
        const SizedBox(height: 8),
        const Text('Speed:'),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (level) {
            final selected = level == _joystickSpeed;
            return GestureDetector(
              onTap: hasCentroid
                  ? null
                  : () => setState(() => _joystickSpeed = level),
              child: Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFF00FF66)
                      : const Color(0xFF0F1216),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFF00FF66)
                        : const Color(0xFF2D333F),
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '$level',
                  style: TextStyle(
                    color: selected ? Colors.black : const Color(0xFF888888),
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 10),
        Center(child: _buildJoystickPad(hasCentroid)),
      ],
    );
  }

  Widget _buildJoystickPad(bool disabled) {
    // step size grows with speed level: 1px (finest) .. 11px (coarsest)
    final double step = (1 + _joystickSpeed * 2).toDouble();

    Widget dPadButton(IconData icon, VoidCallback onTap) {
      return SizedBox(
        width: 44,
        height: 44,
        child: ElevatedButton(
          onPressed: disabled ? null : onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2D333F),
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: const BorderSide(color: Color(0xFF444E60)),
            ),
          ),
          child: Icon(icon,
              color: disabled ? const Color(0xFF555555) : Colors.white,
              size: 20),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        dPadButton(
            Icons.keyboard_arrow_up, () => _crosshairController.nudge(0, -step)),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            dPadButton(Icons.keyboard_arrow_left,
                () => _crosshairController.nudge(-step, 0)),
            const SizedBox(width: 4),
            SizedBox(
              width: 44,
              height: 44,
              child: ElevatedButton(
                onPressed:
                    disabled ? null : () => _crosshairController.resetToCenter(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A1F26),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                    side: BorderSide(
                        color: disabled
                            ? const Color(0xFF222833)
                            : const Color(0xFF00FFFF)),
                  ),
                ),
                child: Icon(Icons.center_focus_strong,
                    color:
                        disabled ? const Color(0xFF555555) : const Color(0xFF00FFFF),
                    size: 18),
              ),
            ),
            const SizedBox(width: 4),
            dPadButton(Icons.keyboard_arrow_right,
                () => _crosshairController.nudge(step, 0)),
          ],
        ),
        const SizedBox(height: 4),
        dPadButton(
            Icons.keyboard_arrow_down, () => _crosshairController.nudge(0, step)),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFFA0AABF),
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
    );
  }
}
