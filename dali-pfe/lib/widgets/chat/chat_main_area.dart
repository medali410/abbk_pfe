import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart' hide Config;
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'chat_theme.dart';

class ChatMainArea extends StatefulWidget {
  final String activeRoomId;
  final Map<String, dynamic>? selectedContactDetails;
  final List<Map<String, dynamic>> messages;
  final ScrollController scrollController;
  final int currentUserId;
  final bool remoteIsTyping;
  final String remoteTypingName;
  final TextEditingController inputController;
  final bool isRecording;
  final String recordingDuration;
  final VoidCallback onPickFile;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;
  final VoidCallback onCancelRecording;
  final VoidCallback onSendMessage;
  final Function(String) onInputChanged;
  final VoidCallback onCloseConversation;
  final VoidCallback? onVideoCall;
  final VoidCallback? onVoiceCall;
  final VoidCallback? onSearchMessages;
  final bool showEmojiPicker;
  final VoidCallback? onToggleEmojiPicker;
  final Function(String)? onEmojiSelected;
  final Widget Function(Map<String, dynamic>) buildMessageItem;

  const ChatMainArea({
    super.key,
    required this.activeRoomId,
    required this.selectedContactDetails,
    required this.messages,
    required this.scrollController,
    required this.currentUserId,
    required this.remoteIsTyping,
    required this.remoteTypingName,
    required this.inputController,
    required this.isRecording,
    required this.recordingDuration,
    required this.onPickFile,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onCancelRecording,
    required this.onSendMessage,
    required this.onInputChanged,
    required this.onCloseConversation,
    required this.buildMessageItem,
    this.onVideoCall,
    this.onVoiceCall,
    this.onSearchMessages,
    this.showEmojiPicker = false,
    this.onToggleEmojiPicker,
    this.onEmojiSelected,
  });

  @override
  State<ChatMainArea> createState() => _ChatMainAreaState();
}

class _ChatMainAreaState extends State<ChatMainArea> {
  bool _isSearchingMessages = false;
  final TextEditingController _msgSearchController = TextEditingController();

  @override
  void dispose() {
    _msgSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.activeRoomId.isEmpty) {
      return _buildEmptyState(context);
    }

    final name = widget.selectedContactDetails?['name']?.toString() ?? 'Discussion';
    final role = widget.selectedContactDetails?['roleLabel']?.toString() ?? 'Contact';
    final isDesktop = MediaQuery.of(context).size.width > 900;

    final theme = ChatTheme.of(context);

    // Apply filter if searching
    final query = _msgSearchController.text.toLowerCase().trim();
    final displayedMessages = query.isEmpty
        ? widget.messages
        : widget.messages.where((m) => (m['text'] ?? '').toString().toLowerCase().contains(query)).toList();

    return Container(
      color: theme.bg,
      child: Column(
        children: [
          // En-tête
          Container(
            height: 70,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: theme.header.withOpacity(0.95),
              border: Border(bottom: BorderSide(
                color: Theme.of(context).brightness == Brightness.dark 
                    ? Colors.white.withOpacity(0.05) 
                    : const Color(0xFFCD7F32).withOpacity(0.15),
              )),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: _isSearchingMessages
                ? Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back, color: theme.text),
                        onPressed: () {
                          setState(() {
                            _isSearchingMessages = false;
                            _msgSearchController.clear();
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _msgSearchController,
                          autofocus: true,
                          style: TextStyle(color: theme.text, fontSize: 15),
                          onChanged: (val) {
                            setState(() {});
                          },
                          decoration: InputDecoration(
                            hintText: 'Rechercher des messages...',
                            hintStyle: TextStyle(color: theme.muted.withOpacity(0.6)),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      if (_msgSearchController.text.isNotEmpty)
                        IconButton(
                          icon: Icon(Icons.close, color: theme.muted),
                          onPressed: () {
                            setState(() {
                              _msgSearchController.clear();
                            });
                          },
                        ),
                    ],
                  )
                : Row(
                    children: [
                      if (!isDesktop) ...[
                        IconButton(icon: Icon(Icons.arrow_back, color: theme.text), onPressed: widget.onCloseConversation),
                        const SizedBox(width: 8),
                      ],
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: theme.myBubble.withOpacity(0.2),
                        child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'C', style: TextStyle(color: theme.myBubble, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(name, style: theme.nameStyle),
                            Text(
                              widget.remoteIsTyping ? 'est en train d\'écrire...' : 'En ligne',
                              style: GoogleFonts.inter(color: widget.remoteIsTyping ? theme.accent : theme.online, fontSize: 12, fontStyle: widget.remoteIsTyping ? FontStyle.italic : FontStyle.normal),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.groups, color: theme.muted),
                        onPressed: widget.onVideoCall,
                        tooltip: 'Demander réunion Teams',
                      ),
                      IconButton(
                        icon: Icon(Icons.search, color: theme.muted),
                        onPressed: () {
                          setState(() {
                            _isSearchingMessages = true;
                          });
                        },
                      ),
                    ],
                  ),
          ),

          // Zone des messages
          Expanded(
            child: Stack(
              children: [
                // Fond de la zone de chat (motif léger ou dégradé)
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.03,
                    child: Image.network('https://user-images.githubusercontent.com/15075759/28719144-86dc0f70-73b1-11e7-911d-60d70fcded21.png', repeat: ImageRepeat.repeat),
                  ),
                ),
                
                Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        controller: widget.scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                        itemCount: displayedMessages.length,
                        itemBuilder: (context, index) {
                          // TODO: Ajouter séparateurs de date intelligents ici
                          return widget.buildMessageItem(displayedMessages[index]);
                        },
                      ),
                    ),
                    
                    if (widget.remoteIsTyping)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(color: theme.otherBubble, borderRadius: BorderRadius.circular(20)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: theme.muted)),
                                const SizedBox(width: 8),
                                Text('${widget.remoteTypingName.isNotEmpty ? widget.remoteTypingName : "Quelqu'un"} écrit...', style: GoogleFonts.inter(color: theme.muted, fontSize: 12, fontStyle: FontStyle.italic)),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Input Bar
          SafeArea(
            bottom: true,
            child: Container(
              margin: EdgeInsets.fromLTRB(16, 0, 16, 16),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              decoration: theme.glassDecoration.copyWith(
                borderRadius: BorderRadius.circular(30),
              ),
              child: widget.isRecording
                  ? Row(
                      children: [
                        const Icon(Icons.mic, color: Colors.redAccent),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text('Enregistrement en cours... ${widget.recordingDuration}', style: TextStyle(color: theme.text, fontSize: 15)),
                        ),
                        IconButton(icon: Icon(Icons.delete, color: theme.muted), onPressed: widget.onCancelRecording),
                        const SizedBox(width: 8),
                        FloatingActionButton(
                          mini: true,
                          backgroundColor: theme.myBubble,
                          onPressed: widget.onStopRecording,
                          child: const Icon(Icons.send, color: Colors.white, size: 20),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        IconButton(icon: Icon(Icons.attach_file, color: theme.muted), onPressed: widget.onPickFile),
                        IconButton(
                          icon: Icon(
                            widget.showEmojiPicker ? Icons.keyboard : Icons.emoji_emotions_outlined,
                            color: widget.showEmojiPicker ? theme.accent : theme.muted,
                          ),
                          onPressed: widget.onToggleEmojiPicker ?? () {},
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            decoration: theme.inputDecoration,
                            child: TextField(
                              controller: widget.inputController,
                              onChanged: widget.onInputChanged,
                              style: TextStyle(color: theme.text),
                              minLines: 1,
                              maxLines: 5,
                              decoration: InputDecoration(
                                hintText: 'Tapez un message...',
                                hintStyle: TextStyle(color: theme.muted.withValues(alpha: 0.6), fontWeight: FontWeight.w500),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FloatingActionButton(
                          mini: true,
                          backgroundColor: theme.myBubble,
                          elevation: 4,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          onPressed: widget.onSendMessage,
                          child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                        ),
                      ],
                    ),
            ),
          ),

          // Emoji Picker
          if (widget.showEmojiPicker)
            SizedBox(
              height: 280,
              child: EmojiPicker(
                onEmojiSelected: (category, emoji) {
                  widget.onEmojiSelected?.call(emoji.emoji);
                },
                config: Config(
                  height: 280,
                  checkPlatformCompatibility: true,
                  emojiViewConfig: EmojiViewConfig(
                    emojiSizeMax: 28,
                    backgroundColor: theme.header,
                    noRecents: Text('Pas d\'emojis récents', style: TextStyle(color: theme.muted, fontSize: 14)),
                  ),
                  categoryViewConfig: CategoryViewConfig(
                    backgroundColor: theme.header,
                    indicatorColor: theme.myBubble,
                    iconColorSelected: theme.myBubble,
                    iconColor: theme.muted,
                    dividerColor: theme.bg,
                  ),
                  searchViewConfig: SearchViewConfig(
                    backgroundColor: theme.header,
                    buttonIconColor: theme.muted,
                    hintText: 'Rechercher un emoji...',
                  ),
                  bottomActionBarConfig: const BottomActionBarConfig(enabled: false),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = ChatTheme.of(context);
    return Container(
      color: theme.bg,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: theme.header.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: theme.muted.withValues(alpha: 0.1)),
            boxShadow: [
              BoxShadow(
                color: theme.myBubble.withValues(alpha: 0.05),
                blurRadius: 40,
                spreadRadius: 10,
              )
            ]
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.myBubble.withValues(alpha: 0.15),
                      theme.myBubble.withValues(alpha: 0.02)
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.myBubble.withValues(alpha: 0.15), width: 2),
                ),
                child: Icon(Icons.maps_ugc_rounded, size: 70, color: theme.myBubble.withValues(alpha: 0.9)),
              ),
              const SizedBox(height: 32),
              Text(
                'Bienvenue dans votre messagerie', 
                style: GoogleFonts.inter(color: theme.text, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 480,
                child: Text(
                  'Sélectionnez un contact dans la liste pour commencer une conversation, ou utilisez la barre de recherche pour trouver un membre de votre équipe.',
                  style: GoogleFonts.inter(color: theme.muted, fontSize: 15, height: 1.6, fontWeight: FontWeight.w500),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () {}, // Handled by search interaction
                icon: const Icon(Icons.search),
                label: const Text('Rechercher un contact'),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.myBubble,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
