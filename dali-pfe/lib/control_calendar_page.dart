import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'services/api_service.dart';
import 'widgets/machine_control_calendar_panel.dart';

enum _ControlPriority { urgent, high, normal, low, done }
enum _ChecklistDecision { valide, aChanger }

class _ChecklistItem {
  _ChecklistItem({
    required this.label,
  });

  final String label;
  _ChecklistDecision decision = _ChecklistDecision.valide;
  String anomaly = '';
}

class ControlCalendarPage extends StatefulWidget {
  const ControlCalendarPage({super.key});

  @override
  State<ControlCalendarPage> createState() => _ControlCalendarPageState();
}

class _ControlCalendarPageState extends State<ControlCalendarPage> {
  static const _bg = Color(0xFF10102B);
  static const _surface = Color(0xFF1D1D38);
  static const _surfaceHeader = Color(0xFF131422);
  static const _accent = Color(0xFFFF6E00);
  static const _muted = Color(0xFFA0A0B0);
  static const _ok = Color(0xFF43A047);
  static const _warn = Color(0xFFFBC02D);
  static const _warn2 = Color(0xFFFB8C00);
  static const _danger = Color(0xFFE53935);
  static const _cyan = Color(0xFF75D1FF);

  /// Si aucune machine n’est passée en route/URL, on tente de résoudre une machine dont le nom contient cette chaîne (ex. « alfa »).
  static const String _defaultMachineNameHint = 'alfa';

  final List<Map<String, dynamic>> _allControles = <Map<String, dynamic>>[];
  final Map<String, double> _tempsMarcheLiveByMachineId = <String, double>{};
  io.Socket? _socket;

  bool _isLoading = true;
  bool _argsLoaded = false;
  bool _isFinishingFromScan = false;
  bool _isSavingChecklist = false;
  bool _showOnlyCurrentWeek = true;
  bool _managerMode = false;

  String? _errorMessage;
  String? _urgentAlert;

  String _technicianName = 'TECHNICIEN';
  String _requestedTechnicianId = '';
  String _apiTechnicianId = '';
  List<Map<String, dynamic>> _techniciansDirectory = <Map<String, dynamic>>[];

  /// Périmètre machines (même logique que le profil technicien) : id → libellé.
  final Map<String, String> _fleetMachineLabels = <String, String>{};
  String _companyIdForFleet = '';
  List<String> _rawRouteMachineIds = const <String>[];

  /// Machine affichée dans le calendrier mensuel interactif (route ou choix utilisateur).
  String _routeMachineId = '';
  String _routeMachineName = '';
  String _calendarMachineId = '';
  /// Sous-chaîne pour résoudre automatiquement une machine (query `?machine=alfa` ou défaut interne).
  String _machineNameHint = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsLoaded) return;
    _argsLoaded = true;

    final routeArgs = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final saved = ApiService.savedTechnicianProfile;
    final Map<String, dynamic> args = <String, dynamic>{
      if (saved != null) ...saved,
      if (routeArgs != null) ...routeArgs,
    };
    final qp = Uri.base.queryParameters;
    _technicianName = (args['technicianName'] ?? args['name'] ?? qp['technicianName'] ?? 'TECHNICIEN').toString();
    _requestedTechnicianId = (args['technicianId'] ?? args['id'] ?? args['_id'] ?? qp['technicienId'] ?? qp['technicianId'] ?? '')
        .toString()
        .trim();
    final role = (args['role'] ?? args['viewerRole'] ?? qp['role'] ?? ApiService.savedUserRole ?? '').toString().toLowerCase();
    _managerMode = role == 'maintenance' || role == 'admin' || role == 'conception' || (_requestedTechnicianId.isEmpty && role != 'technician');

    _routeMachineId = (args['machineId'] ?? '').toString().trim();
    final rawMachineIds = args['machineIds'];
    if (_routeMachineId.isEmpty && rawMachineIds is List) {
      for (final x in rawMachineIds) {
        final s = x.toString().trim();
        if (s.isNotEmpty) {
          _routeMachineId = s;
          break;
        }
      }
    }
    if (_routeMachineId.isEmpty) {
      final qMid = (qp['machineId'] ?? '').toString().trim();
      if (qMid.isNotEmpty) _routeMachineId = qMid;
    }
    _routeMachineName = (args['machineName'] ?? qp['machineName'] ?? '').toString();
    _machineNameHint = (args['machine'] ?? qp['machine'] ?? '').toString();
    _companyIdForFleet = (args['companyId'] ?? args['clientId'] ?? qp['companyId'] ?? qp['clientId'] ?? '')
        .toString()
        .trim();
    _rawRouteMachineIds = <String>[];
    if (rawMachineIds is List) {
      _rawRouteMachineIds = rawMachineIds
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (_routeMachineId.isNotEmpty) {
      _calendarMachineId = _routeMachineId;
    }

    _initialize();
  }

  @override
  void dispose() {
    _socket?.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    if (!_managerMode) {
      await _resolveApiTechnicianId();
    }
    await _loadTechniciansDirectory();
    if (!_managerMode) {
      await _resolveFleetMachinesForTechnician();
    }
    await _resolvePreferredMachineFromCatalog();
    await _fetchControles();
    _initSocket();
  }

  String _docMachineId(Map<String, dynamic> m) =>
      (m['id'] ?? m['_id'] ?? m['machineId'] ?? '').toString().trim();

  /// Remplit [ _fleetMachineLabels ] et, si besoin, la machine courante — aligné sur le profil technicien.
  Future<void> _resolveFleetMachinesForTechnician() async {
    _fleetMachineLabels.clear();
    var companyId = _companyIdForFleet;
    var resolvedIds = List<String>.from(_rawRouteMachineIds);

    Future<void> ingestList(List<Map<String, dynamic>> docs) async {
      for (final m in docs) {
        final mid = _docMachineId(m);
        if (mid.isEmpty) continue;
        final name = (m['name'] ?? m['nom'] ?? mid).toString();
        _fleetMachineLabels[mid] = name;
      }
    }

    if (_techniciansDirectory.isNotEmpty && _requestedTechnicianId.isNotEmpty) {
      final q = _requestedTechnicianId.toLowerCase();
      for (final t in _techniciansDirectory) {
        final mid = (t['_id'] ?? t['id'] ?? '').toString();
        final tid = (t['technicianId'] ?? '').toString();
        if (q.isNotEmpty && (mid.toLowerCase() == q || tid.toLowerCase() == q)) {
          if (companyId.isEmpty) {
            companyId = (t['companyId'] ?? '').toString().trim();
            _companyIdForFleet = companyId;
          }
          if (resolvedIds.isEmpty) {
            final tMachines = t['machineIds'];
            if (tMachines is List) {
              for (final x in tMachines) {
                final s = x.toString().trim();
                if (s.isNotEmpty) resolvedIds.add(s);
              }
            }
          }
          break;
        }
      }
    }

    if (resolvedIds.isNotEmpty && companyId.isNotEmpty) {
      try {
        final cm = await ApiService.getMachinesForClient(companyId);
        await ingestList(cm);
      } catch (_) {}
    }

    if (resolvedIds.isEmpty && companyId.isNotEmpty) {
      try {
        final cm = await ApiService.getMachinesForClient(companyId);
        await ingestList(cm);
        resolvedIds = cm.map(_docMachineId).where((e) => e.isNotEmpty).toList();
      } catch (_) {}
    }

    if (resolvedIds.isEmpty && companyId.isNotEmpty) {
      bool sameCo(Map<String, dynamic> m) => (m['companyId'] ?? '').toString().trim() == companyId;
      try {
        final all = await ApiService.getAllMachinesFromMongo();
        final subset = all.where(sameCo).toList();
        await ingestList(subset);
        resolvedIds = subset.map(_docMachineId).where((e) => e.isNotEmpty).toList();
      } catch (_) {}
    }

    if (resolvedIds.isEmpty && companyId.isNotEmpty) {
      bool sameCo(Map<String, dynamic> m) => (m['companyId'] ?? '').toString().trim() == companyId;
      try {
        final std = await ApiService.getMachines();
        final subset = std.where(sameCo).toList();
        await ingestList(subset);
        resolvedIds = subset.map(_docMachineId).where((e) => e.isNotEmpty).toList();
      } catch (_) {}
    }

    for (final id in resolvedIds) {
      _fleetMachineLabels.putIfAbsent(id, () => id);
    }

    if (_routeMachineId.isEmpty && _fleetMachineLabels.isNotEmpty) {
      final first = resolvedIds.isNotEmpty ? resolvedIds.first : _fleetMachineLabels.keys.first;
      _routeMachineId = first;
      _routeMachineName = _fleetMachineLabels[first] ?? first;
      _calendarMachineId = first;
    }

    if (mounted) {
      setState(() {});
    }
  }

  /// Résout automatiquement une machine (ex. nom contenant « alfa ») pour pré-remplir calendrier + liste.
  Future<void> _resolvePreferredMachineFromCatalog() async {
    if (_routeMachineId.isNotEmpty) {
      if (_calendarMachineId.isEmpty) _calendarMachineId = _routeMachineId;
      return;
    }
    final hintRaw = _machineNameHint.trim().isNotEmpty ? _machineNameHint.trim() : _defaultMachineNameHint;
    try {
      final machines = await ApiService.getMachinesForHomeCatalog();
      Map<String, dynamic>? pick;
      final hl = hintRaw.toLowerCase();
      for (final m in machines) {
        final name = (m['nom'] ?? m['name'] ?? '').toString().toLowerCase();
        final mid = (m['machineId'] ?? m['_id'] ?? '').toString().trim();
        if (mid.isEmpty) continue;
        if (name.contains(hl)) {
          pick = m;
          break;
        }
      }
      if (pick != null) {
        final mid = (pick['machineId'] ?? pick['_id'] ?? '').toString().trim();
        final mname = (pick['nom'] ?? pick['name'] ?? mid).toString();
        if (mid.isNotEmpty) {
          _routeMachineId = mid;
          _routeMachineName = mname;
          _calendarMachineId = mid;
        }
      }
    } catch (_) {}
  }

  void _hydrateTempsMarcheFromList(List<Map<String, dynamic>> list) {
    for (final c in list) {
      final mid = (c['machineId'] ?? '').toString();
      if (mid.isEmpty) continue;
      final v = c['machineTempsMarcheLive'];
      if (v is num) {
        _tempsMarcheLiveByMachineId[mid] = v.toDouble();
      }
    }
  }

  Future<void> _loadTechniciansDirectory() async {
    try {
      final list = await ApiService.getTechnicians();
      _techniciansDirectory = list.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      _techniciansDirectory = <Map<String, dynamic>>[];
    }
  }

  bool _looksLikeObjectId(String v) => RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(v);

  Future<void> _resolveApiTechnicianId() async {
    try {
      final techs = await ApiService.getTechnicians();
      final q = _requestedTechnicianId.toLowerCase();
      final nameQ = _technicianName.trim().toLowerCase();
      Map<String, dynamic>? matched;
      for (final t in techs) {
        final mid = (t['_id'] ?? t['id'] ?? '').toString();
        final tid = (t['technicianId'] ?? '').toString();
        final did = (t['displayId'] ?? '').toString();
        final fullName = (t['fullName'] ?? t['name'] ?? t['technicianName'] ?? '').toString().trim().toLowerCase();

        final idMatch = q.isNotEmpty && (mid.toLowerCase() == q || tid.toLowerCase() == q || did.toLowerCase() == q);
        final nameMatch = q.isEmpty && nameQ.isNotEmpty && fullName == nameQ;
        if (idMatch || nameMatch) {
          matched = t;
          break;
        }
      }

      if (matched != null) {
        final resolved = (matched['_id'] ?? matched['id'] ?? '').toString();
        if (resolved.isNotEmpty) {
          _apiTechnicianId = resolved;
          return;
        }
      }
    } catch (_) {}

    if (_requestedTechnicianId.isNotEmpty && _looksLikeObjectId(_requestedTechnicianId)) {
      _apiTechnicianId = _requestedTechnicianId;
      return;
    }
    _apiTechnicianId = _requestedTechnicianId;
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  DateTime? _asDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String && value.trim().isNotEmpty) return DateTime.tryParse(value.trim());
    return null;
  }

  int _seuilHeures(Map<String, dynamic> c) =>
      _asInt(c['prochainControleHeure'] ?? c['heuresDeclenchement'] ?? c['heuresDeClenchement']);

  double _totalHeuresLive(Map<String, dynamic> c) {
    final mid = (c['machineId'] ?? '').toString();
    if (mid.isNotEmpty) {
      final live = _tempsMarcheLiveByMachineId[mid];
      if (live != null) return live;
    }
    final fromApi = c['machineTempsMarcheLive'];
    if (fromApi != null) {
      if (fromApi is num) return fromApi.toDouble();
      return double.tryParse(fromApi.toString()) ?? 0;
    }
    final nested = (c['tempsMarche'] is Map) ? c['tempsMarche']['totalHeures'] : c['tempsMarcheTotalHeures'];
    if (nested is num) return nested.toDouble();
    return double.tryParse(nested?.toString() ?? '0') ?? 0;
  }

  double _heuresRestantesLive(Map<String, dynamic> c) =>
      _seuilHeures(c).toDouble() - _totalHeuresLive(c);

  int _heuresRestantes(Map<String, dynamic> c) => _heuresRestantesLive(c).ceil();

  DateTime? _dueDate(Map<String, dynamic> c) =>
      _asDate(c['datePrevue'] ?? c['dateControle'] ?? c['dateLimite'] ?? c['dueDate'] ?? c['plannedAt'] ?? c['createdAt']);

  String _formatDurationShort(Duration d) {
    if (d.isNegative) return '';
    final mins = d.inMinutes.remainder(60);
    if (d.inDays > 0) return '${d.inDays} j ${d.inHours.remainder(24)} h';
    if (d.inHours > 0) return '${d.inHours} h $mins min';
    if (d.inMinutes > 0) return '${d.inMinutes} min';
    return '< 1 min';
  }

  /// Temps restant lisible : priorité à la date prévue, sinon écart au seuil temps moteur.
  String _tempsRestantControleLabel(Map<String, dynamic> c) {
    if (_isDone(c)) return 'Contrôle terminé';
    final due = _dueDate(c);
    final now = DateTime.now();
    if (due != null) {
      if (due.isAfter(now)) {
        return '${_formatDurationShort(due.difference(now))} avant la date prévue';
      }
      return 'Date prévue dépassée — à traiter en priorité';
    }
    final rest = _heuresRestantesLive(c);
    if (rest > 0.05) {
      return '${rest.toStringAsFixed(1)} h restantes (seuil temps moteur)';
    }
    return 'Seuil temps moteur atteint — intervention à faire';
  }

  Color _tempsRestantAccent(Map<String, dynamic> c, Color priorityColor) {
    if (_isDone(c)) return _ok;
    final due = _dueDate(c);
    if (due != null && !due.isAfter(DateTime.now())) return _danger;
    final rest = _heuresRestantesLive(c);
    if (rest <= 0 && !_isDone(c)) return _warn2;
    return priorityColor;
  }

  DateTime _startOfWeek(DateTime date) {
    final clean = DateTime(date.year, date.month, date.day);
    return clean.subtract(Duration(days: clean.weekday - DateTime.monday));
  }

  bool _isInCurrentWeek(Map<String, dynamic> c) {
    // Contrôles préventifs déclenchés par heures de marche : la date calendaire est indicative ;
    // tout contrôle ouvert (non terminé) reste visible dans « Cette semaine ».
    if (!_isDone(c)) return true;
    final d = _dueDate(c);
    if (d == null) return false;
    final now = DateTime.now();
    final start = _startOfWeek(now);
    final end = start.add(const Duration(days: 7));
    final current = DateTime(d.year, d.month, d.day);
    return !current.isBefore(start) && current.isBefore(end);
  }

  /// Missions **ouvertes** : visibles seulement si la machine est en marche (API enrichit `machineEnMarche` / `machineStatus`).
  /// Pour la **machine sélectionnée** dans le calendrier, on affiche toujours les missions ouvertes (évite liste vide si l’arrêt masque tout).
  /// Missions **terminées** : toujours visibles. Statut machine inconnu : on affiche (évite liste vide si latence API).
  bool _showOpenControleWhenMachineRunning(Map<String, dynamic> c) {
    if (_isDone(c)) return true;
    final cm = _calendarMachineId.trim();
    final mid = (c['machineId'] ?? '').toString().trim();
    if (cm.isNotEmpty && (mid == cm || mid.toUpperCase() == cm.toUpperCase())) {
      return true;
    }
    final st = (c['machineStatus'] ?? '').toString().trim().toUpperCase();
    if (c['machineEnMarche'] == true || st == 'RUNNING') return true;
    if (c['machineEnMarche'] == false || st == 'STOPPED' || st == 'MAINTENANCE') {
      return false;
    }
    return true;
  }

  List<Map<String, dynamic>> _visibleControles() {
    var list = _allControles.where(_showOpenControleWhenMachineRunning);
    if (_showOnlyCurrentWeek) {
      list = list.where(_isInCurrentWeek);
    }
    var result = list.toList();
    final cm = _calendarMachineId.trim();
    if (cm.isNotEmpty) {
      result = result.where((c) {
        final mid = (c['machineId'] ?? '').toString().trim();
        return mid == cm || mid.toUpperCase() == cm.toUpperCase();
      }).toList();
    }
    return result;
  }

  String _status(Map<String, dynamic> c) => (c['statut'] ?? 'en_attente').toString().toLowerCase();
  bool _isDone(Map<String, dynamic> c) => _status(c) == 'terminé' || _status(c) == 'termine';
  String _prettyStatus(String raw) {
    final s = raw.toLowerCase().replaceAll('_', ' ');
    switch (s) {
      case 'en attente':
        return 'EN ATTENTE';
      case 'assignee':
      case 'assignée':
        return 'ASSIGNÉE';
      case 'en cours':
        return 'EN COURS';
      case 'planifié':
      case 'planifie':
        return 'PLANIFIÉE';
      case 'terminé':
      case 'termine':
        return 'TERMINÉE';
      case 'annulé':
      case 'annule':
        return 'ANNULÉE';
      default:
        return raw.toUpperCase();
    }
  }

  _ControlPriority _priorityOf(Map<String, dynamic> c) {
    if (_isDone(c)) return _ControlPriority.done;
    final rest = _heuresRestantesLive(c);
    if (rest <= 0) return _ControlPriority.urgent;
    if (rest <= 10) return _ControlPriority.high;
    if (rest <= 120) return _ControlPriority.normal;
    return _ControlPriority.low;
  }

  int _priorityRank(_ControlPriority p) {
    switch (p) {
      case _ControlPriority.urgent:
        return 0;
      case _ControlPriority.high:
        return 1;
      case _ControlPriority.normal:
        return 2;
      case _ControlPriority.low:
        return 3;
      case _ControlPriority.done:
        return 4;
    }
  }

  Color _priorityColor(_ControlPriority p) {
    switch (p) {
      case _ControlPriority.urgent:
        return _danger;
      case _ControlPriority.high:
        return _warn2;
      case _ControlPriority.normal:
        return _warn;
      case _ControlPriority.low:
        return const Color(0xFF8BC34A);
      case _ControlPriority.done:
        return _ok;
    }
  }

  String _priorityLabel(_ControlPriority p) {
    switch (p) {
      case _ControlPriority.urgent:
        return 'URGENT';
      case _ControlPriority.high:
        return 'HAUTE';
      case _ControlPriority.normal:
        return 'NORMALE';
      case _ControlPriority.low:
        return 'BASSE';
      case _ControlPriority.done:
        return 'TERMINÉ';
    }
  }

  Future<void> _fetchControles() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      if (!_managerMode && _apiTechnicianId.isEmpty) {
        throw Exception('Technicien non identifié.');
      }
      final data = _managerMode
          ? await ApiService.getAllControles(days: 60)
          : await ApiService.getControlesForTechnician(_apiTechnicianId, days: 30);
      final normalized = data.map((e) => Map<String, dynamic>.from(e)).toList();
      _sortControls(normalized);
      if (!mounted) return;
      setState(() {
        _allControles
          ..clear()
          ..addAll(normalized);
        _hydrateTempsMarcheFromList(normalized);
        _isLoading = false;
        _applyCalendarMachineResolution();
      });
      await _mergeControlesForSelectedMachine();
      if (mounted) {
        setState(() {
          _applyCalendarMachineResolution();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// Machines uniques (id → libellé) pour le sélecteur du calendrier interactif.
  List<MapEntry<String, String>> _machinePickerEntries() {
    final map = <String, String>{};
    for (final e in _fleetMachineLabels.entries) {
      map[e.key] = e.value;
    }
    for (final c in _allControles) {
      final mid = (c['machineId'] ?? '').toString().trim();
      if (mid.isEmpty) continue;
      final name = (c['machineName'] ?? mid).toString();
      map[mid] = name;
    }
    if (_routeMachineId.isNotEmpty && !map.containsKey(_routeMachineId)) {
      map[_routeMachineId] = _routeMachineName.isNotEmpty ? _routeMachineName : _routeMachineId;
    }
    final list = map.entries.toList()..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    return list;
  }

  void _applyCalendarMachineResolution() {
    final entries = _machinePickerEntries();
    final ids = entries.map((e) => e.key).toSet();
    if (_routeMachineId.isNotEmpty) {
      if (ids.contains(_routeMachineId)) {
        _calendarMachineId = _routeMachineId;
        return;
      }
      _calendarMachineId = _routeMachineId;
      return;
    }
    if (_calendarMachineId.isNotEmpty && ids.contains(_calendarMachineId)) return;
    if (entries.isNotEmpty) {
      _calendarMachineId = entries.first.key;
    }
  }

  /// Complète la liste technicien avec les contrôles de la machine sélectionnée (ex. Alfa absente du filtre tech).
  Future<void> _mergeControlesForSelectedMachine() async {
    final mid = (_calendarMachineId.isNotEmpty ? _calendarMachineId : _routeMachineId).trim();
    if (mid.isEmpty) return;
    try {
      final extra = await ApiService.getControlesForMachine(mid);
      if (!mounted) return;
      setState(() {
        final seen = <String>{};
        for (final c in _allControles) {
          final id = (c['id'] ?? c['_id'] ?? '').toString();
          if (id.isNotEmpty) seen.add(id);
        }
        var added = false;
        for (final raw in extra) {
          final map = Map<String, dynamic>.from(raw);
          final id = (map['id'] ?? map['_id'] ?? '').toString();
          if (id.isNotEmpty && seen.contains(id)) continue;
          if (id.isNotEmpty) seen.add(id);
          _allControles.add(map);
          added = true;
        }
        if (added) {
          _sortControls(_allControles);
          _hydrateTempsMarcheFromList(_allControles);
        }
      });
    } catch (_) {}
  }

  String _calendarMachineDisplayName() {
    for (final e in _machinePickerEntries()) {
      if (e.key == _calendarMachineId) return e.value;
    }
    return _routeMachineName;
  }

  void _sortControls(List<Map<String, dynamic>> list) {
    list.sort((a, b) {
      final byPriority = _priorityRank(_priorityOf(a)).compareTo(_priorityRank(_priorityOf(b)));
      if (byPriority != 0) return byPriority;
      final da = _dueDate(a);
      final db = _dueDate(b);
      if (da != null && db != null) return da.compareTo(db);
      if (da != null) return -1;
      if (db != null) return 1;
      return _heuresRestantes(a).compareTo(_heuresRestantes(b));
    });
  }

  bool _matchesCurrentTechnician(Map<String, dynamic> c) {
    if (_managerMode) return true;
    final payloadId = (c['technicienId'] ?? c['technicianId'] ?? '').toString().trim();
    if (payloadId.isEmpty) return true;
    return payloadId == _apiTechnicianId || payloadId == _requestedTechnicianId;
  }

  void _upsertControle(Map<String, dynamic> raw) {
    final next = Map<String, dynamic>.from(raw);
    final id = (next['id'] ?? next['_id'] ?? next['controleId']).toString();
    if (id.isEmpty || !_matchesCurrentTechnician(next)) return;
    final idx = _allControles.indexWhere((c) => (c['id'] ?? c['_id']).toString() == id);
    if (idx >= 0) {
      _allControles[idx] = {..._allControles[idx], ...next};
    } else {
      _allControles.add(next);
    }
    _sortControls(_allControles);
  }

  void _notifyBanner(String text, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        backgroundColor: color.withOpacity(0.15),
        content: Text(text, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
        actions: [
          TextButton(
            onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  void _initSocket() {
    _socket?.dispose();
    _socket = io.io(ApiService.socketBaseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });
    _socket!.on('nouveau_controle', (raw) {
      try {
        final payload = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
        if (!mounted) return;
        setState(() => _upsertControle(payload));
      } catch (_) {}
    });
    _socket!.on('temps_marche_update', (raw) {
      try {
        if (raw is! List) return;
        if (!mounted) return;
        setState(() {
          for (final item in raw) {
            if (item is! Map) continue;
            final m = Map<String, dynamic>.from(item);
            final mid = (m['machineId'] ?? '').toString();
            final th = m['totalHeures'];
            if (mid.isEmpty) continue;
            if (th is num) {
              _tempsMarcheLiveByMachineId[mid] = th.toDouble();
            } else {
              final p = double.tryParse(th?.toString() ?? '');
              if (p != null) _tempsMarcheLiveByMachineId[mid] = p;
            }
          }
        });
      } catch (_) {}
    });
    _socket!.on('controle_urgent', (raw) {
      try {
        final payload = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
        if (!mounted) return;
        setState(() {
          _upsertControle(payload);
          final m = (payload['machineName'] ?? payload['machineId'] ?? 'Machine').toString();
          final t = (payload['typeControle'] ?? 'Contrôle').toString();
          _urgentAlert = 'Alerte rouge: $m - $t';
        });
        _notifyBanner('Contrôle urgent détecté.', _danger);
      } catch (_) {}
    });
    _socket!.on('machine_status_update', (raw) {
      try {
        if (raw is! Map) return;
        if (!mounted) return;
        final m = Map<String, dynamic>.from(raw);
        final mid = (m['machineId'] ?? '').toString();
        final st = (m['status'] ?? '').toString().trim().toUpperCase();
        if (mid.isEmpty) return;
        setState(() {
          for (var i = 0; i < _allControles.length; i++) {
            if ((_allControles[i]['machineId'] ?? '').toString() != mid) continue;
            final updated = Map<String, dynamic>.from(_allControles[i]);
            updated['machineStatus'] = st;
            updated['machineEnMarche'] = st == 'RUNNING';
            _allControles[i] = updated;
          }
        });
      } catch (_) {}
    });
  }

  Future<void> _assignControle(Map<String, dynamic> c) async {
    final id = (c['id'] ?? c['_id']).toString();
    if (id.isEmpty) return;
    if (_techniciansDirectory.isEmpty) {
      _notifyBanner('Aucun technicien disponible pour affectation.', _warn2);
      return;
    }
    String? selectedId;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        title: Text('Assigner la mission', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.w700)),
        content: StatefulBuilder(
          builder: (ctx, setModalState) => DropdownButtonFormField<String>(
            value: selectedId,
            dropdownColor: _surface,
            items: _techniciansDirectory.map((t) {
              final id = (t['_id'] ?? t['id'] ?? '').toString();
              final name = (t['name'] ?? t['fullName'] ?? t['technicianName'] ?? t['email'] ?? id).toString();
              return DropdownMenuItem<String>(
                value: id,
                child: Text(name, style: GoogleFonts.inter(color: Colors.white)),
              );
            }).toList(),
            onChanged: (v) => setModalState(() => selectedId = v),
            decoration: const InputDecoration(
              labelText: 'Technicien',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () async {
              if (selectedId == null || selectedId!.isEmpty) return;
              await ApiService.assignControleToTechnician(id, technicienId: selectedId!);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Assigner'),
          ),
        ],
      ),
    );
    await _fetchControles();
  }

  Future<void> _validerControle(Map<String, dynamic> c) async {
    final id = (c['id'] ?? c['_id']).toString();
    if (id.isEmpty) return;
    if (_apiTechnicianId.isEmpty) {
      _notifyBanner('Technicien non identifié pour la prise en charge.', _danger);
      return;
    }
    try {
      await ApiService.updateControleStatus(
        id,
        'en_cours',
        technicienId: _apiTechnicianId,
      );
      await _fetchControles();
      if (mounted) _notifyBanner('Prise en charge enregistrée. Vous pouvez terminer le contrôle.', _ok);
    } catch (e) {
      if (mounted) {
        _notifyBanner(e.toString().replaceFirst('Exception: ', ''), _danger);
      }
    }
  }

  List<_ChecklistItem> _defaultChecklist(Map<String, dynamic> c) {
    final type = (c['typeControle'] ?? c['elementControle'] ?? '').toString().trim();
    final t = type.toLowerCase();
    if (t.contains('condensateur')) {
      return <_ChecklistItem>[
        _ChecklistItem(label: 'Inspection visuelle (gonflement, trace d’huile, connectiques)'),
        _ChecklistItem(label: 'Mesure / test de capacité si procédure applicable'),
        _ChecklistItem(label: 'Serrage, isolation, température de boîtier'),
        _ChecklistItem(label: 'Espace de refroidissement et ventilation autour du banc condensateurs'),
        _ChecklistItem(label: 'Sécurité : coupure, consignation respectée'),
      ];
    }
    if (t.contains('moteur') || t.contains('capteur')) {
      return <_ChecklistItem>[
        _ChecklistItem(label: 'Vérification capteurs moteur (câblage, fixations, connecteurs)'),
        _ChecklistItem(label: 'Valeurs live vs seuils (température, vibration si disponible)'),
        _ChecklistItem(label: 'Niveau huile / refroidissement selon fiche machine'),
        _ChecklistItem(label: 'Bruit anormal, jeu mécanique, échauffement'),
        _ChecklistItem(label: 'Sécurité : arrêt d’urgence testé si prévu par procédure'),
      ];
    }
    final dynamic rawList = c['checklist'] ?? c['controleChecklist'] ?? c['inspectionItems'];
    if (rawList is List && rawList.isNotEmpty) {
      final parsed = rawList
          .map((e) {
            if (e is Map) {
              final label = (e['label'] ?? e['title'] ?? e['name'] ?? '').toString().trim();
              if (label.isNotEmpty) return _ChecklistItem(label: label);
            } else if (e is String && e.trim().isNotEmpty) {
              return _ChecklistItem(label: e.trim());
            }
            return null;
          })
          .whereType<_ChecklistItem>()
          .toList();
      if (parsed.isNotEmpty) return parsed;
    }
    return <_ChecklistItem>[
      _ChecklistItem(label: 'Contrôle capteur'),
      _ChecklistItem(label: 'Contrôle moteur'),
      _ChecklistItem(label: 'Contrôle courroie'),
      _ChecklistItem(label: 'Contrôle lubrification'),
      _ChecklistItem(label: 'Contrôle sécurité'),
    ];
  }

  String _decisionLabel(_ChecklistDecision value) =>
      value == _ChecklistDecision.valide ? 'Valide' : 'À changer';

  Future<void> _finishControle(Map<String, dynamic> c) async {
    final id = (c['id'] ?? c['_id']).toString();
    if (id.isEmpty) return;
    final currentStatus = (c['statut'] ?? '').toString().toLowerCase();
    if (currentStatus != 'en_cours') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Validez d’abord la prise en charge avec le bouton « Valider ».')),
        );
      }
      return;
    }
    final machineName = (c['machineName'] ?? c['machineId'] ?? 'Machine').toString();
    final checklist = _defaultChecklist(c);
    final generalCtrl = TextEditingController();
    final compteRenduCtrl = TextEditingController();
    final anomalyCtrls = List<TextEditingController>.generate(
      checklist.length,
      (i) => TextEditingController(text: checklist[i].anomaly),
    );
    var selectedResultat = 'Conforme';
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rapport de contrôle - $machineName',
                  style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  'Technicien: $_technicianName · ${DateTime.now().toLocal().toString().split(".").first}',
                  style: GoogleFonts.inter(color: _muted, fontSize: 12),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  dropdownColor: _surface,
                  style: GoogleFonts.inter(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Résultat',
                    border: OutlineInputBorder(),
                  ),
                  value: selectedResultat,
                  items: ['Conforme', 'Non conforme', 'À surveiller']
                      .map(
                        (e) => DropdownMenuItem<String>(
                          value: e,
                          child: Text(e, style: GoogleFonts.inter(color: Colors.white)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setModalState(() => selectedResultat = v ?? selectedResultat),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: compteRenduCtrl,
                  minLines: 2,
                  maxLines: 5,
                  style: GoogleFonts.inter(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Compte-rendu détaillé',
                    hintText:
                        'Ex. capteur en bon état · ou : pièce remplacée — capteur de température changé…',
                    hintStyle: GoogleFonts.inter(color: _muted.withOpacity(0.7)),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Checklist technicien', style: GoogleFonts.inter(color: _muted)),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: checklist.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final item = checklist[i];
                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.label, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: [
                                ChoiceChip(
                                  selectedColor: _ok.withOpacity(0.2),
                                  label: const Text('Valide'),
                                  selected: item.decision == _ChecklistDecision.valide,
                                  onSelected: (_) => setModalState(() {
                                    item.decision = _ChecklistDecision.valide;
                                    item.anomaly = '';
                                    anomalyCtrls[i].text = '';
                                  }),
                                ),
                                ChoiceChip(
                                  selectedColor: _danger.withOpacity(0.2),
                                  label: const Text('À changer'),
                                  selected: item.decision == _ChecklistDecision.aChanger,
                                  onSelected: (_) => setModalState(() => item.decision = _ChecklistDecision.aChanger),
                                ),
                              ],
                            ),
                            if (item.decision == _ChecklistDecision.aChanger) ...[
                              const SizedBox(height: 8),
                              TextField(
                                controller: anomalyCtrls[i],
                                minLines: 2,
                                maxLines: 3,
                                style: GoogleFonts.inter(color: Colors.white),
                                decoration: const InputDecoration(
                                  labelText: 'Panne / anomalie constatée (obligatoire)',
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (v) => item.anomaly = v.trim(),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: generalCtrl,
                  minLines: 2,
                  maxLines: 3,
                  style: GoogleFonts.inter(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Notes générales (optionnel)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: _isSavingChecklist
                        ? null
                        : () {
                            for (final item in checklist) {
                              if (item.decision == _ChecklistDecision.aChanger && item.anomaly.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Saisissez l’anomalie pour chaque élément marqué "À changer".')),
                                );
                                return;
                              }
                            }
                            Navigator.pop(ctx, true);
                          },
                    child: _isSavingChecklist
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Enregistrer le rapport'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (confirmed != true) {
      for (final ctrl in anomalyCtrls) {
        ctrl.dispose();
      }
      generalCtrl.dispose();
      compteRenduCtrl.dispose();
      return;
    }

    final details = checklist
        .map((e) => {
              'element': e.label,
              'decision': _decisionLabel(e.decision),
              'anomalie': e.decision == _ChecklistDecision.aChanger ? e.anomaly.trim() : '',
            })
        .toList();
    final anomalies = details.where((e) => (e['decision'] ?? '') == 'À changer').toList();
    final notes = [
      'Rapport contrôle préventif ($machineName)',
      'Résultat global: $selectedResultat',
      if (compteRenduCtrl.text.trim().isNotEmpty) 'Compte-rendu: ${compteRenduCtrl.text.trim()}',
      for (final d in details)
        '- ${d['element']}: ${d['decision']}${(d['anomalie'] as String).isNotEmpty ? ' (${d['anomalie']})' : ''}',
      if (generalCtrl.text.trim().isNotEmpty) 'Notes: ${generalCtrl.text.trim()}',
    ].join('\n');

    setState(() => _isSavingChecklist = true);
    try {
      final nowIso = DateTime.now().toIso8601String();
      await ApiService.updateControleStatus(
        id,
        'terminé',
        notes: notes,
        technicienId: _apiTechnicianId,
        extraPayload: {
          'rapportControle': {
            'technicianName': _technicianName,
            'technicienId': _apiTechnicianId,
            'machineName': machineName,
            'machineId': (c['machineId'] ?? '').toString(),
            'typeMaintenance': 'preventive',
            'elementControle': (c['elementControle'] ?? c['typeControle'] ?? '').toString(),
            'datePrevue': (c['datePrevue'] ?? c['dateControle'] ?? '').toString(),
            'dateRealisation': nowIso,
            'statutFinal': 'terminé',
            'createdAt': nowIso,
            'resultat': selectedResultat,
            'declencheParHeuresMarche': true,
            'compteRenduTechnicien': compteRenduCtrl.text.trim(),
            'items': details,
            'hasAnomaly': anomalies.isNotEmpty,
            'generalNote': generalCtrl.text.trim(),
          },
        },
      );
    await _fetchControles();
    if (mounted) {
        _notifyBanner(
          anomalies.isEmpty
              ? 'Rapport enregistré. Contrôle terminé et archivé.'
              : 'Rapport enregistré avec anomalies. Responsable maintenance notifié.',
          anomalies.isEmpty ? _ok : _warn2,
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingChecklist = false);
      for (final ctrl in anomalyCtrls) {
        ctrl.dispose();
      }
      generalCtrl.dispose();
      compteRenduCtrl.dispose();
    }
  }

  Future<void> _scanAndFinish(Map<String, dynamic> selected) async {
    if (_isFinishingFromScan) return;
    setState(() => _isFinishingFromScan = true);
    try {
      final isWeb = kIsWeb;
      final message = isWeb
          ? 'Scan QR disponible sur mobile Android/iOS.'
          : 'Scanner temporairement indisponible sur cette version.';
      _notifyBanner(message, _warn2);
    } finally {
      if (mounted) setState(() => _isFinishingFromScan = false);
    }
  }

  String _emptyCalendarMessage() {
    if (_allControles.isEmpty) {
      return _showOnlyCurrentWeek
          ? 'Aucun contrôle prévu pour cette semaine.'
          : 'Aucun contrôle assigné pour ce technicien.';
    }
    final hasOpenButStopped = _allControles.any(
      (c) => !_isDone(c) && !_showOpenControleWhenMachineRunning(c),
    );
    if (hasOpenButStopped) {
      return 'Les missions ouvertes s’affichent uniquement lorsque la machine est en marche (RUNNING). '
          'À l’arrêt, elles sont masquées ; les interventions terminées restent visibles selon la période.';
    }
    return _showOnlyCurrentWeek
        ? 'Aucun contrôle prévu pour cette semaine.'
        : 'Aucun contrôle assigné pour ce technicien.';
  }

  Map<_ControlPriority, int> _stats() {
    final s = <_ControlPriority, int>{
      _ControlPriority.urgent: 0,
      _ControlPriority.high: 0,
      _ControlPriority.normal: 0,
      _ControlPriority.low: 0,
      _ControlPriority.done: 0,
    };
    for (final c in _visibleControles()) {
      final p = _priorityOf(c);
      s[p] = (s[p] ?? 0) + 1;
    }
    return s;
  }

  void _openReportsHistory() {
    Navigator.pushNamed(
      context,
      '/control-reports-history',
      arguments: {
        'technicianName': _technicianName,
        'technicianId': _apiTechnicianId.isNotEmpty ? _apiTechnicianId : _requestedTechnicianId,
        'historyMode': 'reports',
      },
    );
  }

  void _openControlsHistory() {
    Navigator.pushNamed(
      context,
      '/control-reports-history',
      arguments: {
        'technicianName': _technicianName,
        'technicianId': _apiTechnicianId.isNotEmpty ? _apiTechnicianId : _requestedTechnicianId,
        'historyMode': 'all_controls',
      },
    );
  }

  void _openPreventiveHistoryGlobal() {
    Navigator.pushNamed(context, '/preventive-history');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surfaceHeader,
        title: Text('Calendrier de contrôle', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
        actions: [
          if (_managerMode)
            IconButton(
              tooltip: 'Historique préventif global',
              onPressed: _openPreventiveHistoryGlobal,
              icon: const Icon(Icons.fact_check_outlined),
            ),
          IconButton(
            tooltip: 'Historique des contrôles (base)',
            onPressed: _openControlsHistory,
            icon: const Icon(Icons.assignment_turned_in_outlined),
          ),
          IconButton(
            tooltip: 'Historique rapports détaillés',
            onPressed: _openReportsHistory,
            icon: const Icon(Icons.history),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: _accent));

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: _danger, size: 40),
              const SizedBox(height: 12),
              Text(_errorMessage!, textAlign: TextAlign.center, style: GoogleFonts.inter(color: Colors.white)),
              const SizedBox(height: 12),
              FilledButton(onPressed: _fetchControles, child: const Text('Réessayer')),
            ],
          ),
        ),
      );
    }

    final visible = _visibleControles();
    final stats = _stats();
    final pickerEntries = _machinePickerEntries();

    return RefreshIndicator(
      onRefresh: _fetchControles,
      color: _accent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (_urgentAlert != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _danger.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _danger.withOpacity(0.9)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: _danger),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_urgentAlert!, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600))),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _accent.withOpacity(0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.engineering_outlined, color: _accent, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Contrôle routine (préventif)',
                      style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Chaque machine possède des missions préventives (ex. routine capteurs moteur, condensateurs) '
                  'générées automatiquement selon le temps de marche lorsque la machine est en service. '
                  'Le technicien ouvre la mission dans la liste ci-dessous, appuie sur « Valider » puis '
                  '« Terminer » : la checklist (capteurs en bon état ou à corriger) et le compte-rendu sont '
                  'enregistrés en base de données.',
                  style: GoogleFonts.inter(color: _muted, fontSize: 12, height: 1.45),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_calendarMachineId.isNotEmpty) ...[
            if (pickerEntries.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DropdownButtonFormField<String>(
                  value: _calendarMachineId,
                  isExpanded: true,
                  dropdownColor: _surface,
                  style: GoogleFonts.inter(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Machine',
                    labelStyle: GoogleFonts.inter(color: _muted),
                    filled: true,
                    fillColor: _surface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
                    ),
                  ),
                  items: pickerEntries
                      .map(
                        (e) => DropdownMenuItem<String>(
                          value: e.key,
                          child: Text(
                            e.value == e.key ? e.key : '${e.value} · ${e.key}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _calendarMachineId = v);
                  },
                ),
              ),
            MachineControlCalendarPanel(
              key: ValueKey<String>(_calendarMachineId),
              machineId: _calendarMachineId,
              machineName: _calendarMachineDisplayName(),
              panelColor: _surface,
              accentOrange: _accent,
              accentCyan: _cyan,
              textColor: Colors.white,
              mutedColor: _muted,
              technicianId: _apiTechnicianId.isNotEmpty
                  ? _apiTechnicianId
                  : (_requestedTechnicianId.isNotEmpty ? _requestedTechnicianId : null),
              technicianName: _technicianName.trim().isNotEmpty ? _technicianName.trim() : null,
              allowSaisieTerrain: !_managerMode,
            ),
          ] else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Column(
                children: [
                  Icon(Icons.calendar_month_rounded, size: 48, color: _accent.withOpacity(0.85)),
                  const SizedBox(height: 16),
                  Text(
                    'Aucune machine disponible pour le calendrier.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _emptyCalendarMessage(),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(color: _muted, fontSize: 13, height: 1.4),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: _openControlsHistory,
                icon: const Icon(Icons.assignment_turned_in_outlined, size: 18),
                label: const Text('Historique des contrôles'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              ),
              OutlinedButton.icon(
                onPressed: _openReportsHistory,
                icon: const Icon(Icons.history, size: 18),
                label: const Text('Historique rapports'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              ),
              if (_managerMode)
                OutlinedButton.icon(
                  onPressed: _openPreventiveHistoryGlobal,
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: const Text('Historique préventif'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (!_managerMode)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                '${_technicianName.toUpperCase()} · ${_requestedTechnicianId.isNotEmpty ? _requestedTechnicianId : "session"}',
                style: GoogleFonts.spaceGrotesk(color: _muted, fontSize: 11),
              ),
            ),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.white24),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                _calendarMachineId.isNotEmpty
                    ? 'Vue liste — ${_calendarMachineDisplayName()} (${visible.length})'
                    : 'Vue liste des missions (${visible.length})',
                style: GoogleFonts.spaceGrotesk(color: Colors.white70, fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                _calendarMachineId.isNotEmpty
                    ? 'Missions de contrôle pour cette machine'
                    : 'Statistiques, filtres et cartes détaillées',
                style: GoogleFonts.inter(color: _muted, fontSize: 12),
              ),
              children: [
                const SizedBox(height: 8),
                _buildStatsCard(stats),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _rangeTab(
                          label: 'Cette semaine',
                          selected: _showOnlyCurrentWeek,
                          onTap: () => setState(() => _showOnlyCurrentWeek = true),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _rangeTab(
                          label: 'Tout',
                          selected: !_showOnlyCurrentWeek,
                          onTap: () => setState(() => _showOnlyCurrentWeek = false),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (visible.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      _emptyCalendarMessage(),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(color: _muted),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildControlsResponsiveGrid(visible),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard(Map<_ControlPriority, int> stats) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('STATISTIQUES', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _statLine('Urgents', stats[_ControlPriority.urgent] ?? 0, _danger),
          _statLine('Hautes', stats[_ControlPriority.high] ?? 0, _warn2),
          _statLine('Normales', stats[_ControlPriority.normal] ?? 0, _warn),
          _statLine('Terminés', stats[_ControlPriority.done] ?? 0, _ok),
        ],
      ),
    );
  }

  Widget _statLine(String label, int value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: GoogleFonts.inter(color: Colors.white))),
          Text('$value', style: GoogleFonts.inter(color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _rangeTab({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final bg = selected ? _accent.withOpacity(0.22) : Colors.transparent;
    final border = selected ? _accent : Colors.white24;
    final fg = selected ? Colors.white : _muted;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(color: fg, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildControlsResponsiveGrid(List<Map<String, dynamic>> controls) {
    return LayoutBuilder(
      builder: (context, constraints) {
        int columns = 1;
        if (constraints.maxWidth >= 1300) {
          columns = 3;
        } else if (constraints.maxWidth >= 780) {
          columns = 2;
        }
        if (columns == 1) {
          return Column(children: controls.map(_buildControlCard).toList());
        }
        return GridView.builder(
          itemCount: controls.length,
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: columns >= 2 ? 1.28 : 1.45,
          ),
          itemBuilder: (context, index) => _buildControlCard(controls[index]),
        );
      },
    );
  }

  Widget _buildControlCard(Map<String, dynamic> c) {
    final priority = _priorityOf(c);
    final pColor = _priorityColor(priority);
    final machineName = (c['machineName'] ?? c['machineId'] ?? 'Machine').toString();
    final machineId = (c['machineId'] ?? '').toString();
    final location = (c['machineLocation'] ?? c['machine_location'] ?? '').toString().trim();
    final type = (c['typeControle'] ?? 'Contrôle').toString();
    final status = (c['statut'] ?? 'en_attente').toString();
    final stLower = _status(c);
    final elementControle = (c['elementControle'] ?? c['typeControle'] ?? 'Élément').toString();
    final assignedTech = (c['technicienNom'] ?? c['technicianName'] ?? c['technicienId'] ?? '').toString();
    final seuil = _seuilHeures(c);
    final totalLive = _totalHeuresLive(c);
    final due = _dueDate(c);
    final tempsRestantColor = _tempsRestantAccent(c, pColor);
    final debut = _asDate(c['machineDebutSessionMarche']);
    final enMarche = c['machineEnMarche'] == true;
    final canValider = !_managerMode && !_isDone(c) && stLower != 'en_cours';
    final canTerminer = !_managerMode && !_isDone(c) && stLower == 'en_cours';

    return Card(
      color: _surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: pColor.withOpacity(0.8), width: 1.4),
        borderRadius: BorderRadius.circular(14),
      ),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _badge(_priorityLabel(priority), pColor),
                const Spacer(),
                _badge(_prettyStatus(status), Colors.white70),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.22),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: pColor.withOpacity(0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.precision_manufacturing, color: pColor, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              machineName,
                              style: GoogleFonts.spaceGrotesk(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            if (machineId.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  'ID machine : $machineId',
                                  style: GoogleFonts.inter(color: _muted, fontSize: 12.5),
                                ),
                              ),
                            if (location.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Icon(Icons.place_outlined, size: 16, color: _accent),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      location,
                                      style: GoogleFonts.inter(color: Colors.white.withOpacity(0.92), fontSize: 13, height: 1.3),
                                    ),
                                  ),
                                ],
                              ),
                            ] else ...[
                              const SizedBox(height: 4),
                              Text(
                                'Position : non renseignée',
                                style: GoogleFonts.inter(color: _muted, fontSize: 11.5, fontStyle: FontStyle.italic),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(Icons.timer_outlined, size: 18, color: tempsRestantColor),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Temps restant pour le contrôle',
                              style: GoogleFonts.inter(color: _muted, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _tempsRestantControleLabel(c),
                              style: GoogleFonts.inter(
                                color: tempsRestantColor,
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                                height: 1.25,
                              ),
                            ),
                            if (due != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Date prévue : ${due.toLocal().toString().split('.').first}',
                                  style: GoogleFonts.inter(color: Colors.white70, fontSize: 11),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text('Type : $type', style: GoogleFonts.inter(color: _muted)),
            const SizedBox(height: 4),
            Text('Élément à contrôler : $elementControle', style: GoogleFonts.inter(color: Colors.white70)),
            if (assignedTech.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Technicien : $assignedTech', style: GoogleFonts.inter(color: Colors.white70)),
            ],
            const SizedBox(height: 4),
            Text(
              'Début marche (session) : ${debut != null ? debut.toLocal().toString().split(".").first : "—"}',
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text('Machine en marche : ${enMarche ? "oui" : "non"}', style: GoogleFonts.inter(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              'Cumul temps de fonctionnement : ${totalLive.toStringAsFixed(1)} h / seuil ${seuil} h',
              style: GoogleFonts.inter(color: Colors.white70),
            ),
            if (!_isDone(c)) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_managerMode) ...[
                    FilledButton.icon(
                      onPressed: () => _assignControle(c),
                      icon: const Icon(Icons.person_add_alt_1, size: 18),
                      label: const Text('Assigner'),
                      style: FilledButton.styleFrom(minimumSize: const Size(140, 48), backgroundColor: _accent),
                    ),
                  ] else ...[
                    if (canValider)
                      FilledButton.icon(
                        onPressed: () => _validerControle(c),
                        icon: const Icon(Icons.how_to_reg_outlined, size: 18),
                        label: const Text('Valider'),
                        style: FilledButton.styleFrom(minimumSize: const Size(140, 48), backgroundColor: _accent),
                      ),
                    if (canTerminer) ...[
                      FilledButton.icon(
                        onPressed: _isFinishingFromScan ? null : () => _scanAndFinish(c),
                        icon: const Icon(Icons.qr_code_scanner, size: 18),
                        label: const Text('Scanner'),
                        style: FilledButton.styleFrom(minimumSize: const Size(140, 48), backgroundColor: _accent),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _finishControle(c),
                        icon: const Icon(Icons.task_alt, size: 18),
                        label: const Text('Terminer'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(140, 48)),
                      ),
                    ],
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.8)),
      ),
      child: Text(text, style: GoogleFonts.inter(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}
