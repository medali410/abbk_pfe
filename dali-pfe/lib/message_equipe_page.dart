import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'services/api_service.dart';

class MessageEquipePage extends StatefulWidget {
  const MessageEquipePage({super.key});

  @override
  State<MessageEquipePage> createState() => _MessageEquipePageState();
}

class _MessageEquipePageState extends State<MessageEquipePage> {
  static const _bg = Color(0xFF10102B);
  static const _low = Color(0xFF191934);
  static const _container = Color(0xFF1D1D38);
  static const _high = Color(0xFF272743);
  static const _highest = Color(0xFF32324E);
  static const _primary = Color(0xFFFF6E00);
  static const _secondary = Color(0xFF75D1FF);
  static const _text = Color(0xFFE2DFFF);
  static const _muted = Color(0xFFE2BFB0);
  static const _error = Color(0xFFFFB4AB);

  io.Socket? _socket;
  final TextEditingController _input = TextEditingController();
  List<Map<String, dynamic>> _conversations = [];
  List<Map<String, dynamic>> _messages = [];
  String _activeRoomId = '';
  String _senderName = 'Technicien';
  String _senderRole = 'technician';
  String _technicianId = '';
  String _clientId = '';
  bool _isTyping = false;
  final ScrollController _messagesScroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _messagesScroll.dispose();
    _socket?.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_socket != null) return;
    final args = (ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?) ?? {};
    _technicianId = (args['technicianId'] ?? args['id'] ?? '').toString();
    _clientId = (args['clientId'] ?? args['companyId'] ?? '').toString();
    _senderName = (args['name'] ?? 'Technicien').toString();
    _senderRole = (args['role'] ?? 'technician').toString().toLowerCase();
    if (_senderRole != 'client' && _senderRole != 'technician' && _senderRole != 'conception') {
      _senderRole = 'technician';
    }
    _initChat();
  }

  Future<void> _initChat() async {
    try {
      if (_senderRole == 'client') {
        if (_clientId.isNotEmpty) {
          _conversations = await ApiService.getClientConversations(_clientId);
        }
      } else if (_senderRole == 'conception') {
        _conversations = await ApiService.getConceptionConversations();
      } else {
        if (_technicianId.isNotEmpty) {
          _conversations = await ApiService.getTechnicianConversations(_technicianId);
        }
      }
      if (_conversations.isNotEmpty) {
        _activeRoomId = (_conversations.first['roomId'] ?? '').toString();
      } else if (_senderRole == 'conception' && _technicianId.isNotEmpty) {
        _activeRoomId = 'chat_conception_$_technicianId';
      } else if (_clientId.isNotEmpty && _technicianId.isNotEmpty) {
        _activeRoomId = 'chat_${_clientId}_$_technicianId';
      }
      if (_activeRoomId.isNotEmpty) {
        _messages = await ApiService.getChatMessages(_activeRoomId, limit: 300);
      }
      if (mounted) setState(() {});
    } catch (_) {}

    _socket = io.io(ApiService.socketBaseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });
    _socket!.onConnect((_) {
      if (_activeRoomId.isNotEmpty) {
        _socket!.emit('join_chat_room', {'roomId': _activeRoomId});
      }
    });
    _socket!.on('chat_message', (raw) {
      try {
        final data = raw is String ? jsonDecode(raw) : raw;
        if (data is! Map) return;
        final m = Map<String, dynamic>.from(data);
        if ((m['roomId'] ?? '').toString() != _activeRoomId) return;
        final fromMe = (m['senderName'] ?? '').toString() == _senderName &&
            (m['from'] ?? '').toString() == _senderRole;
        if (fromMe) return;
        if (!mounted) return;
        setState(() => _messages.add(m));
        _scrollToLatest();
      } catch (_) {}
    });
  }

  Future<void> _switchConversation(Map<String, dynamic> c) async {
    final room = (c['roomId'] ?? '').toString();
    if (room.isEmpty) return;
    _activeRoomId = room;
    _socket?.emit('join_chat_room', {'roomId': room});
    try {
      _messages = await ApiService.getChatMessages(room, limit: 300);
      if (mounted) setState(() {});
      _scrollToLatest();
    } catch (_) {}
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;

    if (_activeRoomId.isEmpty && _clientId.isNotEmpty && _technicianId.isNotEmpty) {
      _activeRoomId = 'chat_${_clientId}_$_technicianId';
    }
    if (_activeRoomId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conversation non initialisée. Réessayez.')),
        );
      }
      return;
    }

    // Ensure the socket joins the room before emitting message.
    _socket?.emit('join_chat_room', {'roomId': _activeRoomId});

    final localMessage = <String, dynamic>{
      'roomId': _activeRoomId,
      'from': _senderRole,
      'senderName': _senderName,
      'text': text,
      'createdAt': DateTime.now().toIso8601String(),
    };

    if (mounted) {
      setState(() {
        _messages.add(localMessage);
      });
      _scrollToLatest();
    }

    _socket?.emit('chat_message', {
      'roomId': _activeRoomId,
      'from': _senderRole,
      'senderName': _senderName,
      'text': text,
    });
    _input.clear();
    if (mounted) setState(() => _isTyping = false);
    _scrollToLatest();
  }

  String _fmtTime(dynamic raw) {
    final dt = DateTime.tryParse((raw ?? '').toString());
    if (dt == null) return '--:--';
    final d = dt.toLocal();
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_messagesScroll.hasClients) return;
      _messagesScroll.animateTo(
        _messagesScroll.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Row(
        children: [
          Container(
            width: 280,
            color: _low,
            child: Column(
              children: [
                const SizedBox(height: 80),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: _high.withOpacity(0.45),
                          border: Border(
                            right: BorderSide(color: _primary, width: 2),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.groups, color: _primary, size: 20),
                            const SizedBox(width: 10),
                            Text(
                              'Équipe Assignée',
                              style: GoogleFonts.inter(
                                color: _primary,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        child: Row(
                          children: [
                            Icon(Icons.description_outlined, color: _muted.withOpacity(0.8), size: 20),
                            const SizedBox(width: 10),
                            Text(
                              'Documents Techniques',
                              style: GoogleFonts.inter(
                                color: _muted.withOpacity(0.9),
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Divider(color: _muted.withOpacity(0.12), height: 1),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('DISCUSSIONS RÉCENTES',
                          style: GoogleFonts.spaceGrotesk(color: _muted, fontSize: 11, letterSpacing: 1.3)),
                      const SizedBox(height: 10),
                      Container(
                        height: 36,
                        decoration: BoxDecoration(
                          color: _highest.withOpacity(0.45),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _muted.withOpacity(0.12)),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          children: [
                            Icon(Icons.search, color: _muted.withOpacity(0.7), size: 16),
                            const SizedBox(width: 8),
                            Text('Rechercher...',
                                style: GoogleFonts.inter(color: _muted.withOpacity(0.6), fontSize: 11)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _conversations.length,
                    itemBuilder: (context, i) {
                      final c = _conversations[i];
                      final room = (c['roomId'] ?? '').toString();
                      final active = room == _activeRoomId;
                      return InkWell(
                        onTap: () => _switchConversation(c),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: active ? _high : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: active ? Border(left: const BorderSide(color: _primary, width: 3)) : null,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  _senderRole == 'conception'
                                      ? (c['technicianName'] ?? c['clientName'] ?? 'Technicien').toString()
                                      : _senderRole == 'technician'
                                          ? (c['clientName'] ?? 'Client').toString()
                                          : (c['technicianName'] ?? 'Technicien').toString(),
                                  style: GoogleFonts.inter(color: _text, fontWeight: FontWeight.w700, fontSize: 13)),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Text(_fmtTime(c['lastAt']),
                                      style: GoogleFonts.spaceGrotesk(color: _muted.withOpacity(0.7), fontSize: 9)),
                                  const Spacer(),
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: active ? _primary : _secondary.withOpacity(0.7),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text((c['lastText'] ?? 'Aucun message').toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(color: _muted, fontSize: 11)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 76,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(color: _bg, border: Border(bottom: BorderSide(color: _muted.withOpacity(0.15)))),
                  child: Row(
                    children: [
                      Text(
                          _senderRole == 'conception' ? 'Maintenance Portal' :
                          _senderRole == 'client' ? 'Client Portal' : 'Technicien Portal',
                          style: GoogleFonts.inter(color: _primary, fontSize: 20, fontWeight: FontWeight.w900)),
                      const SizedBox(width: 24),
                      Text('Documentation',
                          style: GoogleFonts.inter(color: _primary, fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 18),
                      Text('Historique',
                          style: GoogleFonts.inter(color: _muted.withOpacity(0.9), fontSize: 13)),
                      const SizedBox(width: 18),
                      Text('Support Direct',
                          style: GoogleFonts.inter(color: _muted.withOpacity(0.9), fontSize: 13)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _highest.withOpacity(0.45),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _muted.withOpacity(0.15)),
                        ),
                        child: Text('Connecté',
                            style: GoogleFonts.spaceGrotesk(color: _secondary, fontSize: 10, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 10),
                      Text('message_equipe', style: GoogleFonts.spaceGrotesk(color: _secondary)),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    color: _container.withOpacity(0.45),
                    child: ListView.builder(
                      controller: _messagesScroll,
                      padding: const EdgeInsets.all(20),
                      itemCount: _messages.length,
                      itemBuilder: (context, i) {
                        final m = _messages[i];
                        final sender = (m['senderName'] ?? 'User').toString();
                        final text = (m['text'] ?? '').toString();
                        final mine = sender == _senderName;
                        final critical = text.toLowerCase().contains('alerte critique');
                        return Align(
                          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 540),
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: critical
                                  ? _error.withOpacity(0.18)
                                  : (mine ? _primary.withOpacity(0.9) : _highest),
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(12),
                                topRight: const Radius.circular(12),
                                bottomLeft: Radius.circular(mine ? 12 : 4),
                                bottomRight: Radius.circular(mine ? 4 : 12),
                              ),
                              border: critical ? Border.all(color: _error.withOpacity(0.7)) : null,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.14),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!mine)
                                  Text(sender,
                                      style: GoogleFonts.inter(
                                          color: _muted, fontSize: 10, fontWeight: FontWeight.w700)),
                                Text(text, style: GoogleFonts.inter(color: _text, fontSize: 13)),
                                const SizedBox(height: 4),
                                Text(
                                  _fmtTime(m['createdAt'] ?? m['at']),
                                  style: GoogleFonts.spaceGrotesk(
                                    color: _muted.withOpacity(0.8),
                                    fontSize: 9,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: _low, border: Border(top: BorderSide(color: _muted.withOpacity(0.15)))),
                  child: Column(
                    children: [
                      if (_isTyping)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: _highest.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            'Vous êtes en train d\'écrire...',
                            style: GoogleFonts.spaceGrotesk(color: _muted, fontSize: 10),
                          ),
                        ),
                      Row(
                        children: [
                          IconButton(
                            onPressed: () {},
                            icon: const Icon(Icons.add_circle_outline, color: _muted),
                          ),
                          IconButton(
                            onPressed: () {},
                            icon: const Icon(Icons.description_outlined, color: _muted),
                          ),
                          IconButton(
                            onPressed: () {},
                            icon: const Icon(Icons.photo_library_outlined, color: _muted),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _input,
                              onChanged: (v) {
                                if (!mounted) return;
                                setState(() => _isTyping = v.trim().isNotEmpty);
                              },
                              style: GoogleFonts.inter(color: _text),
                              decoration: InputDecoration(
                                hintText: 'Rédiger votre message technique...',
                                hintStyle: GoogleFonts.inter(color: _muted.withOpacity(0.5)),
                                filled: true,
                                fillColor: _highest.withOpacity(0.5),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: _muted.withOpacity(0.2)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: _muted.withOpacity(0.2)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: _secondary.withOpacity(0.7)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: _send,
                            style: ElevatedButton.styleFrom(backgroundColor: _primary),
                            child: const Icon(Icons.send, color: Colors.white),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),
          Container(
            width: 280,
            color: _low,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 80),
                Text('DÉTAILS DE L\'ACTIF',
                    style: GoogleFonts.spaceGrotesk(color: _muted, fontSize: 11, letterSpacing: 1.2)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: _container, borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Machine Thermique Alpha-7',
                          style: GoogleFonts.inter(color: _text, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('Status: ALERTE', style: GoogleFonts.inter(color: _error, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text('DOCUMENTS TECHNIQUES',
                    style: GoogleFonts.spaceGrotesk(color: _muted, fontSize: 11, letterSpacing: 1.2)),
                const SizedBox(height: 10),
                _docItem('Manuel_Maintenance_V4.pdf', '4.2 MB', Icons.picture_as_pdf_outlined),
                const SizedBox(height: 8),
                _docItem('Plan_Electrique_A7.dwg', '12.8 MB', Icons.schema_outlined),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _docItem(String name, String size, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _highest.withOpacity(0.45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _muted.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Icon(icon, color: _secondary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(color: _text, fontSize: 11, fontWeight: FontWeight.w700)),
                Text(size, style: GoogleFonts.spaceGrotesk(color: _muted, fontSize: 9)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
