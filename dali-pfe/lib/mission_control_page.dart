import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'services/api_service.dart';
import 'package:fl_chart/fl_chart.dart';

class MissionControlPage extends StatefulWidget {
  const MissionControlPage({super.key});

  @override
  State<MissionControlPage> createState() => _MissionControlPageState();
}

class _MissionControlPageState extends State<MissionControlPage> {
  IO.Socket? _socket;
  final List<Map<String, dynamic>> _logs = [];
  final TextEditingController _commandController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String _healthScore = "74";
  String _coreTemp = "88.4";
  String _bandwidth = "440";
  String _status = "DEGRADED";
  List<double> _bandwidthHistory = [30, 45, 20, 60, 55, 80, 40, 70, 90, 30];
  
  String _agentName = "OPERATOR";
  String _techId = "X9-HYPERION";
  String _latestCoordNote = "Confirm node isolation to prevent cascade.";
  Map<String, dynamic>? _latestMission;
  String? _latestNoteId;
  String? _interventionId;
  bool _isSendingMission = false; // Verrou anti-double-clic

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args != null) {
      if (args.containsKey('name')) {
        _agentName = args['name'].toString().toUpperCase();
      }
      if (args.containsKey('techId')) {
        _techId = args['techId'].toString().toUpperCase();
      }
      if (args.containsKey('interventionId')) {
        _interventionId = args['interventionId'].toString();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _initSocket();
    _findActiveIntervention();
  }

  Future<void> _findActiveIntervention() async {
    if (_interventionId != null) return;
    try {
      final list = await ApiService.getDiagnosticInterventions();
      // On cherche une intervention ouverte pour cette machine ou ce technicien
      // _techId contient souvent le nom de la machine (ex: DZLI)
      final active = list.firstWhere(
        (i) {
          final isOpen = i['status'] != 'DONE' && i['status'] != 'CANCELLED';
          if (!isOpen) return false;
          
          final mId = (i['machineId'] ?? '').toString();
          final mName = (i['machineName'] ?? '').toString().toUpperCase();
          final tId = (i['technicianId'] ?? '').toString().toUpperCase();
          
          return mId == _techId || mName == _techId || tId == _techId;
        },
        orElse: () => {},
      );

      if (active.containsKey('id')) {
        setState(() {
          _interventionId = active['id'].toString();
          
          // Charger l'historique des messages
          final messages = List.from(active['messages'] ?? []);
          for (var msg in messages) {
            final author = (msg['authorName'] ?? msg['authorRole'] ?? 'Unknown').toString().toUpperCase();
            final isMe = author == _agentName.toUpperCase();
            
            _logs.add({
              'type': isMe ? 'YOU' : 'MAINT_HUB // $author',
              'text': msg['content'] ?? '',
              'timestamp': msg['createdAt'] != null 
                  ? TimeOfDay.fromDateTime(DateTime.parse(msg['createdAt'])).format(context)
                  : '--:--',
            });
          }

          final notes = List.from(active['coordinationNotes'] ?? []);
          if (notes.isNotEmpty) {
            for (var note in notes) {
              final isM = note['isMission'] == true || note['missionStatus'] != null;
              final nId = (note['_id'] ?? note['id'])?.toString();
              
              if (isM) {
                _latestMission = Map<String, dynamic>.from(note);
                _latestMission!['id'] = nId;
              }
              _latestNoteId = nId;
              _latestCoordNote = (note['content'] ?? '').toString().toUpperCase();

              _logs.add({
                "type": isM ? "CRITICAL_EVENT" : "OP_TECH",
                "text": _latestCoordNote,
                "timestamp": note['createdAt'] != null 
                    ? TimeOfDay.fromDateTime(DateTime.parse(note['createdAt'])).format(context)
                    : '--:--',
                "isMission": isM,
                "noteId": nId,
                "missionStatus": note['missionStatus'],
              });
            }
          }
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('Error finding active intervention: $e');
    }
  }

  void _initSocket() {
    final baseUrl = ApiService.baseUrl.replaceFirst('/api', '');
    _socket = IO.io(baseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });

    _socket!.onConnect((_) {
      debugPrint('Connected to Mission Control socket');
    });

    _socket!.on('mission_control_metrics', (data) {
      if (mounted) {
        setState(() {
          _healthScore = data['healthScore'] ?? _healthScore;
          _coreTemp = data['coreTemp'] ?? _coreTemp;
          _bandwidth = data['bandwidth'] ?? _bandwidth;
          _status = data['status'] ?? _status;
          
          _bandwidthHistory.add(double.tryParse(_bandwidth) ?? 440);
          if (_bandwidthHistory.length > 10) _bandwidthHistory.removeAt(0);
        });
      }
    });

    _socket!.on('diagnostic_coordination', (data) {
      if (mounted) {
        final incomingInterventionId = data['interventionId'].toString();
        debugPrint('COORD_RECV: $incomingInterventionId (Current: $_interventionId)');
        
        // Si le technicien n'a pas d'intervention active ou si l'ID a changé
        // On accepte le nouvel ID pour rester synchronisé avec l'agent
        if (_interventionId == null || _interventionId == '') {
           _interventionId = incomingInterventionId;
        }

        if (incomingInterventionId == _interventionId) {
          final note = data['note'];
          setState(() {
            _latestCoordNote = (note['content'] ?? '').toString().toUpperCase();
            _latestNoteId = (note['id'] ?? note['_id'])?.toString();
            final isM = note['isMission'] == true || note['isMission'] == 'true' || note['missionStatus'] != null;
            
            if (isM) {
              _latestMission = Map<String, dynamic>.from(note);
              _latestMission!['id'] = _latestNoteId;
              // POP-UP AUTOMATIQUE si c'est une nouvelle mission
              if (note['missionStatus'] == 'SENT') {
                 _showMissionPopup(note);
              }
            }

            // Toujours ajouter au log terminal pour que le technicien voie l'activité
            final author = (note['authorName'] ?? 'AGENCE').toString().toUpperCase();
            _logs.add({
              "type": isM ? "CRITICAL_EVENT" : "MAINT_HUB // $author",
              "text": _latestCoordNote,
              "timestamp": DateTime.now().toLocal().toString().substring(11, 16),
              "isMission": isM,
              "noteId": _latestNoteId,
              "missionStatus": note['missionStatus'] ?? 'SENT',
            });
            if (_logs.length > 50) _logs.removeAt(0);
          });
        }
      }
    });

    _socket!.on('diagnostic_coordination_update', (data) {
      if (mounted && data['interventionId'].toString() == _interventionId) {
        final noteId = data['noteId']?.toString();
        final status = data['status'];

        setState(() {
          // Mettre à jour la mission actuelle si elle correspond
          if (_latestMission != null && (_latestMission!['id'] == noteId || _latestMission!['_id'] == noteId)) {
            _latestMission!['missionStatus'] = status;
          }

          // Mettre à jour le statut dans les logs du terminal
          for (var log in _logs) {
            if (log['isMission'] == true && log['noteId'] == noteId) {
              log['missionStatus'] = status;
            }
          }

          if (status == 'CONFIRMED') {
             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('MISSION CONFIRMÉE / STARTED'), backgroundColor: Colors.cyanAccent,));
          } else if (status == 'COMPLETED') {
             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('MISSION TERMINÉE / DONE'), backgroundColor: Colors.greenAccent,));
          }
        });
      }
    });

    _socket!.on('diagnostic_message', (data) {
      if (mounted) {
        final incomingInterventionId = data['interventionId'].toString();
        if (_interventionId != null && incomingInterventionId != _interventionId) return;

        final msg = data['message'];
        final author = (msg['authorName'] ?? msg['authorRole'] ?? '').toString().toUpperCase();
        
        // Éviter les doublons : si le message vient de nous-mêmes (déjà ajouté via _sendCommand)
        if (author == _agentName.toUpperCase()) return;

        setState(() {
          _logs.add({
            'type': 'MAINT_HUB // $author',
            'text': msg['content'],
            'timestamp': msg['createdAt'] != null 
                ? TimeOfDay.fromDateTime(DateTime.parse(msg['createdAt'])).format(context)
                : 'NOW',
          });
        });
        _scrollToBottom();
      }
    });
  }

  void _sendCommand() {
    final cmd = _commandController.text.trim();
    if (cmd.isEmpty) return;

    _socket!.emit('mission_control_command', {'command': cmd});
    
    // Si on a une intervention active, on envoie aussi au canal de discussion
    if (_interventionId != null) {
      ApiService.addDiagnosticMessage(_interventionId!, cmd, authorName: _agentName);
    }
    
    setState(() {
      _logs.add({
        'type': 'YOU',
        'text': cmd,
        'timestamp': TimeOfDay.now().format(context),
      });
    });
    
    _commandController.clear();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _socket?.disconnect();
    _commandController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      body: Column(
        children: [
          _buildTopNav(),
          Expanded(
            child: Row(
              children: [
                Expanded(flex: 3, child: _buildTerminalArea()),
                Expanded(flex: 1, child: _buildMetricsPanel()),
              ],
            ),
          ),
          _buildBottomStatusBar(),
        ],
      ),
    );
  }

  Widget _buildTopNav() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E14),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.cyanAccent),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 10),
          Text(
            'TECH_OS // MISSION_CONTROL // $_agentName',
            style: GoogleFonts.orbitron(
              color: Colors.cyanAccent,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const Spacer(),
          _buildNavTab('SYSTEM_HUB', false),
          _buildNavTab('FLEET_SYNC', true),
          _buildNavTab('NETWORK_LOGS', false),
          const SizedBox(width: 20),
          const Icon(Icons.notifications_none, color: Colors.cyanAccent, size: 20),
          const SizedBox(width: 20),
          const Icon(Icons.dashboard_customize_outlined, color: Colors.cyanAccent, size: 20),
        ],
      ),
    );
  }

  Widget _buildNavTab(String label, bool active) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 15),
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        border: active ? const Border(bottom: BorderSide(color: Colors.cyanAccent, width: 2)) : null,
      ),
      child: Text(
        label,
        style: GoogleFonts.spaceGrotesk(
          color: active ? Colors.white : Colors.blueGrey,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildActiveMissionHeader() {
    if (_latestMission == null || _latestMission!['missionStatus'] == 'COMPLETED') {
      return const SizedBox.shrink();
    }

    final status = _latestMission!['missionStatus'] ?? 'PENDING';
    final content = (_latestMission!['content'] ?? '').toString().toUpperCase();
    final isConfirmed = status == 'CONFIRMED' || status == 'STARTED';

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isConfirmed ? Colors.cyanAccent.withOpacity(0.05) : Colors.purpleAccent.withOpacity(0.05),
        border: Border.all(color: isConfirmed ? Colors.cyanAccent : Colors.purpleAccent, width: 2),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(color: (isConfirmed ? Colors.cyanAccent : Colors.purpleAccent).withOpacity(0.2), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isConfirmed ? Icons.engineering : Icons.rocket_launch, color: isConfirmed ? Colors.cyanAccent : Colors.purpleAccent, size: 20),
              const SizedBox(width: 10),
              Text(
                isConfirmed ? 'MISSION_EN_COURS' : 'NOUVELLE_MISSION // STATUT: ENVOYÉE',
                style: GoogleFonts.orbitron(color: isConfirmed ? Colors.cyanAccent : Colors.purpleAccent, fontSize: 10, fontWeight: FontWeight.bold),
              ),
              if (!isConfirmed && _latestNoteId != null) ...[
                const SizedBox(width: 15),
                Text(
                  'ID: ${_latestNoteId!.substring(_latestNoteId!.length > 6 ? _latestNoteId!.length - 6 : 0)}',
                  style: GoogleFonts.jetBrainsMono(color: Colors.white.withOpacity(0.5), fontSize: 9),
                ),
              ],
              const Spacer(),
              // Bouton CONFIRMER
              ElevatedButton.icon(
                onPressed: (status == 'SENT' && !_isSendingMission)
                    ? () async {
                        if (_interventionId != null && _latestNoteId != null) {
                          setState(() => _isSendingMission = true);
                          // Mise à jour optimiste : UI réagit immédiatement
                          setState(() {
                            _latestMission?['missionStatus'] = 'CONFIRMED';
                            for (var log in _logs) {
                              if (log['isMission'] == true && log['noteId'] == _latestNoteId) {
                                log['missionStatus'] = 'CONFIRMED';
                              }
                            }
                          });
                          try {
                            await ApiService.updateMissionStatus(_interventionId!, _latestNoteId!, 'CONFIRMED');
                          } catch (e) {
                            // Rollback si erreur
                            setState(() {
                              _latestMission?['missionStatus'] = 'SENT';
                              for (var log in _logs) {
                                if (log['isMission'] == true && log['noteId'] == _latestNoteId) {
                                  log['missionStatus'] = 'SENT';
                                }
                              }
                            });
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.redAccent),
                              );
                            }
                          } finally {
                            if (mounted) setState(() => _isSendingMission = false);
                          }
                        }
                      }
                    : null,
                icon: _isSendingMission && status == 'SENT'
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : Icon(
                        status == 'SENT' ? Icons.circle_outlined : Icons.check_circle,
                        size: 14,
                        color: status == 'SENT' ? Colors.black : Colors.greenAccent,
                      ),
                label: Text(
                  _isSendingMission && status == 'SENT' ? '...' : (status == 'SENT' ? 'CONFIRMER' : 'CONFIRMÉ'),
                  style: GoogleFonts.orbitron(fontSize: 10, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: status == 'SENT' ? Colors.cyanAccent : Colors.white.withOpacity(0.05),
                  foregroundColor: status == 'SENT' ? Colors.black : Colors.white.withOpacity(0.3),
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  disabledBackgroundColor: Colors.white.withOpacity(0.05),
                  disabledForegroundColor: Colors.white.withOpacity(0.3),
                ),
              ),
              const SizedBox(width: 10),
              // Bouton TERMINER
              ElevatedButton.icon(
                onPressed: (isConfirmed && !_isSendingMission)
                    ? () async {
                        if (_interventionId != null && _latestNoteId != null) {
                          setState(() => _isSendingMission = true);
                          // Mise à jour optimiste
                          setState(() {
                            _latestMission?['missionStatus'] = 'COMPLETED';
                            for (var log in _logs) {
                              if (log['isMission'] == true && log['noteId'] == _latestNoteId) {
                                log['missionStatus'] = 'COMPLETED';
                              }
                            }
                          });
                          try {
                            await ApiService.updateMissionStatus(_interventionId!, _latestNoteId!, 'COMPLETED');
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('✅ MISSION TERMINÉE'), backgroundColor: Colors.green),
                              );
                            }
                          } catch (e) {
                            setState(() {
                              _latestMission?['missionStatus'] = 'CONFIRMED';
                              for (var log in _logs) {
                                if (log['isMission'] == true && log['noteId'] == _latestNoteId) {
                                  log['missionStatus'] = 'CONFIRMED';
                                }
                              }
                            });
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.redAccent),
                              );
                            }
                          } finally {
                            if (mounted) setState(() => _isSendingMission = false);
                          }
                        }
                      }
                    : null,
                icon: _isSendingMission && isConfirmed
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : Icon(
                        Icons.stop_circle_outlined,
                        size: 14,
                        color: isConfirmed ? Colors.black : Colors.white.withOpacity(0.2),
                      ),
                label: Text(
                  _isSendingMission && isConfirmed ? '...' : 'TERMINER',
                  style: GoogleFonts.orbitron(fontSize: 10, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isConfirmed ? Colors.greenAccent : Colors.white.withOpacity(0.05),
                  foregroundColor: isConfirmed ? Colors.black : Colors.white.withOpacity(0.2),
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  disabledBackgroundColor: Colors.white.withOpacity(0.05),
                  disabledForegroundColor: Colors.white.withOpacity(0.2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            color: Colors.white.withOpacity(0.05),
            child: Text(
              content,
              style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTerminalArea() {
    return Container(
      margin: const EdgeInsets.all(20),
      child: Column(
        children: [
          _buildActiveMissionHeader(),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.only(bottom: 20),
              itemCount: _logs.length,
              itemBuilder: (context, index) {
                return _buildLogEntry(_logs[index]);
              },
            ),
          ),
          _buildCommandInput(),
        ],
      ),
    );
  }

  Widget _buildLogEntry(Map<String, dynamic> log) {
    Color accentColor;
    String type = log['type'];
    bool isMe = type == 'YOU';
    
    if (type.startsWith('OP_TECH')) {
      accentColor = Colors.blueAccent;
    } else if (type == 'SYSTEM_OS') {
      accentColor = Colors.purpleAccent;
    } else if (type == 'CRITICAL_EVENT') {
      accentColor = Colors.redAccent;
    } else {
      accentColor = isMe ? Colors.orangeAccent : Colors.cyanAccent;
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 15),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isMe) ...[
                  Text(
                    log['timestamp'],
                    style: GoogleFonts.spaceGrotesk(color: Colors.blueGrey, fontSize: 10),
                  ),
                  const SizedBox(width: 10),
                ],
                Text(
                  type,
                  style: GoogleFonts.orbitron(color: accentColor, fontSize: 10, fontWeight: FontWeight.bold),
                ),
                if (!isMe) ...[
                  const SizedBox(width: 10),
                  Text(
                    log['timestamp'],
                    style: GoogleFonts.spaceGrotesk(color: Colors.blueGrey, fontSize: 10),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 5),
            Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.6),
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: accentColor.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    log['text'],
                    style: GoogleFonts.spaceGrotesk(color: Colors.white.withOpacity(0.9), fontSize: 13),
                  ),
                  if (log['isMission'] == true) ...[
                    const SizedBox(height: 15),
                    Row(
                      children: [
                        if (log['missionStatus'] != 'COMPLETED') ...[
                          // Bouton CONFIRMER
                          ElevatedButton.icon(
                            onPressed: (log['missionStatus'] == 'SENT' || log['missionStatus'] == 'PENDING')
                                ? () async {
                                   if (_interventionId != null && log['noteId'] != null) {
                                     // Mise à jour optimiste du log
                                     setState(() {
                                       log['missionStatus'] = 'CONFIRMED';
                                       if (_latestMission != null && _latestMission!['id'] == log['noteId']) {
                                         _latestMission!['missionStatus'] = 'CONFIRMED';
                                       }
                                     });
                                     try {
                                       await ApiService.updateMissionStatus(_interventionId!, log['noteId'], 'CONFIRMED');
                                     } catch (e) {
                                       setState(() { log['missionStatus'] = 'SENT'; });
                                       if (mounted) {
                                         ScaffoldMessenger.of(context).showSnackBar(
                                           SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.redAccent),
                                         );
                                       }
                                     }
                                   }
                                }
                                : null,
                            icon: Icon(
                              (log['missionStatus'] == 'SENT' || log['missionStatus'] == 'PENDING') ? Icons.circle_outlined : Icons.check_circle,
                              size: 12,
                              color: (log['missionStatus'] == 'SENT' || log['missionStatus'] == 'PENDING') ? Colors.black : Colors.greenAccent,
                            ),
                            label: Text(
                              (log['missionStatus'] == 'SENT' || log['missionStatus'] == 'PENDING') ? 'CONFIRMER' : 'CONFIRMÉ',
                              style: GoogleFonts.orbitron(fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: (log['missionStatus'] == 'SENT' || log['missionStatus'] == 'PENDING') ? Colors.cyanAccent : Colors.white.withOpacity(0.05),
                              foregroundColor: (log['missionStatus'] == 'SENT' || log['missionStatus'] == 'PENDING') ? Colors.black : Colors.white.withOpacity(0.3),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Bouton TERMINER
                          ElevatedButton.icon(
                            onPressed: (log['missionStatus'] == 'CONFIRMED' || log['missionStatus'] == 'STARTED')
                                ? () async {
                                   if (_interventionId != null && log['noteId'] != null) {
                                     setState(() {
                                       log['missionStatus'] = 'COMPLETED';
                                       if (_latestMission != null && _latestMission!['id'] == log['noteId']) {
                                         _latestMission!['missionStatus'] = 'COMPLETED';
                                       }
                                     });
                                     try {
                                       await ApiService.updateMissionStatus(_interventionId!, log['noteId'], 'COMPLETED');
                                     } catch (e) {
                                       setState(() { log['missionStatus'] = 'CONFIRMED'; });
                                       if (mounted) {
                                         ScaffoldMessenger.of(context).showSnackBar(
                                           SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.redAccent),
                                         );
                                       }
                                     }
                                   }
                                }
                                : null,
                            icon: Icon(
                              Icons.stop_circle_outlined,
                              size: 12,
                              color: (log['missionStatus'] == 'CONFIRMED' || log['missionStatus'] == 'STARTED') ? Colors.black : Colors.white.withOpacity(0.2),
                            ),
                            label: Text(
                              'TERMINER',
                              style: GoogleFonts.orbitron(fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: (log['missionStatus'] == 'CONFIRMED' || log['missionStatus'] == 'STARTED') ? Colors.greenAccent : Colors.white.withOpacity(0.05),
                              foregroundColor: (log['missionStatus'] == 'CONFIRMED' || log['missionStatus'] == 'STARTED') ? Colors.black : Colors.white.withOpacity(0.2),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                        ],
                        if (log['missionStatus'] == 'COMPLETED') ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.2), 
                              borderRadius: BorderRadius.circular(4), 
                              border: Border.all(color: Colors.greenAccent.withOpacity(0.5))
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 14),
                                const SizedBox(width: 6),
                                Text('MISSION TERMINÉE', style: GoogleFonts.orbitron(color: Colors.greenAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommandInput() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1322),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          const Text('>_', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
          const SizedBox(width: 15),
          Expanded(
            child: TextField(
              controller: _commandController,
              onSubmitted: (_) => _sendCommand(),
              style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'ENTER_COMMAND...',
                hintStyle: GoogleFonts.jetBrainsMono(color: Colors.blueGrey, fontSize: 14),
                border: InputBorder.none,
              ),
            ),
          ),
          TextButton(
            onPressed: _sendCommand,
            style: TextButton.styleFrom(backgroundColor: Colors.cyanAccent.withOpacity(0.8)),
            child: Text(
              'SEND >',
              style: GoogleFonts.orbitron(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF090D18),
        border: Border(left: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('MACHINE_METRICS'),
            const SizedBox(height: 20),
            _buildMetricInfo('ID_IDENTIFIER', _techId),
            const SizedBox(height: 15),
            _buildMetricInfoWithIcon('LOCALISATION', 'SECTOR_04 // GRID_B2 // PARIS_HUB', Icons.location_on),
            const SizedBox(height: 20),
            _buildCircuitVisual(),
            const SizedBox(height: 20),
            _buildStatCard('HEALTH_SCORE', '$_healthScore%', double.parse(_healthScore) / 100, Colors.pinkAccent, "STATUS: $_status"),
            const SizedBox(height: 15),
            _buildStatCard('CORE_TEMP', '$_coreTemp°C', double.parse(_coreTemp) / 100, Colors.orangeAccent, "WARNING"),
            const SizedBox(height: 25),
            _buildOverrideBox(),
            const SizedBox(height: 25),
            _buildBandwidthChart(),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        Text(
          title,
          style: GoogleFonts.orbitron(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const Spacer(),
        Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle)),
      ],
    );
  }

  Widget _buildMetricInfo(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.spaceGrotesk(color: Colors.blueGrey, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(value, style: GoogleFonts.orbitron(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildMetricInfoWithIcon(String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.spaceGrotesk(color: Colors.blueGrey, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(icon, color: Colors.cyanAccent, size: 14),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                value,
                style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCircuitVisual() {
    return Container(
      height: 120,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: CustomPaint(
          painter: CircuitPainter(),
          child: Center(
            child: Icon(Icons.qr_code, color: Colors.white.withOpacity(0.1), size: 40),
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, double progress, Color color, String badge) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1322),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: GoogleFonts.spaceGrotesk(color: Colors.blueGrey, fontSize: 10, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(2)),
                child: Text(badge, style: GoogleFonts.spaceGrotesk(color: color, fontSize: 8, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(value, style: GoogleFonts.orbitron(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.white.withOpacity(0.05),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 4,
          ),
        ],
      ),
    );
  }

  Widget _buildOverrideBox() {
    final hasMission = _latestMission != null;
    final status = _latestMission?['missionStatus'] ?? 'SENT';
    final missionId = _latestMission?['id'] ?? _latestMission?['_id'];

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            hasMission ? Colors.orangeAccent.withOpacity(0.1) : Colors.blueAccent.withOpacity(0.1),
            Colors.purpleAccent.withOpacity(0.05)
          ],
        ),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: hasMission ? Colors.orangeAccent.withOpacity(0.3) : Colors.cyanAccent.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(hasMission ? Icons.assignment_late : Icons.security, color: hasMission ? Colors.orangeAccent : Colors.cyanAccent, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasMission ? 'ACTIVE MISSION PROTOCOL' : 'SYSTEM OVERRIDE PROTOCOL',
                      style: GoogleFonts.orbitron(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _latestCoordNote,
                      style: GoogleFonts.spaceGrotesk(color: hasMission ? Colors.orangeAccent : Colors.cyanAccent, fontSize: 8, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              if (hasMission)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: status == 'COMPLETED' ? Colors.greenAccent.withOpacity(0.1) : Colors.orangeAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    status,
                    style: GoogleFonts.spaceGrotesk(
                      color: status == 'COMPLETED' ? Colors.greenAccent : Colors.orangeAccent,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 15),
          if (hasMission) ...[
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (status == 'SENT' && !_isSendingMission)
                        ? () async {
                            if (_interventionId != null && missionId != null) {
                              setState(() => _isSendingMission = true);
                              setState(() {
                                _latestMission?['missionStatus'] = 'CONFIRMED';
                                for (var log in _logs) {
                                  if (log['isMission'] == true && log['noteId'] == missionId.toString()) {
                                    log['missionStatus'] = 'CONFIRMED';
                                  }
                                }
                              });
                              try {
                                await ApiService.updateMissionStatus(_interventionId!, missionId.toString(), 'CONFIRMED');
                              } catch (e) {
                                setState(() { _latestMission?['missionStatus'] = 'SENT'; });
                                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.redAccent));
                              } finally {
                                if (mounted) setState(() => _isSendingMission = false);
                              }
                            }
                          }
                        : null,
                    icon: _isSendingMission && status == 'SENT'
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : Icon(status == 'SENT' ? Icons.circle_outlined : Icons.check_circle, size: 14, color: status == 'SENT' ? Colors.black : Colors.greenAccent),
                    label: Text(
                      _isSendingMission && status == 'SENT' ? '...' : (status == 'SENT' ? 'CONFIRMER' : 'CONFIRMÉ'),
                      style: GoogleFonts.orbitron(fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: status == 'SENT' ? Colors.cyanAccent.withOpacity(0.8) : Colors.white.withOpacity(0.05),
                      disabledBackgroundColor: Colors.white.withOpacity(0.05),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: ((status == 'CONFIRMED' || status == 'STARTED') && !_isSendingMission)
                        ? () async {
                            if (_interventionId != null && missionId != null) {
                              setState(() => _isSendingMission = true);
                              setState(() {
                                _latestMission?['missionStatus'] = 'COMPLETED';
                                for (var log in _logs) {
                                  if (log['isMission'] == true && log['noteId'] == missionId.toString()) {
                                    log['missionStatus'] = 'COMPLETED';
                                  }
                                }
                              });
                              try {
                                await ApiService.updateMissionStatus(_interventionId!, missionId.toString(), 'COMPLETED');
                                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ MISSION TERMINÉE'), backgroundColor: Colors.green));
                              } catch (e) {
                                setState(() { _latestMission?['missionStatus'] = 'CONFIRMED'; });
                                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.redAccent));
                              } finally {
                                if (mounted) setState(() => _isSendingMission = false);
                              }
                            }
                          }
                        : null,
                    icon: _isSendingMission && (status == 'CONFIRMED' || status == 'STARTED')
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : Icon(Icons.stop_circle_outlined, size: 14, color: (status == 'CONFIRMED' || status == 'STARTED') ? Colors.black : Colors.white.withOpacity(0.2)),
                    label: Text(
                      _isSendingMission && (status == 'CONFIRMED' || status == 'STARTED') ? '...' : 'TERMINER',
                      style: GoogleFonts.orbitron(fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: (status == 'CONFIRMED' || status == 'STARTED') ? Colors.greenAccent.withOpacity(0.8) : Colors.white.withOpacity(0.05),
                      disabledBackgroundColor: Colors.white.withOpacity(0.05),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ] else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {},
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.blueGrey),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text('DISMISS', style: GoogleFonts.orbitron(color: Colors.blueGrey, fontSize: 10)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      if (_interventionId != null && _latestNoteId != null) {
                        await ApiService.updateMissionStatus(_interventionId!, _latestNoteId!, 'CONFIRMED');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF09E8C).withOpacity(0.8),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text('CONFIRMER', style: GoogleFonts.orbitron(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildBandwidthChart() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('REAL_TIME_BANDWIDTH', style: GoogleFonts.spaceGrotesk(color: Colors.blueGrey, fontSize: 9, fontWeight: FontWeight.bold)),
            Text('$_bandwidth GB/S', style: GoogleFonts.orbitron(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 15),
        SizedBox(
          height: 80,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: 100,
              barTouchData: BarTouchData(enabled: false),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              gridData: const FlGridData(show: false),
              barGroups: _bandwidthHistory.asMap().entries.map((e) {
                return BarChartGroupData(
                  x: e.key,
                  barRods: [
                    BarChartRodData(
                      toY: e.value / 5,
                      color: Colors.cyanAccent.withOpacity(0.4),
                      width: 8,
                      borderRadius: BorderRadius.circular(1),
                      backDrawRodData: BackgroundBarChartRodData(
                        show: true,
                        toY: 100,
                        color: Colors.white.withOpacity(0.02),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomStatusBar() {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF05080E),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Row(
        children: [
          _buildStatusInfo('SERVER_STATUS: OPERATIONAL'),
          const SizedBox(width: 20),
          _buildStatusInfo('UPTIME: 1,442 HOURS'),
          const Spacer(),
          Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.cyanAccent, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          _buildStatusInfo('SYNC_ACTIVE'),
          const SizedBox(width: 20),
          _buildStatusInfo('OS_VERSION: 4.2.0_STABLE'),
        ],
      ),
    );
  }

  void _showMissionPopup(Map<String, dynamic> note) {
    final content = (note['content'] ?? '').toString().toUpperCase();
    final noteId = (note['id'] ?? note['_id'])?.toString();
    if (noteId == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0C1322),
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Colors.cyanAccent, width: 2),
          borderRadius: BorderRadius.circular(4),
        ),
        title: Row(
          children: [
            const Icon(Icons.rocket_launch_rounded, color: Colors.cyanAccent),
            const SizedBox(width: 10),
            Text(
              'NEW_MISSION_PROTOCOL // STATUT: ENVOYÉE',
              style: GoogleFonts.orbitron(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'OBJECTIF:',
              style: GoogleFonts.spaceGrotesk(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 5),
            Text(
              content,
              style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 20),
            Text(
              'ID MISSION:',
              style: GoogleFonts.spaceGrotesk(color: Colors.blueGrey, fontSize: 10, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 5),
            Text(
              noteId,
              style: GoogleFonts.jetBrainsMono(color: Colors.white70, fontSize: 10),
            ),
            const SizedBox(height: 15),
            Text(
              'ACTIONS_REQUISES:',
              style: GoogleFonts.spaceGrotesk(color: Colors.blueGrey, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.blueGrey)),
            child: Text('ANNULER', style: GoogleFonts.orbitron(color: Colors.blueGrey, fontSize: 12)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_interventionId != null) {
                // Optimistic update avant fermeture popup
                setState(() {
                  _latestMission?['missionStatus'] = 'CONFIRMED';
                  _latestNoteId = noteId;
                  for (var log in _logs) {
                    if (log['isMission'] == true && log['noteId'] == noteId) {
                      log['missionStatus'] = 'CONFIRMED';
                    }
                  }
                });
                Navigator.pop(ctx);
                try {
                  await ApiService.updateMissionStatus(_interventionId!, noteId, 'CONFIRMED');
                } catch (e) {
                  setState(() { _latestMission?['missionStatus'] = 'SENT'; });
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.redAccent));
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyanAccent,
              foregroundColor: Colors.black,
            ),
            child: Text('CONFIRMER', style: GoogleFonts.orbitron(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_interventionId != null) {
                setState(() {
                  _latestMission?['missionStatus'] = 'COMPLETED';
                  for (var log in _logs) {
                    if (log['isMission'] == true && log['noteId'] == noteId) {
                      log['missionStatus'] = 'COMPLETED';
                    }
                  }
                });
                Navigator.pop(ctx);
                try {
                  await ApiService.updateMissionStatus(_interventionId!, noteId, 'COMPLETED');
                } catch (e) {
                  setState(() { _latestMission?['missionStatus'] = 'CONFIRMED'; });
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.redAccent));
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.greenAccent,
              foregroundColor: Colors.black,
            ),
            child: Text('TERMINER', style: GoogleFonts.orbitron(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusInfo(String text) {
    return Text(
      text,
      style: GoogleFonts.jetBrainsMono(color: Colors.blueGrey, fontSize: 8, fontWeight: FontWeight.bold),
    );
  }
}

class CircuitPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.cyanAccent.withOpacity(0.1)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (var i = 0; i < 5; i++) {
      path.moveTo(0, 20.0 * i);
      path.lineTo(size.width * 0.3, 20.0 * i);
      path.lineTo(size.width * 0.4, 20.0 * i + 20);
      path.lineTo(size.width, 20.0 * i + 20);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
