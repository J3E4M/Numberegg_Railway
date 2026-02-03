import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'custom_bottom_nav.dart';
import '../database/egg_database.dart';
import '../database/user_database.dart';
import '../services/supabase_service.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String selectedFilter = 'ทั้งหมด';
  DateTime? _selectedDate;
  bool _showDatePicker = false;
  final Set<int> _selectedSessions = {}; // เก็บ session IDs ที่เลือก

  late Future<List<Map<String, dynamic>>> _historyFuture;
  final ImagePicker _imagePicker = ImagePicker();

  final List<String> filters = [
    'ทั้งหมด',
    'วันนี้',
    'วันที่ผ่านมา',
    'สัปดาห์ที่ผ่านมา',
    'เลือกวันที่',
  ];

  // Form controllers สำหรับการเพิ่ม session (ถ้าต้องการใช้ในอนาคต)
  final _grade0CountController = TextEditingController();
  final _grade1CountController = TextEditingController();
  final _grade2CountController = TextEditingController();
  final _grade3CountController = TextEditingController();
  final _grade4CountController = TextEditingController();
  final _grade5CountController = TextEditingController();
  final _successPercentController = TextEditingController(text: '100.0');
  String? _selectedImagePath;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    debugPrint("INIT HISTORY PAGE");
    _historyFuture = EggDatabase.instance.getHistoryForUI();
  }

  // ฟังก์ชันช่วยเลือกสีตามขนาดไข่
  Color _getEggColor(String tag) {
    if (tag.contains('เบอร์ 0')) return Colors.red;
    if (tag.contains('เบอร์ 1')) return Colors.orange;
    if (tag.contains('เบอร์ 2')) return Colors.amber;
    if (tag.contains('เบอร์ 3')) return Colors.green;
    if (tag.contains('เบอร์ 4')) return Colors.blueGrey;
    if (tag.contains('เบอร์ 5')) return Colors.grey;
    return Colors.grey;
  }

  bool _isSectionAllowed(String section) {
    switch (selectedFilter) {
      case 'วันนี้':
        return section == 'TODAY';
      case 'วันที่ผ่านมา':
        return section == 'YESTERDAY';
      case 'สัปดาห์ที่ผ่านมา':
        return section == 'LAST WEEK';
      case 'เลือกวันที่':
        // สำหรับเลือกวันที่ จะกรองจาก _selectedDate
        return true; // จะกรองใน _getFilteredHistory()
      case 'ทั้งหมด':
      default:
        return true; // รวม OLDER ด้วย
    }
  }

  /// แสดง Date Picker สำหรับเลือกวันที่
  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)), // 1 ปีข้างหน้า
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        selectedFilter = 'เลือกวันที่';
      });
      _refreshHistory();
    }
  }

  /// กรองข้อมูลประวัติตามตัวกรองที่ที่เลือก
  Future<List<Map<String, dynamic>>> _getFilteredHistory() async {
    final db = await EggDatabase.instance.database;
    
    String whereClause = '';
    List<dynamic> whereArgs = [];
    
    if (selectedFilter == 'วันนี้') {
      final today = DateTime.now();
      final todayString = "${today.year.toString().padLeft(4, '0')}-"
          "${today.month.toString().padLeft(2, '0')}-"
          "${today.day.toString().padLeft(2, '0')}";
      whereClause = 'day = ?';
      whereArgs = [todayString];
    } else if (selectedFilter == 'เลือกวันที่' && _selectedDate != null) {
      final selectedDateString = "${_selectedDate!.year.toString().padLeft(4, '0')}-"
          "${_selectedDate!.month.toString().padLeft(2, '0')}-"
          "${_selectedDate!.day.toString().padLeft(2, '0')}";
      whereClause = 'day = ?';
      whereArgs = [selectedDateString];
    }
    
    final result = await db.query(
      'egg_session',
      where: whereClause.isNotEmpty ? whereClause : null,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'created_at DESC',
    );

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return result.map((row) {
      final dayRaw = DateTime.parse(row['day'] as String);
      final targetDay = DateTime(dayRaw.year, dayRaw.month, dayRaw.day);

      final diff = today.difference(targetDay).inDays;

      String section;
      if (diff == 0) {
        section = 'TODAY';
      } else if (diff == 1) {
        section = 'YESTERDAY';
      } else if (diff <= 7) {
        section = 'LAST WEEK';
      } else {
        section = 'OLDER';
      }

      // สร้าง tags จาก DB จริง
      final List<String> tags = [];
      if ((row['grade0_count'] as int) > 0) {
        tags.add("${row['grade0_count']}xเบอร์ 0");
      }
      if ((row['grade1_count'] as int) > 0) {
        tags.add("${row['grade1_count']}xเบอร์ 1");
      }
      if ((row['grade2_count'] as int) > 0) {
        tags.add("${row['grade2_count']}xเบอร์ 2");
      }
      if ((row['grade3_count'] as int) > 0) {
        tags.add("${row['grade3_count']}xเบอร์ 3");
      }
      if ((row['grade4_count'] as int) > 0) {
        tags.add("${row['grade4_count']}xเบอร์ 4");
      }
      if ((row['grade5_count'] as int) > 0) {
        tags.add("${row['grade5_count']}xเบอร์ 5");
      }

      return {
        "sessionId": row['id'],
        "section": section,
        "date": row['created_at'],
        "count": row['egg_count'],
        "isSuccess": (row['success_percent'] as num) >= 60,
        "tags": tags,
        "imagePath": row['image_path'],
      };
    }).toList();
  }

  // ==================== CRUD FUNCTIONS ====================
  
  /// รีเฟรชข้อมูลประวัติ
  void _refreshHistory() {
    setState(() {
      if (selectedFilter == 'เลือกวันที่') {
        _historyFuture = _getFilteredHistory();
      } else {
        _historyFuture = EggDatabase.instance.getHistoryForUI();
      }
    });
  }

  /// ลบ session และ egg items ที่เกี่ยวข้อง
  Future<void> _deleteSession(int sessionId) async {
    try {
      // แสดง dialog ยืนยันการลบ
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('ยืนยันการลบ'),
          content: const Text('คุณต้องการลบข้อมูล session นี้ใช่ไหม?\nการลบจะไม่สามารถกู้คืนได้'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ยกเลิก'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('ลบ', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        // ลบ egg items ก่อน
        await EggDatabase.instance.deleteEggItemsBySession(sessionId);
        
        // ลบ session
        final db = await EggDatabase.instance.database;
        await db.delete(
          'egg_session',
          where: 'id = ?',
          whereArgs: [sessionId],
        );

        // แสดง SnackBar
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ลบข้อมูลเรียบร้อยแล้ว'),
              backgroundColor: Colors.green,
            ),
          );
        }

        // รีเฟรชข้อมูล
        _refreshHistory();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาดในการลบ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// ลบข้อมูลตาม section ที่เลือก
  Future<void> _deleteSectionData(String section) async {
    try {
      String sectionText;
      DateTime? startDate;
      DateTime? endDate;
      
      switch (section) {
        case 'TODAY':
          sectionText = 'วันนี้';
          final now = DateTime.now();
          startDate = DateTime(now.year, now.month, now.day);
          endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
          break;
        case 'YESTERDAY':
          sectionText = 'วันที่ผ่านมา';
          final yesterday = DateTime.now().subtract(const Duration(days: 1));
          startDate = DateTime(yesterday.year, yesterday.month, yesterday.day);
          endDate = DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);
          break;
        case 'LAST WEEK':
          sectionText = 'สัปดาห์ที่ผ่านมา';
          final now = DateTime.now();
          startDate = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 7));
          endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
          break;
        case 'OLDER':
          sectionText = 'ข้อมูลเก่า';
          final now = DateTime.now();
          startDate = DateTime(2020, 1, 1); // ข้อมูลเก่าทั้งหมด
          endDate = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 8));
          break;
        default:
          return;
      }

      // แสดง dialog ยืนยันการลบ
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('ลบข้อมูล$sectionText'),
          content: Text('คุณต้องการลบข้อมูล$sectionTextทั้งหมดใช่ไหม?\nการลบจะไม่สามารถกู้คืนได้'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ยกเลิก'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('ลบ', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        // ลบข้อมูลตามช่วงเวลา
        final db = await EggDatabase.instance.database;
        
        // ลบ egg items ก่อน
        await db.delete(
          'egg_item',
          where: 'session_id IN (SELECT id FROM egg_session WHERE created_at BETWEEN ? AND ?)',
          whereArgs: [startDate?.toIso8601String(), endDate?.toIso8601String()],
        );
        
        // ลบ sessions
        await db.delete(
          'egg_session',
          where: 'created_at BETWEEN ? AND ?',
          whereArgs: [startDate?.toIso8601String(), endDate?.toIso8601String()],
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('ลบข้อมูล$sectionTextเรียบร้อยแล้ว'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }

        // รีเฟรชข้อมูล
        _refreshHistory();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาดในการลบ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// แสดง dialog เลือกรายการที่จะลบ (Multiple Selection)
  void _showMultiSelectDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            height: MediaQuery.of(context).size.height * 0.7,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'เลือกรายการที่จะลบ',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // List of items
                Expanded(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: _historyFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      
                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return const Center(child: Text('ไม่มีข้อมูล'));
                      }
                      
                      final history = snapshot.data!;
                      final grouped = _groupHistoryBySection(history);
                      
                      return Column(
                        children: [
                          // Select All / Deselect All
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _selectedSessions.clear();
                                      // เลือกทั้งหมด
                                      for (var section in grouped) {
                                        for (var item in section['items']) {
                                          _selectedSessions.add(item['sessionId']);
                                        }
                                      }
                                    });
                                  },
                                  icon: const Icon(Icons.select_all),
                                  label: const Text('เลือกทั้งหมด'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _selectedSessions.clear();
                                    });
                                  },
                                  icon: const Icon(Icons.deselect),
                                  label: const Text('ยกเลิกทั้งหมด'),
                                ),
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Items list
                          Expanded(
                            child: ListView.builder(
                              itemCount: grouped.length,
                              itemBuilder: (context, index) {
                                final section = grouped[index];
                                final sectionTitle = _getSectionTitle(section['section']);
                                final items = section['items'] as List<Map<String, dynamic>>;
                                
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Section header
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      child: Text(
                                        sectionTitle,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ),
                                    
                                    // Items in this section
                                    ...items.map((item) {
                                      final sessionId = item['sessionId'];
                                      final isSelected = _selectedSessions.contains(sessionId);
                                      
                                      return CheckboxListTile(
                                        value: isSelected,
                                        onChanged: (bool? value) {
                                          setState(() {
                                            if (value == true) {
                                              _selectedSessions.add(sessionId);
                                            } else {
                                              _selectedSessions.remove(sessionId);
                                            }
                                          });
                                        },
                                        title: Text('${item['count']} ฟอง'),
                                        subtitle: Text(item['date']),
                                        secondary: Container(
                                          width: 50,
                                          height: 50,
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade200,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: item['imagePath'] != null && File(item['imagePath']).existsSync()
                                              ? ClipRRect(
                                                  borderRadius: BorderRadius.circular(8),
                                                  child: Image.file(
                                                    File(item['imagePath']),
                                                    fit: BoxFit.cover,
                                                  ),
                                                )
                                              : const Icon(Icons.image, color: Colors.grey),
                                        ),
                                      );
                                    }).toList(),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                
                // Bottom actions
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('ยกเลิก'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _selectedSessions.isEmpty ? null : () {
                          Navigator.pop(context);
                          _deleteSelectedSessions();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        child: Text('ลบ ${_selectedSessions.length} รายการ'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// ลบ sessions ที่เลือก
  Future<void> _deleteSelectedSessions() async {
    if (_selectedSessions.isEmpty) return;
    
    try {
      // แสดง dialog ยืนยัน
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('ลบ ${_selectedSessions.length} รายการ'),
          content: Text('คุณต้องการลบ ${_selectedSessions.length} รายการที่เลือกใช่ไหม?\nการลบจะไม่สามารถกู้คืนได้'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ยกเลิก'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('ลบ', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        // ลบทีละรายการ
        for (final sessionId in _selectedSessions) {
          await EggDatabase.instance.deleteEggItemsBySession(sessionId);
          
          final db = await EggDatabase.instance.database;
          await db.delete(
            'egg_session',
            where: 'id = ?',
            whereArgs: [sessionId],
          );
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('ลบ ${_selectedSessions.length} รายการเรียบร้อยแล้ว'),
              backgroundColor: Colors.green,
            ),
          );
        }

        // ล้างรายการที่เลือกและรีเฟรช
        setState(() {
          _selectedSessions.clear();
        });
        _refreshHistory();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาดในการลบ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// จัดกลุ่มข้อมูลตาม section
  List<Map<String, dynamic>> _groupHistoryBySection(List<Map<String, dynamic>> history) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    
    for (final item in history) {
      final section = item['section'] ?? 'OTHER';
      if (!grouped.containsKey(section)) {
        grouped[section] = [];
      }
      grouped[section]!.add(item);
    }
    
    // จัดลำดับ section
    final order = ['TODAY', 'YESTERDAY', 'LAST WEEK', 'OLDER'];
    final result = <Map<String, dynamic>>[];
    
    for (final section in order) {
      if (grouped.containsKey(section)) {
        result.add({
          'section': section,
          'items': grouped[section]!,
        });
      }
    }
    
    return result;
  }

  /// ดึงชื่อ section เป็นภาษาไทย
  String _getSectionTitle(String section) {
    switch (section) {
      case 'TODAY':
        return 'วันนี้';
      case 'YESTERDAY':
        return 'วันที่ผ่านมา';
      case 'LAST WEEK':
        return 'สัปดาห์ที่ผ่านมา';
      case 'OLDER':
        return 'ข้อมูลเก่า';
      default:
        return 'อื่นๆ';
    }
  }
  void _showDeleteSectionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('เลือกช่วงเวลาที่จะลบ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDeleteSectionOption('วันนี้', 'TODAY'),
            _buildDeleteSectionOption('วันที่ผ่านมา', 'YESTERDAY'),
            _buildDeleteSectionOption('สัปดาห์ที่ผ่านมา', 'LAST WEEK'),
            _buildDeleteSectionOption('ข้อมูลเก่า', 'OLDER'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
        ],
      ),
    );
  }

  /// สร้างปุ่มเลือก section สำหรับลบ
  Widget _buildDeleteSectionOption(String title, String section) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: Text(title),
        leading: Icon(
          _getSectionIcon(section),
          color: _getSectionColor(section),
        ),
        onTap: () {
          Navigator.pop(context);
          _deleteSectionData(section);
        },
      ),
    );
  }

  /// ดึง icon ตาม section
  IconData _getSectionIcon(String section) {
    switch (section) {
      case 'TODAY':
        return Icons.today;
      case 'YESTERDAY':
        return Icons.history; // เปลี่ยนจาก Icons.yesterday เป็น Icons.history
      case 'LAST WEEK':
        return Icons.date_range;
      case 'OLDER':
        return Icons.history;
      default:
        return Icons.folder;
    }
  }

  /// ดึงสีตาม section
  Color _getSectionColor(String section) {
    switch (section) {
      case 'TODAY':
        return Colors.green;
      case 'YESTERDAY':
        return Colors.orange;
      case 'LAST WEEK':
        return Colors.blue;
      case 'OLDER':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }
  Future<void> _clearAllData() async {
    try {
      // แสดง dialog ยืนยันการลบทั้งหมด
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('ลบข้อมูลทั้งหมด'),
          content: const Text('⚠️ คำเตือน: การลบข้อมูลทั้งหมดจะไม่สามารถกู้คืนได้\nคุณแน่ใจว่าต้องการลบข้อมูลทั้งหมดใช่ไหม?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ยกเลิก'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('ลบทั้งหมด', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        // ใช้ฟังก์ชันจาก egg_database.dart แทน
        final db = await EggDatabase.instance.database;
        await db.delete('egg_session');
        await db.delete('egg_item');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ลบข้อมูลทั้งหมดเรียบร้อยแล้ว'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }

        // รีเฟรชข้อมูล
        _refreshHistory();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาดในการลบ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// เลือกรูปภาพสำหรับ session ใหม่
  Future<void> _pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );

      if (image != null) {
        setState(() {
          _selectedImagePath = image.path;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาดในการเลือกรูป: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// เพิ่ม session ใหม่พร้อมข้อมูลไข่
  Future<void> _addNewSession() async {
    if (_grade0CountController.text.isEmpty ||
        _grade1CountController.text.isEmpty ||
        _grade2CountController.text.isEmpty ||
        _grade3CountController.text.isEmpty ||
        _grade4CountController.text.isEmpty ||
        _grade5CountController.text.isEmpty ||
        _selectedImagePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('กรุณากรอกข้อมูลให้ครบถ้วยและเลือกรูปภาพ'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final grade0Count = int.parse(_grade0CountController.text);
      final grade1Count = int.parse(_grade1CountController.text);
      final grade2Count = int.parse(_grade2CountController.text);
      final grade3Count = int.parse(_grade3CountController.text);
      final grade4Count = int.parse(_grade4CountController.text);
      final grade5Count = int.parse(_grade5CountController.text);
      final totalEggs = grade0Count + grade1Count + grade2Count + grade3Count + grade4Count + grade5Count;
      final successPercent = double.parse(_successPercentController.text);

      // สร้าง session ใหม่ใน Supabase (แทน local SQLite)
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id') ?? 1; // Default to 1 if not found
      
      debugPrint("🔍 HistoryPage Debug - User ID: $userId");
      
      try {
        // สร้าง egg items สำหรับส่งไป Supabase
        final eggItems = <Map<String, dynamic>>[];
        final gradeBuckets = <int, int>{
          0: grade0Count,
          1: grade1Count,
          2: grade2Count,
          3: grade3Count,
          4: grade4Count,
          5: grade5Count,
        };
        for (int grade = 0; grade <= 5; grade++) {
          for (int i = 0; i < (gradeBuckets[grade] ?? 0); i++) {
            final confidence = 85.0 - (grade * 5) + (i * 1.5);

            eggItems.add({
              'grade': grade,
              'confidence': confidence,
            });
          }
        }

        // สร้าง session พร้อม items ใน Supabase
        await SupabaseService.createEggSessionWithItems(
          userId: userId,
          imagePath: _selectedImagePath!,
          eggCount: totalEggs,
          successPercent: successPercent,
          grade0Count: grade0Count,
          grade1Count: grade1Count,
          grade2Count: grade2Count,
          grade3Count: grade3Count,
          grade4Count: grade4Count,
          grade5Count: grade5Count,
          day: DateTime.now().toIso8601String().substring(0, 10),
          eggItems: eggItems,
        );

        debugPrint("✅ Supabase save successful");

        // ✅ HYBRID: บันทึกลง Local SQLite ด้วยหลัง Supabase สำเริ่ม
        try {
          debugPrint("🗄️ HistoryPage: Saving manual entry to SQLite...");
          debugPrint("📊 History manual data - Total: $totalEggs, Grade0: $grade0Count, Grade1: $grade1Count, Grade2: $grade2Count, Grade3: $grade3Count, Grade4: $grade4Count, Grade5: $grade5Count");
          
          final localSessionId = await EggDatabase.instance.insertSession(
            userId: userId,
            imagePath: _selectedImagePath!,
            eggCount: totalEggs,
            successPercent: successPercent,
            grade0Count: grade0Count,
            grade1Count: grade1Count,
            grade2Count: grade2Count,
            grade3Count: grade3Count,
            grade4Count: grade4Count,
            grade5Count: grade5Count,
            day: DateTime.now().toIso8601String().substring(0, 10),
          );

          debugPrint("✅ HistoryPage: Manual session saved with ID: $localSessionId");

          // บันทึก egg items ลง SQLite
          int itemsSaved = 0;
          for (int grade = 0; grade <= 5; grade++) {
            for (int i = 0; i < (gradeBuckets[grade] ?? 0); i++) {
              final confidence = 85.0 - (grade * 5) + (i * 1.5);

              await EggDatabase.instance.insertEggItem(
                sessionId: localSessionId,
                grade: grade,
                confidence: confidence,
              );
              itemsSaved++;
            }
          }
          
          debugPrint("✅ HistoryPage: Total egg items saved to SQLite: $itemsSaved");
          debugPrint("✅ Local SQLite save successful: Session $localSessionId");
        } catch (sqliteError) {
          debugPrint("❌ Local SQLite save failed: $sqliteError");
          // ไม่ต้องแสดง error ให้ user เพราะ Supabase สำเร็จแล้ว
        }

      } catch (e) {
        debugPrint("❌ Supabase save failed: $e");
        
        // Fallback ไป local SQLite ถ้า Supabase ล้มเหลว
        try {
          debugPrint("🗄️ HistoryPage: Fallback - saving to SQLite only...");
          debugPrint("📊 Fallback data - Total: $totalEggs, Grade0: $grade0Count, Grade1: $grade1Count, Grade2: $grade2Count, Grade3: $grade3Count, Grade4: $grade4Count, Grade5: $grade5Count");
          
          final sessionId = await EggDatabase.instance.insertSession(
            userId: userId,
            imagePath: _selectedImagePath!,
            eggCount: totalEggs,
            successPercent: successPercent,
            grade0Count: grade0Count,
            grade1Count: grade1Count,
            grade2Count: grade2Count,
            grade3Count: grade3Count,
            grade4Count: grade4Count,
            grade5Count: grade5Count,
            day: DateTime.now().toIso8601String().substring(0, 10),
          );

          debugPrint("✅ HistoryPage: Fallback session saved with ID: $sessionId");

          // เพิ่ม egg items (สร้างข้อมูลจำลองสำหรับแต่ละไข่)
          final gradeBuckets = <int, int>{
            0: grade0Count,
            1: grade1Count,
            2: grade2Count,
            3: grade3Count,
            4: grade4Count,
            5: grade5Count,
          };
          int fallbackItemsSaved = 0;
          for (int grade = 0; grade <= 5; grade++) {
            for (int i = 0; i < (gradeBuckets[grade] ?? 0); i++) {
              final confidence = 85.0 - (grade * 5) + (i * 1.5);

              await EggDatabase.instance.insertEggItem(
                sessionId: sessionId,
                grade: grade,
                confidence: confidence,
              );
              fallbackItemsSaved++;
            }
          }
          debugPrint("✅ HistoryPage: Fallback total egg items saved: $fallbackItemsSaved");
          debugPrint("✅ Fallback SQLite save successful: Session $sessionId");
        } catch (fallbackError) {
          debugPrint("❌ Fallback SQLite also failed: $fallbackError");
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เพิ่มข้อมูล session ใหม่เรียบร้อยแล้ว ($totalEggs ฟอง)'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // ปิด dialog และรีเฟรชข้อมูล
      Navigator.pop(context);
      _refreshHistory();
      
      // ล้างฟอร์ม
      _clearForm();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาดในการเพิ่มข้อมูล: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// ล้างฟอร์ม
  void _clearForm() {
    _grade0CountController.clear();
    _grade1CountController.clear();
    _grade2CountController.clear();
    _grade3CountController.clear();
    _grade4CountController.clear();
    _grade5CountController.clear();
    _successPercentController.text = '100.0';
    _selectedImagePath = null;
  }

  /// แสดง dialog เพิ่ม session ใหม่
  void _showAddSessionDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'เพิ่ม Session ใหม่',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Image picker
                  GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      height: 150,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: _selectedImagePath != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                File(_selectedImagePath!),
                                fit: BoxFit.cover,
                              ),
                            )
                          : const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_photo_alternate, 
                                     size: 40, color: Colors.grey),
                                const SizedBox(height: 8),
                                Text('เลือกรูปภาพ', 
                                     style: TextStyle(color: Colors.grey)),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Egg counts
                  const Text('จำนวนไข่แยกตามขนาด',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _grade0CountController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'เบอร์ 0 (Extra Large)',
                            border: OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.egg),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _grade1CountController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'เบอร์ 1 (Large)',
                            border: OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.egg_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _grade2CountController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'เบอร์ 2 (Medium)',
                            border: OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.egg_alt),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Success percent
                  TextField(
                    controller: _successPercentController,
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'อัตราความสำเร็จ (%)',
                      border: OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.percent),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            _clearForm();
                            Navigator.pop(context);
                          },
                          child: const Text('ยกเลิก'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _addNewSession,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFC107),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : const Text('เพิ่มข้อมูล'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // ---------- HEADER ----------
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'History',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  Row(
                    children: [
                      // Clear data button (เมนูเลือกวิธีลบ)
                      PopupMenuButton<String>(
                        icon: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.delete_sweep, color: Colors.red.shade700),
                        ),
                        onSelected: (value) {
                          if (value == 'select') {
                            _showMultiSelectDeleteDialog();
                          } else if (value == 'section') {
                            _showDeleteSectionDialog();
                          } else if (value == 'all') {
                            _clearAllData();
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'select',
                            child: Row(
                              children: [
                                Icon(Icons.checklist, color: Colors.blue),
                                SizedBox(width: 8),
                                Text('เลือกลบรายการ'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'section',
                            child: Row(
                              children: [
                                Icon(Icons.folder_delete, color: Colors.orange),
                                SizedBox(width: 8),
                                Text('ลบตามช่วงเวลา'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'all',
                            child: Row(
                              children: [
                                Icon(Icons.delete_forever, color: Colors.red),
                                SizedBox(width: 8),
                                Text('ลบทั้งหมด'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      // Date picker button (แทน search)
                      IconButton(
                        onPressed: _selectDate,
                        icon: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.calendar_today, color: Colors.blue.shade700),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ---------- FILTER ----------
            SizedBox(
              height: 40,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                scrollDirection: Axis.horizontal,
                itemCount: filters.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final item = filters[index];
                  final isSelected = selectedFilter == item;
                  return GestureDetector(
                    onTap: () {
                      setState(() => selectedFilter = item);
                      if (item == 'เลือกวันที่') {
                        _selectDate();
                      } else {
                        _refreshHistory();
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFFFF8E1)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(25),
                        border: isSelected
                            ? Border.all(
                                color: const Color(0xFFFFC107), width: 1.5)
                            : Border.all(color: Colors.transparent),
                      ),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              item,
                              style: TextStyle(
                                color: isSelected
                                    ? const Color(0xFF6D4C41)
                                    : Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (item == 'เลือกวันที่' && _selectedDate != null)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Text(
                                  '(${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year})',
                                  style: TextStyle(
                                    color: const Color(0xFF6D4C41),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // แสดงวันที่ที่เลือก (ถ้าเลือกวันที่)
            if (selectedFilter == 'เลือกวันที่' && _selectedDate != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFC107).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_today, color: const Color(0xFF6D4C41)),
                      const SizedBox(width: 8),
                      Text(
                        'กำลังแสดงข้อมูลวันที่: ${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}',
                        style: const TextStyle(
                          color: Color(0xFF6D4C41),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _selectDate,
                        child: Icon(Icons.edit, color: const Color(0xFF6D4C41)),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 24),

            // ---------- CONTENT ----------
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _historyFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text("เกิดข้อผิดพลาด: ${snapshot.error}"),
                    );
                  }

                  final rawData = snapshot.data ?? [];

                  if (rawData.isEmpty) {
                    return const Center(child: Text("ยังไม่มีประวัติ"));
                  }

                  // 🔁 Filter logic
                  List<Map<String, dynamic>> displayList = rawData
                      .where((e) => _isSectionAllowed(e['section']))
                      .toList();

                  // 🔁 Group by section
                  final Map<String, List<Map<String, dynamic>>> groupedData =
                      {};
                  for (var item in displayList) {
                    final section = item['section']?.toString() ?? 'UNKNOWN';

                    groupedData.putIfAbsent(section, () => []);
                    groupedData[section]!.add(item);
                  }
                  debugPrint("HISTORY RAW DATA:");
                  for (var e in rawData) {
                    debugPrint(e.toString());
                  }
                  for (var e in rawData) {
                    debugPrint("day=${e['date']} section=${e['section']}");
                  }
                  const sectionOrder = [
                    'TODAY',
                    'YESTERDAY',
                    'LAST WEEK',
                    'OLDER'
                  ];

                  final orderedEntries = sectionOrder
                      .where((key) => groupedData.containsKey(key))
                      .map((key) => MapEntry(key, groupedData[key]!))
                      .toList();

                  return ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    children: [
                      ...orderedEntries.map((entry) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildTimelineHeader(entry.key),
                            ...entry.value.map(
                              (data) => Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: _buildHistoryCard(context, data),
                              ),
                            ),
                          ],
                        );
                      }),
                      const SizedBox(height: 80),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFFFC107),
        child: const Icon(Icons.camera_alt, color: Colors.black),
        onPressed: () {
          Navigator.pushNamed(context, '/camera');
        },
      ),
      bottomNavigationBar: const CustomBottomNav(currentIndex: 0),
    );
  }

  // ---------- UI COMPONENTS ----------
  Widget _buildTimelineHeader(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, top: 8),
      child: Row(
        children: [
          Expanded(child: Divider(color: Colors.grey.shade300)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              text,
              style: TextStyle(
                color: Colors.grey.shade400,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(child: Divider(color: Colors.grey.shade300)),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(BuildContext context, Map<String, dynamic> data) {
    final String date = data['date']?.toString() ?? '-';
    final int count = data['count'] ?? 0;
    final bool isSuccess = data['isSuccess'] ?? true;
    final List<String> tags = List<String>.from(data['tags'] ?? []);
    final String? imagePath = data['imagePath'];
    
    // Extract session ID from the data (we need to get it from the database)
    // For now, we'll use a workaround by getting the session ID from the raw data
    final int sessionId = data['sessionId'] ?? 0;

    return Dismissible(
      key: Key(sessionId.toString()),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete, color: Colors.white, size: 30),
            Text('ลบ', style: TextStyle(color: Colors.white, fontSize: 14)),
          ],
        ),
      ),
      onDismissed: (direction) {
        _deleteSession(sessionId);
      },
      child: GestureDetector(
        onTap: () {
          Navigator.pushNamed(
            context,
            '/result',
            arguments: data,
          );
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFDD865),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              // ---------- IMAGE ----------
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: imagePath != null && File(imagePath).existsSync()
                      ? Image.file(File(imagePath), fit: BoxFit.cover)
                      : const Icon(Icons.image, color: Colors.grey),
                ),
              ),

              const SizedBox(width: 16),

              // ---------- INFO ----------
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // วันที่
                    Text(
                      date,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // จำนวนไข่
                    Text(
                      "$count ฟอง",
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 6),

                    // ---------- TAGS (เกรดไข่) ----------
                    Wrap(
                      spacing: 6,
                      children: tags.map((tag) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            tag,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),

              // ---------- STATUS + ARROW ----------
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSuccess ? Colors.green : Colors.orange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isSuccess ? "สำเร็จ" : "ตรวจสอบ",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Icon(
                    Icons.chevron_right,
                    color: Colors.white,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
