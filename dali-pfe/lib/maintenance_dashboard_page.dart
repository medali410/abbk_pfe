import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'maintenance_ai_analysis_content.dart';
import 'maintenance_ai_chat_page.dart';
import 'maintenance_home_dashboard_content.dart';
import 'maintenance_machine_hub_page.dart';
import 'maintenance_mission_history_content.dart';
import 'maintenance_profile_page.dart';
import 'services/api_service.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'machine_detail_ai_page.dart';

class MaintenanceDashboardPage extends StatefulWidget {
  const MaintenanceDashboardPage({super.key});

  @override
  State<MaintenanceDashboardPage> createState() =>
      _MaintenanceDashboardPageState();
}

class _MaintenanceDashboardPageState extends State<MaintenanceDashboardPage> {
  late Future<Map<String, dynamic>> _future;
  IO.Socket? _socket;
  final Map<String, DateTime> _lastToastTime = {};
  final Map<String, String> _machineLiveStates = {};

  /// Vue shell : `dashboard` · `profile` · `machineDetail` · `missionHistory` · `aiAnalysis` (défaut : dashboard).
  String _shellNav = 'dashboard';

  /// Incrémenté à chaque `_reload()` pour rafraîchir l’historique des missions.
  int _workspaceReloadNonce = 0;

  @override
  void initState() {
    super.initState();
    _future = ApiService.getMaintenanceWorkspace();
    _initSocket();
  }

  void _initSocket() {
    try {
      _socket = IO.io(ApiService.socketBaseUrl, <String, dynamic>{
        'transports': <String>['websocket'],
        'autoConnect': true,
      });

      _socket!.onConnect((_) => debugPrint('[Dashboard] Socket Connected'));

      _future.then((data) {
        if (!mounted) return;
        final machines = data['machines'] as List? ?? [];
        for (final m in machines) {
          if (m is Map) {
            final mId = (m['machineId'] ?? m['id'] ?? m['_id'] ?? '').toString();
            final mName = (m['machineName'] ?? m['name'] ?? mId).toString();
            void handleAiEvent(payload) {
              if (!mounted) return;
              final p = payload is Map ? Map<String, dynamic>.from(payload) : <String, dynamic>{};
              final sourceData = p.containsKey('metrics') && p['metrics'] is Map ? p['metrics'] as Map : p;
              
              double? getDouble(String k1, [String? k2, String? k3]) {
                final val = sourceData[k1] ?? (k2 != null ? sourceData[k2] : null) ?? (k3 != null ? sourceData[k3] : null);
                if (val == null) return null;
                if (val is num) return val.toDouble();
                return double.tryParse(val.toString());
              }

              final thermal = getDouble('thermal', 'temperature', 'temperature_contact') ?? getDouble('temp');
              final vibration = getDouble('vibration', 'vibration_x', 'vibration_y');
              
              bool isDanger = false;
              String dangerType = '';
              
              if (thermal != null && thermal >= 75) {
                isDanger = true;
                dangerType = 'Température critique (${thermal.toStringAsFixed(1)} °C)';
              } else if (vibration != null && vibration >= 12) {
                isDanger = true;
                dangerType = 'Forte vibration (${vibration.toStringAsFixed(1)} mm/s)';
              }
              
              final probPanne = getDouble('prob_panne') ?? getDouble('scenarioProbPanne');
              if (probPanne != null && probPanne >= 70) {
                isDanger = true;
                if (dangerType.isEmpty) dangerType = 'Risque de panne élevé IA';
              }
              
              String newState = 'NORMAL';
              if (isDanger) {
                newState = 'DANGER';
              } else if ((thermal != null && thermal > 55) || (vibration != null && vibration > 7)) {
                newState = 'WARNING';
              }
              
              if (_machineLiveStates[mId] != newState) {
                setState(() {
                  _machineLiveStates[mId] = newState;
                });
              }
              
              if (isDanger) {
                final now = DateTime.now();
                final last = _lastToastTime[mId];
                // Throttle to 1 toast every 2 minutes per machine
                if (last == null || now.difference(last).inMinutes >= 2) {
                  _lastToastTime[mId] = now;
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: const Color(0xFFF44336),
                      content: Row(
                        children: [
                          const Icon(Icons.warning_rounded, color: Colors.white),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'DANGER SUR $mName : $dangerType',
                              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      action: SnackBarAction(
                        label: 'AFFICHER',
                        textColor: Colors.white,
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MachineDetailAiPage(
                                machineId: mId,
                                machineName: mName,
                              ),
                            ),
                          );
                        },
                      ),
                      duration: const Duration(seconds: 10),
                    ),
                  );
                }
              }
            }

            if (mId.isNotEmpty) {
              _socket!.on('ai:$mId', handleAiEvent);
            }
            if (mName.isNotEmpty && mName != mId) {
              _socket!.on('ai:$mName', handleAiEvent);
            }
          }
        }
      });

      _socket!.on('diagnostic_coordination_update', (data) {
        if (mounted) {
          final status = (data['status'] ?? '').toString().toUpperCase().trim();
          final interventionId = (data['interventionId'] ?? '').toString();

          if (status == 'CONFIRMED') {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Le technicien a confirmé la mission (intervention $interventionId). Données enregistrées.',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
                backgroundColor: const Color(0xFFFF6E00),
                duration: const Duration(seconds: 6),
              ),
            );
          } else if (status == 'COMPLETED') {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Le technicien a terminé la mission (intervention $interventionId). Statut enregistré en base.',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
                backgroundColor: const Color(0xFF2E7D32),
                duration: const Duration(seconds: 6),
              ),
            );
            _showMissionCompletedDialog(interventionId);
          }
          _reload();
        }
      });

      _socket!.on('diagnostic_message_update', (data) {
        if (mounted) {
          final status = (data['status'] ?? '').toString().toUpperCase().trim();
          final interventionId = (data['interventionId'] ?? '').toString();
          if (status == 'CONFIRMED') {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Le technicien a confirmé la consigne / message (intervention $interventionId).',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
                backgroundColor: const Color(0xFFFF6E00),
                duration: const Duration(seconds: 5),
              ),
            );
          } else if (status == 'COMPLETED') {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Le technicien a terminé la consigne (intervention $interventionId). Statut enregistré.',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
                backgroundColor: const Color(0xFF2E7D32),
                duration: const Duration(seconds: 6),
              ),
            );
            _showMissionCompletedDialog(interventionId);
          }
          _reload();
        }
      });

      _socket!.on('diagnostic_message', (data) {
        if (mounted) {
          final msg = data['message'];
          final author = (msg['authorName'] ?? 'Technicien').toString();

          // Ne pas afficher si c'est nous (MAINTENANCE_AGENT) qui avons envoyé?
          // En fait, c'est bien de voir la confirmation.

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("MESSAGE DE $author : ${msg['content']}"),
              backgroundColor: const Color(0xFF327AFF),
              action: SnackBarAction(
                label: 'VOIR',
                textColor: Colors.white,
                onPressed: () {
                  // Optionnel: ouvrir une vue détaillée
                },
              ),
            ),
          );
          _reload();
        }
      });

      _socket!.on('diagnostic_coordination', (data) {
        if (mounted) {
          final note = data['note'];
          if (note['isMission'] == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("NOUVELLE MISSION ENVOYÉE : ${note['content']}"),
                backgroundColor: Colors.purpleAccent,
              ),
            );
          }
          _reload();
        }
      });
    } catch (e) {
      debugPrint('Dashboard Socket Error: $e');
    }
  }

  @override
  void dispose() {
    _socket?.dispose();
    super.dispose();
  }

  void _reload() => setState(() {
    _future = ApiService.getMaintenanceWorkspace();
    _workspaceReloadNonce++;
  });

  Future<void> _showMissionDialog(Map<String, dynamic> machine) async {
    final missionCtrl = TextEditingController();
    final interventionId = await _getOrCreateInterventionId(machine);
    if (interventionId == null) return;

    final sent = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(
              'Mission — ${(machine['machineName'] ?? machine['machineId']).toString()}',
              style: GoogleFonts.orbitron(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: const Color(0xFFFF6E00),
              ),
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Cette mission sera envoyée au Mission Control du technicien (messages avec Confirmer puis Terminer).',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.blueGrey,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Modèles rapides',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFFF6E00),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ('Contrôle capteurs', 'control capteur'),
                      ('Relevé thermique', 'relevé thermique et pression capteurs'),
                      ('État machine', 'demande état machine complète'),
                      ('Validation terrain', 'validation terrain : contrôle effectué'),
                    ].map((e) {
                      return ActionChip(
                        label: Text(e.$1, style: GoogleFonts.inter(fontSize: 11)),
                        onPressed: () {
                          missionCtrl.text = e.$2;
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: missionCtrl,
                    maxLines: 3,
                    style: GoogleFonts.inter(fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Détails de la mission',
                      hintText:
                          'ex: control capteur — secteur hydraulique…',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler'),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  final text = missionCtrl.text.trim();
                  if (text.isEmpty) return;
                  try {
                    await ApiService.addCoordinationNote(
                      interventionId,
                      text,
                      isMission: true,
                      authorName: 'MAINTENANCE_AGENT',
                    );
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx, true);
                  } catch (e) {
                    if (!ctx.mounted) return;
                    ScaffoldMessenger.of(
                      ctx,
                    ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
                  }
                },
                icon: const Icon(Icons.send_rounded, size: 16),
                label: const Text('Envoyer au Mission Control'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6E00),
                ),
              ),
            ],
          ),
    );

    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mission transmise avec succès.')),
      );
    }
  }

  Future<String?> _getOrCreateInterventionId(
    Map<String, dynamic> machine,
  ) async {
    try {
      final interventions = await ApiService.getDiagnosticInterventions();
      final mId = (machine['machineId'] ?? '').toString();
      final active = interventions.firstWhere(
        (i) =>
            i['machineId'] == mId &&
            i['status'] != 'DONE' &&
            i['status'] != 'CANCELLED',
        orElse: () => {},
      );

      if (active.isNotEmpty) {
        return active['id'].toString();
      }

      // Si pas d'intervention, on en crée une automatique?
      // Ou on demande à l'utilisateur. Pour l'instant, créons-en une basique.
      final newInt = await ApiService.createDiagnosticIntervention({
        'machineId': mId,
        'companyId': (machine['companyId'] ?? '').toString(),
        'scenarioType': 'SENSOR_COMM',
        'summary':
            'Mission coordination initiée depuis le Dashboard Maintenance.',
      });
      return newInt['id'].toString();
    } catch (e) {
      debugPrint('Error finding/creating intervention: $e');
      return null;
    }
  }

  Future<void> _showMissionCompletedDialog(String interventionId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: Text(
              'Mission terminée',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                color: Colors.greenAccent,
              ),
            ),
            content: Text(
              'Le technicien a terminé sa mission.\nQue souhaitez-vous faire ?',
              style: GoogleFonts.inter(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _findMachineAndOpenMission(interventionId);
                },
                child: const Text(
                  'Envoyer une nouvelle mission',
                  style: TextStyle(color: Colors.cyanAccent),
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  try {
                    await ApiService.setDiagnosticStatus(
                      interventionId,
                      'DONE',
                    );
                    if (!mounted) return;
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Panne clôturée. Machine remise en service.',
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                    _reload();
                  } catch (e) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text('Clôturer la panne'),
              ),
            ],
          ),
    );
  }

  Future<void> _findMachineAndOpenMission(String interventionId) async {
    try {
      final interventions = await ApiService.getDiagnosticInterventions();
      final inter = interventions.firstWhere(
        (i) => i['id'] == interventionId,
        orElse: () => {},
      );
      if (inter.isNotEmpty) {
        final machineId = inter['machineId'];
        final data = await ApiService.getMaintenanceWorkspace();
        final machines =
            (data['machines'] as List? ?? [])
                .map((e) => e as Map<String, dynamic>)
                .toList();
        final machine = machines.firstWhere(
          (m) => m['machineId'] == machineId,
          orElse: () => {},
        );
        if (machine.isNotEmpty) {
          _showMissionDialog(machine);
        }
      }
    } catch (e) {
      debugPrint('Error re-opening mission dialog: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF10102B);
    const text = Color(0xFFE2DFFF);
    const muted = Color(0xFFE2BFB0);
    const accent = Color(0xFFFF6E00);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text(
          _shellNav == 'dashboard'
              ? 'Tableau de bord'
              : _shellNav == 'machineDetail'
                  ? 'Détail machine'
                  : _shellNav == 'missionHistory'
                      ? 'Historique maintenance'
                      : _shellNav == 'aiAnalysis'
                          ? 'Analyse IA'
                          : 'Profil',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        backgroundColor: bg,
        foregroundColor: text,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MaintenanceTopNav(
            mutedColor: muted,
            accentColor: accent,
            selectedShellId: _shellNav,
            onShellSelect: (id) => setState(() => _shellNav = id),
          ),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: accent),
                  );
                }
                if (snap.hasError) {
                  final err = '${snap.error}';
                  final looksLikeAuth =
                      err.toLowerCase().contains('session') ||
                      err.toLowerCase().contains('reconnectez') ||
                      err.toLowerCase().contains('authentification');
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            err,
                            style: GoogleFonts.inter(color: muted),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 14),
                          if (looksLikeAuth)
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pushReplacementNamed(
                                  '/maintenance-login',
                                );
                              },
                              child: Text(
                                'Connexion maintenance',
                                style: GoogleFonts.inter(
                                  color: accent,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          TextButton(
                            onPressed: _reload,
                            child: const Text('Réessayer'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final data = snap.data ?? const <String, dynamic>{};
                if (_shellNav == 'dashboard') {
                  return MaintenanceHomeDashboardContent(
                    data: data,
                    liveStates: _machineLiveStates,
                    onTabSelect: (id) => setState(() => _shellNav = id),
                    onWorkspaceReload: _reload,
                  );
                }
                if (_shellNav == 'profile') {
                  return MaintenanceProfileContent(
                    data: data,
                    onWorkspaceReload: _reload,
                  );
                }
                if (_shellNav == 'missionHistory') {
                  return MaintenanceMissionHistoryContent(
                    key: ValueKey(_workspaceReloadNonce),
                    data: data,
                    onWorkspaceReload: _reload,
                  );
                }
                if (_shellNav == 'aiAnalysis') {
                  return MaintenanceAiAnalysisContent(
                    data: data,
                    onWorkspaceReload: _reload,
                  );
                }
                return MaintenanceMachineHubContent(data: data);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Barre de navigation horizontale sous l’AppBar (remplace l’ancienne sidebar gauche).
class _MaintenanceTopNav extends StatelessWidget {
  const _MaintenanceTopNav({
    required this.mutedColor,
    required this.accentColor,
    required this.selectedShellId,
    required this.onShellSelect,
  });

  final Color mutedColor;
  final Color accentColor;
  /// `dashboard` · `profile` · `machineDetail` · `missionHistory` · `aiAnalysis`
  final String selectedShellId;
  final ValueChanged<String> onShellSelect;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF131429),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.white.withOpacity(0.08)),
          ),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _MaintenanceTopNavItem(
                icon: Icons.dashboard_outlined,
                label: 'TABLEAU DE BORD',
                selected: selectedShellId == 'dashboard',
                accentColor: accentColor,
                mutedColor: mutedColor,
                onTap: () => onShellSelect('dashboard'),
              ),
              _MaintenanceTopNavItem(
                icon: Icons.person_outline_rounded,
                label: 'PROFIL',
                selected: selectedShellId == 'profile',
                accentColor: accentColor,
                mutedColor: mutedColor,
                onTap: () => onShellSelect('profile'),
              ),


              _MaintenanceTopNavItem(
                icon: Icons.analytics_outlined,
                label: 'ANALYSE IA',
                selected: selectedShellId == 'aiAnalysis',
                accentColor: accentColor,
                mutedColor: mutedColor,
                onTap: () => onShellSelect('aiAnalysis'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MaintenanceTopNavItem extends StatelessWidget {
  const _MaintenanceTopNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.accentColor,
    required this.mutedColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color accentColor;
  final Color mutedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? accentColor : mutedColor.withOpacity(0.65);
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: fg,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
