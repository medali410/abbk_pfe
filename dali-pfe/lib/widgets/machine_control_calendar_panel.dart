import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';

/// Événement affiché dans le calendrier machine (contrôles préventifs + ordres maintenance).
enum _MachineCalEventKind { controle, maintenance }

class _MachineCalEvent {
  _MachineCalEvent({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.day,
  });

  final _MachineCalEventKind kind;
  final String title;
  final String subtitle;
  final DateTime day;
}

/// Calendrier mensuel interactif pour le panneau de contrôle machine : navigation mois/année,
/// sélection de jour, indicateurs contrôles / maintenance (données API).
class MachineControlCalendarPanel extends StatefulWidget {
  const MachineControlCalendarPanel({
    super.key,
    required this.machineId,
    this.machineName = '',
    this.panelColor = const Color(0xFF161826),
    this.accentOrange = const Color(0xFFFF7E21),
    this.accentCyan = const Color(0xFF75D1FF),
    this.textColor = const Color(0xFFE2DFFF),
    this.mutedColor = const Color(0xFFE2BFB0),
    this.compact = false,
    /// Mongo `_id` ou id métier — associé au compte-rendu.
    this.technicianId,
    /// Nom affiché du technicien (stocké en base avec le contrôle terminé).
    this.technicianName,
    /// Saisie libre + envoi API (désactiver ex. vue gestionnaire lecture seule).
    this.allowSaisieTerrain = true,
    this.showCalendar = false,
    this.onSaisieCalendrierSuccess,
  });

  final String machineId;
  final String machineName;
  final Color panelColor;
  final Color accentOrange;
  final Color accentCyan;
  final Color textColor;
  final Color mutedColor;
  final bool compact;
  final String? technicianId;
  final String? technicianName;
  final bool allowSaisieTerrain;
  final bool showCalendar;

  /// Après enregistrement réussi du compte rendu (collection control_calendrier + contrôle).
  final VoidCallback? onSaisieCalendrierSuccess;

  @override
  State<MachineControlCalendarPanel> createState() => _MachineControlCalendarPanelState();
}

class _MachineControlCalendarPanelState extends State<MachineControlCalendarPanel> {
  late DateTime _visibleMonth;
  DateTime? _selectedDay;
  bool _loading = true;
  String? _error;
  final Map<String, List<_MachineCalEvent>> _eventsByDay = {};
  List<_MachineCalEvent> _selectedEvents = [];
  final TextEditingController _saisieCtrl = TextEditingController();
  bool _saisieSubmitting = false;

  static String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  DateTime? _parseControlDay(Map<String, dynamic> c) {
    for (final k in ['datePrevue', 'dateControle', 'dateLimite', 'plannedAt', 'createdAt']) {
      final raw = c[k];
      if (raw == null) continue;
      final dt = DateTime.tryParse(raw.toString());
      if (dt != null) {
        final local = dt.toLocal();
        return DateTime(local.year, local.month, local.day);
      }
    }
    return null;
  }

  DateTime? _parseMaintenanceDay(Map<String, dynamic> o) {
    for (final k in ['scheduledAt', 'plannedDate', 'dueDate', 'createdAt', 'updatedAt']) {
      final raw = o[k];
      if (raw == null) continue;
      final dt = DateTime.tryParse(raw.toString());
      if (dt != null) {
        final local = dt.toLocal();
        return DateTime(local.year, local.month, local.day);
      }
    }
    return null;
  }

  static const Color _controleAccentRed = Color(0xFFE53935);

  bool _isCapteurStyleTitle(String title) {
    final t = title.toLowerCase();
    return t.contains('capteur') || t.contains('sensor') || t.contains('moteur');
  }

  String _jourYyyyMmDd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _submitSaisieTerrain() async {
    final d = _selectedDay;
    if (d == null) return;
    final text = _saisieCtrl.text.trim();
    if (text.isEmpty || widget.machineId.trim().isEmpty) return;
    setState(() => _saisieSubmitting = true);
    try {
      await ApiService.submitControleCalendrierSaisie(
        machineId: widget.machineId.trim(),
        jourYyyyMmDd: _jourYyyyMmDd(d),
        compteRendu: text,
        technicienId: widget.technicianId,
        technicienNom: widget.technicianName?.trim().isNotEmpty == true
            ? widget.technicianName!.trim()
            : null,
      );
      if (!mounted) return;
      _saisieCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Contrôle terminé — enregistré en base de données.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          backgroundColor: const Color(0xFF2E7D32),
        ),
      );
      await _load();
      widget.onSaisieCalendrierSuccess?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', ''), style: GoogleFonts.inter()),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _saisieSubmitting = false);
    }
  }

  Future<void> _load() async {
    final mid = widget.machineId.trim();
    if (mid.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Identifiant machine manquant.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ApiService.getControlesForMachine(mid),
        ApiService.getMaintenanceOrders(),
      ]);
      final controles = results[0];
      final allOrders = results[1];
      final orders = allOrders.where((o) {
        final m = (o['machineId'] ?? '').toString();
        return m == mid || m.toUpperCase() == mid.toUpperCase();
      }).toList();

      final map = <String, List<_MachineCalEvent>>{};
      for (final c in controles) {
        final day = _parseControlDay(Map<String, dynamic>.from(c));
        if (day == null) continue;
        final type = (c['typeControle'] ?? 'Contrôle').toString();
        final stat = (c['statut'] ?? '').toString();
        final k = _dayKey(day);
        map.putIfAbsent(k, () => []).add(
              _MachineCalEvent(
                kind: _MachineCalEventKind.controle,
                title: type,
                subtitle: 'Statut : $stat',
                day: day,
              ),
            );
      }
      for (final o in orders) {
        final day = _parseMaintenanceDay(Map<String, dynamic>.from(o));
        if (day == null) continue;
        final desc = (o['description'] ?? 'Maintenance').toString();
        final st = (o['status'] ?? '').toString();
        final k = _dayKey(day);
        map.putIfAbsent(k, () => []).add(
              _MachineCalEvent(
                kind: _MachineCalEventKind.maintenance,
                title: desc.length > 48 ? '${desc.substring(0, 45)}…' : desc,
                subtitle: 'Ordre · $st',
                day: day,
              ),
            );
      }

      for (final list in map.values) {
        list.sort((a, b) {
          final pa = a.kind == _MachineCalEventKind.controle && _isCapteurStyleTitle(a.title);
          final pb = b.kind == _MachineCalEventKind.controle && _isCapteurStyleTitle(b.title);
          if (pa && !pb) return -1;
          if (!pa && pb) return 1;
          return 0;
        });
      }

      if (!mounted) return;
      setState(() {
        _eventsByDay
          ..clear()
          ..addAll(map);
        _loading = false;
        _syncSelectionAfterLoad();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _syncSelectionAfterLoad() {
    if (_selectedDay == null) return;
    final k = _dayKey(_selectedDay!);
    _selectedEvents = List<_MachineCalEvent>.from(_eventsByDay[k] ?? []);
  }

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _visibleMonth = DateTime(n.year, n.month, 1);
    _selectedDay = DateTime(n.year, n.month, n.day);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _saisieCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MachineControlCalendarPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.machineId != widget.machineId) {
      _load();
    }
  }

  void _shiftMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta, 1);
    });
  }

  Future<void> _pickYearMonth() async {
    var yy = _visibleMonth.year;
    var mm = _visibleMonth.month;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: widget.panelColor,
          title: Text('Mois et année', style: GoogleFonts.spaceGrotesk(color: widget.textColor, fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<int>(
                value: yy,
                dropdownColor: widget.panelColor,
                isExpanded: true,
                items: List.generate(11, (i) => DateTime.now().year - 5 + i)
                    .map(
                      (y) => DropdownMenuItem(
                        value: y,
                        child: Text('$y', style: GoogleFonts.inter(color: widget.textColor)),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setS(() => yy = v ?? yy),
              ),
              const SizedBox(height: 12),
              DropdownButton<int>(
                value: mm,
                dropdownColor: widget.panelColor,
                isExpanded: true,
                items: List.generate(
                  12,
                  (i) => DropdownMenuItem(
                    value: i + 1,
                    child: Text(
                      DateFormat.MMMM('fr_FR').format(DateTime(yy, i + 1)),
                      style: GoogleFonts.inter(color: widget.textColor),
                    ),
                  ),
                ),
                onChanged: (v) => setS(() => mm = v ?? mm),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Annuler', style: GoogleFonts.inter(color: widget.mutedColor))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
          ],
        ),
      ),
    );
    if (ok == true && mounted) {
      setState(() => _visibleMonth = DateTime(yy, mm, 1));
    }
  }

  void _selectDay(DateTime day) {
    setState(() {
      _selectedDay = day;
      _selectedEvents = List<_MachineCalEvent>.from(_eventsByDay[_dayKey(day)] ?? []);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showCalendar) return const SizedBox.shrink();

    final title = widget.machineName.isNotEmpty ? 'CALENDRIER · ${widget.machineName}' : 'CALENDRIER INTERVENTIONS';
    final monthLabel = DateFormat.yMMMM('fr_FR').format(_visibleMonth);
    final cellSize = widget.compact ? 30.0 : 38.0;
    final headerFs = widget.compact ? 9.0 : 10.0;
    final dayFs = widget.compact ? 12.0 : 14.0;

    return Container(
      padding: EdgeInsets.all(widget.compact ? 12 : 16),
      decoration: BoxDecoration(
        color: widget.panelColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_month_rounded, color: widget.accentOrange, size: widget.compact ? 18 : 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.spaceGrotesk(
                    color: widget.accentOrange,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    fontSize: widget.compact ? 10 : 11,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Actualiser',
                onPressed: _loading ? null : _load,
                icon: _loading
                    ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: widget.accentOrange))
                    : Icon(Icons.refresh_rounded, color: widget.accentOrange, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(
                onPressed: () => _shiftMonth(-1),
                icon: Icon(Icons.chevron_left_rounded, color: widget.textColor),
                tooltip: 'Mois précédent',
              ),
              Expanded(
                child: InkWell(
                  onTap: _pickYearMonth,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      monthLabel,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.spaceGrotesk(
                        color: widget.textColor,
                        fontWeight: FontWeight.w800,
                        fontSize: widget.compact ? 14 : 16,
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _shiftMonth(1),
                icon: Icon(Icons.chevron_right_rounded, color: widget.textColor),
                tooltip: 'Mois suivant',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim']
                .map(
                  (w) => Expanded(
                    child: Center(
                      child: Text(
                        w,
                        style: GoogleFonts.spaceGrotesk(color: widget.mutedColor, fontSize: headerFs, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 6),
          _buildMonthGrid(cellSize, dayFs),
          const SizedBox(height: 12),
          _legend(),
          if (_selectedDay != null) ...[
            const SizedBox(height: 14),
            Text(
              'Jour sélectionné : ${DateFormat.yMd('fr_FR').format(_selectedDay!)}',
              style: GoogleFonts.inter(color: widget.mutedColor, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (_selectedEvents.isEmpty)
              Text(
                'Aucun événement enregistré pour ce jour.',
                style: GoogleFonts.inter(color: widget.textColor.withValues(alpha: 0.75), fontSize: 13),
              )
            else
              ..._selectedEvents.map((e) => _eventTile(e)),
            if (widget.allowSaisieTerrain) ...[
              const SizedBox(height: 16),
              Text(
                'Compte rendu de visite',
                style: GoogleFonts.spaceGrotesk(
                  color: widget.accentOrange,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Décrivez l’intervention (ex. contrôle capteurs, constat). Valider enregistre en base et marque le contrôle comme terminé.',
                style: GoogleFonts.inter(color: widget.mutedColor, fontSize: 11, height: 1.35),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _saisieCtrl,
                maxLines: 4,
                enabled: !_saisieSubmitting,
                style: GoogleFonts.inter(color: widget.textColor, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Ex. : contrôle capteur effectué, tout est OK',
                  hintStyle: GoogleFonts.inter(color: widget.mutedColor.withValues(alpha: 0.8)),
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.22),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: widget.accentOrange.withValues(alpha: 0.85)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _saisieSubmitting || widget.machineId.trim().isEmpty
                    ? null
                    : () {
                        if (_saisieCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Saisissez un compte rendu.', style: GoogleFonts.inter()),
                              backgroundColor: Colors.orange.shade800,
                            ),
                          );
                          return;
                        }
                        _submitSaisieTerrain();
                      },
                icon: _saisieSubmitting
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black.withValues(alpha: 0.7),
                        ),
                      )
                    : const Icon(Icons.check_circle_outline, size: 20),
                label: Text(
                  'Valider',
                  style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w800),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: widget.accentOrange,
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _legend() {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        _legendDot(widget.accentOrange, 'Contrôle / préventif'),
        _legendDot(_controleAccentRed, 'Contrôle capteurs / seuil'),
        _legendDot(widget.accentCyan, 'Maintenance'),
      ],
    );
  }

  Widget _legendDot(Color c, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: GoogleFonts.inter(color: widget.mutedColor, fontSize: 11)),
      ],
    );
  }

  Widget _eventTile(_MachineCalEvent e) {
    final col = e.kind != _MachineCalEventKind.maintenance
        ? (_isCapteurStyleTitle(e.title) ? _controleAccentRed : widget.accentOrange)
        : widget.accentCyan;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: col.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                e.kind == _MachineCalEventKind.controle ? Icons.fact_check_outlined : Icons.build_circle_outlined,
                size: 16,
                color: col,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  e.title,
                  style: GoogleFonts.inter(color: widget.textColor, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(e.subtitle, style: GoogleFonts.inter(color: widget.mutedColor, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildMonthGrid(double cellSize, double dayFs) {
    final y = _visibleMonth.year;
    final m = _visibleMonth.month;
    final first = DateTime(y, m, 1);
    final daysInMonth = DateTime(y, m + 1, 0).day;
    final leading = first.weekday - 1;
    final totalCells = ((leading + daysInMonth + 6) ~/ 7) * 7;
    final today = DateTime.now();
    final todayNorm = DateTime(today.year, today.month, today.day);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final cellW = maxW / 7;
        return Column(
          children: List.generate(totalCells ~/ 7, (row) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: List.generate(7, (col) {
                  final i = row * 7 + col;
                  if (i < leading || i >= leading + daysInMonth) {
                    return SizedBox(width: cellW, height: cellSize + 10);
                  }
                  final dayNum = i - leading + 1;
                  final d = DateTime(y, m, dayNum);
                  final k = _dayKey(d);
                  final events = _eventsByDay[k] ?? [];
                  final hasC = events.any((e) => e.kind == _MachineCalEventKind.controle);
                  final hasCapteur = events.any(
                    (e) => e.kind == _MachineCalEventKind.controle && _isCapteurStyleTitle(e.title),
                  );
                  final hasM = events.any((e) => e.kind == _MachineCalEventKind.maintenance);
                  final isSel = _selectedDay != null && _dayKey(_selectedDay!) == k;
                  final isToday = _dayKey(d) == _dayKey(todayNorm);
                  final primaryMission =
                      events.isNotEmpty ? events.first.title : '';
                  final selBorder = isSel
                      ? (hasCapteur ? _controleAccentRed : widget.accentOrange)
                      : isToday
                          ? widget.accentCyan.withValues(alpha: 0.5)
                          : Colors.white.withValues(alpha: 0.06);
                  final selFill = isSel
                      ? (hasCapteur
                          ? _controleAccentRed.withValues(alpha: 0.14)
                          : widget.accentOrange.withValues(alpha: 0.12))
                      : null;

                  return SizedBox(
                    width: cellW,
                    height: cellSize + (primaryMission.isNotEmpty ? 22 : 10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _selectDay(d),
                          borderRadius: BorderRadius.circular(8),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: selBorder,
                                width: isSel ? 2 : 1,
                              ),
                              color: selFill,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '$dayNum',
                                  style: GoogleFonts.spaceGrotesk(
                                    color: widget.textColor,
                                    fontWeight: isToday ? FontWeight.w900 : FontWeight.w600,
                                    fontSize: dayFs,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (hasC)
                                      Container(
                                        width: 5,
                                        height: 5,
                                        margin: const EdgeInsets.symmetric(horizontal: 1),
                                        decoration: BoxDecoration(
                                          color: hasCapteur ? _controleAccentRed : widget.accentOrange,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    if (hasM)
                                      Container(
                                        width: 5,
                                        height: 5,
                                        margin: const EdgeInsets.symmetric(horizontal: 1),
                                        decoration: BoxDecoration(color: widget.accentCyan, shape: BoxShape.circle),
                                      ),
                                    if (!hasC && !hasM) const SizedBox(height: 5),
                                  ],
                                ),
                                if (primaryMission.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2, left: 2, right: 2),
                                    child: Text(
                                      primaryMission,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.inter(
                                        color: hasCapteur ? _controleAccentRed : widget.mutedColor,
                                        fontSize: widget.compact ? 7 : 8,
                                        fontWeight: FontWeight.w600,
                                        height: 1.1,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            );
          }),
        );
      },
    );
  }
}
