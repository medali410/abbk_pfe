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
    final _border = Theme.of(context).brightness == Brightness.dark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFCD7F32).withValues(alpha: 0.2);
    final _divider = Theme.of(context).brightness == Brightness.dark ? Colors.white10 : const Color(0xFFCD7F32).withValues(alpha: 0.15);

    return Container(
      color: _bg,
      child: Column(
        children: [
          // En-tête
          Container(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Messages', style: theme.titleStyle),
                    const SizedBox(height: 6),
                    Text('${conversations.where((c) => c['isSectionHeader'] != true).length} conversations',
                        style: theme.subtitleStyle),
                  ],
                ),
                FloatingActionButton.small(
                  elevation: 0,
                  backgroundColor: theme.myBubble.withValues(alpha: 0.1),
                  foregroundColor: theme.myBubble,
                  onPressed: onNewDiscussion ?? () {},
                  tooltip: 'Nouvelle discussion',
                  child: const Icon(Icons.edit_square, size: 20),
                ),
              ],
            ),
          ),

          // Barre de recherche
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Container(
              height: 48,
              decoration: theme.inputDecoration,
              child: TextField(
                controller: searchController,
                onChanged: onSearchChanged,
                style: TextStyle(color: _text, fontSize: 15, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.search, color: _muted),
                  hintText: 'Rechercher un contact...',
                  hintStyle: TextStyle(color: _muted.withValues(alpha: 0.6), fontSize: 14),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  suffixIcon: isSearching
                    ? IconButton(
                        icon: Icon(Icons.close, color: _muted, size: 18),
                        onPressed: onClearSearch,
                      )
                    : null,
                ),
              ),
            ),
          ),

          const SizedBox(height: 4),
          Divider(color: _divider, height: 1),
          const SizedBox(height: 8),

          // Liste des contacts
          Expanded(
            child: ListView.builder(
              itemCount: conversations.length,
              itemBuilder: (context, index) {
                final c = conversations[index];
                if (c['isSectionHeader'] == true) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(28, 24, 20, 8),
                    child: Row(
                      children: [
                        Icon(_getIconForSection(c['sectionIcon']), size: 16, color: _getColorForSection(context, c['sectionColor']).withValues(alpha: 0.8)),
                        const SizedBox(width: 8),
                        Text(
                          (c['sectionLabel'] ?? '').toString().toUpperCase(),
                          style: GoogleFonts.inter(color: _getColorForSection(context, c['sectionColor']), fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2),
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

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  child: InkWell(
                    onTap: () => onSelectConversation(c['roomId'], c),
                    borderRadius: BorderRadius.circular(16),
                    hoverColor: active ? _active : theme.otherBubble.withValues(alpha: 0.3),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: active ? _active : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        border: active ? Border.all(color: theme.myBubble.withValues(alpha: 0.3)) : Border.all(color: Colors.transparent),
                      ),
                      child: Row(
                        children: [
                          Stack(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: theme.myBubble.withValues(alpha: 0.15),
                                child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'C', style: GoogleFonts.inter(color: theme.myBubble, fontWeight: FontWeight.bold, fontSize: 16)),
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: theme.online,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: active ? theme.myBubble.withValues(alpha: 0.2) : _bg, width: 2.5),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(name, style: theme.nameStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    ),
                                    if (c['isPinned'] == true)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 6),
                                        child: Icon(Icons.push_pin, color: theme.accent, size: 14),
                                      ),
                                    if (c['isMuted'] == true)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 6),
                                        child: Icon(Icons.volume_off, color: _muted, size: 14),
                                      ),
                                    if (time.isNotEmpty)
                                      Text(time, style: theme.timeStyle),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        lastText,
                                        style: GoogleFonts.inter(color: unread > 0 ? _text : _muted, fontSize: 13, fontStyle: unread > 0 ? FontStyle.normal : FontStyle.normal, fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (unread > 0)
                                      Container(
                                        margin: const EdgeInsets.only(left: 8),
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(color: theme.unread, borderRadius: BorderRadius.circular(12)),
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
