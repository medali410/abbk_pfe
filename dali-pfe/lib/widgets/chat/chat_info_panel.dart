import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'chat_theme.dart';

class ChatInfoPanel extends StatelessWidget {
  final Map<String, dynamic>? selectedContactDetails;
  final VoidCallback onClose;
  final VoidCallback onTogglePin;
  final VoidCallback onBlock;
  final VoidCallback onClearHistory;
  final bool isPinned;
  final bool isBlocked;

  const ChatInfoPanel({
    super.key,
    required this.selectedContactDetails,
    required this.onClose,
    required this.onTogglePin,
    required this.onBlock,
    required this.onClearHistory,
    this.isPinned = false,
    this.isBlocked = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ChatTheme.of(context);
    
    if (selectedContactDetails == null) {
      return Container(
        color: theme.panel,
        child: Center(child: CircularProgressIndicator(color: theme.myBubble)),
      );
    }

    final name = (selectedContactDetails!['name'] ?? 'Contact').toString();
    final role = (selectedContactDetails!['specialite'] ?? selectedContactDetails!['roleLabel'] ?? 'Membre de l\'équipe').toString();
    final machines = selectedContactDetails!['machines'] as List? ?? [];

    final borderDivider = Theme.of(context).brightness == Brightness.dark 
        ? Colors.white.withOpacity(0.05) 
        : const Color(0xFFCD7F32).withOpacity(0.15);

    return Container(
      color: theme.panel,
      child: Column(
        children: [
          // En-tête du panneau
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: borderDivider, width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Détails du contact', style: GoogleFonts.inter(color: theme.text, fontSize: 14, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: Icon(Icons.close, color: theme.muted, size: 20),
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
                    backgroundColor: theme.myBubble.withOpacity(0.2),
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'C', 
                      style: TextStyle(color: theme.myBubble, fontSize: 32, fontWeight: FontWeight.bold)
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Nom et Rôle
                  Text(name, style: GoogleFonts.inter(color: theme.text, fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(role, style: GoogleFonts.inter(color: theme.accent, fontSize: 14, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  
                  // Statut en ligne
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.online.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: theme.online.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: theme.online, shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Text('En ligne', style: GoogleFonts.inter(color: theme.online, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  Divider(color: borderDivider),
                  const SizedBox(height: 24),
                  
                  // Machines Associées
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('MACHINES ASSIGNÉES', style: GoogleFonts.spaceGrotesk(color: theme.muted, fontSize: 11, letterSpacing: 1.2)),
                  ),
                  const SizedBox(height: 16),
                  if (machines.isEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Aucune machine', style: TextStyle(color: theme.muted, fontSize: 13)),
                    )
                  else
                    ...machines.map((m) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: theme.glassDecoration.copyWith(color: theme.bg.withOpacity(0.4)),
                      child: Row(
                        children: [
                          Icon(Icons.precision_manufacturing, color: theme.myBubble, size: 20),
                          const SizedBox(width: 12),
                          Expanded(child: Text(m.toString(), style: GoogleFonts.inter(color: theme.text, fontSize: 13, fontWeight: FontWeight.w500))),
                        ],
                      ),
                    )),
                    
                  const SizedBox(height: 32),
                  
                  // Actions rapides
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('ACTIONS', style: GoogleFonts.spaceGrotesk(color: theme.muted, fontSize: 11, letterSpacing: 1.2)),
                  ),
                  const SizedBox(height: 16),
                  _buildActionButton(isPinned ? Icons.push_pin : Icons.push_pin_outlined, isPinned ? 'Désépingler' : 'Épingler la discussion', theme.text, onTogglePin),
                  _buildActionButton(Icons.delete_outline, 'Effacer l\'historique', theme.roleAdmin, onClearHistory),
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
