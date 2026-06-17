import codecs

path = r'C:\Users\ASUS\Documents\abbk_pfe\dali-pfe\lib\maintenance_machine_hub_page.dart'

with codecs.open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Normalize newlines
content = content.replace('\r\n', '\n')

target_timer = '''    // Polling as a fallback to update the UI if socket misses something
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) {
        _loadData(silent: true);
      }
    });'''

replacement_timer = '''    // Polling as a fallback to update the UI if socket misses something
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        _pollTelemetryForAllMachines();
      }
    });'''

target_loaddata = '''  Future<void> _loadData({bool silent = false}) async {
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
  }'''

replacement_loaddata = '''  Future<void> _loadData({bool silent = false}) async {
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
        _pollTelemetryForAllMachines();
      }
    } catch (e) {
      // Ignore errors on silent poll
    }
  }

  Future<void> _pollTelemetryForAllMachines() async {
    if (_currentData == null || !mounted) return;
    final machines = List<Map<String, dynamic>>.from(_currentData!['machines'] ?? []);
    bool updated = false;
    for (int i = 0; i < machines.length; i++) {
      final m = machines[i];
      final mId = (m['machineId'] ?? m['id'] ?? m['_id'] ?? '').toString();
      if (mId.isNotEmpty) {
        try {
          final tel = await ApiService.getLatestTelemetry(mId);
          if (tel != null && mounted) {
            final newM = Map<String, dynamic>.from(m);
            if (newM['metrics'] == null || newM['metrics'] is! Map) {
              newM['metrics'] = <String, dynamic>{};
            }
            final metrics = Map<String, dynamic>.from(newM['metrics'] as Map);
            
            final rawMetrics = tel['metrics'];
            final telMetrics = rawMetrics is Map ? Map<String, dynamic>.from(rawMetrics) : null;
            
            metrics['thermal'] = tel['temperature'] ?? tel['temp'] ?? telMetrics?['thermal'] ?? telMetrics?['temp'] ?? metrics['thermal'];
            metrics['vibration'] = tel['vibration'] ?? telMetrics?['vibration'] ?? metrics['vibration'];
            metrics['pressure'] = tel['pressure'] ?? tel['pression'] ?? telMetrics?['pressure'] ?? telMetrics?['pression'] ?? metrics['pressure'];
            metrics['magnetic'] = tel['magnetic'] ?? tel['magnet'] ?? telMetrics?['magnetic'] ?? telMetrics?['magnet'] ?? metrics['magnetic'];
            metrics['power'] = tel['power'] ?? telMetrics?['power'] ?? metrics['power'];
            metrics['infrared'] = tel['infrared'] ?? telMetrics?['infrared'] ?? metrics['infrared'];
            
            newM['metrics'] = metrics;
            machines[i] = newM;
            updated = true;
          }
        } catch (_) {}
      }
    }
    if (updated && mounted) {
      setState(() {
        _currentData!['machines'] = machines;
        _future = Future.value(_currentData);
      });
    }
  }'''

content = content.replace(target_timer, replacement_timer)
content = content.replace(target_loaddata, replacement_loaddata)

with codecs.open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Modification complete.")
