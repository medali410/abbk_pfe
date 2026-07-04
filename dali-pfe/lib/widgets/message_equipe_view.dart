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
import 'chat/chat_theme.dart';
import 'chat/chat_layout.dart';
import 'chat/chat_sidebar.dart';
import 'chat/chat_main_area.dart';
import 'chat/chat_info_panel.dart';

class MessageEquipeView extends StatefulWidget {
  final String? technicianId;
  final String? clientId;
  final String? senderName;
  final String? senderRole;
  final bool embedded;
  final String? initialRoomId;

  static String? currentActiveRoomId;

  const MessageEquipeView({
    super.key,
    this.technicianId,
    this.clientId,
    this.senderName,
    this.senderRole,
    this.embedded = false,
    this.initialRoomId,
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
  bool _remoteIsTyping = false;
  String _remoteTypingName = '';
  Timer? _typingDebounceTimer;
  Timer? _typingTimer;
  
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
    
    if (_technicianId.isEmpty && ApiService.savedTechnicianProfile != null) {
      final tProfile = ApiService.savedTechnicianProfile!;
      _technicianId = (tProfile['technicianId'] ?? tProfile['id'] ?? tProfile['_id'] ?? '').toString();
    }
    if (_clientId.isEmpty && ApiService.savedClientId != null) {
      _clientId = ApiService.savedClientId!;
    }
    
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

    if (_senderRole != 'client' && _senderRole != 'technician' &&
        _senderRole != 'conception' && _senderRole != 'maintenance') {
      _senderRole = 'technician';
    }

    if (widget.initialRoomId != null && widget.initialRoomId!.isNotEmpty) {
      _activeRoomId = widget.initialRoomId!;
      MessageEquipeView.currentActiveRoomId = _activeRoomId;
    }

    _initChat();
  }

  @override
  void dispose() {
    MessageEquipeView.currentActiveRoomId = null;
    _input.dispose();
    _searchController.dispose();
    _messagesScroll.dispose();
    _socket?.dispose();
    _audioRecorder.dispose();
    _recordingTimer?.cancel();
    _pollingTimer?.cancel();
    _typingDebounceTimer?.cancel();
    _typingTimer?.cancel();
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

        if (rId != _activeRoomId) {
          // Increment unread count if it's not the active room
          final idx = _conversations.indexWhere((c) => c['roomId'] == rId);
          if (idx >= 0 && mounted) {
            setState(() {
              _conversations[idx]['unreadCount'] = (_conversations[idx]['unreadCount'] ?? 0) + 1;
            });
          }
          return;
        }
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

    _socket!.on('typing', (raw) {
      try {
        final data = raw is String ? jsonDecode(raw) : raw;
        if (data is! Map) return;
        final roomId = (data['roomId'] ?? '').toString();
        if (roomId != _activeRoomId) return;
        if (!mounted) return;
        setState(() {
          _remoteIsTyping = true;
          _remoteTypingName = (data['senderName'] ?? '').toString();
        });
        _typingTimer?.cancel();
        _typingTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _remoteIsTyping = false);
        });
      } catch (_) {}
    });

    _socket!.on('stop_typing', (raw) {
      try {
        final data = raw is String ? jsonDecode(raw) : raw;
        if (data is! Map) return;
        final roomId = (data['roomId'] ?? '').toString();
        if (roomId != _activeRoomId) return;
        if (mounted) setState(() => _remoteIsTyping = false);
      } catch (_) {}
    });

    if (_socket!.connected && _activeRoomId.isNotEmpty) {
      _socket!.emit('join_chat_room', {'roomId': _activeRoomId});
    }

    try {
      final userRole = ApiService.savedUserRole?.toLowerCase();
      final isConcepteur = userRole == 'concepteur' || (userRole == 'conception' && !ApiService.isSuperAdmin);

      if (_senderRole == 'client') {
        if (_clientId.isNotEmpty) {
          final list = <Map<String, dynamic>>[];
          final contacts = await ApiService.getClientContacts();

          // Group by role
          final concepteurs = contacts.where((c) => c['role'] == 'conception').toList();
          final techs = contacts.where((c) => c['role'] == 'technician').toList();
          final agents = contacts.where((c) => c['role'] == 'maintenance').toList();

          list.add({'roomId': '__section_admin__', 'isSectionHeader': true, 'sectionLabel': 'SUPPORT GÉNÉRAL', 'sectionIcon': 'admin_panel_settings', 'sectionColor': 'red'});
          list.add({
            'roomId': 'chat_client_${_clientId}_admin', 'name': 'Administrateur',
            'subId': 'admin', 'roleLabel': 'Admin', 'lastText': 'Contacter le support', 'lastAt': DateTime.now().toIso8601String(), 'senderName': '',
            'role': 'admin'
          });

          if (concepteurs.isNotEmpty) {
            list.add({'roomId': '__section_concep__', 'isSectionHeader': true, 'sectionLabel': 'CONCEPTEURS', 'sectionIcon': 'engineering', 'sectionColor': 'purple'});
            for (final c in concepteurs) {
              list.add({
                'roomId': 'chat_client_${_clientId}_concepteur_${c['subId']}', 'name': c['name'], 'subId': c['subId'].toString(),
                'roleLabel': c['roleLabel'], 'lastText': 'Ouvrir la discussion', 'lastAt': DateTime.now().toIso8601String(), 'senderName': '',
                'machineId': c['machineId'], 'role': 'conception'
              });
            }
          }

          if (techs.isNotEmpty) {
            list.add({'roomId': '__section_tech__', 'isSectionHeader': true, 'sectionLabel': 'TECHNICIENS', 'sectionIcon': 'build', 'sectionColor': 'blue'});
            for (final t in techs) {
              list.add({
                'roomId': 'chat_client_${_clientId}_tech_${t['subId']}', 'name': t['name'], 'subId': t['subId'].toString(),
                'roleLabel': t['roleLabel'], 'lastText': 'Ouvrir la discussion', 'lastAt': DateTime.now().toIso8601String(), 'senderName': '',
                'machineId': t['machineId'], 'role': 'technician'
              });
            }
          }

          if (agents.isNotEmpty) {
            list.add({'roomId': '__section_maint__', 'isSectionHeader': true, 'sectionLabel': 'AGENTS DE MAINTENANCE', 'sectionIcon': 'support_agent', 'sectionColor': 'orange'});
            for (final a in agents) {
              list.add({
                'roomId': 'chat_client_${_clientId}_maint_${a['subId']}', 'name': a['name'], 'subId': a['subId'].toString(),
                'roleLabel': a['roleLabel'], 'lastText': 'Ouvrir la discussion', 'lastAt': DateTime.now().toIso8601String(), 'senderName': '',
                'machineId': a['machineId'], 'role': 'maintenance'
              });
            }
          }

          _conversations = list;
        }
      } else if (_senderRole == 'conception' || _senderRole == 'concepteur') {
        final list = <Map<String, dynamic>>[];
        final isAdmin = ApiService.isSuperAdmin;

        if (isAdmin) {
          // ── Admin : charger tous les contacts du système ──
          list.add({'roomId': '__section_tech__', 'isSectionHeader': true, 'sectionLabel': 'TECHNICIENS', 'sectionIcon': 'engineering', 'sectionColor': 'purple'});
          try {
            final techs = await ApiService.getTechnicians();
            for (final t in techs) {
              final techId = (t['technicianId'] ?? t['id'] ?? '').toString();
              final fullName = '${t['firstName'] ?? ''} ${t['lastName'] ?? ''}'.trim();
              if (techId.isEmpty) continue;
              list.add({
                'roomId': 'chat_admin_tech_$techId', 'name': fullName.isNotEmpty ? fullName : 'Technicien',
                'subId': techId, 'roleLabel': 'Technicien', 'lastText': 'Ouvrir la discussion', 'lastAt': DateTime.now().toIso8601String(), 'senderName': '',
              });
            }
          } catch (_) {}

          list.add({'roomId': '__section_maint__', 'isSectionHeader': true, 'sectionLabel': 'AGENTS DE MAINTENANCE', 'sectionIcon': 'support_agent', 'sectionColor': 'blue'});
          try {
            final agents = await ApiService.getMaintenanceAgents();
            for (final a in agents) {
              final agentId = (a['maintenanceAgentId'] ?? a['id'] ?? '').toString();
              final fullName = '${a['firstName'] ?? a['nom'] ?? ''} ${a['lastName'] ?? ''}'.trim();
              if (agentId.isEmpty) continue;
              list.add({
                'roomId': 'chat_admin_maint_$agentId', 'name': fullName.isNotEmpty ? fullName : 'Agent Maintenance',
                'subId': agentId, 'roleLabel': 'Maintenance', 'lastText': 'Ouvrir la discussion', 'lastAt': DateTime.now().toIso8601String(), 'senderName': '',
              });
            }
          } catch (_) {}

          list.add({'roomId': '__section_clients__', 'isSectionHeader': true, 'sectionLabel': 'CLIENTS', 'sectionIcon': 'groups', 'sectionColor': 'green'});
          try {
            final clients = await ApiService.getClients();
            for (final c in clients) {
              final clientId = (c['clientId'] ?? c['id'] ?? '').toString();
              final clientName = (c['nom'] ?? c['name'] ?? c['companyName'] ?? '').toString();
              if (clientId.isEmpty) continue;
              list.add({
                'roomId': 'chat_admin_client_$clientId', 'name': clientName.isNotEmpty ? clientName : 'Client',
                'subId': clientId, 'roleLabel': 'Client', 'lastText': 'Ouvrir la discussion', 'lastAt': DateTime.now().toIso8601String(), 'senderName': '',
              });
            }
          } catch (_) {}
        } else {
          // ── Concepteur : charger uniquement ses contacts (par machine) ──
          final myProfile = ApiService.savedConcepteurProfile;
          final myConcepteurId = myProfile != null ? (myProfile['id'] ?? myProfile['_id'] ?? '').toString() : '';
          
          if (myConcepteurId.isNotEmpty) {
            list.add({
              'roomId': 'chat_conception_$myConcepteurId',
              'name': 'Admin',
              'lastText': 'Discuter avec l\'administrateur',
              'lastAt': DateTime.now().toIso8601String(),
              'senderName': 'Admin',
              'roleLabel': 'Admin',
            });
          }

          try {
            final contacts = await ApiService.getConcepteurContacts();
            
            final techs = contacts.where((c) => c['role'] == 'technician').toList();
            final agents = contacts.where((c) => c['role'] == 'maintenance').toList();
            final clients = contacts.where((c) => c['role'] == 'client').toList();
            final concepteurs = contacts.where((c) => c['role'] == 'conception').toList();

            if (concepteurs.isNotEmpty) {
              list.add({'roomId': '__section_concepteurs__', 'isSectionHeader': true, 'sectionLabel': 'CONCEPTEURS', 'sectionIcon': 'engineering', 'sectionColor': 'orange'});
              for (final c in concepteurs) {
                list.add({
                  'roomId': 'chat_conception_${c['id']}', 'name': c['name'], 'subId': c['id'].toString(),
                  'roleLabel': c['roleLabel'], 'lastText': 'Ouvrir la discussion', 'lastAt': DateTime.now().toIso8601String(), 'senderName': '',
                });
              }
            }

            if (clients.isNotEmpty) {
              list.add({'roomId': '__section_clients__', 'isSectionHeader': true, 'sectionLabel': 'CLIENTS', 'sectionIcon': 'groups', 'sectionColor': 'green'});
              for (final c in clients) {
                list.add({
                  'roomId': 'chat_conception_${c['id']}', 'name': c['name'], 'subId': c['id'].toString(),
                  'roleLabel': c['roleLabel'], 'lastText': 'Ouvrir la discussion', 'lastAt': DateTime.now().toIso8601String(), 'senderName': '',
                });
              }
            }

            if (techs.isNotEmpty) {
              list.add({'roomId': '__section_tech__', 'isSectionHeader': true, 'sectionLabel': 'TECHNICIENS', 'sectionIcon': 'engineering', 'sectionColor': 'purple'});
              for (final c in techs) {
                list.add({
                  'roomId': 'chat_conception_${c['id']}', 'name': c['name'], 'subId': c['id'].toString(),
                  'roleLabel': c['roleLabel'], 'lastText': 'Ouvrir la discussion', 'lastAt': DateTime.now().toIso8601String(), 'senderName': '',
                });
              }
            }

            if (agents.isNotEmpty) {
              list.add({'roomId': '__section_maint__', 'isSectionHeader': true, 'sectionLabel': 'AGENTS DE MAINTENANCE', 'sectionIcon': 'support_agent', 'sectionColor': 'blue'});
              for (final c in agents) {
                list.add({
                  'roomId': 'chat_conception_${c['id']}', 'name': c['name'], 'subId': c['id'].toString(),
                  'roleLabel': c['roleLabel'], 'lastText': 'Ouvrir la discussion', 'lastAt': DateTime.now().toIso8601String(), 'senderName': '',
                });
              }
            }
          } catch (_) {}
        }

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
          final list = <Map<String, dynamic>>[];
          list.add({
            'roomId': 'chat_technicien_$_technicianId',
            'name': 'Admin',
            'lastText': 'Discuter avec l\'administrateur',
            'lastAt': DateTime.now().toIso8601String(),
            'senderName': 'Admin',
            'roleLabel': 'Admin',
          });

          try {
            final contacts = await ApiService.getTechnicianContacts();
            
            final concepteurs = contacts.where((c) => c['role'] == 'conception').toList();
            final agents = contacts.where((c) => c['role'] == 'maintenance').toList();
            final clients = contacts.where((c) => c['role'] == 'client').toList();

            if (concepteurs.isNotEmpty) {
              list.add({'roomId': '__section_concep__', 'isSectionHeader': true, 'sectionLabel': 'CONCEPTEURS', 'sectionIcon': 'engineering', 'sectionColor': 'orange'});
              for (final c in concepteurs) {
                list.add({
                  'roomId': 'chat_direct_${_technicianId}_${c['id']}', 'name': c['name'], 'subId': c['id'].toString(),
                  'roleLabel': c['roleLabel'], 'lastText': 'Ouvrir la discussion', 'lastAt': DateTime.now().toIso8601String(), 'senderName': '',
                });
              }
            }

            if (agents.isNotEmpty) {
              list.add({'roomId': '__section_maint__', 'isSectionHeader': true, 'sectionLabel': 'AGENTS DE MAINTENANCE', 'sectionIcon': 'support_agent', 'sectionColor': 'blue'});
              for (final c in agents) {
                list.add({
                  'roomId': 'chat_direct_${_technicianId}_${c['id']}', 'name': c['name'], 'subId': c['id'].toString(),
                  'roleLabel': c['roleLabel'], 'lastText': 'Ouvrir la discussion', 'lastAt': DateTime.now().toIso8601String(), 'senderName': '',
                });
              }
            }

            if (clients.isNotEmpty) {
              list.add({'roomId': '__section_clients__', 'isSectionHeader': true, 'sectionLabel': 'CLIENTS', 'sectionIcon': 'groups', 'sectionColor': 'green'});
              for (final c in clients) {
                list.add({
                  'roomId': 'chat_direct_${_technicianId}_${c['id']}', 'name': c['name'], 'subId': c['id'].toString(),
                  'roleLabel': c['roleLabel'], 'lastText': 'Ouvrir la discussion', 'lastAt': DateTime.now().toIso8601String(), 'senderName': '',
                });
              }
            }
          } catch (_) {}

          _conversations = list;
          if (mounted) setState(() {});
          return;
        }
      } 
      
      if (_senderRole == 'maintenance') {

        // ── Agent de maintenance : charger ses contacts (par machine) ──
        String myAgentId = '';
        try {
          final workspace = await ApiService.getMaintenanceWorkspace();
          final agent = workspace['agent'] as Map<String, dynamic>?;
          myAgentId = (agent?['maintenanceAgentId'] ?? agent?['id'] ?? '').toString();
        } catch (_) {}

        final list = <Map<String, dynamic>>[];
        final adminRoomId = myAgentId.isNotEmpty
            ? 'chat_maintenance_${myAgentId}_admin'
            : 'chat_maintenance_admin';
        list.add({
          'roomId': adminRoomId,
          'name': 'Admin',
          'lastText': 'Discuter avec l\'administrateur',
          'lastAt': DateTime.now().toIso8601String(),
          'senderName': 'Admin',
          'roleLabel': 'Admin',
          'role': 'admin',
        });

        try {
          final contacts = await ApiService.getMaintenanceAgentContacts();

          final concepteurs = contacts.where((c) => c['role'] == 'conception').toList();
          final techs = contacts.where((c) => c['role'] == 'technician').toList();
          final clients = contacts.where((c) => c['role'] == 'client').toList();

          if (concepteurs.isNotEmpty) {
            list.add({'roomId': '__section_concep__', 'isSectionHeader': true, 'sectionLabel': 'CONCEPTEURS', 'sectionIcon': 'engineering', 'sectionColor': 'purple'});
            for (final c in concepteurs) {
              final agentId = myAgentId.isNotEmpty ? myAgentId : 'agent';
              list.add({
                'roomId': 'chat_direct_maint_${agentId}_${c['id']}',
                'name': c['name'], 'subId': c['id'].toString(),
                'roleLabel': c['roleLabel'],
                'lastText': 'Ouvrir la discussion',
                'lastAt': DateTime.now().toIso8601String(),
                'senderName': '', 'role': 'conception',
              });
            }
          }

          if (techs.isNotEmpty) {
            list.add({'roomId': '__section_tech__', 'isSectionHeader': true, 'sectionLabel': 'TECHNICIENS', 'sectionIcon': 'build', 'sectionColor': 'blue'});
            for (final c in techs) {
              final agentId = myAgentId.isNotEmpty ? myAgentId : 'agent';
              list.add({
                'roomId': 'chat_direct_maint_${agentId}_${c['id']}',
                'name': c['name'], 'subId': c['id'].toString(),
                'roleLabel': c['roleLabel'],
                'lastText': 'Ouvrir la discussion',
                'lastAt': DateTime.now().toIso8601String(),
                'senderName': '', 'role': 'technician',
              });
            }
          }

          if (clients.isNotEmpty) {
            list.add({'roomId': '__section_clients__', 'isSectionHeader': true, 'sectionLabel': 'CLIENTS', 'sectionIcon': 'groups', 'sectionColor': 'green'});
            for (final c in clients) {
              final agentId = myAgentId.isNotEmpty ? myAgentId : 'agent';
              list.add({
                'roomId': 'chat_direct_maint_${agentId}_${c['id']}',
                'name': c['name'], 'subId': c['id'].toString(),
                'roleLabel': c['roleLabel'],
                'lastText': 'Ouvrir la discussion',
                'lastAt': DateTime.now().toIso8601String(),
                'senderName': '', 'role': 'client',
              });
            }
          }
        } catch (_) {}

        _conversations = list;
        if (mounted) setState(() {});

        // Load last message preview
        for (final conv in _conversations) {
          if (conv['isSectionHeader'] == true) continue;
          try {
            final msgs = await ApiService.getChatMessages(conv['roomId'], limit: 1);
            if (msgs.isNotEmpty) {
              conv['lastText'] = msgs.first['text'] ?? '';
              conv['lastAt'] = msgs.first['createdAt'] ?? '';
              conv['senderName'] = msgs.first['senderName'] ?? '';
            }
          } catch (_) {}
        }
        if (mounted) setState(() {});
        return;
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
    MessageEquipeView.currentActiveRoomId = room;
    _socket?.emit('join_chat_room', {'roomId': room});

    // Reset unread count for this room
    if (mounted) {
      setState(() {
        c['unreadCount'] = 0;
      });
    }

    _selectedDesignerDetails = c;

    final userRole = ApiService.savedUserRole?.toLowerCase();
    final isConcepteur = userRole == 'concepteur' || (userRole == 'conception' && !ApiService.isSuperAdmin);

    if (isConcepteur || _senderRole == 'client') {
      if (mounted) {
        setState(() {
          _selectedDesignerDetails = {
            'name': (c['name'] ?? 'Admin').toString(),
            'specialite': (c['roleLabel'] ?? '').toString(),
            'machines': c['machineId'] != null && c['machineId'].toString().isNotEmpty ? <String>[ c['machineId'].toString() ] : <String>[],
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
    MessageEquipeView.currentActiveRoomId = null;
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
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
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

  Color _getRoleColor(String roleLabel) {
    final lower = roleLabel.toLowerCase();
    if (lower.contains('admin')) return const Color(0xFFEF4444); // Red
    if (lower.contains('concepteur') || lower.contains('conception')) return const Color(0xFFA855F7); // Purple
    if (lower.contains('technicien') || lower.contains('technician')) return const Color(0xFF3B82F6); // Blue
    if (lower.contains('maintenance')) return const Color(0xFFF97316); // Orange
    if (lower.contains('client')) return const Color(0xFF10B981); // Green
    return const Color(0xFF6366F1); // Indigo default
  }

  String _formatRoleBadge(String roleLabel) {
    if (roleLabel.isEmpty) return 'CONTACT';
    final lower = roleLabel.toLowerCase();
    if (lower.contains('admin')) return 'ADMIN';
    if (lower.contains('concepteur') || lower.contains('conception')) {
      final machine = roleLabel.contains('machine ') ? roleLabel.split('machine ').last : '';
      return machine.isNotEmpty ? 'CONCEPTEUR • $machine'.toUpperCase() : 'CONCEPTEUR';
    }
    if (lower.contains('technicien') || lower.contains('technician')) {
      final machine = roleLabel.contains('machine ') ? roleLabel.split('machine ').last : '';
      return machine.isNotEmpty ? 'TECHNICIEN • $machine'.toUpperCase() : 'TECHNICIEN';
    }
    if (lower.contains('maintenance')) {
      final machine = roleLabel.contains('machine ') ? roleLabel.split('machine ').last : '';
      return machine.isNotEmpty ? 'MAINTENANCE • $machine'.toUpperCase() : 'MAINTENANCE';
    }
    if (lower.contains('client')) {
      final machine = roleLabel.contains('machine ') ? roleLabel.split('machine ').last : '';
      return machine.isNotEmpty ? 'CLIENT • $machine'.toUpperCase() : 'CLIENT';
    }
    return roleLabel.toUpperCase();
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

    final body = ChatLayout(
      showSidebarOnMobile: showSidebar,
      sidebar: ChatSidebar(
        conversations: _conversations,
        activeRoomId: _activeRoomId,
        searchController: _searchController,
        isSearching: _isSearching,
        onSearchChanged: (val) {
          setState(() {
            _isSearching = val.isNotEmpty;
          });
          // TODO: Implémenter la logique de recherche
        },
        onClearSearch: () {
          _searchController.clear();
          setState(() {
            _isSearching = false;
          });
        },
        onSelectConversation: (roomId, details) {
          _switchConversation(details);
        },
      ),
      mainArea: showChat ? ChatMainArea(
        activeRoomId: _activeRoomId,
        selectedContactDetails: _selectedDesignerDetails,
        messages: _messages,
        scrollController: _messagesScroll,
        currentUserId: _currentUserId,
        remoteIsTyping: _remoteIsTyping,
        remoteTypingName: _remoteTypingName,
        inputController: _input,
        isRecording: _isRecording,
        recordingDuration: '${(_recordingDurationSeconds / 60).floor()}:${(_recordingDurationSeconds % 60).toString().padLeft(2, '0')}',
        onPickFile: () => _pickAndUploadFile(isImage: false),
        onStartRecording: _startVoiceRecording,
        onStopRecording: _stopVoiceRecording,
        onCancelRecording: _cancelVoiceRecording,
        onSendMessage: _send,
        onInputChanged: (v) {
          final isTypingNow = v.trim().isNotEmpty;
          if (isTypingNow != _isTyping) {
            setState(() => _isTyping = isTypingNow);
          }
          if (isTypingNow) {
            _socket?.emit('typing', {'roomId': _activeRoomId, 'senderName': _senderName});
            _typingDebounceTimer?.cancel();
            _typingDebounceTimer = Timer(const Duration(seconds: 2), () {
              _socket?.emit('stop_typing', {'roomId': _activeRoomId});
            });
          } else {
            _socket?.emit('stop_typing', {'roomId': _activeRoomId});
            _typingDebounceTimer?.cancel();
          }
        },
        onCloseConversation: _closeConversation,
        buildMessageItem: (m) {
          final senderId = (m['senderId'] ?? m['sender_id'] ?? 0) as int;
          final mine = senderId == _currentUserId;
          final text = (m['text'] ?? '').toString();

          return Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: mine ? ChatTheme.myBubble : ChatTheme.otherBubble,
                borderRadius: BorderRadius.circular(16).copyWith(
                  bottomRight: mine ? const Radius.circular(0) : const Radius.circular(16),
                  bottomLeft: !mine ? const Radius.circular(0) : const Radius.circular(16),
                ),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!mine && m['senderName'] != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(m['senderName'].toString(), style: GoogleFonts.inter(color: ChatTheme.accent, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                    
                  if (m['attachmentUrl'] != null && m['attachmentUrl'].toString().isNotEmpty) ...[
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
                        decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(8), border: Border.all(color: ChatTheme.muted.withOpacity(0.3))),
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
                        color: mine ? Colors.white : ChatTheme.myBubble,
                      ),
                    const SizedBox(height: 5),
                  ],

                  if (text.isNotEmpty)
                    Text(text, style: ChatTheme.messageStyle),
                  
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_fmtTime(m['createdAt'] ?? m['at']), style: ChatTheme.timeStyle.copyWith(fontSize: 10)),
                      if (mine) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.done_all, color: Colors.blueAccent, size: 14),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ) : const SizedBox.shrink(),
      infoPanel: _activeRoomId.isNotEmpty ? ChatInfoPanel(
        selectedContactDetails: _selectedDesignerDetails,
        onClose: () {},
      ) : null,
    );

    if (widget.embedded) return SizedBox.expand(child: body);

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
