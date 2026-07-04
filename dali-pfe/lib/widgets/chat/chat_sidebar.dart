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
  final VoidCallback? onNewDiscussion;
  final bool isDarkMode;

  const ChatSidebar({
    super.key,
    required this.conversations,
    required this.activeRoomId,
    required this.onSelectConversation,
    required this.searchController,
    required this.isSearching,
    required this.onSearchChanged,
    required this.onClearSearch,
    this.onNewDiscussion,
    this.isDarkMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ChatTheme.of(context);
    final _bg = theme.sidebar;
    final _text = theme.text;
    final _muted = theme.muted;
    final _active = theme.activeItem;
    final _border = Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.05) : const Color(0xFFCD7F32).withOpacity(0.2);
    final _inputBg = theme.inputDecoration.color ?? const Color(0xFFF5F0E8);
    final _divider = Theme.of(context).brightness == Brightness.dark ? Colors.white10 : const Color(0xFFCD7F32).withOpacity(0.15);

    return Container(
      color: _bg,
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
                    Text('Messages', style: GoogleFonts.inter(color: _text, fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('${conversations.where((c) => c['isSectionHeader'] != true).length} conversations',
                        style: GoogleFonts.inter(color: _muted, fontSize: 13, fontWeight: FontWeight.w500)),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.edit_square, color: _text, size: 20),
                      onPressed: onNewDiscussion ?? () {},
                      tooltip: 'Nouvelle discussion',
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
              decoration: BoxDecoration(
                color: _inputBg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _border),
              ),
              child: TextField(
                controller: searchController,
                onChanged: onSearchChanged,
                style: TextStyle(color: _text, fontSize: 14),
                decoration: InputDecoration(
                  hintText: '🔍 Rechercher un contact...',
                  hintStyle: TextStyle(color: _muted.withOpacity(0.6), fontSize: 13),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  suffixIcon: isSearching
                    ? IconButton(
                        icon: Icon(Icons.close, color: _muted, size: 16),
                        onPressed: onClearSearch,
                      )
                    : null,
                ),
              ),
            ),
          ),



          Divider(color: _divider, height: 1),

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
                        Icon(_getIconForSection(c['sectionIcon']), size: 14, color: _getColorForSection(context, c['sectionColor'])),
                        const SizedBox(width: 8),
                        Text(
                          (c['sectionLabel'] ?? '').toString().toUpperCase(),
                          style: GoogleFonts.inter(color: _getColorForSection(context, c['sectionColor']), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
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
                    color: active ? _active : Colors.transparent,
                    child: Row(
                      children: [
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: theme.myBubble.withOpacity(0.2),
                              child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'C', style: TextStyle(color: theme.myBubble, fontWeight: FontWeight.bold)),
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: theme.online,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: _bg, width: 2),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(name, style: GoogleFonts.inter(color: _text, fontSize: 15, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ),
                                  if (c['isPinned'] == true)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 4),
                                      child: Icon(Icons.push_pin, color: theme.accent, size: 14),
                                    ),
                                  if (c['isMuted'] == true)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 4),
                                      child: Icon(Icons.volume_off, color: _muted, size: 14),
                                    ),
                                  if (time.isNotEmpty)
                                    Text(time, style: GoogleFonts.inter(color: _muted, fontSize: 11)),
                                ],
                              ),
                              const SizedBox(height: 2),
                              if (role.isNotEmpty)
                                Text(role, style: GoogleFonts.inter(color: theme.accent, fontSize: 10, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      lastText,
                                      style: GoogleFonts.inter(color: unread > 0 ? _text : _muted, fontSize: 13, fontStyle: unread > 0 ? FontStyle.normal : FontStyle.italic),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (unread > 0)
                                    Container(
                                      margin: const EdgeInsets.only(left: 8),
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: theme.unread, borderRadius: BorderRadius.circular(10)),
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


  IconData _getIconForSection(String? name) {
    switch (name) {
      case 'groups': return Icons.groups;
      case 'engineering': return Icons.engineering;
      case 'support_agent': return Icons.support_agent;
      default: return Icons.person;
    }
  }

  Color _getColorForSection(BuildContext context, String? name) {
    final theme = ChatTheme.of(context);
    switch (name) {
      case 'green': return theme.roleClient;
      case 'purple': return theme.roleConcepteur;
      case 'blue': return theme.roleTechnicien;
      case 'orange': return theme.roleMaintenance;
      default: return theme.muted;
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
