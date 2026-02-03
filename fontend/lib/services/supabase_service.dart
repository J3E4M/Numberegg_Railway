import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:io';
import '../config/supabase_config.dart';
import 'supabase_storage_service.dart';

class SupabaseService {
  static SupabaseClient? _client;
  
  /// ดึง Supabase Client instance
  static SupabaseClient get client {
    if (_client == null) {
      if (!SupabaseConfig.isConfigured) {
        throw Exception('Supabase ยังไม่ได้ตั้งค่า กรุณาตั้งค่าใน supabase_config.dart');
      }
      _client = Supabase.instance.client;
    }
    return _client!;
  }
  
  /// ตรวจสอบสถานะการเชื่อมต่อ
  static Future<bool> checkConnection() async {
    try {
      final response = await client.from('privileges').select('count').count();
      return response.count != null;
    } catch (e) {
      debugPrint('Supabase connection error: $e');
      return false;
    }
  }
  
  /// ดึงข้อมูล privileges ทั้งหมด
  static Future<List<Map<String, dynamic>>> getPrivileges() async {
    try {
      final response = await client
          .from('privileges')
          .select('*')
          .order('level');
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('เกิดข้อผิดพลาดในการดึงข้อมูล privileges: $e');
    }
  }
  
  /// ดึงข้อมูล users ทั้งหมดพร้อม privilege
  static Future<List<Map<String, dynamic>>> getUsers() async {
    try {
      final response = await client
          .from('users')
          .select('''
            *,
            privileges (
              name,
              level
            )
          ''')
          .order('created_at', ascending: false);
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('เกิดข้อผิดพลาดในการดึงข้อมูล users: $e');
    }
  }
  
  /// สร้าง user ใหม่
  static Future<Map<String, dynamic>> createUser({
    required String email,
    required String password,
    required String name,
    required int privilegeId,
  }) async {
    try {
      final response = await client
          .from('users')
          .insert({
            'email': email,
            'password': password, // ควรเข้ารหัสใน production
            'name': name,
            'privilege_id': privilegeId,
          })
          .select()
          .single();
      
      return response;
    } catch (e) {
      throw Exception('เกิดข้อผิดพลาดในการสร้าง user: $e');
    }
  }
  
  /// ตรวจสอบการเข้าสู่ระบบ
  static Future<Map<String, dynamic>?> login(String email, String password) async {
    try {
      final response = await client
          .from('users')
          .select('''
            *,
            privileges (
              name,
              level
            )
          ''')
          .eq('email', email)
          .eq('password', password) // ควรเข้ารหัสใน production
          .maybeSingle();
      
      return response;
    } catch (e) {
      throw Exception('เกิดข้อผิดพลาดในการเข้าสู่ระบบ: $e');
    }
  }

  // ==================== EGG SESSION CRUD ====================

  /// สร้าง egg session ใหม่
  static Future<Map<String, dynamic>> createEggSession({
    required int userId,
    required String imagePath,
    required int eggCount,
    required double successPercent,
    required int grade0Count,
    required int grade1Count,
    required int grade2Count,
    required int grade3Count,
    required int grade4Count,
    required int grade5Count,
    required String day,
  }) async {
    try {
      debugPrint("🔄 Creating egg session with userId: $userId");
      debugPrint("📊 Session data: eggs=$eggCount, grade0=$grade0Count, grade1=$grade1Count, grade2=$grade2Count, grade3=$grade3Count, grade4=$grade4Count, grade5=$grade5Count");
      
      final response = await client
          .from('egg_session')
          .insert({
            'user_id': userId,
            'image_path': imagePath,
            'egg_count': eggCount,
            'success_percent': successPercent,
            'grade0_count': grade0Count,
            'grade1_count': grade1Count,
            'grade2_count': grade2Count,
            'grade3_count': grade3Count,
            'grade4_count': grade4Count,
            'grade5_count': grade5Count,
            'day': day,
            'created_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();
      
      debugPrint("✅ Session created successfully: ${response['id']}");
      return response;
    } catch (e) {
      throw Exception('เกิดข้อผิดพลาดในการสร้าง egg session: $e');
    }
  }

  /// สร้าง egg item ใหม่
  static Future<Map<String, dynamic>> createEggItem({
    required int sessionId,
    required int grade,
    required double confidence,
    double? x1,
    double? y1,
    double? x2,
    double? y2,
  }) async {
    try {
      final response = await client
          .from('egg_item')
          .insert({
            'session_id': sessionId,
            'grade': grade,
            'confidence': confidence,
            'x1': x1 ?? 0.0,
            'y1': y1 ?? 0.0,
            'x2': x2 ?? 0.0,
            'y2': y2 ?? 0.0,
          })
          .select()
          .single();
      
      return response;
    } catch (e) {
      throw Exception('เกิดข้อผิดพลาดในการสร้าง egg item: $e');
    }
  }

  /// สร้าง egg session พร้อม egg items พร้อมกัน
  static Future<Map<String, dynamic>> createEggSessionWithItems({
    required int userId,
    required String imagePath,
    required int eggCount,
    required double successPercent,
    required int grade0Count,
    required int grade1Count,
    required int grade2Count,
    required int grade3Count,
    required int grade4Count,
    required int grade5Count,
    required String day,
    required List<Map<String, dynamic>> eggItems,
  }) async {
    try {
      debugPrint("🔄 Creating egg session with image upload");
      debugPrint("📸 Original imagePath: $imagePath");
      
      // อัพโหลดรูปภาพขึ้น Supabase Storage ก่อน
      String uploadedImagePath = imagePath;
      
      try {
        if (imagePath.isNotEmpty && File(imagePath).existsSync()) {
          // อ่านไฟล์รูปภาพ
          final imageFile = File(imagePath);
          final imageBytes = await imageFile.readAsBytes();
          final fileName = imagePath.split('/').last;
          
          debugPrint("📤 Uploading image to Supabase Storage: $fileName");
          debugPrint("📏 Image size: ${imageBytes.length} bytes");
          
          // อัพโหลดขึ้น Supabase Storage
          uploadedImagePath = await SupabaseStorageService.uploadEggImage(
            imageBytes: imageBytes,
            fileName: fileName,
          );
          
          debugPrint("✅ Image uploaded successfully: $uploadedImagePath");
        } else {
          debugPrint("⚠️ Image file not found or path empty: $imagePath");
          debugPrint("🔍 File exists check: ${imagePath.isNotEmpty ? File(imagePath).existsSync() : 'Empty path'}");
        }
      } catch (uploadError) {
        debugPrint("❌ Image upload failed, using original path: $uploadError");
        // ใช้ path เดิมถ้าอัพโหลดล้มเหลว
      }
      
      // สร้าง session ด้วย uploaded image path
      final sessionResponse = await createEggSession(
        userId: userId,
        imagePath: uploadedImagePath,
        eggCount: eggCount,
        successPercent: successPercent,
        grade0Count: grade0Count,
        grade1Count: grade1Count,
        grade2Count: grade2Count,
        grade3Count: grade3Count,
        grade4Count: grade4Count,
        grade5Count: grade5Count,
        day: day,
      );

      // สร้าง egg items
      final itemsWithSessionId = eggItems.map((item) => {
        ...item,
        'session_id': sessionResponse['id'],
      }).toList();
      
      debugPrint("📦 Creating ${itemsWithSessionId.length} egg items for session ${sessionResponse['id']}");
      debugPrint("📋 Sample item: ${itemsWithSessionId.isNotEmpty ? itemsWithSessionId.first : 'No items'}");
      debugPrint("📋 All items data: $itemsWithSessionId");

      final insertResponse = await client.from('egg_item').insert(itemsWithSessionId).select();
      debugPrint("✅ Egg items inserted successfully: ${insertResponse.length} items");
      debugPrint("📋 Inserted items response: $insertResponse");
      
      // ตรวจสอบว่า items ถูกบันทึกจริงโดยดึงข้อมูลกลับมา
      try {
        final verifyItems = await client.from('egg_item')
            .select('*')
            .eq('session_id', sessionResponse['id'])
            .order('id', ascending: true);
        debugPrint("🔍 Verified ${verifyItems.length} items in database for session ${sessionResponse['id']}");
        if (verifyItems.isNotEmpty) {
          debugPrint("📋 First verified item: ${verifyItems.first}");
        }
      } catch (verifyError) {
        debugPrint("❌ Error verifying items: $verifyError");
      }
      
      if (insertResponse.isEmpty) {
        debugPrint("⚠️ No items were inserted, checking data structure...");
        for (var item in itemsWithSessionId) {
          debugPrint("Item data: $item");
        }
      }
      
      debugPrint("✅ Egg session and items created successfully with uploaded image");

      return sessionResponse;
    } catch (e) {
      throw Exception('เกิดข้อผิดพลาดในการสร้าง egg session พร้อม items: $e');
    }
  }

  /// ดึงข้อมูล egg sessions ทั้งหมด
  static Future<List<Map<String, dynamic>>> getEggSessions() async {
    try {
      final response = await client
          .from('egg_session')
          .select('''
            *,
            users (
              name,
              email
            )
          ''')
          .order('created_at', ascending: false);
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('เกิดข้อผิดพลาดในการดึงข้อมูล egg sessions: $e');
    }
  }

  /// ดึงข้อมูล egg sessions ตาม user_id
  static Future<List<Map<String, dynamic>>> getEggSessionsByUser(int userId) async {
    try {
      final response = await client
          .from('egg_session')
          .select('*')
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('เกิดข้อผิดพลาดในการดึงข้อมูล egg sessions ตาม user: $e');
    }
  }

  /// ดึงข้อมูล egg items ตาม session_id
  static Future<List<Map<String, dynamic>>> getEggItemsBySession(int sessionId) async {
    try {
      final response = await client
          .from('egg_item')
          .select('*')
          .eq('session_id', sessionId)
          .order('id', ascending: true);
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('เกิดข้อผิดพลาดในการดึงข้อมูล egg items: $e');
    }
  }

  /// ดึงข้อมูลสถิติไข่ทั้งหมด
  static Future<Map<String, dynamic>> getEggStatistics() async {
    try {
      final response = await client
          .from('egg_session')
          .select('''
            egg_count,
            success_percent,
            grade0_count,
            grade1_count,
            grade2_count,
            grade3_count,
            grade4_count,
            grade5_count
          ''');

      final sessions = List<Map<String, dynamic>>.from(response);
      
      if (sessions.isEmpty) {
        return {
          'total_sessions': 0,
          'total_eggs': 0,
          'total_grade0': 0,
          'total_grade1': 0,
          'total_grade2': 0,
          'total_grade3': 0,
          'total_grade4': 0,
          'total_grade5': 0,
          'average_success_percent': 0.0,
        };
      }

      final totalSessions = sessions.length;
      final totalEggs = sessions.fold<int>(0, (sum, session) => sum + (session['egg_count'] as int? ?? 0));
      final totalGrade0 = sessions.fold<int>(0, (sum, session) => sum + (session['grade0_count'] as int? ?? 0));
      final totalGrade1 = sessions.fold<int>(0, (sum, session) => sum + (session['grade1_count'] as int? ?? 0));
      final totalGrade2 = sessions.fold<int>(0, (sum, session) => sum + (session['grade2_count'] as int? ?? 0));
      final totalGrade3 = sessions.fold<int>(0, (sum, session) => sum + (session['grade3_count'] as int? ?? 0));
      final totalGrade4 = sessions.fold<int>(0, (sum, session) => sum + (session['grade4_count'] as int? ?? 0));
      final totalGrade5 = sessions.fold<int>(0, (sum, session) => sum + (session['grade5_count'] as int? ?? 0));
      final avgSuccess = sessions.fold<double>(0, (sum, session) => sum + (session['success_percent'] as num? ?? 0)) / totalSessions;

      return {
        'total_sessions': totalSessions,
        'total_eggs': totalEggs,
        'total_grade0': totalGrade0,
        'total_grade1': totalGrade1,
        'total_grade2': totalGrade2,
        'total_grade3': totalGrade3,
        'total_grade4': totalGrade4,
        'total_grade5': totalGrade5,
        'average_success_percent': double.parse(avgSuccess.toStringAsFixed(2)),
      };
    } catch (e) {
      throw Exception('เกิดข้อผิดพลาดในการดึงข้อมูลสถิติ: $e');
    }
  }

  // ==================== SYNC LOCAL TO SUPABASE ====================

  /// Sync ข้อมูล egg sessions และ items จาก local SQLite ขึ้น Supabase ทั้งหมด
  static Future<Map<String, dynamic>> syncLocalDataToSupabase() async {
    try {
      int syncedSessions = 0;
      int syncedItems = 0;
      int skippedSessions = 0;

      // ดึงข้อมูลจาก local SQLite
      final localSessions = await _getLocalSessions();
      
      for (final session in localSessions) {
        try {
          // ตรวจสอบว่า session นี้มีใน Supabase แล้วหรือไม่ (ตรวจสอบด้วย created_at + user_id)
          final existingSessions = await client
              .from('egg_session')
              .select('id')
              .eq('user_id', session['user_id'])
              .eq('created_at', session['created_at']);

          if (existingSessions.isNotEmpty) {
            skippedSessions++;
            continue; // ข้าม session ที่ sync ไปแล้ว
          }

          // สร้าง session ใหม่ใน Supabase
          final sessionResponse = await client
              .from('egg_session')
              .insert({
                'user_id': session['user_id'],
                'image_path': session['image_path'],
                'egg_count': session['egg_count'],
                'success_percent': session['success_percent'],
                'grade0_count': session['grade0_count'],
                'grade1_count': session['grade1_count'],
                'grade2_count': session['grade2_count'],
                'grade3_count': session['grade3_count'],
                'grade4_count': session['grade4_count'],
                'grade5_count': session['grade5_count'],
                'day': session['day'],
                'created_at': session['created_at'],
              })
              .select()
              .single();

          syncedSessions++;

          // ดึง egg items ของ session นี้จาก local
          final localItems = await _getLocalItemsBySession(session['id']);
          
          // สร้าง items ใน Supabase
          if (localItems.isNotEmpty) {
            final itemsForSupabase = localItems.map((item) => {
              'session_id': sessionResponse['id'],
              'grade': item['grade'],
              'confidence': item['confidence'],
              'x1': item['x1'] ?? 0.0,
              'y1': item['y1'] ?? 0.0,
              'x2': item['x2'] ?? 0.0,
              'y2': item['y2'] ?? 0.0,
            }).toList();

            await client.from('egg_item').insert(itemsForSupabase);
            syncedItems += itemsForSupabase.length;
          }
        } catch (e) {
          print('Error syncing session ${session['id']}: $e');
          continue;
        }
      }

      return {
        'synced_sessions': syncedSessions,
        'synced_items': syncedItems,
        'skipped_sessions': skippedSessions,
        'total_local_sessions': localSessions.length,
        'message': 'Sync completed successfully',
      };
    } catch (e) {
      throw Exception('เกิดข้อผิดพลาดในการ sync ข้อมูล: $e');
    }
  }

  /// ดึงข้อมูล sessions จาก local SQLite
  static Future<List<Map<String, dynamic>>> _getLocalSessions() async {
    try {
      // ต้อง import EggDatabase หรือใช้วิธีอื่นในการเข้าถึง local database
      final db = await openDatabase(
        join(await getDatabasesPath(), 'egg.db'),
      );
      
      final sessions = await db.query(
        'egg_session',
        orderBy: 'created_at ASC',
      );
      
      await db.close();
      return sessions;
    } catch (e) {
      print('Error getting local sessions: $e');
      return [];
    }
  }

  /// ดึงข้อมูล items ตาม session_id จาก local SQLite
  static Future<List<Map<String, dynamic>>> _getLocalItemsBySession(int sessionId) async {
    try {
      final db = await openDatabase(
        join(await getDatabasesPath(), 'egg.db'),
      );
      
      final items = await db.query(
        'egg_item',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'id ASC',
      );
      
      await db.close();
      return items;
    } catch (e) {
      print('Error getting local items for session $sessionId: $e');
      return [];
    }
  }
}
