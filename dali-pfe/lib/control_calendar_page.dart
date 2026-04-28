import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_barcode_scanner/flutter_barcode_scanner.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'services/api_service.dart';

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

  final List<Map<String, dynamic>> _allControles = <Map<String, dynamic>>[];
  io.Socket? _socket;

  bool _isLoading = true;
  bool _argsLoaded = false;
  bool _isFinishingFromScan = false;
  bool _isSavingChecklist = false;
  bool _showOnlyCurrentWeek = true;

  String? _errorMessage;
  String? _urgentAlert;

  String _technicianName = 'TECHNICIEN';
  String _requestedTechnicianId = '';
  String _apiTechnicianId = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsLoaded) return;
    _argsLoaded = true;

    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final qp = Uri.base.queryParameters;
    _technicianName = (args?['technicianName'] ?? qp['technicianName'] ?? 'TECHNICIEN').toString();
    _requestedTechnicianId = (args?['technicianId'] ?? qp['technicienId'] ?? qp['technicianId'] ?? '').toString().trim();

    _initialize();
  }

  @override
  void dispose() {
    _socket?.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _resolveApiTechnicianId();
    await _fetchControles();
    _initSocket();
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

  int _totalHeures(Map<String, dynamic> c) => _asInt(
        (c['tempsMarche'] is Map) ? c['tempsMarche']['totalHeures'] : c['tempsMarcheTotalHeures'],
      );

  int _heuresRestantes(Map<String, dynamic> c) => _seuilHeures(c) - _totalHeures(c);

  DateTime? _dueDate(Map<String, dynamic> c) =>
      _asDate(c['dateLimite'] ?? c['dueDate'] ?? c['plannedAt'] ?? c['createdAt']);

  DateTime _startOfWeek(DateTime date) {
    final clean = DateTime(date.year, date.month, date.day);
    return clean.subtract(Duration(days: clean.weekday - DateTime.monday));
  }

  bool _isInCurrentWeek(Map<String, dynamic> c) {
    final d = _dueDate(c);
    if (d == null) return false;
    final now = DateTime.now();
    final start = _startOfWeek(now);
    final end = start.add(const Duration(days: 7));
    final current = DateTime(d.year, d.month, d.day);
    return !current.isBefore(start) && current.isBefore(end);
  }

  List<Map<String, dynamic>> _visibleControles() {
    if (!_showOnlyCurrentWeek) return _allControles;
    return _allControles.where(_isInCurrentWeek).toList();
  }

  String _status(Map<String, dynamic> c) => (c['statut'] ?? 'planifié').toString().toLowerCase();
  bool _isDone(Map<String, dynamic> c) => _status(c) == 'terminé' || _status(c) == 'termine';

  _ControlPriority _priorityOf(Map<String, dynamic> c) {
    if (_isDone(c)) return _ControlPriority.done;
    final rest = _heuresRestantes(c);
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
      if (_apiTechnicianId.isEmpty) {
        throw Exception('Technicien non identifié.');
      }
      final data = await ApiService.getControlesForTechnician(_apiTechnicianId, days: 30);
      final normalized = data.map((e) => Map<String, dynamic>.from(e)).toList();
      _sortControls(normalized);
      if (!mounted) return;
      setState(() {
        _allControles
          ..clear()
          ..addAll(normalized);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
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
    final payloadId = (c['technicienId'] ?? c['technicianId'] ?? '').toString().trim();
    if (payloadId.isEmpty) return true;
    return payloadId == _apiTechnicianId || payloadId == _requestedTechnicianId;
  }

  void _upsertControle(Map<String, dynamic> raw) {
    final next = Map<String, dynamic>.from(raw);
    final id = (next['id'] ?? next['_id']).toString();
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
  }

  Future<void> _finishControleDirect(Map<String, dynamic> c, {required String notes}) async {
    final id = (c['id'] ?? c['_id']).toString();
    if (id.isEmpty) return;
    await ApiService.updateControleStatus(id, 'terminé', notes: notes);
    await _fetchControles();
  }

  List<_ChecklistItem> _defaultChecklist(Map<String, dynamic> c) {
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
    final machineName = (c['machineName'] ?? c['machineId'] ?? 'Machine').toString();
    final checklist = _defaultChecklist(c);
    final generalCtrl = TextEditingController();
    final anomalyCtrls = List<TextEditingController>.generate(
      checklist.length,
      (i) => TextEditingController(text: checklist[i].anomaly),
    );
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
      for (final d in details)
        '- ${d['element']}: ${d['decision']}${(d['anomalie'] as String).isNotEmpty ? ' (${d['anomalie']})' : ''}',
      if (generalCtrl.text.trim().isNotEmpty) 'Notes: ${generalCtrl.text.trim()}',
    ].join('\n');

    setState(() => _isSavingChecklist = true);
    try {
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
            'createdAt': DateTime.now().toIso8601String(),
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
              ? 'Rapport enregistré. Contrôle validé.'
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
    }
  }

  Future<void> _scanAndFinish(Map<String, dynamic> selected) async {
    if (kIsWeb) {
      _notifyBanner('Scan QR disponible sur mobile Android/iOS.', _warn2);
      return;
    }
    if (_isFinishingFromScan) return;
    setState(() => _isFinishingFromScan = true);
    try {
      final scanResult = await FlutterBarcodeScanner.scanBarcode('#FF6E00', 'Annuler', true, ScanMode.QR);
      if (!mounted || scanResult == '-1') return;
      final scanned = scanResult.trim().toLowerCase();

      final pending = _allControles.where((c) => !_isDone(c)).toList();
      Map<String, dynamic> match = {};
      final selectedId = (selected['id'] ?? selected['_id'] ?? '').toString();
      if (selectedId.isNotEmpty) {
        match = pending.firstWhere((c) => (c['id'] ?? c['_id']).toString() == selectedId, orElse: () => <String, dynamic>{});
      }
      if (match.isEmpty) {
        match = pending.firstWhere((c) {
          final machineId = (c['machineId'] ?? '').toString().toLowerCase();
          final machineName = (c['machineName'] ?? '').toString().toLowerCase();
          return machineId == scanned || machineName == scanned || scanned.contains(machineId) || scanned.contains(machineName);
        }, orElse: () => <String, dynamic>{});
      }
      if (match.isEmpty) {
        _notifyBanner('Aucun contrôle assigné trouvé pour ce QR.', _danger);
        return;
      }
      await _finishControleDirect(match, notes: 'Contrôle terminé via scan QR.');
      _notifyBanner('Contrôle marqué terminé via scanner.', _ok);
    } catch (e) {
      _notifyBanner('Erreur scanner: $e', _danger);
    } finally {
      if (mounted) setState(() => _isFinishingFromScan = false);
    }
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
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surfaceHeader,
        title: Text('Calendrier de contrôle', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Historique rapports',
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
    return RefreshIndicator(
      onRefresh: _fetchControles,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('TECHNICIEN ${_technicianName.toUpperCase()} - Mes contrôles',
              style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('ID: $_requestedTechnicianId', style: GoogleFonts.spaceGrotesk(color: _muted, fontSize: 12)),
          if (_requestedTechnicianId != _apiTechnicianId)
            Text('ID API résolu: $_apiTechnicianId', style: GoogleFonts.spaceGrotesk(color: _warn2, fontSize: 11)),
          if (_urgentAlert != null) ...[
            const SizedBox(height: 12),
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
          ],
          const SizedBox(height: 14),
          _buildStatsCard(stats),
          const SizedBox(height: 10),
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
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _openReportsHistory,
            icon: const Icon(Icons.history),
            label: const Text('Voir historique des rapports'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
          ),
          const SizedBox(height: 16),
          if (visible.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 30),
                child: Text(
                  _showOnlyCurrentWeek
                      ? 'Aucun contrôle prévu pour cette semaine.'
                      : 'Aucun contrôle assigné pour ce technicien.',
                  style: GoogleFonts.inter(color: _muted),
                ),
              ),
            )
          else
            _buildControlsResponsiveGrid(visible),
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
            childAspectRatio: 1.6,
          ),
          itemBuilder: (context, index) => _buildControlCard(controls[index]),
        );
      },
    );
  }

  Widget _buildControlCard(Map<String, dynamic> c) {
    final priority = _priorityOf(c);
    final pColor = _priorityColor(priority);
    final rest = _heuresRestantes(c);
    final machineName = (c['machineName'] ?? c['machineId'] ?? 'Machine').toString();
    final machineId = (c['machineId'] ?? '').toString();
    final type = (c['typeControle'] ?? 'Contrôle').toString();
    final status = (c['statut'] ?? 'planifié').toString();
    final seuil = _seuilHeures(c);
    final total = _totalHeures(c);
    final due = _dueDate(c);
    final hoursBadge = _isDone(c) ? '✅' : '${rest}h';

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
                _badge(status.toUpperCase(), Colors.white70),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Machine: $machineName${machineId.isNotEmpty ? ' (ID: $machineId)' : ''}',
              style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text('Type: $type', style: GoogleFonts.inter(color: _muted)),
            const SizedBox(height: 4),
            Text('Temps de marche: ${total}h / ${seuil}h', style: GoogleFonts.inter(color: Colors.white70)),
            const SizedBox(height: 4),
            Text('Heures restantes: $hoursBadge', style: GoogleFonts.inter(color: pColor, fontWeight: FontWeight.w700)),
            if (due != null) ...[
              const SizedBox(height: 4),
              Text('Date limite: ${due.toLocal().toString().split(".").first}', style: GoogleFonts.inter(color: Colors.white70)),
            ],
            if (!_isDone(c)) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
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
