import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'chat_theme.dart';

class ChatMainArea extends StatelessWidget {
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
  final Widget Function(Map<String, dynamic>) buildMessageItem; // On délègue le rendu complexe à la vue principale pour l'instant

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
  });

  @override
  Widget build(BuildContext context) {
    if (activeRoomId.isEmpty) {
      return _buildEmptyState();
    }

    final name = selectedContactDetails?['name']?.toString() ?? 'Discussion';
    final role = selectedContactDetails?['roleLabel']?.toString() ?? 'Contact';
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return Container(
      color: ChatTheme.bg,
      child: Column(
        children: [
          // En-tête
          Container(
            height: 70,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: ChatTheme.header.withOpacity(0.95),
              border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: Row(
              children: [
                if (!isDesktop) ...[
                  IconButton(icon: const Icon(Icons.arrow_back, color: ChatTheme.text), onPressed: onCloseConversation),
                  const SizedBox(width: 8),
                ],
                CircleAvatar(
                  radius: 20,
                  backgroundColor: ChatTheme.myBubble.withOpacity(0.2),
                  child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'C', style: const TextStyle(color: ChatTheme.myBubble, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(name, style: ChatTheme.nameStyle),
                      Text(
                        remoteIsTyping ? 'est en train d\'écrire...' : 'En ligne',
                        style: GoogleFonts.inter(color: remoteIsTyping ? ChatTheme.accent : ChatTheme.online, fontSize: 12, fontStyle: remoteIsTyping ? FontStyle.italic : FontStyle.normal),
                      ),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.videocam_outlined, color: ChatTheme.muted), onPressed: () {}),
                IconButton(icon: const Icon(Icons.call_outlined, color: ChatTheme.muted), onPressed: () {}),
                IconButton(icon: const Icon(Icons.search, color: ChatTheme.muted), onPressed: () {}),
                IconButton(icon: const Icon(Icons.more_vert, color: ChatTheme.muted), onPressed: () {}),
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
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          // TODO: Ajouter séparateurs de date intelligents ici
                          return buildMessageItem(messages[index]);
                        },
                      ),
                    ),
                    
                    if (remoteIsTyping)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(color: ChatTheme.otherBubble, borderRadius: BorderRadius.circular(20)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: ChatTheme.muted)),
                                const SizedBox(width: 8),
                                Text('${remoteTypingName.isNotEmpty ? remoteTypingName : "Quelqu'un"} écrit...', style: GoogleFonts.inter(color: ChatTheme.muted, fontSize: 12, fontStyle: FontStyle.italic)),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: ChatTheme.header,
              border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
            ),
            child: isRecording
                ? Row(
                    children: [
                      const Icon(Icons.mic, color: Colors.redAccent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('Enregistrement en cours... $recordingDuration', style: const TextStyle(color: ChatTheme.text, fontSize: 15)),
                      ),
                      IconButton(icon: const Icon(Icons.delete, color: ChatTheme.muted), onPressed: onCancelRecording),
                      const SizedBox(width: 8),
                      FloatingActionButton(
                        mini: true,
                        backgroundColor: ChatTheme.myBubble,
                        onPressed: onStopRecording,
                        child: const Icon(Icons.send, color: Colors.white, size: 20),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      IconButton(icon: const Icon(Icons.attach_file, color: ChatTheme.muted), onPressed: onPickFile),
                      IconButton(icon: const Icon(Icons.emoji_emotions_outlined, color: ChatTheme.muted), onPressed: () {}),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          decoration: ChatTheme.inputDecoration,
                          child: TextField(
                            controller: inputController,
                            onChanged: onInputChanged,
                            style: const TextStyle(color: ChatTheme.text),
                            minLines: 1,
                            maxLines: 5,
                            decoration: const InputDecoration(
                              hintText: 'Tapez un message...',
                              hintStyle: TextStyle(color: ChatTheme.muted),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (inputController.text.trim().isEmpty)
                        IconButton(icon: const Icon(Icons.mic, color: ChatTheme.muted), onPressed: onStartRecording)
                      else
                        FloatingActionButton(
                          mini: true,
                          backgroundColor: ChatTheme.myBubble,
                          elevation: 0,
                          onPressed: onSendMessage,
                          child: const Icon(Icons.send, color: Colors.white, size: 20),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      color: ChatTheme.bg,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: ChatTheme.myBubble.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.forum_outlined, size: 60, color: ChatTheme.myBubble),
            ),
            const SizedBox(height: 24),
            Text('Bienvenue dans votre messagerie', style: GoogleFonts.inter(color: ChatTheme.text, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(
              width: 400,
              child: Text(
                'Sélectionnez un contact pour commencer une conversation ou utilisez la recherche pour trouver un membre de votre équipe.',
                style: GoogleFonts.inter(color: ChatTheme.muted, fontSize: 14, height: 1.5),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
