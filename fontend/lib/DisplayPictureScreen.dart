import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'database/egg_database.dart';
import 'services/supabase_service.dart';
import 'camera.dart';

// --- หน้าแสดงผลและ Save หลังจากถ่ายภาพ ---
class DisplayPictureScreen extends StatefulWidget {
  final String imagePath;
  final List<Detection>? detections;
  final Uint8List? imageBytes;
  final Map<String, dynamic>? railwayResponse; // เพิ่ม railway response
  
  const DisplayPictureScreen({
    Key? key, 
    required this.imagePath,
    this.detections,
    this.imageBytes,
    this.railwayResponse, // เพิ่ม parameter
  }) : super(key: key);

  @override
  State<DisplayPictureScreen> createState() => _DisplayPictureScreenState();
}

class _DisplayPictureScreenState extends State<DisplayPictureScreen> {
  bool isSaving = false;
  bool isSaved = false;
  bool isLocalSaved = false;

  Future<void> saveImageToGallery() async {
    setState(() { isSaving = true; });
    try {
      var status = await Permission.storage.request();
      if (status.isDenied) {
        status = await Permission.photos.request();
      }

      if (status.isGranted || await Permission.storage.isGranted || await Permission.photos.isGranted) {
        final Directory? directory = await getExternalStorageDirectory();
        if (directory != null) {
          String newPath = "";
          if (Platform.isAndroid) {
             newPath = "/storage/emulated/0/DCIM/Camera"; 
             final dir = Directory(newPath);
             if (!dir.existsSync()) {
               newPath = directory.path; 
             }
          } else {
            newPath = directory.path;
          }

          String fileName = "Egg_${DateTime.now().millisecondsSinceEpoch}.jpg";
          String fullPath = "$newPath/$fileName";
          
          await File(widget.imagePath).copy(fullPath);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('บันทึกรูปภาพลงเครื่องเรียบร้อย: $fileName'), 
                backgroundColor: const Color(0xFF4CAF50),
                behavior: SnackBarBehavior.floating,
              ),
            );
            setState(() { isLocalSaved = true; });
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('กรุณาอนุญาตให้เข้าถึงรูปภาพ'), backgroundColor: Colors.red),
          );
        }
        openAppSettings();
      }
    } catch (e) {
      debugPrint("Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() { isSaving = false; });
    }
  }

  // 📊 บันทึกลง History (SQLite เท่านั้น)
  Future<void> saveToHistory() async {
    setState(() { isSaving = true; });
    try {
      debugPrint("🔄 Save to History - บันทึกลง SQLite เท่านั้น");
      
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id') ?? 1;
      
      debugPrint("🔍 DisplayPictureScreen Debug - User ID: $userId");
      
      // บันทึกลง SQLite เท่านั้น
      final eggItems = <Map<String, dynamic>>[];
      
      // ใช้ข้อมูลจากการ detect จริงเท่านั้น
      if (widget.detections != null && widget.detections!.isNotEmpty) {
        for (final detection in widget.detections!) {
          // ตรวจสอบว่า confidence ไม่เป็น null ก่อน
          if (detection.confidence == null || detection.confidence! < 0.3) continue; // กรอง confidence ต่ำ
          
          // ตรวจสอบว่า grade ไม่เป็น null
          if (detection.grade == null) continue;
          
          // แปลง grade string เป็นตัวเลข (NEW SYSTEM - grade0-5 เท่านั้น)
          int grade;
          switch (detection.grade!.toLowerCase()) {
            // New system (จาก Railway ใหม่)
            case 'grade0':
              grade = 0;  // เบอร์ 0 (พิเศษ)
              break;
            case 'grade1':
              grade = 1;  // เบอร์ 1 (ใหญ่)
              break;
            case 'grade2':
              grade = 2;  // เบอร์ 2 (กลาง)
              break;
            case 'grade3':
              grade = 3;  // เบอร์ 3 (เล็ก)
              break;
            case 'grade4':
              grade = 4;  // เบอร์ 4 (เล็กมาก)
              break;
            case 'grade5':
              grade = 5;  // เบอร์ 5 (พิเศษเล็ก)
              break;
            
            default:
              grade = 2;  // default เป็นกลาง
          }
          
          eggItems.add({
            'grade': grade,
            'confidence': detection.confidence * 100,
          });
        }
        debugPrint("📝 Using real detection data: ${eggItems.length} eggs found");
      } else {
        debugPrint("📝 No detection data available");
      }
      
      // ถ้าไม่มีข้อมูลจากการ detect จริง ไม่ต้องบันทึก
      if (eggItems.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("ไม่พบข้อมูลการตรวจจับ ไม่สามารถบันทึกได้"),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // บันทึกลง SQLite เท่านั้น
      try {
        final sessionId = await EggDatabase.instance.insertSession(
          userId: userId,
          imagePath: widget.imagePath ?? 'display_image',
          eggCount: eggItems.length,
          successPercent: eggItems.isEmpty ? 0 : 
            (eggItems.where((e) => e != null && e['confidence'] != null)
             .map((e) => e['confidence'] as double)
             .reduce((a, b) => a + b) / eggItems.length),
          grade0Count: eggItems.where((e) => e != null && e['grade'] == 0).length,
          grade1Count: eggItems.where((e) => e != null && e['grade'] == 1).length,
          grade2Count: eggItems.where((e) => e != null && e['grade'] == 2).length,
          grade3Count: eggItems.where((e) => e != null && e['grade'] == 3).length,
          grade4Count: eggItems.where((e) => e != null && e['grade'] == 4).length,
          grade5Count: eggItems.where((e) => e != null && e['grade'] == 5).length,
          day: DateTime.now().toString().substring(0, 10),
        );
        
        // บันทึกรายการไข่แต่ละอันลง SQLite
        for (final item in eggItems) {
          if (item != null && item['grade'] != null && item['confidence'] != null) {
            await EggDatabase.instance.insertEggItem(
              sessionId: sessionId,
              grade: item['grade'] as int,
              confidence: item['confidence'] as double,
            );
          }
        }
        
        debugPrint("✅ Save to SQLite สำเร็จ - Session ID: $sessionId");
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("บันทึกประวัติเรียบร้อยแล้ว!"),
              backgroundColor: Colors.green,
            ),
          );
        }
        
        setState(() { isSaved = true; });
        
      } catch (sqliteError) {
        debugPrint("❌ Save to SQLite ล้มเหลว: $sqliteError");
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("ไม่สามารถบันทึกประวัติได้: $sqliteError"),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
      
    } catch (e) {
      debugPrint("❌ Save to History - บันทึกล้มเหลว: $e");
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("ไม่สามารถบันทึกประวัติได้: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() { isSaving = false; });
      }
    }
  }

  @override 
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black54, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        title: const Text(
          "ผลการตรวจจับ", 
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)
        ),
        centerTitle: true,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              icon: Icon(
                isSaved ? Icons.check_circle : Icons.save_alt,
                color: isSaved ? Colors.green : Colors.grey,
              ),
              onPressed: isSaved ? null : saveToHistory,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Image Section
          Expanded(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: widget.imageBytes != null
                    ? Image.memory(
                        widget.imageBytes!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                      )
                    : (widget.imagePath.startsWith('http') 
                        ? CachedNetworkImage(
                            imageUrl: widget.imagePath,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            placeholder: (context, url) => Container(
                              color: Colors.grey[200],
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: Colors.grey[200],
                              child: const Center(
                                child: Icon(Icons.broken_image, color: Colors.grey),
                              ),
                            ),
                          )
                        : Image.file(
                            File(widget.imagePath), 
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                          )
                      ),
              ),
            ),
          ),
          
          // Results Section
          Expanded(
            flex: 2,
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Summary Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "การตรวจจับสำเร็จ",
                                style: TextStyle(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "พบไข่ ${widget.detections?.length ?? 0} ฟอง",
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                              ),
                              // เพิ่มข้อมูลเพิ่มเติมจาก detection
                              if (widget.detections != null && widget.detections!.isNotEmpty)
                                Text(
                                  "ความแม่นยำเฉลี่ย: ${_calculateAverageConfidence()}%",
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            "${widget.detections?.length ?? 0}",
                            style: const TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Egg Details
                  const Text(
                    "รายละเอียดไข่",
                    style: TextStyle(
                      fontSize: 18, 
                      fontWeight: FontWeight.bold, 
                      color: Colors.black87
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Dynamic Egg List
                  Expanded(
                    child: widget.detections != null && widget.detections!.isNotEmpty
                        ? ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: widget.detections!.length,
                            itemBuilder: (context, index) {
                              final detection = widget.detections![index];
                              return _buildEggItem(index + 1, detection);
                            },
                          )
                        : Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.egg_outlined,
                                  size: 48,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  "ไม่พบไข่ในภาพ",
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

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

  // เพิ่มฟังก์ชันคำนวณความแม่นยำเฉลี่ย
  double _calculateAverageConfidence() {
    if (widget.detections == null || widget.detections!.isEmpty) {
      return 0.0;
    }
    
    double totalConfidence = 0.0;
    for (final detection in widget.detections!) {
      totalConfidence += detection.confidence;
    }
    
    return (totalConfidence / widget.detections!.length) * 100;
  }
}
