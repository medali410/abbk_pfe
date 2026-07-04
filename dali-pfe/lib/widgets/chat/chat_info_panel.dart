import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'chat_theme.dart';

class ChatInfoPanel extends StatelessWidget {
  final Map<String, dynamic>? selectedContactDetails;
  final VoidCallback onClose;

  const ChatInfoPanel({
    super.key,
    required this.selectedContactDetails,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedContactDetails == null) {
      return Container(
        color: ChatTheme.panel,
        child: const Center(child: CircularProgressIndicator(color: ChatTheme.myBubble)),
      );
    }

    final name = (selectedContactDetails!['name'] ?? 'Contact').toString();
    final role = (selectedContactDetails!['specialite'] ?? selectedContactDetails!['roleLabel'] ?? 'Membre de l\'équipe').toString();
    final machines = selectedContactDetails!['machines'] as List? ?? [];

    return Container(
      color: ChatTheme.panel,
      child: Column(
        children: [
          // En-tête du panneau
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white10, width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Détails du contact', style: GoogleFonts.inter(color: ChatTheme.text, fontSize: 14, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.close, color: ChatTheme.muted, size: 20),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Grand Avatar
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: ChatTheme.myBubble.withOpacity(0.2),
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'C', 
                      style: const TextStyle(color: ChatTheme.myBubble, fontSize: 32, fontWeight: FontWeight.bold)
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Nom et Rôle
                  Text(name, style: GoogleFonts.inter(color: ChatTheme.text, fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(role, style: GoogleFonts.inter(color: ChatTheme.accent, fontSize: 14, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  
                  // Statut en ligne
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: ChatTheme.online.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: ChatTheme.online.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 8, height: 8, decoration: const BoxDecoration(color: ChatTheme.online, shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Text('En ligne', style: GoogleFonts.inter(color: ChatTheme.online, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 24),
                  
                  // Machines Associées
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('MACHINES ASSIGNÉES', style: GoogleFonts.spaceGrotesk(color: ChatTheme.muted, fontSize: 11, letterSpacing: 1.2)),
                  ),
                  const SizedBox(height: 16),
                  if (machines.isEmpty)
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Aucune machine', style: TextStyle(color: ChatTheme.muted, fontSize: 13)),
                    )
                  else
                    ...machines.map((m) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: ChatTheme.glassDecoration.copyWith(color: ChatTheme.bg.withOpacity(0.4)),
                      child: Row(
                        children: [
                          const Icon(Icons.precision_manufacturing, color: ChatTheme.myBubble, size: 20),
                          const SizedBox(width: 12),
                          Expanded(child: Text(m.toString(), style: GoogleFonts.inter(color: ChatTheme.text, fontSize: 13, fontWeight: FontWeight.w500))),
                        ],
                      ),
                    )),
                    
                  const SizedBox(height: 32),
                  
                  // Actions rapides
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('ACTIONS', style: GoogleFonts.spaceGrotesk(color: ChatTheme.muted, fontSize: 11, letterSpacing: 1.2)),
                  ),
                  const SizedBox(height: 16),
                  _buildActionButton(Icons.push_pin_outlined, 'Épingler la discussion', Colors.white, () {}),
                  _buildActionButton(Icons.notifications_off_outlined, 'Mettre en sourdine', Colors.white, () {}),
                  _buildActionButton(Icons.block_outlined, 'Bloquer le contact', ChatTheme.roleAdmin, () {}),
                  _buildActionButton(Icons.delete_outline, 'Effacer l\'historique', ChatTheme.roleAdmin, () {}),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: [
            Icon(icon, color: color.withOpacity(0.8), size: 20),
            const SizedBox(width: 16),
            Text(label, style: GoogleFonts.inter(color: color, fontSize: 14, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
