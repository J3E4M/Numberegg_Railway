import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:uuid/uuid.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';

import 'utils/server_config.dart';
import 'DisplayPictureScreen.dart';
import 'database/egg_database.dart';
import 'package:http_parser/http_parser.dart';
import 'services/supabase_service.dart';

const List<String> yoloClasses = [
  "egg", // class 0
  "egg1", // class 1
  "egg2", // class 2
];

/// ================== MODEL ==================
class Detection {
  final double x1, y1, x2, y2;
  final double confidence;
  final int cls;
  final String grade;

  Detection.fromJson(Map<String, dynamic> json)
      : x1 = (json['bbox']?['x1'] as num?)?.toDouble() ?? 0.0,
        y1 = (json['bbox']?['y1'] as num?)?.toDouble() ?? 0.0,
        x2 = (json['bbox']?['x2'] as num?)?.toDouble() ?? 0.0,
        y2 = (json['bbox']?['y2'] as num?)?.toDouble() ?? 0.0,
        confidence = (json['confidence'] as num?)?.toDouble() ?? 0.0,
        cls = (json['id'] as num?)?.toInt() ?? 0,
        grade = json['grade'] as String? ?? 'unknown';
}

/// ================== MAIN ==================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  runApp(const MyApp());
}

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      home: SelectImageScreen(),
    );
  }
}

/// ================== SELECT IMAGE SCREEN ==================
class SelectImageScreen extends StatefulWidget {
  const SelectImageScreen({super.key});

  @override
  State<SelectImageScreen> createState() => _SelectImageScreenState();
}

class _SelectImageScreenState extends State<SelectImageScreen> {
  bool isLoading = false;
  final ImagePicker _imagePicker = ImagePicker();
  int? _currentUserId;
  
  // Camera streaming variables
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  bool _controllerInitialized = false;
  CameraImage? _lastFrame;
  bool _isStreaming = false;
  int _frameCount = 0;
  bool _showCamera = false;
  
  // Live detection variables
  List<Detection> _liveDetections = [];
  bool _isProcessing = false;
  Timer? _detectionTimer;
  int _eggCount = 0;
  String _averageGrade = 'A-';

  @override
  void initState() {
    super.initState();
    _loadUserId().then((_) {
      _initializeCamera();
    });
  }

  @override
  void dispose() {
    _detectionTimer?.cancel();
    if (_isStreaming) {
      _controller.stopImageStream();
    }
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentUserId = prefs.getInt('user_id');
    });
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ไม่พบกล้องในอุปกรณ์')),
          );
        }
        return;
      }
      
      final firstCamera = cameras.first;
      
      _controller = CameraController(
        firstCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      _initializeControllerFuture = _controller.initialize().then((_) {
        _startFastStream();
        _startLiveDetection();
        setState(() {
          _controllerInitialized = true;
        });
      });
      
      setState(() {
        _showCamera = true;
      });
    } catch (e) {
      debugPrint("Camera initialization error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ไม่สามารถเปิดกล้องได้: $e')),
        );
      }
    }
  }

  void _startFastStream() {
    _controller.startImageStream((CameraImage image) {
      setState(() {
        _lastFrame = image;
        _frameCount++;
      });
    });
    setState(() => _isStreaming = true);
  }

  // Live detection every 3 seconds (reduced frequency)
  void _startLiveDetection() {
    _detectionTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (_lastFrame != null && !_isProcessing && !_isStreaming) {
        await _performLiveDetection();
      }
    });
  }

  Future<void> _performLiveDetection() async {
    if (_isProcessing || _lastFrame == null) return;
    
    setState(() => _isProcessing = true);
    
    try {
      // Use a smaller frame for faster processing
      final bytes = await _convertCameraImageToBytes(_lastFrame!);
      final fileName = 'live_frame_${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      final detections = await sendToYolo(bytes, fileName, userId: _currentUserId);
      
      if (mounted) {
        final detectionList = (detections['detection_results']['detections'] as List? ?? [])
            .map((e) => Detection.fromJson(e))
            .toList();
        
        setState(() {
          _liveDetections = detectionList;
          _eggCount = detectionList.length;
          _averageGrade = _calculateAverageGrade(detectionList);
        });
      }
    } catch (e) {
      debugPrint("Live detection error: $e");
      // Don't show error to user for live detection to avoid spam
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  String _calculateAverageGrade(List<Detection> detections) {
    if (detections.isEmpty) return 'เบอร์ 2';
    
    int totalGrade = 0;
    for (var d in detections) {
      switch (d.grade.toLowerCase()) {
        case 'grade0':
          totalGrade += 0;
          break;
        case 'grade1':
          totalGrade += 1;
          break;
        case 'grade2':
          totalGrade += 2;
          break;
        case 'grade3':
          totalGrade += 3;
          break;
        case 'grade4':
          totalGrade += 4;
          break;
        case 'grade5':
          totalGrade += 5;
          break;
        default:
          totalGrade += 2; // default to medium
      }
    }
    
    double avg = totalGrade / detections.length;
    if (avg <= 0.5) return 'เบอร์ 0';
    if (avg <= 1.5) return 'เบอร์ 1';
    if (avg <= 2.5) return 'เบอร์ 2';
    if (avg <= 3.5) return 'เบอร์ 3';
    if (avg <= 4.5) return 'เบอร์ 4';
    return 'เบอร์ 5';
  }

  Future<void> _captureFromStream() async {
    if (_lastFrame == null) return;

    try {
      setState(() { isLoading = true; });
      
      // Stop stream temporarily for capture
      if (_isStreaming) {
        await _controller.stopImageStream();
        setState(() => _isStreaming = false);
      }
      
      final bytes = await _convertCameraImageToBytes(_lastFrame!);
      final fileName = 'camera_capture_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final detections = await sendToYolo(bytes, fileName, userId: _currentUserId);

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DisplayPictureScreen(
            imageBytes: bytes,
            detections: (detections['detection_results']['detections'] as List? ?? [])
                .map((e) => Detection.fromJson(e))
                .toList(),
            imagePath: detections['image_info']['saved_path'] ?? fileName,
            railwayResponse: detections,
          ),
        ),
      );
    } catch (e) {
      debugPrint("Capture from stream error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ไม่สามารถจับภาพได้: $e')),
        );
      }
    } finally {
      if (mounted) setState(() { isLoading = false; });
    }
  }

  Future<Uint8List> _convertCameraImageToBytes(CameraImage cameraImage) async {
    final image = await _convertYUV420ToImage(cameraImage);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<ui.Image> _convertYUV420ToImage(CameraImage cameraImage) async {
    final width = cameraImage.width;
    final height = cameraImage.height;
    
    try {
      // Create a simple canvas-based approach
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      
      // Create a simple representation by drawing pixels
      final yPlane = cameraImage.planes[0];
      final uPlane = cameraImage.planes[1];
      final vPlane = cameraImage.planes[2];
      
      // Sample the image at lower resolution for performance
      final sampleRate = 4; // Process every 4th pixel
      
      for (int y = 0; y < height; y += sampleRate) {
        for (int x = 0; x < width; x += sampleRate) {
          final yIndex = y * yPlane.bytesPerRow + x;
          final uvIndex = (y ~/ 2) * uPlane.bytesPerRow + (x ~/ 2);
          
          final yValue = yPlane.bytes[yIndex];
          final uValue = uPlane.bytes[uvIndex];
          final vValue = vPlane.bytes[uvIndex];
          
          // YUV to RGB conversion
          double r = yValue + 1.402 * (vValue - 128);
          double g = yValue - 0.344 * (uValue - 128) - 0.714 * (vValue - 128);
          double b = yValue + 1.772 * (uValue - 128);
          
          // Clamp values
          r = r.clamp(0.0, 255.0);
          g = g.clamp(0.0, 255.0);
          b = b.clamp(0.0, 255.0);
          
          // Draw a small rectangle for each sampled pixel
          final paint = Paint()
            ..color = Color.fromARGB(255, r.round(), g.round(), b.round());
          
          canvas.drawRect(
            Rect.fromLTWH(x.toDouble(), y.toDouble(), sampleRate.toDouble(), sampleRate.toDouble()),
            paint,
          );
        }
      }
      
      final picture = recorder.endRecording();
      final image = await picture.toImage(width, height);
      return image;
      
    } catch (e) {
      debugPrint("YUV conversion error: $e");
      // Create a simple fallback image
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      
      final paint = Paint()..color = Colors.grey;
      canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), paint);
      
      final picture = recorder.endRecording();
      final image = await picture.toImage(width, height);
      return image;
    }
  }

  Future<void> _disposeCamera() async {
    try {
      _detectionTimer?.cancel();
      if (_isStreaming) {
        await _controller.stopImageStream();
        setState(() => _isStreaming = false);
      }
      if (_controller.value.isInitialized) {
        await _controller.dispose();
      }
      setState(() {
        _showCamera = false;
        _isStreaming = false;
      });
    } catch (e) {
      debugPrint("Dispose camera error: $e");
    }
  }

  Future<Map<String, dynamic>> sendToYolo(
    Uint8List bytes,
    String filename, {
    int? userId,
  }) async {
    try {
      Uint8List compressedBytes = await _compressImage(bytes);
      
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ServerConfig.getRailwayUrl()}/detect'),
      );
      
      if (userId != null) {
        request.fields['user_id'] = userId.toString();
      }
      
      String contentType = 'image/jpeg';
      if (filename.toLowerCase().endsWith('.png')) {
        contentType = 'image/png';
      } else if (filename.toLowerCase().endsWith('.jpg') || filename.toLowerCase().endsWith('.jpeg')) {
        contentType = 'image/jpeg';
      } else if (filename.toLowerCase().endsWith('.webp')) {
        contentType = 'image/webp';
      }
      
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          compressedBytes,
          filename: filename,
          contentType: MediaType.parse(contentType),
        ),
      );

      final response = await request.send();
      final body = await response.stream.bytesToString();
      
      debugPrint('Response status: ${response.statusCode}');
      debugPrint('Original size: ${bytes.length} bytes');
      debugPrint('Compressed size: ${compressedBytes.length} bytes');
      debugPrint('Response body: $body');
      
      if (response.statusCode != 200) {
        throw Exception('API Error: ${response.statusCode} - $body');
      }
      
      // Validate response is JSON, not HTML or error page
      if (!body.startsWith('{') && !body.startsWith('[')) {
        throw Exception('Invalid response format. Expected JSON, got: ${body.substring(0, 100)}...');
      }
      
      final jsonData = jsonDecode(body);

      return jsonData;
    } catch (e) {
      debugPrint('sendToYolo error: $e');
      rethrow;
    }
  }

  /// 
  Future<Uint8List> _compressImage(Uint8List bytes) async {
    try {
      final image = await decodeImageFromList(bytes);
      
      final maxSize = 800;
      int width = image.width;
      int height = image.height;
      
      if (width > maxSize || height > maxSize) {
        final ratio = width > height ? maxSize / width : maxSize / height;
        width = (width * ratio).round();
        height = (height * ratio).round();
      }
      
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      
      final dstRect = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
      final srcRect = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
      
      canvas.drawImageRect(image, srcRect, dstRect, Paint());
      
      final picture = recorder.endRecording();
      final compressedImage = await picture.toImage(width, height);
      final compressedBytes = await compressedImage.toByteData(format: ui.ImageByteFormat.png);
      
      return compressedBytes!.buffer.asUint8List();
    } catch (e) {
      debugPrint('Compress image error: $e');
      return bytes;
    }
  }

  Future<void> takePhoto() async {
    try {
      setState(() => isLoading = true);

      var cameraStatus = await Permission.camera.request();
      if (!cameraStatus.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('กรุณาอนุญาตการใช้กล้อง'),
              backgroundColor: Colors.red,
            ),
          );
        }
        openAppSettings();
        return;
      }

      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (photo == null) return;

      final bytes = await photo.readAsBytes();
      final fileName = photo.name;

      final detections = await sendToYolo(bytes, fileName, userId: _currentUserId);

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DisplayPictureScreen(
            imageBytes: bytes,
            detections: ((detections as Map?)?['detections'] as List? ?? [])
                .map((e) => Detection.fromJson(e))
                .toList(),
            imagePath: ((detections as Map?)?['saved_path']) ?? photo.path ?? '',
            railwayResponse: detections,
          ),
        ),
      );
    } catch (e) {
      debugPrint("Take photo error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> pickImage() async {
    try {
      setState(() => isLoading = true);

      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: false,
        withReadStream: true,
      );

      if (result == null) return;

      final file = result.files.single;
      final fileName = file.name;
      final originalPath = file.path;
      
      const maxSizeInBytes = 10 * 1024 * 1024;
      Uint8List? bytes;
      
      if (file.bytes != null) {
        bytes = file.bytes!;
      } else if (file.path != null) {
        final fileObj = File(file.path!);
        final fileSize = await fileObj.length();
        
        if (fileSize > maxSizeInBytes) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("ไฟล์ใหญ่เกินไป (ต้องไม่เกิน 10MB)"),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
        
        bytes = await fileObj.readAsBytes();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("ไม่สามารถอ่านไฟล์ได้"),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final detections = await sendToYolo(bytes, fileName, userId: _currentUserId);

      if (!mounted) return;

      if (bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("ไม่สามารถอ่านข้อมูลได้"),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DisplayPictureScreen(
            imageBytes: bytes!,
            detections: ((detections as Map?)?['detections'] as List? ?? [])
                .map((e) => Detection.fromJson(e))
                .toList(),
            imagePath: ((detections as Map?)?['saved_path']) ?? originalPath ?? '',
            railwayResponse: detections,
          ),
        ),
      );
    } catch (e) {
      debugPrint("Pick image error: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _buildCameraView(),
      ),
    );
  }

  Widget _buildCameraView() {
    // Check if controller is initialized
    if (!_controllerInitialized) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 20),
            Text(
              "กำลังเปิดกล้อง...",
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      );
    }
    
    return Stack(
      children: [
        // Camera Preview
        FutureBuilder<void>(
          future: _initializeControllerFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.done) {
              return SizedBox.expand(
                child: CameraPreview(_controller),
              );
            } else {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 20),
                    Text(
                      "กำลังเปิดกล้อง...",
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              );
            }
          },
        ),
        
        // Detection Overlay
        if (_liveDetections.isNotEmpty)
          CustomPaint(
            painter: YoloPainter(
              _liveDetections,
              Size(640, 640),
            ),
            size: Size.infinite,
          ),
        
        // Top Bar
        Positioned(
          top: 20,
          left: 0,
          right: 0,
          child: _buildTopBar(),
        ),
        
        // Live Scanning Indicator
        Positioned(
          top: 80,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.9),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'LIVE SCANNING',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        
        // Detection Info (Right side)
        if (_liveDetections.isNotEmpty)
          Positioned(
            right: 20,
            top: 200,
            child: _buildDetectionInfo(),
          ),
        
        // Bottom Counter
        Positioned(
          bottom: 160,
          left: 0,
          right: 0,
          child: _buildBottomCounter(),
        ),
        
        // Bottom Navigation
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: _buildBottomNavigation(),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Back Button
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () async {
                await _disposeCamera();
                if (mounted) {
                  Navigator.pop(context);
                }
              },
            ),
          ),
          // Logo
          Image.asset(
            'assets/images/number_egg_logo.png',
            height: 40,
            errorBuilder: (context, error, stackTrace) {
              return const Text(
                'NumberEgg',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              );
            },
          ),
          // Settings
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.settings, color: Colors.white),
              onPressed: () {
                // TODO: Open settings
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetectionInfo() {
    final detection = _liveDetections.first;
    final gradeText = _getGradeText(detection.grade);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.favorite_border, color: Colors.white, size: 16),
              const SizedBox(width: 4),
              Text(
                'เบอร์ ${_liveDetections.length} : $gradeText',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${(detection.confidence * 100).toStringAsFixed(0)}% ความมั่นใจต่อง',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getGradeText(String grade) {
    switch (grade.toLowerCase()) {
      case 'big':
        return 'เบอร์ 0';
      case 'medium':
        return 'เบอร์ 1';
      case 'small':
        return 'เบอร์ 2';
      default:
        return 'ไม่ทราบ';
    }
  }

  Widget _buildBottomCounter() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.brown.withOpacity(0.8),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'NUMBER',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$_eggCount',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 24),
            const Text(
              'AVG',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _averageGrade,
              style: const TextStyle(
                color: Colors.greenAccent,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Gallery Button
          _buildNavButton(
            icon: Icons.image_outlined,
            onTap: pickImage,
          ),
          // Switch Camera Button
          _buildNavButton(
            icon: Icons.flip_camera_ios_outlined,
            onTap: () {
              // TODO: Switch camera
            },
          ),
          // Capture Button (Center, Larger)
          GestureDetector(
            onTap: isLoading ? null : _captureFromStream,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFC107), Color(0xFFFFB300)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.yellow.withOpacity(0.5),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    )
                  : const Icon(
                      Icons.camera_alt,
                      color: Colors.white,
                      size: 36,
                    ),
            ),
          ),
          // Flash Button
          _buildNavButton(
            icon: Icons.flash_on_outlined,
            onTap: () {
              // TODO: Toggle flash
            },
          ),
          // Unknown Button (seems like video/settings)
          _buildNavButton(
            icon: Icons.videocam_outlined,
            onTap: () {
              // TODO: Video mode or other feature
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNavButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }
}

/// ================== YOLO PAINTER ==================
class YoloPainter extends CustomPainter {
  final List<Detection> detections;
  final Size imageSize;
  final double cmPerPixel = 0.02;

  YoloPainter(this.detections, this.imageSize);

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty) return;

    final scale = math.min(
      size.width / imageSize.width,
      size.height / imageSize.height,
    );

    final dx = (size.width - imageSize.width * scale) / 2;
    final dy = (size.height - imageSize.height * scale) / 2;

    for (final d in detections) {
      final widthPx = d.x2 - d.x1;
      final widthCm = widthPx * cmPerPixel;

      Color boxColor;
      String gradeLabel;
      
      // มาตรฐานไข่ไก่ไทย มอก. 227-2524
      if (widthCm >= 4.3) {
        boxColor = Colors.red;
        gradeLabel = "เบอร์ 0";
      } else if (widthCm >= 3.9) {
        boxColor = Colors.orange;
        gradeLabel = "เบอร์ 1";
      } else if (widthCm >= 3.5) {
        boxColor = Colors.yellow;
        gradeLabel = "เบอร์ 2";
      } else if (widthCm >= 3.0) {
        boxColor = Colors.green;
        gradeLabel = "เบอร์ 3";
      } else {
        boxColor = Colors.grey;
        gradeLabel = "เบอร์ 4";
      }

      final paint = Paint()
        ..color = boxColor
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;

      final rect = Rect.fromLTRB(
        d.x1 * scale + dx,
        d.y1 * scale + dy,
        d.x2 * scale + dx,
        d.y2 * scale + dy,
      );

      // Draw rectangle
      canvas.drawRect(rect, paint);

      // Draw corner brackets (more professional look)
      final cornerLength = 20.0;
      final cornerPaint = Paint()
        ..color = boxColor
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke;

      // Top-left corner
      canvas.drawLine(
        Offset(rect.left, rect.top + cornerLength),
        Offset(rect.left, rect.top),
        cornerPaint,
      );
      canvas.drawLine(
        Offset(rect.left, rect.top),
        Offset(rect.left + cornerLength, rect.top),
        cornerPaint,
      );

      // Top-right corner
      canvas.drawLine(
        Offset(rect.right - cornerLength, rect.top),
        Offset(rect.right, rect.top),
        cornerPaint,
      );
      canvas.drawLine(
        Offset(rect.right, rect.top),
        Offset(rect.right, rect.top + cornerLength),
        cornerPaint,
      );

      // Bottom-left corner
      canvas.drawLine(
        Offset(rect.left, rect.bottom - cornerLength),
        Offset(rect.left, rect.bottom),
        cornerPaint,
      );
      canvas.drawLine(
        Offset(rect.left, rect.bottom),
        Offset(rect.left + cornerLength, rect.bottom),
        cornerPaint,
      );

      // Bottom-right corner
      canvas.drawLine(
        Offset(rect.right - cornerLength, rect.bottom),
        Offset(rect.right, rect.bottom),
        cornerPaint,
      );
      canvas.drawLine(
        Offset(rect.right, rect.bottom - cornerLength),
        Offset(rect.right, rect.bottom),
        cornerPaint,
      );

      // Draw label with Thai standard
      final className = d.cls >= 0 && d.cls < yoloClasses.length
          ? yoloClasses[d.cls]
          : 'Unknown';

      final label = "$gradeLabel ${(d.confidence * 100).toStringAsFixed(1)}%\n${widthCm.toStringAsFixed(1)}cm";

      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            backgroundColor: Colors.black87,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelOffset = Offset(
        rect.left,
        rect.top - textPainter.height - 4,
      );

      textPainter.paint(canvas, labelOffset);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Helper classes
class EggResultCard extends StatelessWidget {
  final int index;
  final Detection detection;

  const EggResultCard({
    super.key,
    required this.index,
    required this.detection,
  });

  Widget _buildEggItem(int index, Detection detection) {
    String gradeText;
    Color gradeColor;
    IconData gradeIcon;
    
    switch (detection.grade.toLowerCase()) {
      case 'big':
        gradeText = "เบอร์ 0 (พิเศษ)";
        gradeColor = Colors.red;
        gradeIcon = Icons.egg;
        break;
      case 'medium':
        gradeText = "เบอร์ 1 (ใหญ่)";
        gradeColor = Colors.orange;
        gradeIcon = Icons.egg_alt;
        break;
      case 'small':
        gradeText = "เบอร์ 2 (กลาง)";
        gradeColor = Colors.yellow;
        gradeIcon = Icons.egg_outlined;
        break;
      default:
        gradeText = "เบอร์ 3 (เล็ก)";
        gradeColor = Colors.green;
        gradeIcon = Icons.egg_alt;
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: gradeColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              gradeIcon,
              color: gradeColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "ไข่ $index",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  gradeText,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
                // เพิ่มข้อมูลพิกัดและขนาดจาก detection
                if (detection.x1 != null && detection.x2 != null && detection.y1 != null && detection.y2 != null)
                  Text(
                    "พิกัด: (${detection.x1!.toStringAsFixed(0)}, ${detection.y1!.toStringAsFixed(0)}) - (${detection.x2!.toStringAsFixed(0)}, ${detection.y2!.toStringAsFixed(0)})",
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: gradeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "${(detection.confidence * 100).toStringAsFixed(1)}%",
                  style: TextStyle(
                    color: gradeColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              // เพิ่มขนาดของไข่ถ้ามีข้อมูล
              if (detection.x1 != null && detection.x2 != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    "${(detection.x2! - detection.x1!).toStringAsFixed(0)}px",
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 10,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildEggItem(index, detection);
  }
}

int _calculateGrade(Detection d) {
  switch (d.grade.toLowerCase()) {
    case 'grade0':
      return 0;
    case 'grade1':
      return 1;
    case 'grade2':
      return 2;
    case 'grade3':
      return 3;
    case 'grade4':
      return 4;
    case 'grade5':
      return 5;
    default:
      return 5;
  }
}

Color eggColor(double avgSize) {
  // มาตรฐานไข่ไก่ไทย มอก. 227-2524
  if (avgSize >= 4.3) {
    return Colors.red;      // เบอร์ 0 (พิเศษ)
  } else if (avgSize >= 3.9) {
    return Colors.orange;   // เบอร์ 1 (ใหญ่)
  } else if (avgSize >= 3.5) {
    return Colors.yellow;   // เบอร์ 2 (กลาง)
  } else if (avgSize >= 3.0) {
    return Colors.green;    // เบอร์ 3 (เล็ก)
  } else {
    return Colors.grey;     // เบอร์ 4 (เล็กพิเศษ)
  }
}
