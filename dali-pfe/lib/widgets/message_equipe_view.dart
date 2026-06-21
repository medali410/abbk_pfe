import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../services/api_service.dart';
import 'voice_player_widget.dart';

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
  static const _bg = Color(0xFF080D14);
  static const _sidebar = Color(0xFF0D1526);
  static const _header = Color(0xFF0F1C31);
  static const _itemActive = Color(0xFF162240);
  static const _myBubble = Color(0xFF1A3A6E);
  static const _otherBubble = Color(0xFF0F1C31);
  static const _text = Color(0xFFE2E8F0);
  static const _muted = Color(0xFF6B869A);
  static const _accent = Color(0xFF3B82F6);
  static const _secondary = Color(0xFF3B82F6);
  static const _primary = Color(0xFF3B82F6);
  static const _highest = Color(0xFF162035);
  static const _error = Color(0xFFF15C6D);
  static const _low = Color(0xFF080D14);
  static const _high = Color(0xFF202C33);
  static const _container = Color(0xFF111B21);

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
  bool _isLocating = false;
  
  // Voice Recording State
  bool _isRecording = false;
  String? _recordingPath;
  final AudioRecorder _audioRecorder = AudioRecorder();
  Timer? _recordingTimer;
  Timer? _pollingTimer;
  int _recordingDurationSeconds = 0;

  final ScrollController _messagesScroll = ScrollController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  int get _currentUserId {
    final userRole = ApiService.savedUserRole?.toLowerCase();
    final isConcepteur = userRole == 'concepteur' || (userRole == 'conception' && !ApiService.isSuperAdmin);
    if (isConcepteur) {
      final myProfile = ApiService.savedConcepteurProfile;
      if (myProfile != null) {
        final idStr = (myProfile['id'] ?? myProfile['_id'] ?? myProfile['concepteurId'] ?? myProfile['userId'] ?? '').toString();
        final id = int.tryParse(idStr);
        if (id != null) return id;
      }
    }
    if (_senderRole == 'technician' && _technicianId.isNotEmpty) {
      return int.tryParse(_technicianId) ?? 1;
    }
    if (_senderRole == 'client' && _clientId.isNotEmpty) {
      return int.tryParse(_clientId) ?? 1;
    }
    return 1;
  }
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
        final role = ApiService.savedUserRole!.toLowerCase();
        final isConcepteur = role == 'concepteur' || (role == 'conception' && !ApiService.isSuperAdmin);
        if (role == 'admin' || role == 'superadmin') {
          _senderRole = 'conception';
          _senderName = 'Administrateur';
        } else if (isConcepteur) {
          _senderRole = 'conception';
          _senderName = ApiService.savedConcepteurProfile?['name'] ?? 'Concepteur';
        } else {
          _senderRole = role;
        }
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
    _audioRecorder.dispose();
    _recordingTimer?.cancel();
    _pollingTimer?.cancel();
    super.dispose();
  }

  String _resolveDesignerName(Map<String, dynamic> c) {
    // 1. Try direct fields from the conversation object
    String n = (c['name'] ?? c['displayName'] ?? c['concepteurName'] ?? c['technicianName'] ?? c['clientName'] ?? c['concepteur_name'] ?? c['technician_name'] ?? '').toString();
    
    // 2. If name is missing or is generic "Administrateur", look into participants
    if (n.isEmpty || n.toLowerCase().contains('admin')) {
      final participants = c['participants'] as List?;
      if (participants != null && participants.isNotEmpty) {
        try {
          // Priority A: Find a participant by role (Designer/Technician/etc.)
          Map<String, dynamic>? other;
          final targetRoles = {'conception', 'technician', 'technologique', 'maintenance', 'concepteur', 'designer', 'user'};
          for (final p in participants) {
            final role = (p['role'] ?? p['userRole'] ?? p['user_role'] ?? p['type'] ?? p['status'] ?? '').toString().toLowerCase();
            if (targetRoles.contains(role)) {
              other = Map<String, dynamic>.from(p as Map);
              // If this is a valid role but the name is still "admin", keep looking for a better one
              final nameCheck = (other['fullName'] ?? other['userName'] ?? other['name'] ?? '').toString().toLowerCase();
              if (nameCheck.contains('admin')) {
                other = null;
                continue;
              }
              break;
            }
          }

          // Priority B: Find anyone who is NOT the current user and NOT "admin"
          other ??= Map<String, dynamic>.from(
            (participants.firstWhere(
              (p) {
                final uname = (p['userName'] ?? p['user_name'] ?? p['name'] ?? p['full_name'] ?? p['fullName'] ?? '').toString().toLowerCase();
                final currentLow = _senderName.toLowerCase();
                return uname != currentLow && !uname.contains('admin');
              },
              orElse: () => participants.first,
            )) as Map,
          );

          // Priority C: Resolve the string name from the found participant (check every possible field)
          final first = (other['firstName'] ?? other['first_name'] ?? other['prenom'] ?? '').toString();
          final last = (other['lastName'] ?? other['last_name'] ?? other['nom'] ?? '').toString();
          if (first.isNotEmpty || last.isNotEmpty) {
            n = '$first $last'.trim();
          } else {
            final foundName = (other['fullName'] ?? other['full_name'] ?? other['userName'] ?? other['user_name'] ?? 
                 other['name'] ?? other['displayName'] ?? other['display_name'] ?? '').toString();
            if (foundName.isNotEmpty) n = foundName;
          }
        } catch (_) {}
      }
    }
    
    // Final check: if it still contains admin, but we have NO other choice, just use it.
    // Or if n is completely empty, use 'Discussion'
    return n.isNotEmpty ? n : 'Discussion';
  }

  Future<void> _initChat() async {
    _socket = io.io(ApiService.socketBaseUrl, <String, dynamic>{
      'transports': <String>['websocket'],
      'autoConnect': true,
    });
    _socket!.onConnect((_) {
      debugPrint('⚡ Chat Socket connecté: ${_socket!.id}');
      if (_activeRoomId.isNotEmpty) {
        _socket!.emit('join_chat_room', {'roomId': _activeRoomId});
      }
    });
    _socket!.onConnectError((err) => debugPrint('❌ Chat ConnectError: $err'));
    _socket!.onError((err) => debugPrint('❌ Chat Error: $err'));
    _socket!.onDisconnect((_) => debugPrint('❌ Chat Disconnect'));
    _socket!.on('chat_message', (raw) {
      try {
        final data = raw is String ? jsonDecode(raw) : raw;
        if (data is! Map) return;
        final m = Map<String, dynamic>.from(data);
        
        final rId = (m['roomId'] ?? '').toString();
        final textVal = (m['text'] ?? '').toString();
        final timeVal = (m['createdAt'] ?? DateTime.now().toIso8601String()).toString();
        final senderVal = (m['senderName'] ?? '').toString();
        _updateConversationLastMessage(rId, textVal, timeVal, senderVal);

        if (rId != _activeRoomId) return;
        final fromMe = senderVal == _senderName &&
            (m['from'] ?? '').toString() == _senderRole;
        if (fromMe) return;
        if (!mounted) return;
        setState(() => _messages.add(m));
        _scrollToLatest();
      } catch (_) {}
    });
    _socket!.on('delete_message', (raw) {
      try {
        final data = raw is String ? jsonDecode(raw) : raw;
        if (data is! Map) return;
        final roomId = (data['roomId'] ?? '').toString();
        if (roomId != _activeRoomId) return;
        final msgId = (data['messageId'] ?? '').toString();
        if (msgId.isNotEmpty && mounted) {
          setState(() {
            _messages.removeWhere((m) => (m['id'] ?? '').toString() == msgId);
          });
        }
      } catch (_) {}
    });
    _socket!.on('clear_chat', (raw) {
      try {
        final data = raw is String ? jsonDecode(raw) : raw;
        if (data is! Map) return;
        final roomId = (data['roomId'] ?? '').toString();
        if (roomId == _activeRoomId && mounted) {
          _closeConversation();
        }
      } catch (_) {}
    });

    if (_socket!.connected && _activeRoomId.isNotEmpty) {
      _socket!.emit('join_chat_room', {'roomId': _activeRoomId});
    }

    try {
      final userRole = ApiService.savedUserRole?.toLowerCase();
      final isConcepteur = userRole == 'concepteur' || (userRole == 'conception' && !ApiService.isSuperAdmin);

      if (isConcepteur) {
        final myProfile = ApiService.savedConcepteurProfile;
        final myConcepteurId = myProfile != null ? (myProfile['id'] ?? myProfile['_id'] ?? '').toString() : '';
        final adminRoom = 'chat_conception_$myConcepteurId';
        
        final list = <Map<String, dynamic>>[];
        
        list.add({
          'roomId': adminRoom,
          'name': 'Admin',
          'lastText': 'Discuter avec l\'administrateur',
          'lastAt': DateTime.now().toIso8601String(),
          'senderName': 'Admin',
          'roleLabel': 'Admin',
        });
        
        try {
          final clients = await ApiService.getClients();
          for (final c in clients) {
            final clientId = (c['clientId'] ?? c['id'] ?? '').toString();
            final clientName = (c['nom'] ?? c['name'] ?? 'Client').toString();
            if (clientId.isNotEmpty) {
              list.add({
                'roomId': 'chat_client_${clientId}_conception_${myConcepteurId}',
                'name': clientName,
                'lastText': 'Ouvrir la discussion',
                'lastAt': DateTime.now().toIso8601String(),
                'senderName': '',
                'roleLabel': 'Client',
              });
            }
          }
        } catch (_) {}

        try {
          final concepteurs = await ApiService.getConcepteurs();
          for (final c in concepteurs) {
            final otherConcepteurId = (c['concepteurId'] ?? c['id'] ?? '').toString();
            final concepteurName = (c['nom'] ?? c['name'] ?? 'Concepteur').toString();
            if (otherConcepteurId.isNotEmpty && otherConcepteurId != myConcepteurId) {
              final sortedIds = [myConcepteurId, otherConcepteurId]..sort();
              list.add({
                'roomId': 'chat_concep_${sortedIds[0]}_${sortedIds[1]}',
                'name': concepteurName,
                'lastText': 'Ouvrir la discussion',
                'lastAt': DateTime.now().toIso8601String(),
                'senderName': '',
                'roleLabel': 'Concepteur',
              });
            }
          }
        } catch (_) {}

        try {
          final maintenance = await ApiService.getMaintenanceAgents();
          for (final m in maintenance) {
            final agentId = (m['maintenanceAgentId'] ?? m['id'] ?? '').toString();
            final agentName = (m['nom'] ?? m['name'] ?? '${m['firstName'] ?? ''} ${m['lastName'] ?? ''}'.trim()).toString();
            if (agentId.isNotEmpty) {
              list.add({
                'roomId': 'chat_maintenance_${agentId}_conception_${myConcepteurId}',
                'name': agentName.isNotEmpty ? agentName : 'Agent Maintenance',
                'lastText': 'Ouvrir la discussion',
                'lastAt': DateTime.now().toIso8601String(),
                'senderName': '',
                'roleLabel': 'Maintenance',
              });
            }
          }
        } catch (_) {}
        
        _conversations = list;
        if (mounted) setState(() {});
        
        // Load last message in background
        for (final conv in _conversations) {
          try {
            final messages = await ApiService.getChatMessages(conv['roomId'], limit: 1);
            if (messages.isNotEmpty) {
              conv['lastText'] = messages.first['text'] ?? '';
              conv['lastAt'] = messages.first['createdAt'] ?? '';
              conv['senderName'] = messages.first['senderName'] ?? '';
            }
          } catch (_) {}
        }
        if (mounted) setState(() {});
        
        await _switchConversation(_conversations.first);
      } else if (_senderRole == 'client') {
        if (_clientId.isNotEmpty) {
          _conversations = await ApiService.getClientConversations(_clientId);
        }
      } else if (_senderRole == 'conception') {
        // ── Admin : charger techniciens, agents de maintenance et clients ──
        final list = <Map<String, dynamic>>[];

        // ── SECTION : Techniciens ──
        list.add({
          'roomId': '__section_tech__',
          'isSectionHeader': true,
          'sectionLabel': 'TECHNICIENS',
          'sectionIcon': 'engineering',
          'sectionColor': 'purple',
        });
        try {
          final techs = await ApiService.getTechnicians();
          for (final t in techs) {
            final techId = (t['technicianId'] ?? t['id'] ?? '').toString();
            final firstName = (t['firstName'] ?? '').toString();
            final lastName  = (t['lastName']  ?? '').toString();
            final fullName  = '$firstName $lastName'.trim();
            if (techId.isEmpty) continue;
            list.add({
              'roomId': 'chat_admin_tech_$techId',
              'name': fullName.isNotEmpty ? fullName : 'Technicien',
              'subId': techId,
              'roleLabel': 'Technicien',
              'lastText': 'Ouvrir la discussion',
              'lastAt': DateTime.now().toIso8601String(),
              'senderName': '',
            });
          }
        } catch (_) {}

        // ── SECTION : Agents de Maintenance ──
        list.add({
          'roomId': '__section_maint__',
          'isSectionHeader': true,
          'sectionLabel': 'AGENTS DE MAINTENANCE',
          'sectionIcon': 'support_agent',
          'sectionColor': 'blue',
        });
        try {
          final agents = await ApiService.getMaintenanceAgents();
          for (final a in agents) {
            final agentId   = (a['maintenanceAgentId'] ?? a['id'] ?? '').toString();
            final firstName = (a['firstName'] ?? a['nom'] ?? '').toString();
            final lastName  = (a['lastName']  ?? '').toString();
            final fullName  = '$firstName $lastName'.trim();
            if (agentId.isEmpty) continue;
            list.add({
              'roomId': 'chat_admin_maint_$agentId',
              'name': fullName.isNotEmpty ? fullName : 'Agent Maintenance',
              'subId': agentId,
              'roleLabel': 'Maintenance',
              'lastText': 'Ouvrir la discussion',
              'lastAt': DateTime.now().toIso8601String(),
              'senderName': '',
            });
          }
        } catch (_) {}

        // ── SECTION : Clients ──
        list.add({
          'roomId': '__section_clients__',
          'isSectionHeader': true,
          'sectionLabel': 'CLIENTS',
          'sectionIcon': 'groups',
          'sectionColor': 'green',
        });
        try {
          final clients = await ApiService.getClients();
          for (final c in clients) {
            final clientId   = (c['clientId'] ?? c['id'] ?? '').toString();
            final clientName = (c['nom'] ?? c['name'] ?? c['companyName'] ?? '').toString();
            if (clientId.isEmpty) continue;
            list.add({
              'roomId': 'chat_admin_client_$clientId',
              'name': clientName.isNotEmpty ? clientName : 'Client',
              'subId': clientId,
              'roleLabel': 'Client',
              'lastText': 'Ouvrir la discussion',
              'lastAt': DateTime.now().toIso8601String(),
              'senderName': '',
            });
          }
        } catch (_) {}

        _conversations = list;
        if (mounted) setState(() {});

        // Charger le dernier message pour chaque conversation (non-header)
        for (final conv in _conversations) {
          if (conv['isSectionHeader'] == true) continue;
          try {
            final msgs = await ApiService.getChatMessages(conv['roomId'], limit: 1);
            if (msgs.isNotEmpty) {
              conv['lastText']   = msgs.first['text'] ?? '';
              conv['lastAt']     = msgs.first['createdAt'] ?? '';
              conv['senderName'] = msgs.first['senderName'] ?? '';
            }
          } catch (_) {}
        }
        if (mounted) setState(() {});
        return; // évite le bloc générique ci-dessous
      } else {
        if (_technicianId.isNotEmpty) {
          final allConvs = await ApiService.getTechnicianConversations(_technicianId);
          _conversations = allConvs.where((c) {
            final roomId = (c['roomId'] ?? '').toString();
            if (_technicianId.isNotEmpty && !roomId.contains(_technicianId)) return false;
            return true;
          }).toList();
        }
      }
      
      // Load last message and resolve names for ALL roles
      for (final conv in _conversations) {
        final roomName = (conv['name'] ?? conv['roomId'] ?? '').toString();
        // If name is raw roomId, try to make it prettier
        if (roomName.startsWith('chat_')) {
          final parts = roomName.split('_');
          if (parts.length >= 3) {
            // chat_maintenance_1_TEC -> Admin 1, etc.
            conv['name'] = 'Contact ${parts[2]}';
          }
        }
        
        try {
          final messages = await ApiService.getChatMessages(conv['roomId'], limit: 1);
          if (messages.isNotEmpty) {
            conv['lastText'] = messages.first['text'] ?? '';
            conv['lastAt'] = messages.first['createdAt'] ?? '';
            conv['senderName'] = messages.first['senderName'] ?? '';
          } else {
            conv['lastText'] = 'Aucun message';
          }
        } catch (_) {}
      }

      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _switchConversation(Map<String, dynamic> c) async {
    final room = (c['roomId'] ?? '').toString();
    if (room.isEmpty) return;
    _activeRoomId = room;
    _socket?.emit('join_chat_room', {'roomId': room});

    final userRole = ApiService.savedUserRole?.toLowerCase();
    final isConcepteur = userRole == 'concepteur' || (userRole == 'conception' && !ApiService.isSuperAdmin);

    if (isConcepteur) {
      if (mounted) {
        setState(() {
          _selectedDesignerDetails = {
            'name': (c['name'] ?? 'Admin').toString(),
            'specialite': (c['roleLabel'] ?? '').toString(),
            'machines': <String>[],
          };
        });
      }
    } else {
      // Resolve designer details: find the designer/technician participant (not the admin)
      String designerName = _resolveDesignerName(c);

      if (designerName.isNotEmpty && !designerName.toLowerCase().contains('admin')) {
        // Try to search for the designer first for full profile info
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
            // Fallback: build minimal info from resolved name
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
        // Fallback: show whatever name we resolved
        if (mounted) {
          setState(() {
            _selectedDesignerDetails = {
              'name': designerName.isNotEmpty ? designerName : 'Discussion',
              'specialite': '',
              'machines': <String>[],
            };
          });
        }
      }
    }

    try {
      _messages = await ApiService.getChatMessages(room, limit: 300);
      if (mounted) setState(() {});
      _scrollToLatest();
      _startPolling();
    } catch (_) {}
  }

  void _closeConversation() {
    _pollingTimer?.cancel();
    if (mounted) {
      setState(() {
        _activeRoomId = '';
        _messages = [];
        _selectedDesignerDetails = null;
      });
    }
  }

  Future<void> _deleteConversation() async {
    if (_activeRoomId.isEmpty) return;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _low,
        title: Text('Effacer la discussion', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Voulez-vous vraiment supprimer tout l\'historique de cette discussion ? Cette action est irréversible.', 
          style: GoogleFonts.inter(color: _muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ANNULER', style: TextStyle(color: _muted))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('EFFACER', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ApiService.deleteChatRoom(_activeRoomId);
      _socket?.emit('clear_chat', {
        'roomId': _activeRoomId,
      });
      _closeConversation();
      await _initChat(); // Refresh list
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
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

    final currentUserId = _currentUserId;
    final payload = {
      'roomId': _activeRoomId,
      'from': _senderRole,
      'userId': currentUserId,
      'senderName': _senderName,
      'text': text,
    };

    // 1. Emit socket event instantly for real-time delivery
    _socket?.emit('chat_message', payload);

    // 2. Post to DB via REST API in background
    ApiService.postChatMessage(payload).catchError((err) {
      debugPrint('REST chat message failed: $err');
    });

    _input.clear();
    if (mounted) setState(() => _isTyping = false);
    _updateConversationLastMessage(
      _activeRoomId,
      text,
      DateTime.now().toIso8601String(),
      _senderName,
    );
    _scrollToLatest();
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 800), (timer) {
      if (_activeRoomId.isNotEmpty) {
        _pollMessages();
      }
    });
  }

  Future<void> _pollMessages() async {
    try {
      final latest = await ApiService.getChatMessages(_activeRoomId, limit: 300);
      if (latest.length != _messages.length && mounted) {
        setState(() {
          _messages = latest;
        });
        _scrollToLatest();
      }
    } catch (_) {}
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

        final currentUserId = _currentUserId;

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

  Future<void> _shareRealLocation() async {
    if (_isLocating) return;
    if (mounted) setState(() => _isLocating = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Permission de localisation refusée.'),
                duration: Duration(seconds: 10),
              ),
            );
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Localisation désactivée. Veuillez l\'activer dans les paramètres.'),
              duration: const Duration(seconds: 10),
              action: SnackBarAction(
                label: 'PARAMÈTRES',
                onPressed: () => Geolocator.openAppSettings(),
              ),
            ),
          );
        }
        return;
      }

      // Attempt real location with fallbacks
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );
      } catch (e) {
        debugPrint('High accuracy failed, trying last known... $e');
        position = await Geolocator.getLastKnownPosition();
      }

      if (position != null) {
        final locationText = 'Position GPS: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
        _sendMockText(locationText);
      } else {
        throw FormatException('Impossible d\'obtenir une position (Time-out or No Signal)');
      }
    } catch (e) {
      debugPrint('Erreur localisation: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Erreur: Signal GPS trop faible ou désactivé.'),
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
              label: 'RÉESSAYER',
              onPressed: _shareRealLocation,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }


  Future<void> _startVoiceRecording() async {
    if (!await _audioRecorder.hasPermission()) return;
    
    final dir = await getTemporaryDirectory();
    final filePath = path.join(dir.path, 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a');
    
    await _audioRecorder.start(const RecordConfig(), path: filePath);
    
    if (mounted) {
      setState(() {
        _isRecording = true;
        _recordingPath = filePath;
        _recordingDurationSeconds = 0;
      });
      
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() => _recordingDurationSeconds++);
        }
      });
    }
  }

  Future<void> _stopVoiceRecording() async {
    _recordingTimer?.cancel();
    final finalPath = await _audioRecorder.stop();
    
    if (finalPath != null && mounted) {
      final file = File(finalPath);
      final bytes = await file.readAsBytes();
      final base64Data = base64Encode(bytes);
      
      setState(() {
        _isRecording = false;
        _recordingPath = null;
      });

      final url = await ApiService.uploadChatAttachment(
        base64Data: base64Data,
        filename: path.basename(finalPath),
      );

      if (url != null) {
        final localMessage = <String, dynamic>{
          'roomId': _activeRoomId,
          'from': _senderRole,
          'senderName': _senderName,
          'text': '[Message Vocal]',
          'attachmentUrl': url,
          'attachmentType': 'audio',
          'createdAt': DateTime.now().toIso8601String(),
        };

        if (mounted) {
          setState(() => _messages.add(localMessage));
          _scrollToLatest();
        }

        final currentUserId = _currentUserId;

        _socket?.emit('chat_message', {
          'roomId': _activeRoomId,
          'from': _senderRole,
          'userId': currentUserId,
          'senderName': _senderName,
          'text': '[Message Vocal]',
          'attachmentUrl': url,
          'attachmentType': 'audio',
        });
      }
    }
  }

  Future<void> _cancelVoiceRecording() async {
    _recordingTimer?.cancel();
    await _audioRecorder.stop();
    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordingPath = null;
      });
    }
  }

  Future<void> _deleteMessage(dynamic messageId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text('Supprimer ?', style: GoogleFonts.inter(color: Colors.white)),
        content: Text('Voulez-vous vraiment supprimer ce message ?', style: GoogleFonts.inter(color: _muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('ANNULER', style: TextStyle(color: _muted))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('SUPPRIMER', style: TextStyle(color: _error))),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ApiService.deleteChatMessage(messageId.toString());
        setState(() {
          _messages.removeWhere((m) => (m['id'] ?? '').toString() == messageId.toString());
        });
        _socket?.emit('delete_message', {
          'roomId': _activeRoomId,
          'messageId': messageId.toString(),
        });
      } catch (e) {
        debugPrint('Erreur suppression: $e');
      }
    }
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
    final currentUserId = _currentUserId;

    _socket?.emit('chat_message', {
      'roomId': _activeRoomId,
      'from': _senderRole,
      'userId': currentUserId,
      'senderName': _senderName,
      'text': txt,
    });
    _updateConversationLastMessage(
      _activeRoomId,
      txt,
      DateTime.now().toIso8601String(),
      _senderName,
    );
    _scrollToLatest();
  }

  Future<void> _doSearch(String q) async {
    if (q.trim().isEmpty) {
      if (mounted) setState(() { _searchResults = []; _isSearching = false; });
      return;
    }
    if (mounted) setState(() => _isSearching = true);

    final userRole = ApiService.savedUserRole?.toLowerCase();
    final isConcepteur = userRole == 'concepteur' || (userRole == 'conception' && !ApiService.isSuperAdmin);
    if (isConcepteur && _conversations.isNotEmpty) {
      final query = q.trim().toLowerCase();
      final matches = _conversations.where((c) {
        final name = (c['name'] ?? '').toString().toLowerCase();
        final role = (c['roleLabel'] ?? '').toString().toLowerCase();
        return name.contains(query) || role.contains(query);
      }).toList();
      if (mounted) {
        setState(() {
          _searchResults = matches.map((m) => {
            'id': m['roomId'],
            'roomId': m['roomId'],
            'name': m['name'],
            'roleLabel': m['roleLabel'] ?? 'Contact',
          }).toList();
          _isSearching = false;
        });
      }
      return;
    }

    try {
      final results = await ApiService.searchConcepteurs(q);
      if (mounted) setState(() { _searchResults = results; _isSearching = false; });
    } catch (_) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _startChatWith(Map<String, dynamic> contact) {
    final room = (contact['roomId'] ?? contact['id'] ?? '').toString();
    final name = (contact['name'] ?? 'Contact').toString();
    final role = (contact['roleLabel'] ?? contact['specialite'] ?? '').toString();
    
    if (mounted) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
        _searchController.clear();
        _selectedDesignerDetails = {
          'name': name,
          'specialite': role,
          'machines': <String>[],
        };
      });
    }

    _switchConversation({
      'roomId': room,
      'name': name,
    });
  }

  String _fmtTime(dynamic raw) {
    final dt = DateTime.tryParse((raw ?? '').toString());
    if (dt == null) return '--:--';
    final d = dt.toLocal();
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  void _updateConversationLastMessage(String roomId, String text, String createdAt, String senderName) {
    if (!mounted) return;
    setState(() {
      final index = _conversations.indexWhere((c) => c['roomId'] == roomId);
      if (index != -1) {
        final conv = Map<String, dynamic>.from(_conversations[index]);
        conv['lastText'] = text;
        conv['lastAt'] = createdAt;
        conv['senderName'] = senderName;
        
        _conversations.removeAt(index);
        _conversations.insert(0, conv);
      }
    });
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
    
    final showSidebar = isDesktop || _activeRoomId.isEmpty;
    final showChat = isDesktop || _activeRoomId.isNotEmpty;

    final sidebarContent = Container(
      width: isDesktop ? 320 : null,
      decoration: BoxDecoration(
        color: _low,
        border: Border(right: BorderSide(color: Colors.white.withOpacity(0.05), width: 1)),
      ),
      child: Column(
            children: [
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('MESSAGERIE',
                        style: GoogleFonts.spaceGrotesk(
                          color: _accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                        )),
                    const SizedBox(height: 16),
                    Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                        boxShadow: [
                          BoxShadow(
                            color: _accent.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _searchController,
                        onChanged: _doSearch,
                        style: GoogleFonts.inter(color: _text, fontSize: 13, fontWeight: FontWeight.w500),
                        decoration: InputDecoration(
                          hintText: 'Rechercher un contact...',
                          hintStyle: GoogleFonts.inter(color: _muted.withOpacity(0.3), fontSize: 13),
                          icon: Icon(Icons.search_rounded, color: _accent, size: 22),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Divider(color: Colors.white10),
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
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _conversations.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 2),
                          itemBuilder: (context, i) {
                            final c = _conversations[i];
                            final room = (c['roomId'] ?? '').toString();
                            final active = room == _activeRoomId;
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                              child: Stack(
                                children: [
                                  Material(
                                    color: active ? _accent.withOpacity(0.08) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(16),
                                    child: InkWell(
                                      onTap: () => _switchConversation(c),
                                      borderRadius: BorderRadius.circular(16),
                                      hoverColor: Colors.white.withOpacity(0.04),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: active ? _accent.withOpacity(0.3) : Colors.transparent,
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Stack(
                                              children: [
                                                 _avatar(
                                                  name: _resolveDesignerName(c),
                                                  size: 46,
                                                ),
                                                Positioned(
                                                  right: 0,
                                                  bottom: 0,
                                                  child: Container(
                                                    width: 12,
                                                    height: 12,
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF22C55E),
                                                      shape: BoxShape.circle,
                                                      border: Border.all(color: _low, width: 2),
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
                                                         child: Text(
                                                          _resolveDesignerName(c),
                                                          style: GoogleFonts.inter(
                                                            color: active ? Colors.white : _text,
                                                            fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                                                            fontSize: 14.5,
                                                          ),
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                      Text(_fmtTime(c['lastAt']),
                                                          style: GoogleFonts.inter(
                                                            color: active ? _accent : _muted.withOpacity(0.5),
                                                            fontSize: 10,
                                                            fontWeight: active ? FontWeight.w700 : FontWeight.normal
                                                          )),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    (c['lastText'] ?? 'Ouvrir la discussion').toString(),
                                                    style: GoogleFonts.inter(
                                                      color: active ? Colors.white.withOpacity(0.8) : _muted.withOpacity(0.7),
                                                      fontSize: 12,
                                                      fontWeight: active ? FontWeight.w500 : FontWeight.normal
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (active)
                                    Positioned(
                                      left: 0,
                                      top: 16,
                                      bottom: 16,
                                      child: Container(
                                        width: 3,
                                        decoration: BoxDecoration(
                                          color: _accent,
                                          borderRadius: BorderRadius.circular(4),
                                          boxShadow: [
                                            BoxShadow(
                                              color: _accent.withOpacity(0.6),
                                              blurRadius: 4,
                                              spreadRadius: 1,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
              ),
            ],
          ),
    );

    final body = Row(
      children: [
        if (showSidebar)
          isDesktop ? sidebarContent : Expanded(child: sidebarContent),
        
        if (showChat)
          Expanded(
            child: Column(
            children: [
              if (_activeRoomId.isNotEmpty)
                Container(
                  height: 60,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: const BoxDecoration(
                    color: _header,
                    border: Border(left: BorderSide(color: Colors.white10, width: 0.5)),
                  ),
                  child: Row(
                    children: [
                      if (!isDesktop) ...[
                        IconButton(
                          onPressed: _closeConversation,
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                        ),
                        const SizedBox(width: 8),
                      ],
                      _avatar(name: _selectedDesignerDetails?['name']?.toString() ?? 'C', size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _selectedDesignerDetails?['name'] ?? 'Discussion',
                              style: GoogleFonts.inter(color: _text, fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                            Text('en ligne', style: GoogleFonts.inter(color: _accent, fontSize: 11)),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _closeConversation,
                        icon: const Icon(Icons.close, color: _muted, size: 20),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: _bg,
                    image: DecorationImage(
                      image: const NetworkImage('https://user-images.githubusercontent.com/15075759/28719144-86dc0f70-73b1-11e7-911d-60d70fcded21.png'),
                      repeat: ImageRepeat.repeat,
                      opacity: 0.06,
                      colorFilter: ColorFilter.mode(_bg.withOpacity(0.9), BlendMode.dstATop),
                    ),
                  ),
                  child: ListView.builder(
                    controller: _messagesScroll,
                    padding: const EdgeInsets.all(20),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) {
                      final m = _messages[i];
                      final sender = (m['senderName'] ?? 'User').toString();
                      final text = (m['text'] ?? '').toString();
                      final fromRole = (m['from'] ?? '').toString().toLowerCase();

                      final userRole = ApiService.savedUserRole?.toLowerCase();
                      final isConcepteur = userRole == 'concepteur' || (userRole == 'conception' && !ApiService.isSuperAdmin);

                      final bool mine = sender.trim().toLowerCase() == _senderName.trim().toLowerCase();

                      final displaySender = isConcepteur ? 'Admin' : sender;
                      final critical = text.toLowerCase().contains('alerte critique');

                      return Align(
                        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: GestureDetector(
                          onLongPress: mine && m['id'] != null ? () => _deleteMessage(m['id']) : null,
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 540),
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: mine ? _myBubble : _otherBubble,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.12),
                                  blurRadius: 1,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!mine) ...[
                                  Text(displaySender, style: GoogleFonts.inter(color: _accent, fontSize: 10, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 2),
                                ],
                                
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
                                    )
                                  else if (m['attachmentType'] == 'audio')
                                    VoicePlayerWidget(
                                      url: '${ApiService.baseUrl.replaceAll('/api', '')}${m['attachmentUrl']}',
                                      color: mine ? Colors.white : _primary,
                                    ),
                                  const SizedBox(height: 5),
                                ],

                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Flexible(child: Text(text, style: GoogleFonts.inter(color: _text, fontSize: 13.5))),
                                    const SizedBox(width: 8),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(_fmtTime(m['createdAt'] ?? m['at']), style: GoogleFonts.inter(color: _muted, fontSize: 9)),
                                        if (mine) ...[
                                          const SizedBox(width: 3),
                                          Icon(Icons.done_all, color: Colors.cyanAccent.withOpacity(0.6), size: 12),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );

                    },
                  ),
                ),
              ),
              if (_activeRoomId.isNotEmpty)
                Container(
                  color: _header,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: _isRecording 
                    ? Row(
                        children: [
                          IconButton(
                            onPressed: _cancelVoiceRecording,
                            icon: const Icon(Icons.delete_outline, color: _error, size: 26),
                            tooltip: 'Supprimer l\'enregistrement',
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: _highest,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: _primary.withOpacity(0.3)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.mic, color: _primary, size: 18),
                                  const SizedBox(width: 12),
                                  Text(
                                    '${(_recordingDurationSeconds ~/ 60).toString().padLeft(2, '0')}:${(_recordingDurationSeconds % 60).toString().padLeft(2, '0')}',
                                    style: GoogleFonts.spaceGrotesk(color: _text, fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  const Spacer(),
                                  Text('Enregistrement...', style: GoogleFonts.inter(color: _muted, fontSize: 13, fontStyle: FontStyle.italic)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            decoration: const BoxDecoration(
                              color: _primary,
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              onPressed: _stopVoiceRecording,
                              icon: const Icon(Icons.send, color: Colors.white, size: 22),
                              tooltip: 'Envoyer le message vocal',
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          IconButton(
                            onPressed: () => _pickAndUploadFile(isImage: true),
                            icon: const Icon(Icons.image_outlined, color: _muted, size: 24),
                            tooltip: 'Envoyer une image',
                          ),
                          IconButton(
                            onPressed: _isLocating ? null : _shareRealLocation,
                            icon: _isLocating
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: _accent,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.location_on_outlined, color: _muted, size: 24),
                            tooltip: 'Partager ma localisation',
                          ),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: _highest,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: TextField(
                                controller: _input,
                                onChanged: (v) => setState(() => _isTyping = v.trim().isNotEmpty),
                                style: GoogleFonts.inter(color: _text, fontSize: 15),
                                decoration: const InputDecoration(
                                  hintText: 'Taper un message',
                                  hintStyle: TextStyle(color: _muted),
                                  border: InputBorder.none,
                                ),
                                maxLines: 5,
                                minLines: 1,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            decoration: const BoxDecoration(
                              color: _primary,
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              onPressed: _isTyping ? _send : null,
                              icon: const Icon(Icons.send, color: Colors.white, size: 22),
                              tooltip: 'Envoyer',
                            ),
                          ),
                        ],
                      ),
                ),
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
                    const SizedBox(height: 40),
                    Text('ACTIONS',
                        style: GoogleFonts.spaceGrotesk(color: _muted, fontSize: 11, letterSpacing: 1.2)),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _deleteConversation,
                        icon: const Icon(Icons.delete_sweep_outlined, color: Colors.white, size: 18),
                        label: Text('Effacer la discussion', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent.withOpacity(0.12),
                          foregroundColor: Colors.redAccent,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.redAccent.withOpacity(0.3)),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
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

  Widget _avatar({required String name, double size = 40}) {
    final initials = name.isNotEmpty ? name[0].toUpperCase() : 'C';
    final colors = [
      const Color(0xFFF15C6D),
      const Color(0xFF00A884),
      const Color(0xFF51A5FE),
      const Color(0xFFFF6E00),
      const Color(0xFFA88DFF),
    ];
    final color = colors[name.length % colors.length];

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initials,
          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: size * 0.4),
        ),
      ),
    );
  }
}
