import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:google_fonts/google_fonts.dart';

import '../main.dart'; // Pour globalNavigatorKey
import 'api_service.dart';
import '../widgets/message_equipe_view.dart';
import '../widgets/custom_notification_toast.dart';
import '../mission_control_page.dart';

class GlobalNotificationService with WidgetsBindingObserver {
  static final GlobalNotificationService _instance = GlobalNotificationService._internal();
  factory GlobalNotificationService() => _instance;
  GlobalNotificationService._internal();

  io.Socket? _socket;
  final List<Map<String, dynamic>> _notificationQueue = [];
  bool _isShowingToast = false;
  Timer? _toastTimer;
  OverlayEntry? _overlayEntry;

  final StreamController<Map<String, dynamic>> _machineStatusController = StreamController.broadcast();
  Stream<Map<String, dynamic>> get machineStatusStream => _machineStatusController.stream;

  final StreamController<Map<String, dynamic>> _dangerAlertController = StreamController.broadcast();
  Stream<Map<String, dynamic>> get dangerAlertStream => _dangerAlertController.stream;

  final StreamController<Map<String, dynamic>> _missionUpdateController = StreamController.broadcast();
  Stream<Map<String, dynamic>> get missionUpdateStream => _missionUpdateController.stream;

  final StreamController<Map<String, dynamic>> _dangerMissionAlertController = StreamController.broadcast();
  Stream<Map<String, dynamic>> get dangerMissionAlertStream => _dangerMissionAlertController.stream;

  final StreamController<Map<String, dynamic>> _panneConfirmedAlertController = StreamController.broadcast();
  Stream<Map<String, dynamic>> get panneConfirmedAlertStream => _panneConfirmedAlertController.stream;

  // 📡 Stream en temps réel des données MQTT (sans polling HTTP)
  final StreamController<Map<String, dynamic>> _telemetryLiveController = StreamController.broadcast();
  Stream<Map<String, dynamic>> get telemetryLiveStream => _telemetryLiveController.stream;

  // 🚨 Danger alert pour admin/client/maintenance/concepteur
  final StreamController<Map<String, dynamic>> _dangerAlertAdminController = StreamController.broadcast();
  Stream<Map<String, dynamic>> get dangerAlertAdminStream => _dangerAlertAdminController.stream;

  // ✅ Notification machine en bon état (après résolution danger)
  final StreamController<Map<String, dynamic>> _machineGoodStateController = StreamController.broadcast();
  Stream<Map<String, dynamic>> get machineGoodStateStream => _machineGoodStateController.stream;

  void init() {
    if (_socket != null) return;
    WidgetsBinding.instance.addObserver(this);
    _connectSocket();
  }

  void _connectSocket() {
    final token = ApiService.authToken;
    if (token == null || token.isEmpty) return;

    _socket = io.io(ApiService.socketBaseUrl, <String, dynamic>{
      'transports': <String>['websocket'],
      'autoConnect': true,
    });

    _socket!.onConnect((_) {
      print('🔔 GlobalNotificationService Socket connecté');
      _socket!.emit('join_global_notifications', {'token': token});
    });

    _socket!.on('new_chat_notification', (data) {
      if (data == null) return;
      _handleNewNotification(Map<String, dynamic>.from(data));
    });

    _socket!.on('new_mission', (data) {
      if (data == null) return;
      _handleMissionToast(Map<String, dynamic>.from(data), isCompleted: false);
    });

    _socket!.on('mission_completed', (data) {
      if (data == null) return;
      _handleMissionToast(Map<String, dynamic>.from(data), isCompleted: true);
    });

    _socket!.on('mission_status_updated', (data) {
      if (data == null) return;
      final mapData = Map<String, dynamic>.from(data);
      final status = mapData['status'];
      _handleMissionToast(mapData, isCompleted: status == 'DONE', isConfirmed: status == 'IN_PROGRESS');
    });

    _socket!.on('machine_status_update', (data) {
      if (data == null) return;
      _machineStatusController.add(Map<String, dynamic>.from(data));
    });

    _socket!.on('danger_alert', (data) {
      if (data == null) return;
      _dangerAlertController.add(Map<String, dynamic>.from(data));
    });

    _socket!.on('diagnostic_coordination_update', (data) {
      if (data == null) return;
      _missionUpdateController.add(Map<String, dynamic>.from(data));
    });

    _socket!.on('danger_mission_alert', (data) {
      if (data == null) return;
      _dangerMissionAlertController.add(Map<String, dynamic>.from(data));
    });

    _socket!.on('panne_confirmed_alert', (data) {
      if (data == null) return;
      _panneConfirmedAlertController.add(Map<String, dynamic>.from(data));
    });

    // 📡 Données MQTT live (pas de polling HTTP)
    _socket!.on('telemetry_live', (data) {
      if (data == null) return;
      _telemetryLiveController.add(Map<String, dynamic>.from(data));
    });

    // 🚨 Danger pour admin/maintenance/concepteur
    _socket!.on('danger_alert_admin', (data) {
      if (data == null) return;
      _dangerAlertAdminController.add(Map<String, dynamic>.from(data));
    });

    // ✅ Machine en bon état (danger résolu)
    _socket!.on('machine_good_state', (data) {
      if (data == null) return;
      _machineGoodStateController.add(Map<String, dynamic>.from(data));
    });

    _socket!.onDisconnect((_) {
      print('🔔 GlobalNotificationService Socket déconnecté');
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_socket == null || _socket?.connected == false) {
        logout();
        init();
      }
    }
  }

  void logout() {
    WidgetsBinding.instance.removeObserver(this);
    _socket?.dispose();
    _socket = null;
    _notificationQueue.clear();
    _removeCurrentToast();
  }

  void _handleNewNotification(Map<String, dynamic> data) {
    final roomId = data['roomId']?.toString();
    if (roomId != null && MessageEquipeView.currentActiveRoomId == roomId) {
      return; // Ne pas afficher si l'utilisateur est déjà dans cette conversation
    }
    
    // Éviter les doublons successifs de la même room (si queue)
    if (_notificationQueue.isNotEmpty && 
        _notificationQueue.last['roomId'] == roomId && 
        _notificationQueue.last['text'] == data['text']) {
        return;
    }

    _notificationQueue.add(data);
    _processQueue();
  }

  OverlayEntry? _missionOverlayEntry;

  void _handleMissionToast(Map<String, dynamic> data, {required bool isCompleted, bool isConfirmed = false}) {
    if (globalNavigatorKey.currentState?.overlay == null) return;

    _missionOverlayEntry?.remove();
    _missionOverlayEntry = null;

    final mission = data['mission'] ?? {};
    
    String title;
    if (isCompleted) {
      title = '✅ MISSION TERMINÉE';
    } else if (isConfirmed) {
      title = '⚙️ MISSION EN COURS';
    } else {
      title = '🚀 NOUVELLE MISSION REÇUE';
    }

    final subtitle1 = (isCompleted || isConfirmed) 
        ? 'Technicien : ${mission['techName'] ?? 'Inconnu'}' 
        : 'De : Maintenance Agent (${mission['senderName'] ?? 'Inconnu'})';
    final subtitle2 = 'Machine : ${mission['machineName'] ?? ''} (${mission['machineId'] ?? ''})';
    final description = (isCompleted || isConfirmed) 
        ? 'Mission : ${mission['title'] ?? ''}' 
        : '${mission['title'] ?? ''} - ${mission['description'] ?? ''}';
    
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    _missionOverlayEntry = OverlayEntry(
      builder: (context) => CustomNotificationToast(
        title: title,
        subtitle1: subtitle1,
        subtitle2: subtitle2,
        description: description,
        time: timeStr,
        isCompleted: isCompleted,
        onAction: () {
          _missionOverlayEntry?.remove();
          _missionOverlayEntry = null;
          final ctx = globalNavigatorKey.currentContext;
          if (ctx != null) {
            Navigator.push(ctx, MaterialPageRoute(builder: (_) => const MissionControlPage()));
          }
        },
        onDismiss: () {
          _missionOverlayEntry?.remove();
          _missionOverlayEntry = null;
        },
      ),
    );

    globalNavigatorKey.currentState!.overlay!.insert(_missionOverlayEntry!);
  }

  void _processQueue() {
    if (_isShowingToast || _notificationQueue.isEmpty) return;
    final nextNotif = _notificationQueue.removeAt(0);
    _showToast(nextNotif);
  }

  void _showToast(Map<String, dynamic> data) {
    if (globalNavigatorKey.currentState?.overlay == null) {
      _processQueue();
      return;
    }

    _isShowingToast = true;
    final senderName = data['senderName']?.toString() ?? 'Inconnu';
    final text = data['text']?.toString() ?? '';
    final roomId = data['roomId']?.toString() ?? '';
    final attachmentType = data['attachmentType']?.toString() ?? '';

    String preview = text;
    if (preview.isEmpty && attachmentType.isNotEmpty) {
      preview = '📎 Pièce jointe';
    }
    if (preview.length > 50) preview = preview.substring(0, 47) + '...';

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 60,
        left: 20,
        right: 20,
        child: SafeArea(
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 450),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B).withOpacity(0.85),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.blueAccent.withOpacity(0.2),
                          child: Text(
                            senderName.isNotEmpty ? senderName[0].toUpperCase() : '?',
                            style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                senderName,
                                style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                preview,
                                style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.blueAccent.withOpacity(0.1),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          onPressed: () {
                            _removeCurrentToast();
                            _navigateToChat(roomId);
                          },
                          child: Text('AFFICHER', style: GoogleFonts.spaceGrotesk(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                          onPressed: _removeCurrentToast,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    globalNavigatorKey.currentState!.overlay!.insert(_overlayEntry!);

    _toastTimer = Timer(const Duration(seconds: 4), () {
      _removeCurrentToast();
    });
  }

  void _removeCurrentToast() {
    _toastTimer?.cancel();
    _toastTimer = null;
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isShowingToast = false;
    Future.delayed(const Duration(milliseconds: 300), _processQueue);
  }

  void _navigateToChat(String roomId) {
    final context = globalNavigatorKey.currentContext;
    if (context == null) return;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.9,
        decoration: const BoxDecoration(
          color: Color(0xFF0F172A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: MessageEquipeView(
            embedded: true,
            initialRoomId: roomId,
          ),
        ),
      ),
    );
  }
}
