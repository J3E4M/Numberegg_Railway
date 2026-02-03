import 'package:flutter/foundation.dart';
import 'dart:io';

class ServerConfig {
  // Supabase Configuration
  static const String _supabaseUrl = 'https://gbxxwojlihgrbtthmusq.supabase.co'; // Supabase URL
  static const String _supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdieHh3b2psaWhncmJ0dGhtdXNxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM5NTQ1MjYsImV4cCI6MjA3OTUzMDUyNn0.-XKw6NOhrWBxp4gLvQbPExLU2PHhUfUWdD3zsSc_9_k';
  
  // Detection API URLs
  static const String _railwayUrl = 'https://numbereggrailway-production.up.railway.app'; // Railway URL (production)
  static const String _developmentUrl = 'http://localhost:8000'; // Local development
  static const String _stagingUrl = 'https://your-staging-server.com'; // Staging server
  static const String _localNetworkUrl = 'http://192.168.1.100:8000'; // Local network IP
  static const String _simpleServerUrl = 'http://localhost:8000'; // For simple_server.py
  
  // Environment selection
  static const String _currentEnvironment = 'production'; // development, staging, production, simple, local_network
  
  /// ดึง URL สำหรับการตรวจจับ (Detection API)
  static Future<String> getDetectUrl() async {
    return '${await getApiUrl()}/detect';
  }
  
  /// ดึง URL สำหรับ API หลัก (Detection API)
  static Future<String> getApiUrl() async {
    // ถ้าเป็น debug mode ให้ใช้ development URL
    if (kDebugMode) {
      return _getDevelopmentUrl();
    }
    
    // ถ้าเป็น production ให้ใช้ production URL
    return _getProductionUrl();
  }
  
  static String _getDevelopmentUrl() {
    switch (_currentEnvironment) {
      case 'development':
        return _developmentUrl;
      case 'staging':
        return _stagingUrl;
      case 'simple':
        return _simpleServerUrl;
      case 'local_network':
        return _localNetworkUrl;
      default:
        return _developmentUrl;
    }
  }
  
  static String _getProductionUrl() {
    return _railwayUrl;
  }
  
  /// ดึง URL สำหรับ API อื่นๆ (Supabase)
  static Future<String> getSupabaseApiUrl() async {
    return _supabaseUrl;
  }
  
  /// ดึง Railway URL สำหรับ YOLO detection
  static String getRailwayUrl() {
    return _railwayUrl;
  }
  
  /// ดึง Supabase URL
  static String getSupabaseUrl() {
    return _supabaseUrl;
  }
  
  /// ดึง Supabase Anon Key
  static String getSupabaseAnonKey() {
    return _supabaseAnonKey;
  }
  
  /// สำหรับ testing แบบ manual
  static String getCustomUrl(String url) {
    return url;
  }
  
  /// ฟังก์ชันสำหรับตรวจสอบว่า server พร้อมใช้งานหรือไม่
  static Future<bool> checkServerHealth(String baseUrl) async {
    try {
      final uri = Uri.parse('$baseUrl/detect');
      final request = await HttpClient().getUrl(uri);
      final response = await request.close();
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Health check failed for $baseUrl: $e');
      return false;
    }
  }
}
