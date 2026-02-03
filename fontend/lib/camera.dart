import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'database/egg_database.dart'; // 🔧 ปรับ path ให้ตรงโปรเจกต์คุณ
import 'utils/server_config.dart';

const List<String> yoloClasses = [
  "egg", // class 0
  // เพิ่ม class อื่นได้
];

/// ================== MODEL ==================
class Detection {
  final double x1, y1, x2, y2;
  final double confidence;
  final int cls;
  final String? className;

  Detection.fromJson(Map<String, dynamic> json)
      : x1 = (json['x1'] as num).toDouble(),
        y1 = (json['y1'] as num).toDouble(),
        x2 = (json['x2'] as num).toDouble(),
        y2 = (json['y2'] as num).toDouble(),
        confidence = (json['confidence'] as num?)?.toDouble() ?? 0.0,
        cls = (json['class_id'] as num?)?.toInt() ?? (json['class'] as num?)?.toInt() ?? 0,
        className = json['class_name'] as String?;
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
      scaffoldMessengerKey: scaffoldMessengerKey, // ⭐ เพิ่ม
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

  /// 🔥 ส่งรูปไป YOLO
  Future<List<Detection>> sendToYolo(
    Uint8List bytes,
    String filename,
  ) async {
    try {
      // ใช้ ServerConfig เพื่อดึง URL จาก config
      final baseUrl = await ServerConfig.getApiUrl();
      final url = Uri.parse('$baseUrl/detect');
      
      debugPrint('Sending request to: $url');
      
      final request = http.MultipartRequest('POST', url);
      
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
        ),
      );

      // เพิ่ม headers สำหรับ debugging
      request.headers.addAll({
        'Accept': 'application/json',
        'User-Agent': 'NumberEgg-Flutter-App',
      });

      final response = await request.send();
      debugPrint('Response status code: ${response.statusCode}');
      
      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        throw Exception('API Error: ${response.statusCode} - $errorBody');
      }
      
      final body = await response.stream.bytesToString();
      debugPrint('Response body: $body');
      
      final jsonData = jsonDecode(body);
      
      // จัดการกับ response format ที่แตกต่างกัน
      List<dynamic> detectionsList;
      if (jsonData['detections'] != null) {
        detectionsList = jsonData['detections'] as List;
      } else if (jsonData['eggs'] != null) {
        detectionsList = jsonData['eggs'] as List;
      } else {
        detectionsList = [];
      }
      
      return detectionsList
          .map((e) => Detection.fromJson(e))
          .toList();
    } catch (e) {
      debugPrint('Error in sendToYolo: $e');
      rethrow;
    }
  }

  /// 📁 เลือกรูปจากเครื่อง
  Future<void> pickImage() async {
    try {
      setState(() => isLoading = true);

      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true, // ⭐ สำคัญมาก (Web ต้องใช้)
      );

      if (result == null) return;

      final bytes = result.files.single.bytes!;
      final fileName = result.files.single.name;

      final detections = await sendToYolo(bytes, fileName);

      if (!mounted) return;

      // แสดง debug info
      debugPrint('Found ${detections.length} detections');
      for (int i = 0; i < detections.length; i++) {
        final d = detections[i];
        debugPrint('Detection $i: class=${d.className ?? d.cls}, confidence=${d.confidence}');
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DisplayPictureScreen(
            imageBytes: bytes,
            detections: detections,
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
      body: Center(
        child: isLoading
            ? const CircularProgressIndicator(color: Colors.white)
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/number_egg_logo.png',
                    width: 250,
                  ),
                  const SizedBox(height: 40),
                  ElevatedButton.icon(
                    onPressed: pickImage,
                    icon: const Icon(Icons.image),
                    label: const Text(
                      "เลือกรูปจากเครื่อง",
                      style: TextStyle(fontSize: 18),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFC107),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 30,
                        vertical: 15,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// ================== DISPLAY RESULT ==================
class DisplayPictureScreen extends StatelessWidget {
  final Uint8List imageBytes;
  final List<Detection> detections;

  const DisplayPictureScreen({
    super.key,
    required this.imageBytes,
    required this.detections,
  });

  Future<ui.Image> _loadImage() async {
    return decodeImageFromList(imageBytes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Result")),
      body: FutureBuilder<ui.Image>(
        future: _loadImage(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final image = snapshot.data!;
          final imageSize =
              Size(image.width.toDouble(), image.height.toDouble());

          return Column(
            children: [
              SizedBox(
                height: 300,
                width: double.infinity,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Stack(
                      children: [
                        Image.memory(
                          imageBytes,
                          fit: BoxFit.contain,
                          width: constraints.maxWidth,
                          height: constraints.maxHeight,
                        ),
                        CustomPaint(
                          size: Size(
                            constraints.maxWidth,
                            constraints.maxHeight,
                          ),
                          painter: YoloPainter(
                            detections,
                            imageSize, // ✅ ใช้ขนาดภาพจริง
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              Text(
                "พบวัตถุทั้งหมด: ${detections.length}",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text("บันทึกผลตรวจไข่"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                onPressed: () async {
                  await _saveToDatabase(context);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _saveToDatabase(BuildContext context) async {
    const double cmPerPixel = 0.02; // 🔧 ต้องตรงกับ Painter
    print("START SAVE");
    
    try {
      // 🗄️ STEP 1: บันทึกลง SQLite ก่อน (Offline First)
      print("🗄️ Saving to SQLite first...");
      
      final sessionId = await EggDatabase.instance.insertSession(
        userId: 1, // You might want to get this from user authentication
        imagePath: "picked_image.jpg", // หรือส่งชื่อจริงมา
        eggCount: detections.where((d) => d.cls == 0).length,
        successPercent: 100.0, // You might want to calculate this based on confidence
        day: DateTime.now().toIso8601String().substring(0, 10),
      );

      // Then insert each egg item
      for (final d in detections) {
        // ✅ บันทึกเฉพาะไข่
        if (d.cls != 0) continue;

        final widthCm = (d.x2 - d.x1) * cmPerPixel;
        final heightCm = (d.y2 - d.y1) * cmPerPixel;

        // 🥚 ตัวอย่างเกรด (คุณปรับทีหลังได้)
        int grade;
        if (widthCm >= 6.0) {
          grade = 3;
        } else if (widthCm >= 5.0) {
          grade = 2;
        } else if (widthCm >= 4.0) {
          grade = 1;
        } else {
          grade = 0;
        }

        await EggDatabase.instance.insertEggItem(
          sessionId: sessionId,
          grade: grade,
          confidence: d.confidence,
          x1: d.x1,
          y1: d.y1,
          x2: d.x2,
          y2: d.y2,
        );
      }
      
      print("✅ SQLite save successful: Session $sessionId");
      
      // ☁️ STEP 2: Sync ไป Supabase (Background)
      print("☁️ Syncing to Supabase...");
      _syncToSupabase(sessionId);
      
      if (context.mounted) {
        scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text("บันทึกผลตรวจไข่เรียบร้อย (พร้อม sync ขึ้นคลาวด์)"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print("❌ Save failed: $e");
      if (context.mounted) {
        scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text("บันทึกล้มเหลว: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  // ☁️ Background sync to Supabase
  Future<void> _syncToSupabase(int localSessionId) async {
    try {
      // Get session data from SQLite
      final db = await EggDatabase.instance.database;
      final sessions = await db.query(
        'egg_session',
        where: 'id = ?',
        whereArgs: [localSessionId],
      );
      
      if (sessions.isEmpty) {
        print("❌ Session not found in SQLite");
        return;
      }
      
      final session = sessions.first;
      
      // Get egg items
      final eggItems = await db.query(
        'egg_item',
        where: 'session_id = ?',
        whereArgs: [localSessionId],
      );
      
      // TODO: Sync to Supabase here
      // You'll need to implement Supabase sync logic
      print("📤 Ready to sync session ${session['id']} with ${eggItems.length} egg items to Supabase");
      
      // For now, just log the data
      print("📊 Session data: ${session}");
      print("🥚 Egg items count: ${eggItems.length}");
      
    } catch (e) {
      print("❌ Supabase sync failed: $e");
    }
  }
}

/// ================== YOLO PAINTER ==================
class YoloPainter extends CustomPainter {
  final List<Detection> detections;
  final Size imageSize; // เช่น 640x640

  // ⭐ เพิ่มตรงนี้
  final double cmPerPixel = 0.02; // ปรับตามการวัดจริง

  YoloPainter(this.detections, this.imageSize);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(
      size.width / imageSize.width,
      size.height / imageSize.height,
    );

    final dx = (size.width - imageSize.width * scale) / 2;
    final dy = (size.height - imageSize.height * scale) / 2;

    final boxPaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    for (final d in detections) {
      // 🔲 Bounding box
      final rect = Rect.fromLTRB(
        d.x1 * scale + dx,
        d.y1 * scale + dy,
        d.x2 * scale + dx,
        d.y2 * scale + dy,
      );

      canvas.drawRect(rect, boxPaint);

      // 📐 คำนวณขนาด
      final widthPx = d.x2 - d.x1;
      final heightPx = d.y2 - d.y1;

      final widthCm = widthPx * cmPerPixel;
      final heightCm = heightPx * cmPerPixel;

      // 🏷 Label + confidence + size
      final className = d.className ?? (d.cls >= 0 && d.cls < yoloClasses.length
          ? yoloClasses[d.cls]
          : 'Unknown');

      final label = "$className ${(d.confidence * 100).toStringAsFixed(1)}%\n"
          "${widthCm.toStringAsFixed(1)} x ${heightCm.toStringAsFixed(1)} cm";

      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            backgroundColor: Colors.black87,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // 📍 วาด label เหนือกรอบ
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
