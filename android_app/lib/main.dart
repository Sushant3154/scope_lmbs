import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'calibration_system.dart';
import 'rotating_floor_simulator.dart';
import 'calibration_canvas.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Required by media_kit — must be called before runApp
  MediaKit.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
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
      title: '360° Calibration System',
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
  // Core Business Objects
  final CalibrationSystem _calibrationSystem =
      CalibrationSystem(cameraRadius: 150.0);
  final RotatingFloorSimulator _simulator =
      RotatingFloorSimulator(cameraRadius: 150.0);

  // RTSP Streaming States — media_kit Player + VideoController
  bool _isSimulator = true;
  final TextEditingController _rtspUrlController =
      TextEditingController(text: 'rtsp://192.168.1.141:1945/');
  Player? _player;
  VideoController? _videoController;
  bool _isConnected = false;

  // Rotation & Coordinates
  double _cameraAngle = 0.0;
  double _screenX = 0.0;
  double _screenY = 0.0;
  double _worldX = 0.0;
  double _worldY = 0.0;

  // Log Scroll Controller
  final ScrollController _logScrollController = ScrollController();

  @override
  void dispose() {
    _rtspUrlController.dispose();
    _logScrollController.dispose();
    _player?.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────
  // RTSP connect / disconnect
  // ──────────────────────────────────────────────────────────────
  Future<void> _toggleRtspStream() async {
    if (_isConnected) {
      // ── Disconnect ──
      debugPrint("RTSP: Disconnecting stream...");
      await _player?.stop();
      await _player?.dispose();
      setState(() {
        _player = null;
        _videoController = null;
        _isConnected = false;
      });
    } else {
      // ── Connect ──
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
        await platform.setProperty('hwdec', 'mediacodec'); // enable android hardware decoding
        await platform.setProperty('rtsp_transport', 'tcp');
        await platform.setProperty('profile', 'low-latency');
        await platform.setProperty('cache', 'no');
        await platform.setProperty(
            'demuxer-max-bytes', '8192'); // tiny read-ahead buffer
        await platform.setProperty(
            'demuxer-max-back-bytes', '0'); // free past frames immediately
        await platform.setProperty(
            'untimed', 'yes'); // decode and display frames instantly
        await platform.setProperty(
            'framedrop', 'vo'); // drop late frames to stay live
        await platform.setProperty('vd-lavc-threads',
            '1'); // single-thread decoding for lower overhead
        await platform.setProperty(
            'network-timeout', '5000'); // 5-second timeout
        debugPrint("RTSP: Connection properties configured successfully.");
      } catch (e) {
        debugPrint("RTSP Warning: Failed to set connection properties: $e");
      }

      player.stream.error.listen((err) {
        final errString = err.toString().toLowerCase();
        // Ignore non-fatal seek warnings for live streams
        if (errString.contains('seek') || errString.contains('seekable')) {
          debugPrint("RTSP (Ignored non-fatal warning): $err");
          return;
        }

        debugPrint("RTSP Player Stream Error: $err");
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('RTSP Error: $err'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      });

      try {
        await player.open(Media(url), play: true);
        debugPrint("RTSP: Media open call executed.");
      } catch (e) {
        debugPrint("RTSP Error: Failed to open media: $e");
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open stream: $e'),
            backgroundColor: Colors.red,
          ),
        );
        player.dispose();
        return;
      }

      setState(() {
        _player = player;
        _videoController = controller;
        _isConnected = true;
      });
    }
  }

  // ──────────────────────────────────────────────────────────────
  // Calibration actions
  // ──────────────────────────────────────────────────────────────
  void _addReading() {
    setState(() {
      _calibrationSystem.addReading(_cameraAngle, _screenX, _screenY, 640, 480);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _calculateCenter() {
    setState(() {
      _calibrationSystem.calculateCentroid();
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
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '360° CALIBRATION APP',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
            fontSize: 16,
            fontFamily: 'monospace',
          ),
        ),
        backgroundColor: const Color(0xFF1E222B),
        elevation: 0,
        shape: const Border(
          bottom: BorderSide(color: Color(0xFF2D333F), width: 1),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isTablet = constraints.maxWidth >= 750;

          if (isTablet) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: CalibrationCanvas(
                    isSimulator: _isSimulator,
                    angle: _cameraAngle,
                    calibrationSystem: _calibrationSystem,
                    simulator: _simulator,
                    videoController: _videoController,
                    onAngleChanged: (angle) {
                      setState(() => _cameraAngle = angle);
                    },
                    onCrosshairChanged: (sx, sy, wx, wy) {
                      setState(() {
                        _screenX = sx;
                        _screenY = sy;
                        _worldX = wx;
                        _worldY = wy;
                      });
                    },
                  ),
                ),
                Container(width: 1, color: const Color(0xFF2D333F)),
                SizedBox(
                  width: 380,
                  child: Container(
                    color: const Color(0xFF1E222B),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16.0),
                      child: _buildControlSidebar(),
                    ),
                  ),
                ),
              ],
            );
          } else {
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: constraints.maxHeight * 0.45,
                    child: CalibrationCanvas(
                      isSimulator: _isSimulator,
                      angle: _cameraAngle,
                      calibrationSystem: _calibrationSystem,
                      simulator: _simulator,
                      videoController: _videoController,
                      onAngleChanged: (angle) {
                        setState(() => _cameraAngle = angle);
                      },
                      onCrosshairChanged: (sx, sy, wx, wy) {
                        setState(() {
                          _screenX = sx;
                          _screenY = sy;
                          _worldX = wx;
                          _worldY = wy;
                        });
                      },
                    ),
                  ),
                  const Divider(color: Color(0xFF2D333F), height: 1),
                  Container(
                    color: const Color(0xFF1E222B),
                    padding: const EdgeInsets.all(16.0),
                    child: _buildControlSidebar(),
                  ),
                ],
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildControlSidebar() {
    final readingsCount = _calibrationSystem.readings.length;
    final hasCentroid = _calibrationSystem.centroid != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Section 1: Operation Mode
        _buildSectionHeader('OPERATION MODE'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildRadioButton(
                label: 'Simulator',
                isSelected: _isSimulator,
                onTap: () {
                  setState(() {
                    _isSimulator = true;
                    if (_isConnected) _toggleRtspStream();
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildRadioButton(
                label: 'Live RTSP',
                isSelected: !_isSimulator,
                onTap: () {
                  setState(() => _isSimulator = false);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Section 2: RTSP Connection
        if (!_isSimulator) ...[
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
              backgroundColor: _isConnected
                  ? const Color(0xFF801414)
                  : const Color(0xFF2D333F),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
                side: BorderSide(
                  color: _isConnected
                      ? const Color(0xFFB31C1C)
                      : const Color(0xFF444E60),
                ),
              ),
            ),
            child: Text(
              _isConnected ? 'Disconnect Stream' : 'Connect Stream',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Section 3: Action Buttons (Placed here below Operation Mode / RTSP Connection)
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

        // Section 4: Yaw Angle Slider
        _buildSectionHeader('CAMERA ROTATION (360° YAW)'),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Angle:'),
            Text(
              '${_cameraAngle.toStringAsFixed(1)}°',
              style: const TextStyle(
                color: Color(0xFF00FF66),
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3.0,
            activeTrackColor: const Color(0xFF00FF66),
            inactiveTrackColor: const Color(0xFF2D333F),
            thumbColor: const Color(0xFF00FF66),
            overlayColor: const Color(0x2500FF66),
          ),
          child: Slider(
            value: _cameraAngle,
            min: 0.0,
            max: 360.0,
            onChanged: (val) => setState(() => _cameraAngle = val),
          ),
        ),
        const SizedBox(height: 16),

        // Section 5: Interactive Crosshair Coordinates
        _buildSectionHeader('INTERACTIVE CROSSHAIR'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F1216),
            border: Border.all(color: const Color(0xFF2D333F)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Screen: X=${_screenX.toInt()}, Y=${_screenY.toInt()}'),
              const SizedBox(height: 4),
              Text(
                'World:  X=${_worldX.toStringAsFixed(1)}, Y=${_worldY.toStringAsFixed(1)}',
                style: const TextStyle(color: Color(0xFF00FF66)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Section 6: Calibration Log
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader('CALIBRATION LOG'),
            Text(
              'READINGS: $readingsCount',
              style: const TextStyle(
                color: Color(0xFF00FF66),
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 160,
          decoration: BoxDecoration(
            color: const Color(0xFF0F1216),
            border: Border.all(color: const Color(0xFF2D333F)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: readingsCount == 0 && !hasCentroid
              ? const Center(
                  child: Text(
                    'LOG IS EMPTY\n(Take at least 4 readings)',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF555555), fontSize: 11),
                  ),
                )
              : ListView.builder(
                  controller: _logScrollController,
                  padding: const EdgeInsets.all(8),
                  itemCount: readingsCount + (hasCentroid ? 3 : 0),
                  itemBuilder: (context, idx) {
                    if (idx < readingsCount) {
                      final r = _calibrationSystem.readings[idx];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Text(
                          '#${idx + 1} | AZ: ${r.angle.toStringAsFixed(1)}° | '
                          'Scr: (${r.screenX.toInt()}, ${r.screenY.toInt()}) | '
                          'World: (${r.worldX.toStringAsFixed(1)}, ${r.worldY.toStringAsFixed(1)})',
                          style: const TextStyle(
                              fontSize: 10.5, color: Color(0xFF00FFFF)),
                        ),
                      );
                    } else {
                      final offset = idx - readingsCount;
                      if (offset == 0) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 4.0),
                          child: Text(
                            '--- RESOLVED PIVOT CENTER ---',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11),
                          ),
                        );
                      } else if (offset == 1) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1.0),
                          child: Text(
                            'X_c: ${_calibrationSystem.centroid!.dx.toStringAsFixed(2)} units',
                            style: const TextStyle(
                                color: Color(0xFF00FF66),
                                fontSize: 11,
                                fontWeight: FontWeight.bold),
                          ),
                        );
                      } else {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1.0),
                          child: Text(
                            'Y_c: ${_calibrationSystem.centroid!.dy.toStringAsFixed(2)} units',
                            style: const TextStyle(
                                color: Color(0xFF00FF66),
                                fontSize: 11,
                                fontWeight: FontWeight.bold),
                          ),
                        );
                      }
                    }
                  },
                ),
        ),
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

  Widget _buildRadioButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2D333F) : const Color(0xFF0F1216),
          border: Border.all(
            color:
                isSelected ? const Color(0xFF00FF66) : const Color(0xFF2D333F),
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : const Color(0xFFCCCCCC),
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
