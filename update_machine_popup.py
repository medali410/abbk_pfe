import os

filepath = r"C:\Users\ASUS\Documents\abbk_pfe\dali-pfe\lib\concepteur_dashboard_page.dart"
with open(filepath, "r", encoding="utf-8") as f:
    content = f.read()

# Add the _showMachineMiniDetails function right before _openMachineDetail
mini_detail_func = """
  void _showMachineMiniDetails(BuildContext context, Map<String, dynamic> m) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E2030),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.precision_manufacturing, color: primaryColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _machineNameOf(m),
                  style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: FutureBuilder<Map<String, dynamic>?>(
            future: ApiService.getLatestTelemetry(_machineIdOf(m)).catchError((_) => null),
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 100,
                  child: Center(child: CircularProgressIndicator(color: primaryColor)),
                );
              }
              final data = snap.data;
              final status = (m['status'] ?? 'Inconnu').toString().toUpperCase();
              final isRunning = status == 'RUNNING';
              
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(isRunning ? Icons.play_circle_fill : Icons.stop_circle, 
                           color: isRunning ? const Color(0xFF66BB6A) : const Color(0xFFFFB4AB), size: 16),
                      const SizedBox(width: 8),
                      Text('État : $status', style: GoogleFonts.inter(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (data != null) ...[
                    _miniStatRow('Température', '${data['temperature'] ?? '--'} °C', Icons.thermostat),
                    const SizedBox(height: 8),
                    _miniStatRow('Pression', '${data['pressure'] ?? '--'} bar', Icons.speed),
                    const SizedBox(height: 8),
                    _miniStatRow('Vibration', '${data['vibration'] ?? '--'} mm/s', Icons.waves),
                    const SizedBox(height: 8),
                    _miniStatRow('RPM', '${data['rpm'] ?? '--'} tr/min', Icons.rotate_right),
                    const SizedBox(height: 8),
                    _miniStatRow('Risque panne', '${data['prob_panne'] ?? data['panne_probability'] ?? '--'} %', Icons.warning_amber),
                  ] else
                    Text('Aucune donnée de télémétrie récente.', 
                         style: GoogleFonts.inter(color: Colors.white30, fontSize: 13, fontStyle: FontStyle.italic)),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Fermer', style: GoogleFonts.inter(color: mutedTextColor)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _openMachineDetail(m);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.black,
              ),
              child: Text('Ouvrir détails', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _miniStatRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: primaryColor.withOpacity(0.8), size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: GoogleFonts.inter(color: mutedTextColor, fontSize: 12))),
        Text(value, style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }
"""

if "_showMachineMiniDetails" not in content:
    content = content.replace("  void _openMachineDetail(Map<String, dynamic> m) {", mini_detail_func + "\n  void _openMachineDetail(Map<String, dynamic> m) {")

target_text = """                          if (techM.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Machines ajoutées: ${techM.map((m) => _machineNameOf(m)).join(', ')}',
                              style: GoogleFonts.inter(
                                color: primaryColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],"""

replacement_text = """                          if (techM.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: techM.map((m) {
                                return InkWell(
                                  onTap: () => _showMachineMiniDetails(context, m),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: primaryColor.withOpacity(0.1),
                                      border: Border.all(color: primaryColor.withOpacity(0.3)),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.precision_manufacturing, size: 12, color: primaryColor),
                                        const SizedBox(width: 4),
                                        Text(
                                          _machineNameOf(m),
                                          style: GoogleFonts.inter(color: primaryColor, fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],"""

# The previous script might have used a slightly different encoding or formatting. Let's handle whitespace dynamically or use regex.
import re
pattern = r"if\s*\(techM\.isNotEmpty\)\s*\.\.\.\[\s*const\s*SizedBox\(height:\s*4\),\s*Text\(\s*'Machines ajoutées:\s*\$\{techM\.map[^}]+\}\)',\s*style:\s*GoogleFonts\.inter\(\s*color:\s*primaryColor,\s*fontSize:\s*11,\s*fontWeight:\s*FontWeight\.w500,\s*\),\s*\),\s*\]"

if re.search(pattern, content):
    content = re.sub(pattern, replacement_text, content)
    with open(filepath, "w", encoding="utf-8") as f:
        f.write(content)
    print("Replacement successful.")
else:
    print("Target not found. Try finding with different pattern.")

