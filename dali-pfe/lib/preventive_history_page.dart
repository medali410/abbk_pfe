import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import 'services/api_service.dart';
import 'utils/file_download_stub.dart'
    if (dart.library.html) 'utils/file_download_web.dart';

class PreventiveHistoryPage extends StatefulWidget {
  const PreventiveHistoryPage({super.key});

  @override
  State<PreventiveHistoryPage> createState() => _PreventiveHistoryPageState();
}

class _PreventiveHistoryPageState extends State<PreventiveHistoryPage> {
  static const _bg = Color(0xFF10102B);
  static const _surface = Color(0xFF1D1D38);
  static const _surfaceHeader = Color(0xFF131422);
  static const _accent = Color(0xFFFF6E00);
  static const _muted = Color(0xFFA0A0B0);
  static const _ok = Color(0xFF43A047);
  static const _warn2 = Color(0xFFFB8C00);

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  String _machineFilter = 'Toutes';
  String _techFilter = 'Tous';
  String _statusFilter = 'Tous';
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getPreventiveHistory();
      if (!mounted) return;
      setState(() {
        _items = data.map((e) => Map<String, dynamic>.from(e)).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  DateTime? _asDate(dynamic v) {
    if (v is DateTime) return v;
    if (v is String && v.trim().isNotEmpty) return DateTime.tryParse(v.trim());
    return null;
  }

  List<String> _machineOptions() {
    final set = _items.map((e) => (e['machineName'] ?? e['machineId'] ?? '').toString().trim()).where((e) => e.isNotEmpty).toSet().toList()..sort();
    return ['Toutes', ...set];
  }

  List<String> _techOptions() {
    final set = _items.map((e) => (e['technicienNom'] ?? e['rapportControle']?['technicianName'] ?? '').toString().trim()).where((e) => e.isNotEmpty).toSet().toList()..sort();
    return ['Tous', ...set];
  }

  List<Map<String, dynamic>> _filtered() {
    return _items.where((e) {
      final machine = (e['machineName'] ?? e['machineId'] ?? '').toString();
      final tech = (e['technicienNom'] ?? e['rapportControle']?['technicianName'] ?? '').toString();
      final status = (e['statut'] ?? '').toString().toLowerCase();
      final doneDate = _asDate(e['dateRealisation'] ?? e['completedAt'] ?? e['updatedAt']);
      if (_machineFilter != 'Toutes' && machine != _machineFilter) return false;
      if (_techFilter != 'Tous' && tech != _techFilter) return false;
      if (_statusFilter == 'Terminé' && !status.contains('termin')) return false;
      if (_statusFilter == 'Annulé' && !status.contains('annul')) return false;
      if (_fromDate != null && (doneDate == null || doneDate.isBefore(_fromDate!))) return false;
      if (_toDate != null && (doneDate == null || doneDate.isAfter(_toDate!.add(const Duration(days: 1))))) return false;
      return true;
    }).toList()
      ..sort((a, b) {
        final da = _asDate(a['dateRealisation'] ?? a['completedAt'] ?? a['updatedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final db = _asDate(b['dateRealisation'] ?? b['completedAt'] ?? b['updatedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return db.compareTo(da);
      });
  }

  Future<void> _pickFromDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: _fromDate ?? DateTime.now(),
    );
    if (picked == null) return;
    setState(() => _fromDate = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _pickToDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: _toDate ?? DateTime.now(),
    );
    if (picked == null) return;
    setState(() => _toDate = DateTime(picked.year, picked.month, picked.day));
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered();
    final df = DateFormat('dd/MM/yyyy HH:mm');
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surfaceHeader,
        title: Text('Historique préventif global', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, style: GoogleFonts.inter(color: Colors.white), textAlign: TextAlign.center),
                        const SizedBox(height: 10),
                        FilledButton(onPressed: _load, child: const Text('Réessayer')),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _isExporting ? null : () => _exportCsv(filtered),
                          icon: const Icon(Icons.table_view),
                          label: const Text('Exporter CSV'),
                        ),
                        ElevatedButton.icon(
                          onPressed: _isExporting ? null : () => _exportPdf(filtered),
                          icon: const Icon(Icons.picture_as_pdf),
                          label: const Text('Exporter PDF'),
                        ),
                        if (_isExporting)
                          const Padding(
                            padding: EdgeInsets.only(left: 8, top: 10),
                            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: Wrap(
                        runSpacing: 10,
                        spacing: 10,
                        children: [
                          SizedBox(
                            width: 260,
                            child: DropdownButtonFormField<String>(
                              value: _machineOptions().contains(_machineFilter) ? _machineFilter : 'Toutes',
                              items: _machineOptions().map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                              onChanged: (v) => setState(() => _machineFilter = v ?? 'Toutes'),
                              decoration: const InputDecoration(labelText: 'Machine', border: OutlineInputBorder()),
                            ),
                          ),
                          SizedBox(
                            width: 260,
                            child: DropdownButtonFormField<String>(
                              value: _techOptions().contains(_techFilter) ? _techFilter : 'Tous',
                              items: _techOptions().map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                              onChanged: (v) => setState(() => _techFilter = v ?? 'Tous'),
                              decoration: const InputDecoration(labelText: 'Technicien', border: OutlineInputBorder()),
                            ),
                          ),
                          SizedBox(
                            width: 260,
                            child: DropdownButtonFormField<String>(
                              value: _statusFilter,
                              items: const [
                                DropdownMenuItem(value: 'Tous', child: Text('Tous statuts')),
                                DropdownMenuItem(value: 'Terminé', child: Text('Terminé (vert)')),
                                DropdownMenuItem(value: 'Annulé', child: Text('Annulé (orange)')),
                              ],
                              onChanged: (v) => setState(() => _statusFilter = v ?? 'Tous'),
                              decoration: const InputDecoration(labelText: 'Statut final', border: OutlineInputBorder()),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _pickFromDate,
                            icon: const Icon(Icons.date_range),
                            label: Text(_fromDate == null ? 'Date début' : DateFormat('dd/MM/yyyy').format(_fromDate!)),
                          ),
                          OutlinedButton.icon(
                            onPressed: _pickToDate,
                            icon: const Icon(Icons.event),
                            label: Text(_toDate == null ? 'Date fin' : DateFormat('dd/MM/yyyy').format(_toDate!)),
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              _fromDate = null;
                              _toDate = null;
                              _statusFilter = 'Tous';
                            }),
                            child: const Text('Réinitialiser période'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('Résultats: ${filtered.length}', style: GoogleFonts.inter(color: _muted)),
                    const SizedBox(height: 10),
                    if (filtered.isEmpty)
                      Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Aucun résultat pour les filtres.', style: GoogleFonts.inter(color: _muted))))
                    else
                      ...filtered.map((e) {
                        final machine = (e['machineName'] ?? e['machineId'] ?? 'Machine').toString();
                        final element = (e['elementControle'] ?? e['typeControle'] ?? '-').toString();
                        final planned = _asDate(e['datePrevue'] ?? e['dateControle']);
                        final done = _asDate(e['dateRealisation'] ?? e['completedAt'] ?? e['updatedAt']);
                        final tech = (e['technicienNom'] ?? e['rapportControle']?['technicianName'] ?? '-').toString();
                        final status = (e['statut'] ?? '-').toString();
                        final notes = (e['notes'] ?? '').toString().trim();
                        final statusColor = _statusColor(status);
                        final statusLabel = _statusLabel(status);
                        return Card(
                          color: _surface,
                          margin: const EdgeInsets.only(bottom: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: statusColor.withOpacity(0.8)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: Text(machine, style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.w700))),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: statusColor.withOpacity(0.18),
                                        borderRadius: BorderRadius.circular(999),
                                        border: Border.all(color: statusColor.withOpacity(0.9)),
                                      ),
                                      child: Text(
                                        statusLabel,
                                        style: GoogleFonts.inter(color: statusColor, fontWeight: FontWeight.w700, fontSize: 11),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text('Élément: $element', style: GoogleFonts.inter(color: Colors.white70)),
                                Text('Technicien: $tech', style: GoogleFonts.inter(color: Colors.white70)),
                                Text('Date prévue: ${planned != null ? df.format(planned) : '-'}', style: GoogleFonts.inter(color: Colors.white70)),
                                Text('Date réalisée: ${done != null ? df.format(done) : '-'}', style: GoogleFonts.inter(color: Colors.white70)),
                                Text('Type maintenance: ${(e['typeMaintenance'] ?? 'preventive').toString()}', style: GoogleFonts.inter(color: Colors.white70)),
                                if (notes.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text('Commentaires: $notes', style: GoogleFonts.inter(color: _muted)),
                                ],
                              ],
                            ),
                          ),
                        );
                      }),
                  ],
                ),
    );
  }

  Future<void> _exportCsv(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) {
      _snack('Aucune donnée à exporter.');
      return;
    }
    setState(() => _isExporting = true);
    try {
      final csv = _buildCsv(rows);
      final bytes = csv.codeUnits;
      final filename = 'historique_preventif_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv';
      if (kIsWeb) {
        downloadBytes(filename: filename, bytes: bytes, mimeType: 'text/csv;charset=utf-8');
      } else {
        _snack('CSV prêt: copiez/partagez le contenu depuis cette session web.');
      }
      _snack('Export CSV généré.');
    } catch (e) {
      _snack('Export CSV impossible: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportPdf(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) {
      _snack('Aucune donnée à exporter.');
      return;
    }
    setState(() => _isExporting = true);
    try {
      final pdf = pw.Document();
      final header = <String>[
        'Machine',
        'Element',
        'Date prevue',
        'Date realisee',
        'Technicien',
        'Statut',
        'Commentaires',
      ];
      final data = rows.map((e) {
        final machine = (e['machineName'] ?? e['machineId'] ?? 'Machine').toString();
        final element = (e['elementControle'] ?? e['typeControle'] ?? '-').toString();
        final planned = _formatDate(_asDate(e['datePrevue'] ?? e['dateControle']));
        final done = _formatDate(_asDate(e['dateRealisation'] ?? e['completedAt'] ?? e['updatedAt']));
        final tech = (e['technicienNom'] ?? e['rapportControle']?['technicianName'] ?? '-').toString();
        final status = (e['statut'] ?? '-').toString();
        final notes = (e['notes'] ?? '').toString().trim();
        return <String>[machine, element, planned, done, tech, status, notes];
      }).toList();

      pdf.addPage(
        pw.MultiPage(
          pageTheme: const pw.PageTheme(margin: pw.EdgeInsets.all(24)),
          build: (context) => [
            pw.Text(
              'Historique maintenance preventive',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Text('Genere le ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}'),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: header,
              data: data,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignment: pw.Alignment.centerLeft,
              columnWidths: const {
                0: pw.FlexColumnWidth(1.4),
                1: pw.FlexColumnWidth(1.2),
                2: pw.FlexColumnWidth(1.1),
                3: pw.FlexColumnWidth(1.1),
                4: pw.FlexColumnWidth(1.2),
                5: pw.FlexColumnWidth(0.9),
                6: pw.FlexColumnWidth(1.6),
              },
            ),
          ],
        ),
      );

      final bytes = await pdf.save();
      final filename = 'historique_preventif_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf';
      await Printing.sharePdf(bytes: bytes, filename: filename);
      _snack('Export PDF généré.');
    } catch (e) {
      _snack('Export PDF impossible: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    return DateFormat('dd/MM/yyyy HH:mm').format(date);
  }

  String _buildCsv(List<Map<String, dynamic>> rows) {
    const headers = [
      'machine',
      'element_controle',
      'date_prevue',
      'date_realisation',
      'technicien',
      'statut',
      'type_maintenance',
      'commentaires'
    ];
    final lines = <String>[];
    lines.add(headers.join(';'));
    for (final e in rows) {
      final machine = (e['machineName'] ?? e['machineId'] ?? 'Machine').toString();
      final element = (e['elementControle'] ?? e['typeControle'] ?? '-').toString();
      final planned = _formatDate(_asDate(e['datePrevue'] ?? e['dateControle']));
      final done = _formatDate(_asDate(e['dateRealisation'] ?? e['completedAt'] ?? e['updatedAt']));
      final tech = (e['technicienNom'] ?? e['rapportControle']?['technicianName'] ?? '-').toString();
      final status = (e['statut'] ?? '-').toString();
      final type = (e['typeMaintenance'] ?? 'preventive').toString();
      final notes = (e['notes'] ?? '').toString();
      final values = [machine, element, planned, done, tech, status, type, notes].map(_csvEscape).join(';');
      lines.add(values);
    }
    return lines.join('\n');
  }

  String _csvEscape(String raw) {
    final safe = raw.replaceAll('"', '""').replaceAll('\n', ' ').replaceAll('\r', ' ');
    return '"$safe"';
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Color _statusColor(String status) {
    final s = status.toLowerCase();
    if (s.contains('termin')) return _ok;
    if (s.contains('annul')) return _warn2;
    return Colors.white70;
  }

  String _statusLabel(String status) {
    final s = status.toLowerCase();
    if (s.contains('termin')) return 'TERMINÉ';
    if (s.contains('annul')) return 'ANNULÉ';
    return status.toUpperCase();
  }
}
