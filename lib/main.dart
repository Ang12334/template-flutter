import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

void main() => runApp(const ChronosApexApp());

class ChronosApexApp extends StatelessWidget {
  const ChronosApexApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chronos Apex Hub',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF00E5FF),
        scaffoldBackgroundColor: const Color(0xFF0A0A0E),
        cardColor: const Color(0xFF16161F),
        dividerColor: Colors.white12,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF00E5FF),
          surface: Color(0xFF16161F),
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  BluetoothConnection? _connection;
  List<BluetoothDevice> _devicesList = [];
  BluetoothDevice? _selectedDevice;
  bool _isConnected = false;
  bool _isConnecting = false;
  String _buffer = '';

  final List<String> _taskQueue = [
    'Complete Systems Hardware Spec',
    'Review Firmware Serial Protocol',
    'Integrate Mobile Stream Handlers',
    'Conduct Thermal & Signal Stress Test',
  ];

  final TextEditingController _taskController = TextEditingController();
  int _completedTasksCount = 0;
  int _cumulativeFocusSeconds = 0;
  String _currentHardwareState = 'DISCONNECTED';

  @override
  void initState() {
    super.initState();
    _scanForDevices();
  }

  @override
  void dispose() {
    _connection?.dispose();
    _taskController.dispose();
    super.dispose();
  }

  Future<void> _scanForDevices() async {
    try {
      List<BluetoothDevice> devices = await FlutterBluetoothSerial.instance.getBondedDevices();
      setState(() => _devicesList = devices);
    } catch (e) {
      _notify('Bluetooth Initialization Failed');
    }
  }

  Future<void> _toggleConnect() async {
    if (_isConnected) {
      await _connection?.close();
      return;
    }
    if (_selectedDevice == null) {
      _notify('Please select your HC-05 console first');
      return;
    }

    setState(() {
      _isConnecting = true;
      _currentHardwareState = 'PAIRING...';
    });

    try {
      BluetoothConnection connection = await BluetoothConnection.toAddress(_selectedDevice!.address);
      setState(() {
        _connection = connection;
        _isConnected = true;
        _isConnecting = false;
        _currentHardwareState = 'CONNECTED';
      });
      _notify('Chronos Apex Hardware Linked');
      
      _connection!.input!.listen(_onDataReceived).onDone(() {
        setState(() {
          _isConnected = false;
          _connection = null;
          _currentHardwareState = 'DISCONNECTED';
        });
        _notify('Console Connection Terminated');
      });

      _syncHardwareOLED();
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _isConnected = false;
        _currentHardwareState = 'LINK ERROR';
      });
      _notify('Connection Failed. Check Console Power.');
    }
  }

  void _onDataReceived(Uint8List data) {
    _buffer += utf8.decode(data);
    while (_buffer.contains('\n')) {
      int index = _buffer.indexOf('\n');
      String packet = _buffer.substring(0, index).trim();
      _buffer = _buffer.substring(index + 1);
      if (packet.isNotEmpty) _handleProtocolPacket(packet);
    }
  }

  void _handleProtocolPacket(String packet) {
    setState(() {
      if (packet == 'TASK:DONE') {
        if (_taskQueue.isNotEmpty) {
          _taskQueue.removeAt(0);
          _completedTasksCount++;
          _syncHardwareOLED();
        }
      } else if (packet == 'STAT:FOCUS') {
        _currentHardwareState = 'FOCUS BLOCK ACTIVE';
      } else if (packet == 'STAT:BREAK') {
        _currentHardwareState = 'BREAK PERIOD';
        _cumulativeFocusSeconds += 1500;
      }
    });
  }

  void _syncHardwareOLED() {
    if (!_isConnected || _connection == null) return;
    String cmd = _taskQueue.isNotEmpty ? 'NEXT:${_taskQueue.first}' : 'NEXT:No Active Tasks';
    _connection!.output.add(utf8.encode('$cmd\n'));
  }

  void _addTask() {
    String text = _taskController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _taskQueue.add(text);
      _taskController.clear();
      if (_taskQueue.length == 1) _syncHardwareOLED();
    });
  }

  void _removeTask(int index) {
    setState(() {
      _taskQueue.removeAt(index);
      if (index == 0) _syncHardwareOLED();
    });
  }

  void _reorderTasks(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _taskQueue.removeAt(oldIndex);
      _taskQueue.insert(newIndex, item);
      if (oldIndex == 0 || newIndex == 0) _syncHardwareOLED();
    });
  }

  void _notify(String fallbackMessage) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(fallbackMessage, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF00E5FF),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CHRONOS APEX CONSOLE', style: TextStyle(letterSpacing: 1.5, fontSize: 16, fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: const Color(0xFF16161F),
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF16161F),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: const Color(0xFF0A0A0E), borderRadius: BorderRadius.circular(8)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<BluetoothDevice>(
                        isExpanded: true,
                        hint: const Text('Select System Hardware Port'),
                        value: _selectedDevice,
                        items: _devicesList.map((d) => DropdownMenuItem(value: d, child: Text(d.name ?? d.address))).toList(),
                        onChanged: _isConnected ? null : (val) => setState(() => _selectedDevice = val),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isConnecting ? null : _toggleConnect,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isConnected ? Colors.redAccent : const Color(0xFF00E5FF),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  child: Text(_isConnected ? 'DISCONNECT' : 'CONNECT', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                _telemetryBox('HARDWARE STATUS', _currentHardwareState, _isConnected ? const Color(0xFF00E5FF) : Colors.redAccent),
                const SizedBox(width: 12),
                _telemetryBox('COMPLETED', '$_completedTasksCount Blocks', Colors.white),
                const SizedBox(width: 12),
                _telemetryBox('TOTAL FOCUS', '${_cumulativeFocusSeconds ~/ 60} Mins', Colors.white),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _taskController,
                        decoration: const InputDecoration(hintText: 'Queue next high-value priority...', border: InputBorder.none),
                        onSubmitted: (_) => _addTask(),
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.add_circle, color: Color(0xFF00E5FF)), onPressed: _addTask),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _taskQueue.isEmpty
                ? const Center(child: Text('Execution Queue Empty', style: TextStyle(color: Colors.white30)))
                : ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _taskQueue.length,
                    onReorder: _reorderTasks,
                    itemBuilder: (context, index) {
                      final isTop = index == 0;
                      return Card(
                        key: ValueKey(_taskQueue[index] + index.toString()),
                        color: isTop ? const Color(0x1A00E5FF) : const Color(0xFF16161F),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(color: isTop ? const Color(0xFF00E5FF) : Colors.transparent, width: 1),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: CircleAvatar(
                            backgroundColor: isTop ? const Color(0xFF00E5FF) : const Color(0xFF0A0A0E),
                            foregroundColor: isTop ? Colors.black : Colors.white,
                            child: Text('${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          title: Text(_taskQueue[index], style: TextStyle(fontWeight: isTop ? FontWeight.bold : FontWeight.normal)),
                          subtitle: isTop ? const Text('STREAMING TO PRODUCTION OLED', style: TextStyle(fontSize: 10, color: Color(0xFF00E5FF), fontWeight: FontWeight.bold)) : null,
                          trailing: IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white38, size: 20),
                            onPressed: () => _removeTask(index),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _telemetryBox(String title, String value, Color valueColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFF16161F), borderRadius: BorderRadius.circular(8)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 9, color: Colors.white38, fontWeight: FontWeight.bold, letterSpacing: 1)),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: valueColor), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
