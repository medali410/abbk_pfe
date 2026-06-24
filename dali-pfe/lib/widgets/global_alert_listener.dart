import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/global_notification_service.dart';
import '../services/api_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../main.dart'; // import globalNavigatorKey

class GlobalAlertListener extends StatefulWidget {
  final Widget child;

  const GlobalAlertListener({super.key, required this.child});

  @override
  State<GlobalAlertListener> createState() => _GlobalAlertListenerState();
}

class _GlobalAlertListenerState extends State<GlobalAlertListener> {
  StreamSubscription? _dangerMissionSub;
  StreamSubscription? _panneConfirmedSub;
  StreamSubscription? _dangerAlertAdminSub;
  StreamSubscription? _machineGoodStateSub;

  @override
  void initState() {
    super.initState();
    _dangerMissionSub = GlobalNotificationService().dangerMissionAlertStream.listen(_onDangerMission);
    _panneConfirmedSub = GlobalNotificationService().panneConfirmedAlertStream.listen(_onPanneConfirmed);
    _dangerAlertAdminSub = GlobalNotificationService().dangerAlertAdminStream.listen(_onDangerAlertAdmin);
    _machineGoodStateSub = GlobalNotificationService().machineGoodStateStream.listen(_onMachineGoodState);
  }

  @override
  void dispose() {
    _dangerMissionSub?.cancel();
    _panneConfirmedSub?.cancel();
    _dangerAlertAdminSub?.cancel();
    _machineGoodStateSub?.cancel();
    super.dispose();
  }

  // ─── TECHNICIEN : Mission Danger ──────────────────────────────────────────

  void _onDangerMission(Map<String, dynamic> data) {
    final currentTech = ApiService.savedTechnicianProfile;
    final mission = data['mission'];
    if (currentTech == null || mission == null) return;
    if (mission['technicianId'] != currentTech['technicianId']) return;

    final machineName = data['machineName'] ?? 'Machine';
    final aiReport = data['aiReport'] as Map<String, dynamic>? ?? {};

    HapticFeedback.heavyImpact();
    final overlay = globalNavigatorKey.currentState?.overlay;
    if (overlay == null) return;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: 50,
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.shade900.withOpacity(0.97),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.redAccent, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.redAccent.withOpacity(0.5),
                  blurRadius: 20,
                  spreadRadius: 2,
                )
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.smart_toy, color: Colors.white, size: 36),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "🚨 MISSION DANGER",
                        style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        "Arrêt urgence automatique sur $machineName",
                        style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.red.shade900,
                  ),
                  onPressed: () {
                    entry.remove();
                    // Ouvrir directement la modale IA
                    _showDangerMissionModal(mission, machineName, aiReport);
                  },
                  child: const Text("AFFICHER", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => entry.remove(),
                )
              ],
            ),
          ),
        ),
      ),
    );

    overlay.insert(entry);

    // ⚡ Afficher aussi automatiquement la modale IA après 1 seconde
    Future.delayed(const Duration(seconds: 1), () {
      if (entry.mounted) entry.remove();
      _showDangerMissionModal(mission, machineName, aiReport);
    });
  }

  // ─── CONCEPTEUR : Panne Confirmée ─────────────────────────────────────────

  void _onPanneConfirmed(Map<String, dynamic> data) {
    final machineName = data['machineName'] ?? 'Machine';
    final techName = data['techName'] ?? 'Un technicien';

    // Filtrer : seulement le concepteur concerné
    final currentConcepteur = ApiService.savedConcepteurProfile;
    final targetConcepteurId = data['concepteurId'];
    if (currentConcepteur != null && targetConcepteurId != null) {
      final myConcepteurId = currentConcepteur['concepteurId'] ?? currentConcepteur['id']?.toString();
      if (myConcepteurId != null && myConcepteurId != targetConcepteurId) return;
    }

    HapticFeedback.heavyImpact();
    _showBannerToast(
      icon: Icons.crisis_alert,
      iconColor: Colors.red,
      backgroundColor: Colors.black87,
      borderColor: Colors.red,
      title: "🚨 PANNE CONFIRMÉE",
      subtitle: "sur $machineName par $techName — Rendez-vous dans Missions",
      buttonLabel: "VOIR MISSIONS",
      duration: 10,
      onAction: () {
        if (globalNavigatorKey.currentContext != null) {
          Navigator.of(globalNavigatorKey.currentContext!).pushNamed('/concepteur-dashboard');
        }
      },
    );
  }

  // ─── ADMIN / MAINTENANCE / CLIENT : Danger Alert ──────────────────────────

  void _onDangerAlertAdmin(Map<String, dynamic> data) {
    // Ne pas afficher si c'est un technicien (il a déjà la modale)
    if (ApiService.savedTechnicianProfile != null) return;

    final machineName = data['machineName'] ?? 'Machine';
    final reason = data['reason'] ?? 'Anomalie critique';

    HapticFeedback.mediumImpact();
    _showBannerToast(
      icon: Icons.warning_rounded,
      iconColor: Colors.orange,
      backgroundColor: const Color(0xFF1A0000),
      borderColor: Colors.deepOrange,
      title: "⚠️ DANGER DÉTECTÉ",
      subtitle: "$machineName — $reason — Arrêt automatique déclenché",
      buttonLabel: "VOIR",
      duration: 8,
      onAction: null,
    );
  }

  // ─── TOUS : Machine en bon état ───────────────────────────────────────────

  void _onMachineGoodState(Map<String, dynamic> data) {
    final machineName = data['machineName'] ?? 'Machine';

    _showBannerToast(
      icon: Icons.check_circle,
      iconColor: Colors.greenAccent,
      backgroundColor: const Color(0xFF002200),
      borderColor: Colors.green,
      title: "✅ MACHINE EN BON ÉTAT",
      subtitle: "$machineName — Danger résolu. Peut être relancée.",
      buttonLabel: "OK",
      duration: 8,
      onAction: null,
    );
  }

  // ─── Helper : toast banner ────────────────────────────────────────────────

  void _showBannerToast({
    required IconData icon,
    required Color iconColor,
    required Color backgroundColor,
    required Color borderColor,
    required String title,
    required String subtitle,
    required String buttonLabel,
    required int duration,
    VoidCallback? onAction,
  }) {
    final overlay = globalNavigatorKey.currentState?.overlay;
    if (overlay == null) return;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: 50,
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: backgroundColor.withOpacity(0.97),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 2),
              boxShadow: [
                BoxShadow(color: borderColor.withOpacity(0.4), blurRadius: 20, spreadRadius: 2)
              ],
            ),
            child: Row(
              children: [
                Icon(icon, color: iconColor, size: 36),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(subtitle, style: GoogleFonts.inter(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
                if (onAction != null)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: borderColor, foregroundColor: Colors.white),
                    onPressed: () { entry.remove(); onAction(); },
                    child: Text(buttonLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                  onPressed: () => entry.remove(),
                )
              ],
            ),
          ),
        ),
      ),
    );

    overlay.insert(entry);
    Future.delayed(Duration(seconds: duration), () {
      if (entry.mounted) entry.remove();
    });
  }

  // ─── Modale IA Danger ─────────────────────────────────────────────────────

  void _showDangerMissionModal(Map<String, dynamic> mission, String machineName, Map<String, dynamic> aiReport) {
    final dialogContext = globalNavigatorKey.currentContext;
    if (dialogContext == null) return;

    showDialog(
      context: dialogContext,
      barrierDismissible: false,
      builder: (context) {
        bool isLoading = false;

        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 500),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2E).withOpacity(0.97),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.6), width: 1.5),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 20, spreadRadius: 5)
                  ],
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Row(
                      children: [
                        const Icon(Icons.smart_toy, color: Colors.redAccent, size: 28),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "RAPPORT IA : DANGER IMMINENT",
                            style: GoogleFonts.inter(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 17),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
                          onPressed: () => Navigator.pop(context),
                        )
                      ],
                    ),
                    const Divider(color: Colors.white24, height: 28),

                    // Informations IA
                    _buildAiInfoRow("Machine", machineName, Icons.precision_manufacturing),
                    _buildAiInfoRow("Diagnostic", aiReport['diagnostic'] ?? 'En cours…', Icons.analytics),
                    _buildAiInfoRow("Risque Global", "${aiReport['risk_percentage'] ?? '--'}%", Icons.warning_amber),
                    _buildAiInfoRow("Temps estimé", "${aiReport['details']?['rul_cycles'] ?? 'N/A'} min/cycles", Icons.timer),

                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Recommandations IA",
                              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text(
                            aiReport['recommandation'] ?? 'Intervention immédiate requise.',
                            style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Boutons action
                    if (isLoading)
                      const CircularProgressIndicator(color: Colors.redAccent)
                    else
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // TERMINER — Danger résolu
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade700,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.check_circle),
                              label: const Text("TERMINER\n(Danger résolu)", textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
                              onPressed: () async {
                                setState(() => isLoading = true);
                                try {
                                  await http.post(
                                    Uri.parse('${ApiService.baseUrl}/missions/me/${mission['id']}/danger/resolve'),
                                    headers: await ApiService.jsonHeadersAuthorized(),
                                  );
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                    // Toast succès
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Row(
                                          children: [
                                            const Icon(Icons.check_circle, color: Colors.white),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                "✅ Danger annulé ! La machine peut être remise en marche.",
                                                style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white),
                                              ),
                                            ),
                                          ],
                                        ),
                                        backgroundColor: Colors.green.shade700,
                                        behavior: SnackBarBehavior.floating,
                                        margin: const EdgeInsets.all(20),
                                        duration: const Duration(seconds: 6),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  debugPrint('Erreur resolve: $e');
                                }
                                setState(() => isLoading = false);
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          // PANNE CONFIRMÉE
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade900,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.crisis_alert),
                              label: const Text("PANNE\nCONFIRMÉE", textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
                              onPressed: () async {
                                setState(() => isLoading = true);
                                try {
                                  await http.post(
                                    Uri.parse('${ApiService.baseUrl}/missions/me/${mission['id']}/danger/confirm'),
                                    headers: await ApiService.jsonHeadersAuthorized(),
                                  );
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          "🔧 Panne signalée. Le concepteur a été notifié pour vous guider.",
                                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white),
                                        ),
                                        backgroundColor: Colors.orange.shade800,
                                        behavior: SnackBarBehavior.floating,
                                        margin: const EdgeInsets.all(20),
                                        duration: const Duration(seconds: 6),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  debugPrint('Erreur confirm panne: $e');
                                }
                                setState(() => isLoading = false);
                              },
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAiInfoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white54, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                children: [
                  TextSpan(text: "$label : ", style: const TextStyle(color: Colors.white54)),
                  TextSpan(text: value, style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
