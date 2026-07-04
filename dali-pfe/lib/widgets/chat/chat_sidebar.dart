import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'chat_theme.dart';

class ChatSidebar extends StatelessWidget {
  final List<Map<String, dynamic>> conversations;
  final String activeRoomId;
  final Function(String, Map<String, dynamic>) onSelectConversation;
  final TextEditingController searchController;
  final bool isSearching;
  final Function(String) onSearchChanged;
  final VoidCallback onClearSearch;

  const ChatSidebar({
    super.key,
    required this.conversations,
    required this.activeRoomId,
    required this.onSelectConversation,
    required this.searchController,
    required this.isSearching,
    required this.onSearchChanged,
    required this.onClearSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: ChatTheme.sidebar,
      child: Column(
        children: [
          // En-tête
          Container(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Messages', style: ChatTheme.titleStyle),
                    const SizedBox(height: 4),
                    Text('${conversations.where((c) => c['isSectionHeader'] != true).length} conversations', style: ChatTheme.subtitleStyle),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_square, color: ChatTheme.text, size: 20),
                      onPressed: () {},
                      tooltip: 'Nouveau message',
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings_outlined, color: ChatTheme.muted, size: 20),
                      onPressed: () {},
                      tooltip: 'Paramètres',
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Barre de recherche
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Container(
              height: 40,
              decoration: ChatTheme.inputDecoration,
              child: TextField(
                controller: searchController,
                onChanged: onSearchChanged,
                style: const TextStyle(color: ChatTheme.text, fontSize: 14),
                decoration: InputDecoration(
                  hintText: '🔍 Rechercher un contact...',
                  hintStyle: TextStyle(color: ChatTheme.muted.withOpacity(0.6), fontSize: 13),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  suffixIcon: isSearching 
                    ? IconButton(
                        icon: const Icon(Icons.close, color: ChatTheme.muted, size: 16),
                        onPressed: onClearSearch,
                      )
                    : null,
                ),
              ),
            ),
          ),
          
          // Chips de filtre (UI uniquement pour l'instant)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('Tous', true),
                  _buildFilterChip('Non lus', false),
                  _buildFilterChip('Techniciens', false),
                  _buildFilterChip('Clients', false),
                ],
              ),
            ),
          ),

          const Divider(color: Colors.white10, height: 1),

          // Liste des contacts
          Expanded(
            child: ListView.builder(
              itemCount: conversations.length,
              itemBuilder: (context, index) {
                final c = conversations[index];
                if (c['isSectionHeader'] == true) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                    child: Row(
                      children: [
                        Icon(_getIconForSection(c['sectionIcon']), size: 14, color: _getColorForSection(c['sectionColor'])),
                        const SizedBox(width: 8),
                        Text(
                          (c['sectionLabel'] ?? '').toString().toUpperCase(),
                          style: GoogleFonts.inter(color: _getColorForSection(c['sectionColor']), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                        ),
                      ],
                    ),
                  );
                }

                final active = c['roomId'] == activeRoomId;
                final name = c['name'] ?? 'Contact';
                final lastText = c['lastText'] ?? 'Ouvrir la discussion';
                final time = c['lastAt'] != null ? _formatTime(c['lastAt']) : '';
                final unread = (c['unreadCount'] ?? 0) as int;
                final role = (c['roleLabel'] ?? '').toString();

                return InkWell(
                  onTap: () => onSelectConversation(c['roomId'], c),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    color: active ? ChatTheme.activeItem : Colors.transparent,
                    child: Row(
                      children: [
                        // Avatar avec statut
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: ChatTheme.myBubble.withOpacity(0.2),
                              child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'C', style: const TextStyle(color: ChatTheme.myBubble, fontWeight: FontWeight.bold)),
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: ChatTheme.online,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: ChatTheme.sidebar, width: 2),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        
                        // Infos du contact
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(name, style: ChatTheme.nameStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ),
                                  if (time.isNotEmpty)
                                    Text(time, style: ChatTheme.timeStyle),
                                ],
                              ),
                              const SizedBox(height: 2),
                              if (role.isNotEmpty)
                                Text(role, style: GoogleFonts.inter(color: ChatTheme.accent, fontSize: 10, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      lastText,
                                      style: GoogleFonts.inter(color: unread > 0 ? ChatTheme.text : ChatTheme.muted, fontSize: 13, fontStyle: unread > 0 ? FontStyle.normal : FontStyle.italic),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (unread > 0)
                                    Container(
                                      margin: const EdgeInsets.only(left: 8),
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: ChatTheme.unread, borderRadius: BorderRadius.circular(10)),
                                      child: Text(unread.toString(), style: GoogleFonts.inter(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected ? ChatTheme.myBubble : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isSelected ? ChatTheme.myBubble : Colors.white.withOpacity(0.1)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : ChatTheme.muted,
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }

  IconData _getIconForSection(String? name) {
    switch (name) {
      case 'groups': return Icons.groups;
      case 'engineering': return Icons.engineering;
      case 'support_agent': return Icons.support_agent;
      default: return Icons.person;
    }
  }

  Color _getColorForSection(String? name) {
    switch (name) {
      case 'green': return ChatTheme.roleClient;
      case 'purple': return ChatTheme.roleConcepteur;
      case 'blue': return ChatTheme.roleTechnicien;
      case 'orange': return ChatTheme.roleMaintenance;
      default: return ChatTheme.muted;
    }
  }

  String _formatTime(String isoTime) {
    try {
      final dt = DateTime.parse(isoTime).toLocal();
      final now = DateTime.now();
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}
