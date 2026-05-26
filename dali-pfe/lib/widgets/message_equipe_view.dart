import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:geolocator/geolocator.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../services/api_service.dart';

class MessageEquipeView extends StatefulWidget {
  final String? technicianId;
  final String? clientId;
  final String? senderName;
  final String? senderRole;
  final bool embedded;

  const MessageEquipeView({
    super.key,
    this.technicianId,
    this.clientId,
    this.senderName,
    this.senderRole,
    this.embedded = false,
  });

  @override
  State<MessageEquipeView> createState() => _MessageEquipeViewState();
}

class _MessageEquipeViewState extends State<MessageEquipeView> {
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
  late String _senderName;
  late String _senderRole;
  late String _technicianId;
  late String _clientId;
  bool _isTyping = false;
  final ScrollController _messagesScroll = ScrollController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  Map<String, dynamic>? _selectedDesignerDetails;

  @override
  void initState() {
    super.initState();
    _technicianId = (widget.technicianId ?? '').toString();
    _clientId = (widget.clientId ?? '').toString();
    _senderName = (widget.senderName ?? 'Technicien').toString();
    _senderRole = (widget.senderRole ?? 'technician').toString().toLowerCase();
    
    // Auto-detect based on ApiService if not provided
    if (_senderName == 'Technicien' && ApiService.savedUserRole != null) {
        _senderRole = ApiService.savedUserRole!.toLowerCase();
        if (_senderRole == 'admin' || _senderRole == 'superadmin') _senderRole = 'conception';
        _senderName = 'Administrateur';
    }

    if (_senderRole != 'client' && _senderRole != 'technician' && _senderRole != 'conception') {
      _senderRole = 'technician';
    }
    _initChat();
  }

  @override
  void dispose() {
    _input.dispose();
    _searchController.dispose();
    _messagesScroll.dispose();
    _socket?.dispose();
    super.dispose();
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
      // Ne pas auto-sélectionner — l'utilisateur doit cliquer sur une conversation
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

    // Resolve designer details: use conversation participants as fallback
    final designerName = (c['concepteurName'] ?? c['name'] ?? '').toString();
    if (designerName.isNotEmpty) {
      // Try to search for the designer first
      try {
        final results = await ApiService.searchConcepteurs(designerName);
        if (mounted && results.isNotEmpty) {
          setState(() {
            _selectedDesignerDetails = results.firstWhere(
              (r) => r['name'] == designerName, 
              orElse: () => results.first,
            );
          });
        } else {
          // Fallback: build minimal info from conversation data
          if (mounted) {
            setState(() {
              _selectedDesignerDetails = {
                'name': designerName,
                'specialite': '',
                'machines': <String>[],
              };
            });
          }
        }
      } catch (_) {
        // Fallback on error
        if (mounted) {
          setState(() {
            _selectedDesignerDetails = {
              'name': designerName,
              'specialite': '',
              'machines': <String>[],
            };
          });
        }
      }
    } else {
      // No name available — use participants from conversation data
      final participants = c['participants'] as List?;
      final pName = participants != null && participants.isNotEmpty
          ? (participants.first['userName'] ?? 'Concepteur').toString()
          : 'Concepteur';
      if (mounted) {
        setState(() {
          _selectedDesignerDetails = {
            'name': pName,
            'specialite': '',
            'machines': <String>[],
          };
        });
      }
    }

    try {
      _messages = await ApiService.getChatMessages(room, limit: 300);
      if (mounted) setState(() {});
      _scrollToLatest();
    } catch (_) {}
  }

  void _closeConversation() {
    if (mounted) {
      setState(() {
        _activeRoomId = '';
        _messages = [];
        _selectedDesignerDetails = null;
      });
    }
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

    final currentUserId = (_senderRole == 'technician' && _technicianId.isNotEmpty) 
        ? int.tryParse(_technicianId)
        : (_senderRole == 'client' && _clientId.isNotEmpty)
            ? int.tryParse(_clientId)
            : 1;

    _socket?.emit('chat_message', {
      'roomId': _activeRoomId,
      'from': _senderRole,
      'userId': currentUserId,
      'senderName': _senderName,
      'text': text,
    });
    _input.clear();
    if (mounted) setState(() => _isTyping = false);
    _scrollToLatest();
  }

  Future<void> _pickAndUploadFile({required bool isImage}) async {
    if (_activeRoomId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sélectionnez une conversation d\'abord.')),
        );
      }
      return;
    }

    try {
      final result = await FilePicker.pickFiles(
        type: isImage ? FileType.image : FileType.custom,
        allowedExtensions: isImage ? null : ['pdf', 'doc', 'docx', 'txt'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.bytes == null) return;

      final base64Data = base64Encode(file.bytes!);
      final url = await ApiService.uploadChatAttachment(
        base64Data: base64Data,
        filename: file.name,
      );

      if (url != null) {
        final attachmentType = isImage ? 'image' : 'document';
        final textMsg = isImage ? '[Image]' : '[Document]';

        final localMessage = <String, dynamic>{
          'roomId': _activeRoomId,
          'from': _senderRole,
          'senderName': _senderName,
          'text': textMsg,
          'attachmentUrl': url,
          'attachmentType': attachmentType,
          'createdAt': DateTime.now().toIso8601String(),
        };

        if (mounted) {
          setState(() => _messages.add(localMessage));
          _scrollToLatest();
        }

        final currentUserId = (_senderRole == 'technician' && _technicianId.isNotEmpty) 
            ? int.tryParse(_technicianId)
            : (_senderRole == 'client' && _clientId.isNotEmpty)
                ? int.tryParse(_clientId)
                : 1;

        _socket?.emit('chat_message', {
          'roomId': _activeRoomId,
          'from': _senderRole,
          'userId': currentUserId,
          'senderName': _senderName,
          'text': textMsg,
          'attachmentUrl': url,
          'attachmentType': attachmentType,
        });
      }
    } catch (e) {
      debugPrint('Erreur sélection fichier: $e');
    }
  }

  void _showExtrasOptions() {
    if (_activeRoomId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sélectionnez une conversation d\'abord.')),
        );
      }
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: _muted.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text('Options supplémentaires',
                  style: GoogleFonts.inter(color: _text, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              _extrasButton(
                icon: Icons.location_on,
                color: const Color(0xFFFF6E00),
                title: 'Partager ma localisation',
                subtitle: 'Envoyer mes coordonnées GPS',
                onTap: () {
                  Navigator.pop(ctx);
                  _shareRealLocation();
                },
              ),
              const SizedBox(height: 12),
              _extrasButton(
                icon: Icons.mic,
                color: const Color(0xFF75D1FF),
                title: 'Reconnaissance vocale',
                subtitle: 'Dicter un message',
                onTap: () {
                  Navigator.pop(ctx);
                  _startVoiceRecognition();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _extrasButton({required IconData icon, required Color color, required String title, required String subtitle, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _highest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _muted.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.inter(color: _text, fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: GoogleFonts.inter(color: _muted, fontSize: 11)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: _muted.withOpacity(0.4)),
          ],
        ),
      ),
    );
  }

  Future<void> _shareRealLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Permission de localisation refusée.')),
            );
          }
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Activez la localisation dans les paramètres.')),
          );
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final locationText = '📍 Position GPS: ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
      _sendMockText(locationText);
    } catch (e) {
      debugPrint('Erreur localisation: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur localisation: $e')),
        );
      }
    }
  }

  Future<void> _startVoiceRecognition() async {
    final speech = stt.SpeechToText();
    bool available = await speech.initialize(
      onError: (error) => debugPrint('Erreur STT: $error'),
    );
    if (!available) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reconnaissance vocale non disponible.')),
        );
      }
      return;
    }

    if (!mounted) return;

    // Show listening dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        String recognizedText = '';
        bool isListening = true;

        speech.listen(
          onResult: (result) {
            recognizedText = result.recognizedWords;
            if (result.finalResult) {
              isListening = false;
              Navigator.pop(ctx);
              if (recognizedText.isNotEmpty) {
                _input.text = recognizedText;
                if (mounted) setState(() => _isTyping = true);
              }
            }
          },
          localeId: 'fr_FR',
          listenFor: const Duration(seconds: 15),
        );

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A2E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text('🎙️ Écoute en cours...', style: GoogleFonts.inter(color: _text, fontSize: 16, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: _primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.mic, color: _primary, size: 40),
                  ),
                  const SizedBox(height: 16),
                  Text('Parlez maintenant...', style: GoogleFonts.inter(color: _muted, fontSize: 13)),
                  const SizedBox(height: 10),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    speech.stop();
                    Navigator.pop(ctx);
                  },
                  child: Text('Annuler', style: GoogleFonts.inter(color: _error)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _sendMockText(String txt) {
    if (_activeRoomId.isEmpty) return;
    final localMessage = <String, dynamic>{
      'roomId': _activeRoomId,
      'from': _senderRole,
      'senderName': _senderName,
      'text': txt,
      'createdAt': DateTime.now().toIso8601String(),
    };
    if (mounted) setState(() => _messages.add(localMessage));
    final currentUserId = (_senderRole == 'technician' && _technicianId.isNotEmpty) 
        ? int.tryParse(_technicianId)
        : (_senderRole == 'client' && _clientId.isNotEmpty)
            ? int.tryParse(_clientId)
            : 1; // Default fallback for Concepteur

    _socket?.emit('chat_message', {
      'roomId': _activeRoomId,
      'from': _senderRole,
      'userId': currentUserId,
      'senderName': _senderName,
      'text': txt,
    });
    _scrollToLatest();
  }

  Future<void> _doSearch(String q) async {
    if (q.trim().isEmpty) {
      if (mounted) setState(() { _searchResults = []; _isSearching = false; });
      return;
    }
    if (mounted) setState(() => _isSearching = true);
    try {
      final results = await ApiService.searchConcepteurs(q);
      if (mounted) setState(() { _searchResults = results; _isSearching = false; });
    } catch (_) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _startChatWith(Map<String, dynamic> designer) {
    // Generate a roomId based on user roles
    final designerId = designer['id'].toString();
    final room = 'chat_conception_$designerId';
    
    if (mounted) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
        _searchController.clear();
        _selectedDesignerDetails = designer;
      });
    }

    // Switch to this room
    _switchConversation({
      'roomId': room,
      'concepteurName': designer['name'],
    });
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
    final isDesktop = MediaQuery.sizeOf(context).width > 900;
    
    final body = Row(
      children: [
        // Left Sidebar (Conversations)
        if (isDesktop) Container(
          width: 280,
          color: _low,
          child: Column(
            children: [
              const SizedBox(height: 20),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('RECHERCHE & DISCUSSIONS',
                        style: GoogleFonts.spaceGrotesk(color: _muted, fontSize: 11, letterSpacing: 1.3)),
                    const SizedBox(height: 12),
                    Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: _highest.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _muted.withOpacity(0.15)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: TextField(
                        controller: _searchController,
                        onChanged: _doSearch,
                        style: GoogleFonts.inter(color: _text, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Rechercher concepteur...',
                          hintStyle: GoogleFonts.inter(color: _muted.withOpacity(0.4), fontSize: 13),
                          icon: Icon(Icons.search, color: _muted.withOpacity(0.6), size: 18),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _isSearching 
                  ? const Center(child: CircularProgressIndicator(color: _primary, strokeWidth: 2))
                  : _searchController.text.isNotEmpty && _searchResults.isEmpty
                    ? Center(child: Text('Aucun résultat', style: GoogleFonts.inter(color: _muted, fontSize: 12)))
                    : _searchController.text.isNotEmpty
                      ? ListView.builder(
                          itemCount: _searchResults.length,
                          itemBuilder: (context, i) {
                            final d = _searchResults[i];
                            return InkWell(
                              onTap: () => _startChatWith(d),
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _high.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: _muted.withOpacity(0.08)),
                                ),
                                child: Text(d['name'] ?? 'Concepteur',
                                    style: GoogleFonts.inter(color: _text, fontWeight: FontWeight.bold, fontSize: 13)),
                              ),
                            );
                          },
                        )
                      : ListView.builder(
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
                                        (c['concepteurName'] ?? c['technicianName'] ?? c['clientName'] ?? 'Concepteur').toString(),
                                        style: GoogleFonts.inter(color: _text, fontWeight: FontWeight.w700, fontSize: 13)),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Text(_fmtTime(c['lastAt']),
                                            style: GoogleFonts.spaceGrotesk(color: _muted.withOpacity(0.7), fontSize: 9)),
                                        const Spacer(),
                                        if (active)
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: const BoxDecoration(
                                              color: _primary,
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
        
        // Main Chat Area
        Expanded(
          child: Column(
            children: [
              if (!widget.embedded) Container(
                height: 76,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(color: _bg, border: Border(bottom: BorderSide(color: _muted.withOpacity(0.15)))),
                child: Row(
                  children: [
                    Text(
                        _senderRole == 'conception' ? 'Espace Concepteur' :
                        _senderRole == 'client' ? 'Messagerie Client' : 'Messagerie Technicien',
                        style: GoogleFonts.inter(color: _primary, fontSize: 20, fontWeight: FontWeight.w900)),
                    const Spacer(),
                    if (_activeRoomId.isNotEmpty)
                      IconButton(
                        onPressed: _closeConversation,
                        tooltip: 'Quitter la conversation',
                        icon: const Icon(Icons.close, color: _muted, size: 20),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _highest.withOpacity(0.45),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _muted.withOpacity(0.15)),
                      ),
                      child: Text('En Ligne',
                          style: GoogleFonts.spaceGrotesk(color: _secondary, fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
              if (widget.embedded && _activeRoomId.isNotEmpty)
                Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(color: _bg, border: Border(bottom: BorderSide(color: _muted.withOpacity(0.15)))),
                  child: Row(
                    children: [
                      Text(
                        _selectedDesignerDetails?['name'] ?? 'Conversation',
                        style: GoogleFonts.inter(color: _text, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _closeConversation,
                        tooltip: 'Quitter la conversation',
                        icon: const Icon(Icons.close, color: _muted, size: 18),
                      ),
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
                              
                              if (m['attachmentUrl'] != null && m['attachmentUrl'].toString().isNotEmpty) ...[
                                const SizedBox(height: 5),
                                if (m['attachmentType'] == 'image')
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      '${ApiService.baseUrl.replaceAll('/api', '')}${m['attachmentUrl']}',
                                      width: 200,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                else if (m['attachmentType'] == 'document')
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.black12,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: _muted.withOpacity(0.3)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.insert_drive_file, color: Colors.white70, size: 24),
                                        const SizedBox(width: 8),
                                        Text('Document joint', style: GoogleFonts.inter(color: Colors.white70, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                const SizedBox(height: 5),
                              ],

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
                          onPressed: _showExtrasOptions,
                          icon: const Icon(Icons.add_circle_outline, color: _muted),
                        ),
                        IconButton(
                          onPressed: () => _pickAndUploadFile(isImage: false),
                          icon: const Icon(Icons.description_outlined, color: _muted),
                        ),
                        IconButton(
                          onPressed: () => _pickAndUploadFile(isImage: true),
                          icon: const Icon(Icons.photo_library_outlined, color: _muted),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _input,
                            enabled: _activeRoomId.isNotEmpty,
                            onChanged: (v) {
                              if (!mounted) return;
                              setState(() => _isTyping = v.trim().isNotEmpty);
                            },
                            style: GoogleFonts.inter(color: _text),
                            decoration: InputDecoration(
                              hintText: _activeRoomId.isEmpty ? 'Sélectionnez une conversation...' : 'Rédiger votre message technique...',
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
                          onPressed: _activeRoomId.isNotEmpty ? _send : null,
                          style: ElevatedButton.styleFrom(backgroundColor: _activeRoomId.isNotEmpty ? _primary : _muted.withOpacity(0.3)),
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
        
        // Right Sidebar (Designer Info)
        if (isDesktop && _activeRoomId.isNotEmpty) Container(
          width: 300,
          color: _low,
          padding: const EdgeInsets.all(24),
          child: _selectedDesignerDetails == null 
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    Text('INFORMATIONS CONCEPTEUR',
                        style: GoogleFonts.spaceGrotesk(color: _muted, fontSize: 11, letterSpacing: 1.2)),
                    const SizedBox(height: 20),
                    const Center(child: CircularProgressIndicator(color: _primary)),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    Text('INFORMATIONS CONCEPTEUR',
                        style: GoogleFonts.spaceGrotesk(color: _muted, fontSize: 11, letterSpacing: 1.2)),
                    const SizedBox(height: 32),
                    Center(
                      child: CircleAvatar(
                        radius: 40,
                        backgroundColor: _primary.withOpacity(0.2),
                        child: Text(_selectedDesignerDetails!['name']?[0]?.toUpperCase() ?? 'C', 
                           style: const TextStyle(color: _primary, fontSize: 24, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Text(_selectedDesignerDetails!['name'] ?? 'Concepteur',
                          style: GoogleFonts.inter(color: _text, fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    if (_selectedDesignerDetails!['specialite'] != null && _selectedDesignerDetails!['specialite'].toString().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Center(
                        child: Text(_selectedDesignerDetails!['specialite'],
                            style: GoogleFonts.inter(color: _secondary, fontSize: 14)),
                      ),
                    ],
                    const SizedBox(height: 40),
                    Text('MACHINES ASSIGNÉES',
                        style: GoogleFonts.spaceGrotesk(color: _muted, fontSize: 11, letterSpacing: 1.2)),
                    const SizedBox(height: 16),
                    if ((_selectedDesignerDetails!['machines'] as List? ?? []).isEmpty)
                       Text('Aucune machine', style: GoogleFonts.inter(color: _muted, fontSize: 13))
                    else
                       ...(_selectedDesignerDetails!['machines'] as List).map((m) => Container(
                         margin: const EdgeInsets.only(bottom: 8),
                         padding: const EdgeInsets.all(12),
                         decoration: BoxDecoration(
                           color: _highest.withOpacity(0.4),
                           borderRadius: BorderRadius.circular(8),
                           border: Border.all(color: _muted.withOpacity(0.1)),
                         ),
                         child: Row(
                           children: [
                             const Icon(Icons.precision_manufacturing, color: _primary, size: 16),
                             const SizedBox(width: 12),
                             Expanded(child: Text(m.toString(), style: GoogleFonts.inter(color: _text, fontSize: 13))),
                           ],
                         ),
                       )),
                  ],
                ),
        ),
      ],
    );

    if (widget.embedded) return body;

    return Scaffold(
      backgroundColor: _bg,
      body: body,
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
