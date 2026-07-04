import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'services/api_service.dart';

// ─── Palette ──────────────────────────────────────────────────────────────────
// (colors are now resolved dynamically via isDarkMode – see getters below)
const _kAccent   = Color(0xFFFF6E00);
const _kBlue     = Color(0xFF75D1FF);
const _kPurple   = Color(0xFFB388FF);
const _kGreen    = Color(0xFF4CAF50);
const _kYellow   = Color(0xFFFFC107);
const _kRed      = Color(0xFFEF5350);

// ─── Statuts ─────────────────────────────────────────────────────────────────
const _kAllStatuses = ['TOUS', 'DONE', 'IN_PROGRESS', 'PENDING', 'CANCELLED'];

class AllMissionsHistoryPage extends StatefulWidget {
  final bool isDarkMode;
  const AllMissionsHistoryPage({super.key, this.isDarkMode = false});

  @override
  State<AllMissionsHistoryPage> createState() => _AllMissionsHistoryPageState();
}

class _AllMissionsHistoryPageState extends State<AllMissionsHistoryPage> {
  // ── Theme-aware color getters ──
  Color get _kBg     => widget.isDarkMode ? const Color(0xFF0D0E1C) : const Color(0xFFFCFAF7);
  Color get _kCard   => widget.isDarkMode ? const Color(0xFF13152B) : const Color(0xFFFFFFFF);
  Color get _kBorder => widget.isDarkMode ? const Color(0xFF1E2240) : const Color(0xFFCD7F32).withOpacity(0.25);
  Color get _kText   => widget.isDarkMode ? const Color(0xFFE2DFFF) : const Color(0xFF332A21);
  Color get _kMuted  => widget.isDarkMode ? const Color(0xFFB0AECF) : const Color(0xFF8B5E3C);

  late Future<List<Map<String, dynamic>>> _future;
  String _selectedStatus = 'TOUS';
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _future = ApiService.getAllMissions();
  }

  void _reload() {
    setState(() {
      _future = ApiService.getAllMissions();
    });
  }

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> all) {
    return all.where((m) {
      // Filtre statut
      if (_selectedStatus != 'TOUS') {
        final s = (m['status'] ?? '').toString().toUpperCase();
        if (s != _selectedStatus) return false;
      }
      // Filtre recherche
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final title    = (m['title']       ?? '').toString().toLowerCase();
        final machine  = (m['machineName'] ?? '').toString().toLowerCase();
        final tech     = (m['technicianFullName'] ?? m['technicianId'] ?? '').toString().toLowerCase();
        final agent    = (m['maintenanceAgentName'] ?? '').toString().toLowerCase();
        final desc     = (m['description'] ?? '').toString().toLowerCase();
        if (!title.contains(q) && !machine.contains(q) &&
            !tech.contains(q) && !agent.contains(q) && !desc.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  Color _statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'DONE':        return _kGreen;
      case 'IN_PROGRESS': return _kBlue;
      case 'PENDING':     return _kYellow;
      case 'CANCELLED':   return _kRed;
      default:            return _kMuted;
    }
  }

  String _statusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'DONE':        return 'Terminée';
      case 'IN_PROGRESS': return 'En cours';
      case 'PENDING':     return 'En attente';
      case 'CANCELLED':   return 'Annulée';
      default:            return status;
    }
  }

  IconData _statusIcon(String status) {
    switch (status.toUpperCase()) {
      case 'DONE':        return Icons.check_circle_rounded;
      case 'IN_PROGRESS': return Icons.autorenew_rounded;
      case 'PENDING':     return Icons.schedule_rounded;
      case 'CANCELLED':   return Icons.cancel_rounded;
      default:            return Icons.help_outline_rounded;
    }
  }

  Color _priorityColor(String priority) {
    switch (priority.toUpperCase()) {
      case 'URGENT': return _kRed;
      case 'HIGH':   return _kYellow;
      case 'NORMAL': return _kBlue;
      case 'LOW':    return _kMuted;
      default:       return _kMuted;
    }
  }

  String _priorityLabel(String priority) {
    switch (priority.toUpperCase()) {
      case 'URGENT': return 'URGENT';
      case 'HIGH':   return 'HAUTE';
      case 'NORMAL': return 'NORMALE';
      case 'LOW':    return 'BASSE';
      default:       return priority;
    }
  }

  String _fmtDate(dynamic raw) {
    if (raw == null) return '—';
    final dt = DateTime.tryParse(raw.toString());
    if (dt == null) return '—';
    final local = dt.toLocal();
    final dd  = local.day.toString().padLeft(2, '0');
    final mm  = local.month.toString().padLeft(2, '0');
    final yy  = local.year.toString();
    final hh  = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$yy $hh:$min';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          _buildSearchAndFilter(),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: _kAccent),
                  );
                }
                if (snap.hasError) {
                  return _buildError(snap.error.toString());
                }
                final all      = snap.data ?? [];
                final filtered = _filtered(all);
                if (filtered.isEmpty) {
                  return _buildEmpty(all.isEmpty);
                }
                return _buildList(filtered);
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
      decoration: BoxDecoration(
        color: _kCard,
        border: Border(
          bottom: BorderSide(color: _kBorder, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Back button (si navigué depuis une autre page)
          if (Navigator.canPop(context))
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(Icons.arrow_back_ios_new_rounded, color: _kMuted, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _kAccent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.assignment_rounded, color: _kAccent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Historique Global des Missions',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _kText,
                    letterSpacing: 0.3,
                  ),
                ),
                Text(
                  'Toutes les missions de la base de données',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: _kMuted.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _reload,
            tooltip: 'Actualiser',
            icon: Icon(Icons.refresh_rounded, color: _kAccent, size: 20),
          ),
        ],
      ),
    );
  }

  // ─── Recherche + Filtre statut ─────────────────────────────────────────────
  Widget _buildSearchAndFilter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      color: _kCard,
      child: Column(
        children: [
          // Barre de recherche
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: _kBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kBorder),
            ),
            child: TextField(
              controller: _searchCtrl,
              style: GoogleFonts.inter(fontSize: 13, color: _kText),
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
              decoration: InputDecoration(
                hintText: 'Rechercher mission, machine, technicien, agent...',
                hintStyle: GoogleFonts.inter(fontSize: 12, color: _kMuted.withOpacity(0.5)),
                prefixIcon: Icon(Icons.search_rounded, color: _kMuted, size: 18),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close_rounded, size: 16, color: _kMuted),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Chips statut
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _kAllStatuses.map((s) {
                final isSelected = _selectedStatus == s;
                final color = s == 'TOUS' ? _kAccent : _statusColor(s);
                return Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 12),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedStatus = s),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? color.withOpacity(0.18) : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? color : _kBorder,
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Text(
                        s == 'TOUS' ? 'Tous' : _statusLabel(s),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? color : _kMuted,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Liste ─────────────────────────────────────────────────────────────────
  Widget _buildList(List<Map<String, dynamic>> missions) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      itemCount: missions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _MissionCard(
        mission: missions[i],
        statusColor:   _statusColor,
        statusLabel:   _statusLabel,
        statusIcon:    _statusIcon,
        priorityColor: _priorityColor,
        priorityLabel: _priorityLabel,
        fmtDate:       _fmtDate,
        isDarkMode:    widget.isDarkMode,
      ),
    );
  }

  // ─── Erreur ────────────────────────────────────────────────────────────────
  Widget _buildError(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: _kRed, size: 40),
            const SizedBox(height: 12),
            Text(
              'Erreur de chargement',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 15, fontWeight: FontWeight.w700, color: _kText,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              error,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 12, color: _kMuted),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Réessayer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Vide ──────────────────────────────────────────────────────────────────
  Widget _buildEmpty(bool dbEmpty) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              dbEmpty ? Icons.inbox_rounded : Icons.filter_list_off_rounded,
              color: _kMuted.withOpacity(0.4),
              size: 48,
            ),
            const SizedBox(height: 14),
            Text(
              dbEmpty
                  ? 'Aucune mission dans la base de données'
                  : 'Aucune mission ne correspond aux filtres',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: _kMuted, height: 1.5),
            ),
            if (!dbEmpty) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() {
                    _searchQuery = '';
                    _selectedStatus = 'TOUS';
                  });
                },
                child: Text('Effacer les filtres', style: TextStyle(color: _kAccent)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }
}

// ─── Carte Mission ───────────────────────────────────────────────────────────
class _MissionCard extends StatefulWidget {
  const _MissionCard({
    required this.mission,
    required this.statusColor,
    required this.statusLabel,
    required this.statusIcon,
    required this.priorityColor,
    required this.priorityLabel,
    required this.fmtDate,
    this.isDarkMode = false,
  });

  final Map<String, dynamic> mission;
  final Color Function(String) statusColor;
  final String Function(String) statusLabel;
  final IconData Function(String) statusIcon;
  final Color Function(String) priorityColor;
  final String Function(String) priorityLabel;
  final String Function(dynamic) fmtDate;
  final bool isDarkMode;

  @override
  State<_MissionCard> createState() => _MissionCardState();
}

class _MissionCardState extends State<_MissionCard> {
  bool _expanded = false;

  Color get _kCard   => widget.isDarkMode ? const Color(0xFF13152B) : const Color(0xFFFFFFFF);
  Color get _kBorder => widget.isDarkMode ? const Color(0xFF1E2240) : const Color(0xFFCD7F32).withOpacity(0.25);
  Color get _kText   => widget.isDarkMode ? const Color(0xFFE2DFFF) : const Color(0xFF332A21);
  Color get _kMuted  => widget.isDarkMode ? const Color(0xFFB0AECF) : const Color(0xFF8B5E3C);
  Color get _kBg     => widget.isDarkMode ? const Color(0xFF0D0E1C) : const Color(0xFFFCFAF7);

  @override
  Widget build(BuildContext context) {
    final m         = widget.mission;
    final status    = (m['status']   ?? 'PENDING').toString();
    final priority  = (m['priority'] ?? 'NORMAL').toString();
    final title     = (m['title']    ?? '—').toString();
    final machine   = (m['machineName'] ?? m['machineId'] ?? '—').toString();
    final tech      = (m['technicianFullName']  ?? m['technicianId'] ?? '—').toString();
    final agent     = (m['maintenanceAgentName'] ?? '').toString();
    final desc      = (m['description'] ?? '').toString();
    final missionId = (m['missionId'] ?? '').toString();
    final createdAt = m['createdAt'];
    final completedAt = m['completedAt'];
    final scheduledAt = m['scheduledAt'];

    final sColor = widget.statusColor(status);
    final pColor = widget.priorityColor(priority);

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _expanded ? sColor.withOpacity(0.4) : _kBorder,
            width: _expanded ? 1.5 : 1,
          ),
          boxShadow: _expanded
              ? [BoxShadow(color: sColor.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4))]
              : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header de la carte ──
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icone statut
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: sColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(widget.statusIcon(status), color: sColor, size: 18),
                  ),
                  const SizedBox(width: 10),
                  // Titre + machine
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _kText,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.precision_manufacturing_rounded, size: 12, color: _kMuted),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                machine,
                                style: GoogleFonts.inter(fontSize: 11, color: _kMuted),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Badges
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _Badge(label: widget.statusLabel(status), color: sColor),
                      const SizedBox(height: 4),
                      _Badge(label: widget.priorityLabel(priority), color: pColor, small: true),
                    ],
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: _kMuted.withOpacity(0.6),
                    size: 20,
                  ),
                ],
              ),
            ),

            // ── Infos rapides (toujours visibles) ──
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  _InfoChip(
                    icon: Icons.engineering_rounded,
                    label: tech.isEmpty ? '—' : tech,
                    color: _kPurple,
                  ),
                  if (agent.isNotEmpty)
                    _InfoChip(
                      icon: Icons.support_agent_rounded,
                      label: agent,
                      color: _kBlue,
                    ),
                  _InfoChip(
                    icon: Icons.calendar_today_rounded,
                    label: widget.fmtDate(createdAt),
                    color: _kMuted,
                  ),
                ],
              ),
            ),

            // ── Détails (expand) ──
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.fastOutSlowIn,
              alignment: Alignment.topCenter,
              child: _expanded
                  ? Container(
                      decoration: BoxDecoration(
                        color: widget.isDarkMode ? Colors.white.withOpacity(0.02) : const Color(0xFFCD7F32).withOpacity(0.04),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(14),
                          bottomRight: Radius.circular(14),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Divider(height: 1, color: _kBorder),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ID mission
                                if (missionId.isNotEmpty)
                                  _DetailRow(
                                    icon: Icons.tag_rounded,
                                    label: 'ID Mission',
                                    value: missionId,
                                    valueColor: _kMuted,
                                    isDarkMode: widget.isDarkMode,
                                  ),
                                // Description
                                if (desc.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Description',
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: _kMuted.withOpacity(0.6),
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: _kBg,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: _kBorder),
                                    ),
                                    child: Text(
                                      desc,
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: _kText.withOpacity(0.85),
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                // Dates
                                if (scheduledAt != null)
                                  _DetailRow(
                                    icon: Icons.event_rounded,
                                    label: 'Planifiée le',
                                    value: widget.fmtDate(scheduledAt),
                                    valueColor: _kYellow,
                                    isDarkMode: widget.isDarkMode,
                                  ),
                                if (completedAt != null) ...[
                                  const SizedBox(height: 6),
                                  _DetailRow(
                                    icon: Icons.check_circle_outline_rounded,
                                    label: 'Terminée le',
                                    value: widget.fmtDate(completedAt),
                                    valueColor: _kGreen,
                                    isDarkMode: widget.isDarkMode,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Widgets utilitaires ──────────────────────────────────────────────────────
class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color, this.small = false});
  final String label;
  final Color color;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 7 : 9,
        vertical: small ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: small ? 9 : 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color.withOpacity(0.8)),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            color: color.withOpacity(0.85),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.isDarkMode = false,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool isDarkMode;

  @override
  Widget build(BuildContext context) {
    final mutedColor = isDarkMode ? const Color(0xFFB0AECF) : const Color(0xFF8B5E3C);
    final textColor = valueColor ?? (isDarkMode ? const Color(0xFFE2DFFF) : const Color(0xFF332A21));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: mutedColor.withOpacity(0.6)),
        const SizedBox(width: 6),
        Text(
          '$label : ',
          style: GoogleFonts.inter(
            fontSize: 11,
            color: mutedColor.withOpacity(0.7),
            fontWeight: FontWeight.w600,
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
