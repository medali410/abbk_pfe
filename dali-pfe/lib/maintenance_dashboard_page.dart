import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'machine_detail_ai_page.dart';
import 'services/api_service.dart';

class MaintenanceDashboardPage extends StatefulWidget {
  const MaintenanceDashboardPage({super.key});

  @override
  State<MaintenanceDashboardPage> createState() => _MaintenanceDashboardPageState();
}

class _MaintenanceDashboardPageState extends State<MaintenanceDashboardPage> {
  late Future<Map<String, dynamic>> _future;
  String _levelFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _future = ApiService.getMaintenanceWorkspace();
  }

  void _reload() => setState(() => _future = ApiService.getMaintenanceWorkspace());

  Future<void> _showTakeControlDialog(Map<String, dynamic> machine) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Prendre en charge ${(machine['machineName'] ?? machine['machineId']).toString()}',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Cette action informe le client que la maintenance commence le contrôle du moteur.',
              style: GoogleFonts.inter(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.engineering_rounded, size: 16),
            label: const Text('Confirmer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService.startMaintenanceControl((machine['machineId'] ?? '').toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prise en charge envoyée au client.')),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Prise en charge impossible: $e')),
      );
    }
  }

  Future<void> _finishControl(Map<String, dynamic> machine) async {
    try {
      await ApiService.finishMaintenanceControl((machine['machineId'] ?? '').toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contrôle terminé.')),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fin de contrôle impossible: $e')),
      );
    }
  }

  Future<void> _showCreateCorrectiveDialog(
    Map<String, dynamic> machine,
  ) async {
    final descCtrl = TextEditingController();
    String priority = 'HIGH';
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Corrective — ${(machine['machineName'] ?? machine['machineId']).toString()}',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description panne',
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: priority,
                items: const [
                  DropdownMenuItem(value: 'LOW', child: Text('LOW')),
                  DropdownMenuItem(value: 'MEDIUM', child: Text('MEDIUM')),
                  DropdownMenuItem(value: 'HIGH', child: Text('HIGH')),
                  DropdownMenuItem(value: 'CRITICAL', child: Text('CRITICAL')),
                ],
                onChanged: (v) => priority = v ?? 'HIGH',
                decoration: const InputDecoration(labelText: 'Priorité'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              final desc = descCtrl.text.trim();
              if (desc.isEmpty) return;
              try {
                final payload = <String, dynamic>{
                  'machineId': (machine['machineId'] ?? '').toString(),
                  'companyId': (machine['companyId'] ?? '').toString(),
                  'description': desc,
                  'priority': priority,
                  'type': 'CORRECTIVE',
                };
                await ApiService.createMaintenanceOrder(payload);
                if (!mounted) return;
                Navigator.pop(ctx, true);
              } catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('Création impossible: $e')),
                );
              }
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maintenance corrective créée.')),
      );
    }
  }

  Color _levelColor(String level) {
    switch (level.toUpperCase()) {
      case 'DANGER':
        return const Color(0xFFFF8A80);
      case 'RISQUE':
        return const Color(0xFFFFB74D);
      default:
        return const Color(0xFF81C784);
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF10102B);
    const surface = Color(0xFF1D1D38);
    const text = Color(0xFFE2DFFF);
    const muted = Color(0xFFE2BFB0);
    const accent = Color(0xFFFF6E00);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text('Dashboard Maintenance', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        backgroundColor: bg,
        foregroundColor: text,
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh_rounded)),
          IconButton(
            onPressed: () async {
              await ApiService.clearAuth();
              if (!mounted) return;
              Navigator.pushReplacementNamed(context, '/');
            },
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: accent));
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${snap.error}', style: GoogleFonts.inter(color: muted), textAlign: TextAlign.center),
                    const SizedBox(height: 10),
                    TextButton(onPressed: _reload, child: const Text('Réessayer')),
                  ],
                ),
              ),
            );
          }
          final data = snap.data ?? const <String, dynamic>{};
          final agent = (data['agent'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
          final rows = (data['machines'] as List? ?? const [])
              .map((e) => (e as Map).cast<String, dynamic>())
              .toList();
          final normalCount = rows.where((m) => (m['level'] ?? '').toString().toUpperCase() == 'NORMAL').length;
          final riskCount = rows.where((m) => (m['level'] ?? '').toString().toUpperCase() == 'RISQUE').length;
          final dangerCount = rows.where((m) => (m['level'] ?? '').toString().toUpperCase() == 'DANGER').length;
          final filteredRows = rows.where((m) {
            final level = (m['level'] ?? '').toString().toUpperCase();
            return _levelFilter == 'ALL' || level == _levelFilter;
          }).toList();

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.badge_outlined, color: accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Agent: ${(agent['fullName'] ?? '').toString()}'
                        ' · ${(agent['email'] ?? '').toString()}',
                        style: GoogleFonts.inter(color: text, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: Text('Tous (${rows.length})', style: GoogleFonts.inter(fontSize: 12)),
                    selected: _levelFilter == 'ALL',
                    onSelected: (_) => setState(() => _levelFilter = 'ALL'),
                  ),
                  ChoiceChip(
                    label: Text('Normal ($normalCount)', style: GoogleFonts.inter(fontSize: 12)),
                    selected: _levelFilter == 'NORMAL',
                    onSelected: (_) => setState(() => _levelFilter = 'NORMAL'),
                  ),
                  ChoiceChip(
                    label: Text('Risque ($riskCount)', style: GoogleFonts.inter(fontSize: 12)),
                    selected: _levelFilter == 'RISQUE',
                    onSelected: (_) => setState(() => _levelFilter = 'RISQUE'),
                  ),
                  ChoiceChip(
                    label: Text('Danger ($dangerCount)', style: GoogleFonts.inter(fontSize: 12)),
                    selected: _levelFilter == 'DANGER',
                    onSelected: (_) => setState(() => _levelFilter = 'DANGER'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (filteredRows.isEmpty)
                Text(
                  rows.isEmpty
                      ? 'Aucune machine assignée à ce compte maintenance.'
                      : 'Aucune machine pour ce filtre.',
                  style: GoogleFonts.inter(color: muted),
                ),
              ...filteredRows.map((m) {
                final level = (m['level'] ?? 'NORMAL').toString().toUpperCase();
                final prob = (m['probPanne'] ?? 0).toString();
                final machineId = (m['machineId'] ?? '').toString();
                final machineName = (m['machineName'] ?? machineId).toString();
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _levelColor(level).withOpacity(0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              machineName,
                              style: GoogleFonts.inter(color: text, fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _levelColor(level).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              level,
                              style: GoogleFonts.spaceGrotesk(
                                color: _levelColor(level),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Probabilité panne: $prob% · ID: $machineId',
                        style: GoogleFonts.spaceGrotesk(color: muted, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        (m['recommendation'] ?? '').toString(),
                        style: GoogleFonts.inter(color: _levelColor(level), fontSize: 12),
                      ),
                      if ((m['maintenanceControlActive'] == true)) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Contrôle en cours par ${(m['maintenanceControlBy'] ?? 'Maintenance').toString()}',
                          style: GoogleFonts.inter(color: const Color(0xFF81C784), fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          spacing: 8,
                          children: [
                            if ((m['maintenanceControlActive'] == true))
                              OutlinedButton.icon(
                                onPressed: () => _finishControl(m),
                                icon: const Icon(Icons.task_alt_rounded, size: 16),
                                label: const Text('Terminer contrôle'),
                              )
                            else
                              ElevatedButton.icon(
                                onPressed: () => _showTakeControlDialog(m),
                                icon: const Icon(Icons.engineering_rounded, size: 16),
                                label: const Text('Prendre en charge'),
                              ),
                            ElevatedButton.icon(
                              onPressed: () => _showCreateCorrectiveDialog(m),
                              icon: const Icon(Icons.add_task_rounded, size: 16),
                              label: const Text('Créer corrective'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => MachineDetailPage(
                                      machineId: machineId,
                                      machineName: machineName,
                                      viewerRole: 'maintenance',
                                      viewerName: (agent['fullName'] ?? '').toString(),
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.open_in_new_rounded, size: 16),
                              label: const Text('Voir machine'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

