import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '/custom_bottom_nav.dart';
import '../database/egg_database.dart';
import '../services/supabase_service.dart';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/rendering.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class SummaryReportCard extends StatelessWidget {
  final int totalEgg;
  final double avgSuccess;
  final int grade0;
  final int grade1;
  final int grade2;
  final int grade3;
  final int grade4;
  final int grade5;

  const SummaryReportCard({
    super.key,
    required this.totalEgg,
    required this.avgSuccess,
    required this.grade0,
    required this.grade1,
    required this.grade2,
    required this.grade3,
    required this.grade4,
    required this.grade5,
  });

  List<String> _buildAutoInsight() {
    final List<String> insights = [];

    if (grade0 > grade1 && grade0 > grade2 && grade0 > grade3 && grade0 > grade4 && grade0 > grade5) {
      insights.add('📈 พบไข่เบอร์ 0 มีสัดส่วนสูง แสดงว่าผลผลิตอยู่ในเกณฑ์ดี');
    }

    if (grade2 >= grade0 && grade2 >= grade1 && grade2 >= grade3 && grade2 >= grade4 && grade2 >= grade5) {
      insights.add('🟡 พบไข่เบอร์ 2 เป็นสัดส่วนมากที่สุด');
    }

    if (grade5 > grade0) {
      insights.add(
          '⚠️ พบว่าไข่เบอร์ 5 มีจำนวนมาก ควรปรับปรุงการเลี้ยงหรือโภชนาการ');
    }

    if (avgSuccess < 70) {
      insights.add('⚠️ อัตราความสำเร็จยังไม่สูง ควรปรับกระบวนการคัดแยก');
    } else {
      insights.add('✅ อัตราความสำเร็จอยู่ในระดับที่ดี');
    }

    return insights;
  }

  @override
  Widget build(BuildContext context) {
    final insights = _buildAutoInsight();

    return SingleChildScrollView(
      // ⭐ แก้ overflow
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🔢 SUMMARY
          Center(
            child: Column(
              children: [
                const Text('ไข่ทั้งหมด', style: TextStyle(color: Colors.grey)),
                Text(
                  '$totalEgg ฟอง',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'อัตราความสำเร็จเฉลี่ย ${avgSuccess.toStringAsFixed(1)}%',
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          const Divider(),

          // 🥚 BREAKDOWN
          const Text(
            'สัดส่วนขนาดไข่',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          _buildRow('เบอร์ 0 (Extra Large)', grade0, Colors.red),
          _buildRow('เบอร์ 1 (Large)', grade1, Colors.orange),
          _buildRow('เบอร์ 2 (Medium)', grade2, Colors.amber),
          _buildRow('เบอร์ 3 (Small)', grade3, Colors.green),
          _buildRow('เบอร์ 4 (Extra Small)', grade4, Colors.blueGrey),
          _buildRow('เบอร์ 5 (Pewee)', grade5, Colors.grey),

          const SizedBox(height: 16),
          const Divider(),

          // 🧠 INSIGHT
          const Text(
            'สรุปผลการวิเคราะห์ (beta)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          ...insights.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(e),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(String label, int value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          Text('$value ฟอง'),
        ],
      ),
    );
  }
}

class EggTrendLineChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;

  const EggTrendLineChart({
    super.key,
    required this.data,
  });

  // ---------- UTIL ----------
  double _calculateGrowthPercent(List<double> values) {
    if (values.length < 2 || values.first == 0) return 0;
    return ((values.last - values.first) / values.first) * 100;
  }

  Color _trendColor(double percent) {
    if (percent >= 10) return Colors.green;
    if (percent >= 0) return Colors.orange;
    return Colors.red;
  }

  IconData _trendIcon(double percent) {
    if (percent >= 10) return Icons.trending_up;
    if (percent >= 0) return Icons.trending_flat;
    return Icons.trending_down;
  }

  String _trendLabel(double percent) {
    if (percent >= 10) return 'GOOD';
    if (percent >= 0) return 'WARNING';
    return 'ALERT';
  }

  String _formatDay(String rawDay) {
    final d = DateTime.parse(rawDay);
    return '${d.day}/${d.month}';
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Center(child: Text('ไม่มีข้อมูล'));
    }

    final values = data.map((e) => (e['total'] as num).toDouble()).toList();

    final growthPercent = _calculateGrowthPercent(values);
    final color = _trendColor(growthPercent);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---------- HEADER (ย้าย GOOD ลงล่าง) ----------
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(_trendIcon(growthPercent), size: 14, color: color),
                  const SizedBox(width: 4),
                  Text(
                    _trendLabel(growthPercent),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Text(
              '${growthPercent.toStringAsFixed(1)}%',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),

        const SizedBox(height: 6),

        // ---------- LINE CHART ----------
        SizedBox(
          height: 145, // ⭐ ลดขนาดกราฟ
          child: LineChart(
            LineChartData(
              clipData: FlClipData.none(),
              minX: 0,
              maxX: values.length - 1,

              minY: values.reduce((a, b) => a < b ? a : b) - 2,
              maxY: values.reduce((a, b) => a > b ? a : b) + 2,

              borderData: FlBorderData(show: false),

              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 5,
              ),

              // ---------- X AXIS (DATE) ----------
              titlesData: FlTitlesData(
                topTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    reservedSize: 22,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 || index >= data.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _formatDay(data[index]['day']),
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.black54,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // ---------- TOOLTIP ----------
              lineTouchData: LineTouchData(
                handleBuiltInTouches: true,
                touchTooltipData: LineTouchTooltipData(
                  tooltipBgColor: Colors.black87,
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItems: (spots) {
                    return spots.map((spot) {
                      final index = spot.x.toInt();
                      final day = _formatDay(data[index]['day']);
                      final total = data[index]['total'];

                      return LineTooltipItem(
                        '$day\n$total ฟอง',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    }).toList();
                  },
                ),
              ),

              // ---------- LINE ----------
              lineBarsData: [
                LineChartBarData(
                  spots: List.generate(
                    values.length,
                    (i) => FlSpot(i.toDouble(), values[i]),
                  ),
                  isCurved: true,
                  barWidth: 3,
                  color: color,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                      radius: 4,
                      color: Colors.white,
                      strokeWidth: 2,
                      strokeColor: color,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    color: color.withOpacity(0.12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class TodayEggDonutChart extends StatelessWidget {
  final int grade0;
  final int grade1;
  final int grade2;
  final int grade3;
  final int grade4;
  final int grade5;

  const TodayEggDonutChart({
    super.key,
    required this.grade0,
    required this.grade1,
    required this.grade2,
    required this.grade3,
    required this.grade4,
    required this.grade5,
  });

  @override
  Widget build(BuildContext context) {
    final total = grade0 + grade1 + grade2 + grade3 + grade4 + grade5;

    final items = [
      _EggItem('เบอร์ 0', grade0, Colors.red),
      _EggItem('เบอร์ 1', grade1, Colors.orange),
      _EggItem('เบอร์ 2', grade2, Colors.amber),
      _EggItem('เบอร์ 3', grade3, Colors.green),
      _EggItem('เบอร์ 4', grade4, Colors.blueGrey),
      _EggItem('เบอร์ 5', grade5, Colors.grey),
    ];

    final maxItem = items.reduce((a, b) => a.count >= b.count ? a : b);

    PieChartSectionData section(_EggItem e, bool highlight) {
      return PieChartSectionData(
        value: e.count.toDouble(),
        color: e.color,
        radius: highlight ? 38 : 34,
        title: e.count == 0 ? '' : '${e.label}\n${e.count}',
        titleStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.black,
          height: 1.2,
        ),
        titlePositionPercentageOffset: 0.6,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ---------- LEFT (DONUT) ----------
          Expanded(
            flex: 5,
            child: Center(
              child: SizedBox(
                width: 160,
                height: 160,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        centerSpaceRadius: 46,
                        sectionsSpace: 3,
                        sections:
                            items.map((e) => section(e, e == maxItem)).toList(),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'วันนี้',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        Text(
                          '$total',
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text(
                          'ฟอง',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ---------- SPACE ----------
          const SizedBox(width: 12),

          // ---------- RIGHT (INFO) ----------
          Expanded(
            flex: 4,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'สรุปผลวันนี้',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...items.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _infoRow(
                        'ไข่${e.label}',
                        '${e.count} ฟอง',
                        e.color,
                        bold: e == maxItem,
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

  Widget _infoRow(
    String label,
    String value,
    Color color, {
    bool bold = false,
  }) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
        Text(
          value,
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 13,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

class _EggItem {
  final String label;
  final int count;
  final Color color;

  _EggItem(this.label, this.count, this.color);
}

class _HomePageState extends State<HomePage> {
  String selectedFilter = 'ทั้งหมด';
  final _eggCountCtrl = TextEditingController();
  int _big = 0;
  int _medium = 0;
  int _small = 0;
  int _grade3 = 0;
  int _grade4 = 0;
  int _grade5 = 0;
  DateTime _selectedDate = DateTime.now();
  final GlobalKey _captureKey = GlobalKey();

  int get _totalEgg => _big + _medium + _small + _grade3 + _grade4 + _grade5;

  Future<void> _captureAndSave() async {
    try {
      // 🔐 ขอ permission
      final status = await Permission.photos.request();
      if (!status.isGranted) return;

      // 📸 Capture
      final boundary = _captureKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;

      final ui.Image image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) return;

      final pngBytes = byteData.buffer.asUint8List();

      // 📂 โฟลเดอร์ Pictures
      final directory = Directory('/storage/emulated/0/Pictures/NumberEgg');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final filePath =
          '${directory.path}/egg_report_${DateTime.now().millisecondsSinceEpoch}.png';

      final file = File(filePath);
      await file.writeAsBytes(pngBytes);

      // 🔄 แจ้ง Android ให้ Gallery เห็น
      await Process.run(
        'am',
        [
          'broadcast',
          '-a',
          'android.intent.action.MEDIA_SCANNER_SCAN_FILE',
          '-d',
          'file://$filePath'
        ],
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('📸 บันทึกรูปลง Gallery แล้ว')),
      );
    } catch (e) {
      debugPrint('❌ Save error: $e');
    }
  }

  Future<void> _confirmNewSession() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('เริ่ม Session ใหม่'),
          content: const Text(
            'การดำเนินการนี้จะลบข้อมูลการวิเคราะห์ทั้งหมด\nไม่สามารถกู้คืนได้ คุณต้องการดำเนินการต่อหรือไม่?',
          ),
          actions: [
            TextButton(
              child: const Text('ยกเลิก'),
              onPressed: () => Navigator.pop(context, false),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('ยืนยันลบ'),
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await EggDatabase.instance.clearAllData(); // ⬅️ ฟังก์ชัน DB
      setState(() {}); // รีโหลด UI
    }
  }

  Widget _eggInputField(
    String label,
    int value,
    Function(int) onChanged,
  ) {
    return TextField(
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      onChanged: (v) => onChanged(int.tryParse(v) ?? 0),
    );
  }

  void _showAddEggDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('เพิ่มข้อมูลไข่'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 🔢 TOTAL AUTO
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'จำนวนไข่ทั้งหมด',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '$_totalEgg ฟอง',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                    const Divider(height: 24),

                    _eggInputField('เบอร์ 0 (Extra Large)', _big, (v) {
                      setDialogState(() => _big = v);
                    }),
                    const SizedBox(height: 10),

                    _eggInputField('เบอร์ 1 (Large)', _medium, (v) {
                      setDialogState(() => _medium = v);
                    }),
                    const SizedBox(height: 10),

                    _eggInputField('เบอร์ 2 (Medium)', _small, (v) {
                      setDialogState(() => _small = v);
                    }),
                    const SizedBox(height: 10),

                    _eggInputField('เบอร์ 3 (Small)', _grade3, (v) {
                      setDialogState(() => _grade3 = v);
                    }),
                    const SizedBox(height: 10),

                    _eggInputField('เบอร์ 4 (Extra Small)', _grade4, (v) {
                      setDialogState(() => _grade4 = v);
                    }),
                    const SizedBox(height: 10),

                    _eggInputField('เบอร์ 5 (Pewee)', _grade5, (v) {
                      setDialogState(() => _grade5 = v);
                    }),

                    const SizedBox(height: 14),

                    // 📅 DATE
                    Row(
                      children: [
                        const Icon(Icons.date_range),
                        const SizedBox(width: 8),
                        Text(
                          '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                        ),
                        const Spacer(),
                        TextButton(
                          child: const Text('เลือกวันที่'),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _selectedDate,
                              firstDate: DateTime(2023),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) {
                              setDialogState(() => _selectedDate = picked);
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  child: const Text('ยกเลิก'),
                  onPressed: () => Navigator.pop(context),
                ),
                ElevatedButton(
                  child: const Text('บันทึก'),
                  onPressed: _totalEgg > 0 ? _saveManualEggData : null,
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _counterRow(String label, int value, Function(int) onChanged) {
    return Row(
      children: [
        Expanded(child: Text('ไข่$label')),
        IconButton(
          icon: const Icon(Icons.remove),
          onPressed: value > 0 ? () => onChanged(value - 1) : null,
        ),
        Text('$value'),
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: () => onChanged(value + 1),
        ),
      ],
    );
  }

  Future<void> _saveManualEggData() async {
    if (_totalEgg <= 0) return;

    final day =
        '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id') ?? 1; // Default to 1 if not found
    
    debugPrint("🔍 Debug - User ID from SharedPreferences: $userId");
    debugPrint("🔍 Debug - All prefs keys: ${prefs.getKeys()}");

    debugPrint("🔄 Manual save to Supabase...");
    debugPrint(
        "📊 Manual eggs - Total: $_totalEgg, Grade0: $_big, Grade1: $_medium, Grade2: $_small, Grade3: $_grade3, Grade4: $_grade4, Grade5: $_grade5");

    try {
      // สร้าง egg items สำหรับ manual input
      final eggItems = <Map<String, dynamic>>[];
      
      final gradeBuckets = <int, int>{
        0: _big,
        1: _medium,
        2: _small,
        3: _grade3,
        4: _grade4,
        5: _grade5,
      };
      for (int grade = 0; grade <= 5; grade++) {
        for (int i = 0; i < (gradeBuckets[grade] ?? 0); i++) {
          eggItems.add({
            'grade': grade,
            'confidence': 100.0,
            // ไม่ส่ง bbox เนื่องจากตาราง egg_item ไม่มีคอลัมน์เหล่านี้
          });
        }
      }
      
      debugPrint("📦 Created ${eggItems.length} manual egg items for Supabase");

      // ส่งไป Supabase
      await SupabaseService.createEggSessionWithItems(
        userId: userId,
        imagePath: 'manual',
        eggCount: _totalEgg,
        successPercent: 100,
        grade0Count: _big,
        grade1Count: _medium,
        grade2Count: _small,
        grade3Count: _grade3,
        grade4Count: _grade4,
        grade5Count: _grade5,
        day: day,
        eggItems: eggItems,
      );

      debugPrint("✅ Manual save to Supabase DONE: $_totalEgg eggs");
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("บันทึกข้อมูลไข่ $_totalEgg ฟองลง Supabase แล้ว"),
          backgroundColor: Colors.green,
        ),
      );
      
    } catch (e) {
      debugPrint("❌ Error saving manual data to Supabase: $e");
      
      // Fallback ไป SQLite ถ้า Supabase ล้มเหลว
      debugPrint("🗄️ HomePage: Saving manual data to SQLite...");
      debugPrint("📊 Manual data - Total: $_totalEgg, Grade0: $_big, Grade1: $_medium, Grade2: $_small, Grade3: $_grade3, Grade4: $_grade4, Grade5: $_grade5");
      
      final sessionId = await EggDatabase.instance.insertSession(
        userId: userId,
        imagePath: 'manual',
        eggCount: _totalEgg,
        successPercent: 100,
        grade0Count: _big,
        grade1Count: _medium,
        grade2Count: _small,
        grade3Count: _grade3,
        grade4Count: _grade4,
        grade5Count: _grade5,
        day: day,
      );

      debugPrint("✅ HomePage: Manual session saved with ID: $sessionId");
      debugPrint("📱 Fallback to SQLite: $_totalEgg eggs");
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("บันทึกข้อมูลไข่ $_totalEgg ฟองลงฐานข้อมูลในเครื่อง"),
          backgroundColor: Colors.orange,
        ),
      );
    }

    Navigator.pop(context);

    setState(() {
      _big = 0;
      _medium = 0;
      _small = 0;
      _grade3 = 0;
      _grade4 = 0;
      _grade5 = 0;
    });
  }

  final List<String> filters = [
    'ทั้งหมด',
    'ไข่วันนี้',
    'แนวโน้มผลผลิต',
    'รายงานสรุปผล',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8C6),

      // 🔝 AppBar (Logo)
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        centerTitle: true,
        title: Image.asset(
          'assets/images/number_egg_logo.png',
          height: 50,
        ),
      ),

      // 📊 BODY
      body: RepaintBoundary(
        key: _captureKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ✅ FILTER (ทั้งหมด / ไข่วันนี้ / แนวโน้ม / รายงาน)
              _buildAnalysisFilter(),

              const SizedBox(height: 20),

              // 📈 CARD 1
              if (selectedFilter == 'ทั้งหมด' || selectedFilter == 'ไข่วันนี้')
                FutureBuilder<Map<String, int>>(
                  future: EggDatabase.instance.getTodayEggSummary(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return _resultCard(
                        title: 'ผลการวิเคราะห์จำนวนไข่ตามเบอร์',
                        subtitle: 'จำนวนไข่ตามเบอร์ (ประจำวัน)',
                      );
                    }

                    final data = snapshot.data!;
                    return _resultCard(
                      title: 'ผลการวิเคราะห์จำนวนไข่ตามเบอร์',
                      subtitle: 'จำนวนไข่ตามเบอร์ (ประจำวัน)',
                      chart: TodayEggDonutChart(
                        grade0: data['เบอร์ 0'] ?? 0,
                        grade1: data['เบอร์ 1'] ?? 0,
                        grade2: data['เบอร์ 2'] ?? 0,
                        grade3: data['เบอร์ 3'] ?? 0,
                        grade4: data['เบอร์ 4'] ?? 0,
                        grade5: data['เบอร์ 5'] ?? 0,
                      ),
                    );
                  },
                ),

              const SizedBox(height: 16),

              // 📉 CARD 2
              if (selectedFilter == 'ทั้งหมด' ||
                  selectedFilter == 'แนวโน้มผลผลิต')
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: EggDatabase.instance.getWeeklyTrend(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return _resultCard(
                        title: 'ผลการวิเคราะห์แนวโน้ม',
                        subtitle: 'แนวโน้มผลผลิตไข่',
                      );
                    }

                    return _resultCard(
                      title: 'ผลการวิเคราะห์แนวโน้ม',
                      subtitle: 'แนวโน้มผลผลิตไข่',
                      chart: EggTrendLineChart(data: snapshot.data!),
                    );
                  },
                ),

              const SizedBox(height: 16),

              // 📉 CARD 3
              if (selectedFilter == 'ทั้งหมด' ||
                  selectedFilter == 'รายงานสรุปผล')
                FutureBuilder<Map<String, dynamic>>(
                  future: EggDatabase.instance.getSummaryReport(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return _resultCard(
                        title: 'รายงานสรุปผล',
                        subtitle: 'สรุปผลการวิเคราะห์',
                      );
                    }

                    final data = snapshot.data!;
                    return _resultCard(
                      title: 'รายงานสรุปผล',
                      subtitle: 'สรุปผลการวิเคราะห์',
                      chart: SummaryReportCard(
                        totalEgg: (data['totalEgg'] ?? 0).toInt(),
                        avgSuccess: (data['avgSuccess'] ?? 0).toDouble(),
                        grade0: (data['grade0'] ?? 0).toInt(),
                        grade1: (data['grade1'] ?? 0).toInt(),
                        grade2: (data['grade2'] ?? 0).toInt(),
                        grade3: (data['grade3'] ?? 0).toInt(),
                        grade4: (data['grade4'] ?? 0).toInt(),
                        grade5: (data['grade5'] ?? 0).toInt(),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 14),

              /// 🔴 NEW SESSION BUTTON
              SizedBox(
                width: 80,
                child: OutlinedButton.icon(
                  icon: const Icon(
                    Icons.restart_alt,
                    color: Colors.white,
                  ),
                  label: const Text(
                    'New',
                    style: TextStyle(color: Colors.white),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    side: BorderSide.none, // ❌ ไม่มีเส้นขอบ
                  ),
                  onPressed: _confirmNewSession,
                ),
              )
            ],
          ),
        ),
      ),

      // 📸 Floating Camera Button
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'capture',
            backgroundColor: Colors.green,
            child: const Icon(Icons.save),
            onPressed: _captureAndSave,
          ),
          const SizedBox(width: 12),
          FloatingActionButton.extended(
            heroTag: 'addEgg',
            backgroundColor: const Color(0xFFFFC107),
            icon: const Icon(Icons.add, color: Colors.black),
            label: const Text('เพิ่มข้อมูล',
                style: TextStyle(color: Colors.black)),
            onPressed: () => _showAddEggDialog(),
          ),
          const SizedBox(width: 12),
          FloatingActionButton(
            heroTag: 'camera',
            backgroundColor: const Color(0xFFFFC107),
            child: const Icon(Icons.camera_alt, color: Colors.black),
            onPressed: () {
              Navigator.pushNamed(context, '/camera');
            },
          ),
        ],
      ),

      // ⬇️ Bottom Navigation
      bottomNavigationBar: const CustomBottomNav(currentIndex: 1),
    );
  }

  Widget _buildAnalysisFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ผลการวิเคราะห์',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: filters.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final item = filters[index];
              final isSelected = selectedFilter == item;

              return GestureDetector(
                onTap: () {
                  setState(() {
                    selectedFilter = item;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF212121)
                        : const Color(0xFFE0E0E0),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    item,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.black38,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------- RESULT CARD ----------
  Widget _resultCard({
    required String title,
    required String subtitle,
    Widget? chart,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Container(
            height: 200,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
            ),
            child: chart ?? const Center(child: Text('Chart / Graph')),
          ),
          const SizedBox(height: 12),
          Text(subtitle, style: const TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}
