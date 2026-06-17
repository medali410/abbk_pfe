import codecs
import re

path = r'C:\Users\ASUS\Documents\abbk_pfe\dali-pfe\lib\maintenance_machine_hub_page.dart'

with codecs.open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Normalize newlines
content = content.replace('\r\n', '\n')

# Add imports if not present
if "import 'package:socket_io_client/socket_io_client.dart' as io;" not in content:
    content = content.replace("import 'services/api_service.dart';", "import 'services/api_service.dart';\nimport 'package:socket_io_client/socket_io_client.dart' as io;\nimport 'dart:async';")

target_state = '''class _MaintenanceMachineHubPageState extends State<MaintenanceMachineHubPage> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.getMaintenanceWorkspace();
  }

  void _reload() => setState(() {
        _future = ApiService.getMaintenanceWorkspace();
      });'''

replacement_state = '''class _MaintenanceMachineHubPageState extends State<MaintenanceMachineHubPage> {
  late Future<Map<String, dynamic>> _future;
  Map<String, dynamic>? _currentData;
  late io.Socket _socket;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _initSocket();
    
    // Polling as a fallback to update the UI if socket misses something
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) {
        _loadData(silent: true);
      }
    });
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _future = ApiService.getMaintenanceWorkspace();
      });
    }
    try {
      final data = await ApiService.getMaintenanceWorkspace();
      if (mounted) {
        setState(() {
          _currentData = data;
          _future = Future.value(data);
        });
        _setupSocketListeners();
      }
    } catch (e) {
      // Ignore errors on silent poll
    }
  }
  
  void _setupSocketListeners() {
    if (_currentData == null) return;
    final rows = (_currentData!['machines'] as List? ?? const []).cast<Map<String, dynamic>>();
    for (var m in rows) {
      final mId = (m['machineId'] ?? m['id'] ?? m['_id'] ?? '').toString();
      if (mId.isNotEmpty) {
        _socket.off('ai:$mId');
        _socket.on('ai:$mId', (data) {
          if (!mounted || data is! Map) return;
          _updateMachineData(mId, data);
        });
      }
    }
  }

  void _updateMachineData(String machineId, Map data) {
    if (_currentData == null) return;
    setState(() {
      final machines = List<Map<String, dynamic>>.from(_currentData!['machines'] ?? []);
      for (int i = 0; i < machines.length; i++) {
        final m = machines[i];
        final id = (m['machineId'] ?? m['id'] ?? m['_id'] ?? '').toString();
        if (id == machineId) {
          final newM = Map<String, dynamic>.from(m);
          
          if (newM['metrics'] == null || newM['metrics'] is! Map) {
             newM['metrics'] = <String, dynamic>{};
          }
          final metrics = Map<String, dynamic>.from(newM['metrics'] as Map);
          
          if (data.containsKey('temperature')) metrics['thermal'] = data['temperature'];
          if (data.containsKey('thermal')) metrics['thermal'] = data['thermal'];
          if (data.containsKey('pressure')) metrics['pressure'] = data['pressure'];
          if (data.containsKey('vibration')) metrics['vibration'] = data['vibration'];
          if (data.containsKey('power')) metrics['power'] = data['power'];
          if (data.containsKey('magnetic')) metrics['magnetic'] = data['magnetic'];
          if (data.containsKey('infrared')) metrics['infrared'] = data['infrared'];
          
          newM['metrics'] = metrics;
          
          if (data.containsKey('level')) newM['level'] = data['level'];
          if (data.containsKey('probPanne')) newM['probPanne'] = data['probPanne'];
          if (data.containsKey('failureScenario')) newM['failureScenario'] = data['failureScenario'];
          
          machines[i] = newM;
          break;
        }
      }
      _currentData!['machines'] = machines;
      _future = Future.value(_currentData);
    });
  }

  void _initSocket() {
    _socket = io.io(ApiService.socketBaseUrl, <String, dynamic>{
      'transports': <String>['polling', 'websocket'],
      'autoConnect': true,
    });
    
    _socket.onConnect((_) {
      if (mounted) setState(() {});
    });
    
    _socket.on('nouvelle_prediction', (raw) {
        try {
          final dynamic decoded = raw is String ? jsonDecode(raw) : raw;
          if (decoded is Map) {
             final machineId = (decoded['machineId'] ?? '').toString();
             _updateMachineData(machineId, decoded);
          }
        } catch (_) {}
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _socket.dispose();
    super.dispose();
  }

  void _reload() => _loadData();'''

content = content.replace(target_state, replacement_state)

with codecs.open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Modification complete.")
