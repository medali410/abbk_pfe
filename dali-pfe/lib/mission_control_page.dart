import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'services/api_service.dart';
import 'package:fl_chart/fl_chart.dart';
import 'widgets/machine_control_calendar_panel.dart';
import 'machine_detail_ai_page.dart';

/// Unifie les synonymes de fin de mission pour l’UI (libellés API ou locales).
String _normalizeMissionStatusString(Object? raw) {
  if (raw == null) return 'SENT';
  final t = raw.toString().trim();
  if (t.isEmpty) return 'SENT';
  final s = t.toUpperCase();
  const completed = {'COMPLETED', 'DONE', 'FINISHED', 'TERMINE', 'TERMINEE', 'TERMINÉ'};
  if (completed.contains(s)) return 'COMPLETED';
  return s;
}

class MissionControlPage extends StatefulWidget {
  const MissionControlPage({super.key, this.initialArgs});

  final Map<String, dynamic>? initialArgs;

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
  /// Identifiant machine Mongo (pour API temps de marche) — sans forcer la casse.
  String _resolvedMachineId = '';
  String _machineDisplayName = '';
  String _technicianNavId = '';
  /// `maintenance` lorsque l’écran est ouvert par l’agent maintenance (hub).
  String _viewerRole = '';

  bool get _isMaintenanceViewer =>
      _viewerRole.toLowerCase().trim() == 'maintenance';
  /// Vue focalisée : échanges mission + technicien, sans panneau métriques latéral.
  bool _maintenanceMissionMode = false;
  bool _marcheBusy = false;
  String _latestCoordNote = "Confirm node isolation to prevent cascade.";
  Map<String, dynamic>? _latestMission;
  String? _latestNoteId;
  String? _interventionId;
  bool _isSendingMission = false; // Verrou anti-double-clic
  /// Évite plusieurs chargements ; `_findActiveIntervention` doit partir après `techId` / `machineId` (didChangeDependencies).
  bool _interventionLogsLoaded = false;
  bool _scheduledInterventionBootstrap = false;
  
  List<Map<String, dynamic>> _technicians = [];
  bool _isLoadingTechnicians = false;
  
  List<Map<String, dynamic>> _allMachines = [];
  bool _isLoadingMachines = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args =
        widget.initialArgs ??
        (ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?);
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
      _resolvedMachineId = (args['machineId'] ?? args['techId'] ?? '').toString().trim();
      _machineDisplayName = (args['machineName'] ?? '').toString().trim();
      _technicianNavId = (args['technicianId'] ?? '').toString().trim();
      final vr = (args['viewerRole'] ?? '').toString().toLowerCase().trim();
      if (vr.isNotEmpty) _viewerRole = vr;
    }

    // InitState s’exécute avant didChangeDependencies : sans ce différé, `_techId` restait à la valeur par défaut
    // et aucune intervention n’était résolue → le technicien ne voyait pas les missions (socket filtré par id).
    if (!_scheduledInterventionBootstrap) {
      _scheduledInterventionBootstrap = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _findActiveIntervention();
          if (_isMaintenanceViewer) {
            _loadTechnicians();
          }
        }
      });
    }
  }

  Future<void> _loadTechnicians() async {
    setState(() {
      _isLoadingTechnicians = true;
      _isLoadingMachines = true;
    });
    try {
      final techs = await ApiService.getTechnicians();
      final machines = await ApiService.getMachines();
      if (mounted) {
        setState(() {
          _technicians = techs;
          _allMachines = machines;
        });
      }
    } catch (e) {
      debugPrint('Error loading technicians or machines: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingTechnicians = false;
          _isLoadingMachines = false;
        });
      }
    }
  }

  Future<void> _declarerMachineEnTravail() async {
    final mid = _resolvedMachineId;
    if (mid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Identifiant machine introuvable.')),
      );
      return;
    }
    setState(() => _marcheBusy = true);
    try {
      await ApiService.startMachineMarche(mid);
      if (!mounted) return;
      if (!context.mounted) return;
      final label = _machineDisplayName.isNotEmpty ? _machineDisplayName : mid;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '« $label » est en travail. Le temps de fonctionnement est enregistré ; les contrôles préventifs apparaissent au calendrier.',
          ),
          backgroundColor: const Color(0xFFFF6E00),
          action: _technicianNavId.isEmpty
              ? null
              : SnackBarAction(
                  label: 'Calendrier contrôle',
                  textColor: Colors.white,
                  onPressed: () {
                    if (!context.mounted) return;
                    Navigator.pushNamed(
                      context,
                      '/control-calendar',
                      arguments: <String, dynamic>{
                        'technicianName': _agentName,
                        'technicianId': _technicianNavId,
                        if (_resolvedMachineId.isNotEmpty) 'machineId': _resolvedMachineId,
                        if (_machineDisplayName.isNotEmpty) 'machineName': _machineDisplayName,
                        if (_resolvedMachineId.isNotEmpty) 'machineIds': <String>[_resolvedMachineId],
                      },
                    );
                  },
                ),
        ),
      );
    } catch (e) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _marcheBusy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _initSocket();
  }

  Future<void> _findActiveIntervention() async {
    if (_interventionLogsLoaded) return;
    try {
      final list = await ApiService.getDiagnosticInterventions();
      Map<String, dynamic> active = {};

      final presetId = _interventionId?.trim();
      if (presetId != null && presetId.isNotEmpty) {
        for (final raw in list) {
          final i = Map<String, dynamic>.from(raw as Map);
          if (i['id']?.toString() == presetId) {
            active = i;
            break;
          }
        }
      }

      if (active.isEmpty) {
        final midArg = _resolvedMachineId.toUpperCase().trim();
        final techIdNav = _technicianNavId.toUpperCase().trim();
        final techName = _techId.toUpperCase().trim();

        active = list.lastWhere(
          (i) {
            final isOpen = i['status'] != 'DONE' && i['status'] != 'CANCELLED';
            if (!isOpen) return false;

            final mId = (i['machineId'] ?? '').toString().toUpperCase();
            final mName = (i['machineName'] ?? '').toString().toUpperCase();
            final tId = (i['technicianId'] ?? '').toString().toUpperCase();
            final tName = (i['technicianName'] ?? '').toString().toUpperCase();

            final matchMachine = (midArg.isNotEmpty && mId == midArg) || (mName.isNotEmpty && mName == midArg);
            
            if (_isMaintenanceViewer && techIdNav.isNotEmpty) {
                // En mode maintenance avec technicien sélectionné, on exige machine ET technicien
                return matchMachine && (tId == techIdNav || tName == techName);
            }

            return mId == _techId ||
                mName == _techId ||
                tId == _techId ||
                matchMachine;
          },
          orElse: () => <String, dynamic>{},
        );
      }

      if (active.containsKey('id')) {
        setState(() {
          _interventionId = active['id'].toString();
          
          // Charger l'historique des messages
          final messages = List.from(active['messages'] ?? []);
          for (var msg in messages) {
            final author = (msg['authorName'] ?? msg['authorRole'] ?? 'Unknown').toString().toUpperCase();
            final isMe = author == _agentName.toUpperCase();
            final mid = (msg['_id'] ?? msg['id'])?.toString();

            _logs.add({
              'type': isMe ? 'YOU' : 'MAINT_HUB // $author',
              'text': msg['content'] ?? '',
              'timestamp': msg['createdAt'] != null 
                  ? TimeOfDay.fromDateTime(DateTime.parse(msg['createdAt'])).format(context)
                  : '--:--',
              if (mid != null && mid.isNotEmpty) 'messageId': mid,
              'missionStatus': msg['missionStatus'],
            });

            if (_isMaintenanceViewer &&
                mid != null &&
                mid.isNotEmpty &&
                msg['missionStatus'] != null) {
              final raw = (msg['content'] ?? '').toString();
              final msgSt = _normalizeMissionStatusString(msg['missionStatus']);

              if (msgSt == 'COMPLETED') {
                if (msg['missionConfirmedAt'] != null &&
                    !_logs.any((l) => l['completionEchoKey'] == 'confirm-msg:$mid')) {
                  final echoTsC = TimeOfDay.fromDateTime(
                    DateTime.parse(msg['missionConfirmedAt'].toString()).toLocal(),
                  ).format(context);
                  final tc = raw.trim();
                  final confirmBody = tc.isEmpty
                      ? 'Le technicien a confirmé la mission.'
                      : 'Mission confirmée par le technicien — « $tc ».';
                  _logs.add({
                    'type': 'TECHNICIEN // CONFIRMÉ',
                    'text': confirmBody,
                    'timestamp': echoTsC,
                    'skipAck': true,
                    'completionEchoKey': 'confirm-msg:$mid',
                  });
                }
                final echoTs = msg['missionCompletedAt'] != null
                    ? TimeOfDay.fromDateTime(DateTime.parse(msg['missionCompletedAt'].toString()).toLocal())
                        .format(context)
                    : TimeOfDay.fromDateTime(DateTime.now()).format(context);
                final t = raw.trim();
                final echoBody = t.isEmpty
                    ? 'Le technicien a terminé le contrôle. Mission clôturée.'
                    : 'Contrôle terminé : « $t » — mission clôturée par le technicien.';
                if (!_logs.any((l) => l['completionEchoKey'] == 'msg:$mid')) {
                  _logs.add({
                    'type': 'TECHNICIEN // TERMINÉ',
                    'text': echoBody,
                    'timestamp': echoTs,
                    'skipAck': true,
                    'completionEchoKey': 'msg:$mid',
                  });
                }
              } else if (msgSt == 'CONFIRMED' || msgSt == 'STARTED') {
                final echoTs = msg['missionConfirmedAt'] != null
                    ? TimeOfDay.fromDateTime(DateTime.parse(msg['missionConfirmedAt'].toString()).toLocal())
                        .format(context)
                    : TimeOfDay.fromDateTime(DateTime.now()).format(context);
                final tc = raw.trim();
                final confirmBody = tc.isEmpty
                    ? 'Le technicien a confirmé la mission.'
                    : 'Mission confirmée par le technicien — « $tc ».';
                if (!_logs.any((l) => l['completionEchoKey'] == 'confirm-msg:$mid')) {
                  _logs.add({
                    'type': 'TECHNICIEN // CONFIRMÉ',
                    'text': confirmBody,
                    'timestamp': echoTs,
                    'skipAck': true,
                    'completionEchoKey': 'confirm-msg:$mid',
                  });
                }
              }
            }
          }

          final notes = List.from(active['coordinationNotes'] ?? []);
          if (notes.isNotEmpty) {
            for (var note in notes) {
              final isM = note['isMission'] == true || note['missionStatus'] != null;
              final nId = (note['_id'] ?? note['id'])?.toString();
              final authorU =
                  (note['authorName'] ?? note['authorRole'] ?? '').toString().toUpperCase();
              final skipAck = authorU == _agentName.toUpperCase();
              final displayMissionAsYou =
                  skipAck && isM && _isMaintenanceViewer;

              if (isM) {
                _latestMission = Map<String, dynamic>.from(note);
                _latestMission!['id'] = nId;
              }
              _latestNoteId = nId;
              _latestCoordNote = (note['content'] ?? '').toString().toUpperCase();

              final mIdStr = (active['machineId'] ?? '').toString();
              final rawMName = (active['machineName'] ?? '').toString();
              final mNamePrefix = (rawMName.isNotEmpty ? rawMName : (mIdStr.isNotEmpty ? mIdStr : _machineDisplayName)).toString();
              final prefix = mNamePrefix.isNotEmpty ? '[$mNamePrefix] ' : '[$_resolvedMachineId] ';

              _logs.add({
                "type": displayMissionAsYou
                    ? "YOU"
                    : (isM ? "CRITICAL_EVENT" : "OP_TECH"),
                "text": displayMissionAsYou
                    ? '$prefix${(note['content'] ?? '').toString()}'
                    : '$prefix$_latestCoordNote',
                "timestamp": note['createdAt'] != null 
                    ? TimeOfDay.fromDateTime(DateTime.parse(note['createdAt'])).format(context)
                    : '--:--',
                "isMission": isM,
                "noteId": nId,
                "machineId": mIdStr,
                "missionStatus": note['missionStatus'] ?? (skipAck ? null : 'SENT'),
                if (skipAck || displayMissionAsYou) "skipAck": true,
              });

              if (_isMaintenanceViewer && isM && nId != null && nId.isNotEmpty) {
                final rawMission = (note['content'] ?? '').toString();
                final noteSt = _normalizeMissionStatusString(note['missionStatus']);

                if (noteSt == 'COMPLETED') {
                  if (note['missionConfirmedAt'] != null &&
                      !_logs.any((l) => l['completionEchoKey'] == 'confirm-note:$nId')) {
                    final echoTsC = TimeOfDay.fromDateTime(
                      DateTime.parse(note['missionConfirmedAt'].toString()).toLocal(),
                    ).format(context);
                    final trimmedC = rawMission.trim();
                    final confirmBody = trimmedC.isEmpty
                        ? 'Le technicien a confirmé la mission.'
                        : 'Mission confirmée par le technicien — « $trimmedC ».';
                    _logs.add({
                      'type': 'TECHNICIEN // CONFIRMÉ',
                      'text': confirmBody,
                      'timestamp': echoTsC,
                      'skipAck': true,
                      'completionEchoKey': 'confirm-note:$nId',
                    });
                  }
                  final echoTs = note['missionCompletedAt'] != null
                      ? TimeOfDay.fromDateTime(DateTime.parse(note['missionCompletedAt'].toString()).toLocal())
                          .format(context)
                      : TimeOfDay.fromDateTime(DateTime.now()).format(context);
                  final trimmed = rawMission.trim();
                  final echoBody = trimmed.isEmpty
                      ? 'Le technicien a terminé le contrôle. Mission clôturée.'
                      : 'Contrôle terminé : « $trimmed » — mission clôturée par le technicien.';
                  if (!_logs.any((l) => l['completionEchoKey'] == 'note:$nId')) {
                    _logs.add({
                      'type': 'TECHNICIEN // TERMINÉ',
                      'text': echoBody,
                      'timestamp': echoTs,
                      'skipAck': true,
                      'completionEchoKey': 'note:$nId',
                    });
                  }
                } else if (noteSt == 'CONFIRMED' || noteSt == 'STARTED') {
                  final echoTs = note['missionConfirmedAt'] != null
                      ? TimeOfDay.fromDateTime(DateTime.parse(note['missionConfirmedAt'].toString()).toLocal())
                          .format(context)
                      : TimeOfDay.fromDateTime(DateTime.now()).format(context);
                  final trimmed = rawMission.trim();
                  final confirmBody = trimmed.isEmpty
                      ? 'Le technicien a confirmé la mission.'
                      : 'Mission confirmée par le technicien — « $trimmed ».';
                  if (!_logs.any((l) => l['completionEchoKey'] == 'confirm-note:$nId')) {
                    _logs.add({
                      'type': 'TECHNICIEN // CONFIRMÉ',
                      'text': confirmBody,
                      'timestamp': echoTs,
                      'skipAck': true,
                      'completionEchoKey': 'confirm-note:$nId',
                    });
                  }
                }
              }
            }
          }
        });
        _interventionLogsLoaded = true;
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('Error finding active intervention: $e');
    }
  }

  void _initSocket() {
    final baseUrl = ApiService.baseUrl.replaceFirst('/api', '');
    _socket = IO.io(baseUrl, <String, dynamic>{
      'transports': <String>['websocket'],
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
      if (!mounted) return;
      final incomingInterventionId = data['interventionId'].toString();
      debugPrint('COORD_RECV: $incomingInterventionId (Current: $_interventionId)');

      if (_interventionId == null || _interventionId == '') {
        _interventionId = incomingInterventionId;
      }

      if (incomingInterventionId != _interventionId) return;

      final rawNote = data['note'];
      if (rawNote is! Map) return;
      _mergeIncomingCoordinationNote(Map<String, dynamic>.from(rawNote));
    });

    _socket!.on('diagnostic_coordination_update', (data) {
      if (!mounted) return;
      if (data['interventionId'].toString() != _interventionId) return;
      final noteId = data['noteId']?.toString();
      final status = data['status']?.toString().toUpperCase().trim() ?? '';

      setState(() {
        if (_latestMission != null && (_latestMission!['id'] == noteId || _latestMission!['_id'] == noteId)) {
          _latestMission!['missionStatus'] = status;
        }
        for (var log in _logs) {
          if (log['noteId']?.toString() == noteId) {
            log['missionStatus'] = status;
          }
        }
      });

      if (!mounted) return;
      if (_isMaintenanceViewer &&
          (status == 'CONFIRMED' || status == 'STARTED') &&
          noteId != null &&
          noteId.isNotEmpty) {
        final snippet = _missionSnippetFromLogs(noteId: noteId);
        final fallback = (_latestMission != null &&
                (_latestMission!['id']?.toString() == noteId ||
                    _latestMission!['_id']?.toString() == noteId))
            ? (_latestMission!['content'] ?? '').toString()
            : '';
        _appendMaintenanceConfirmationEcho(
          confirmationKey: 'confirm-note:$noteId',
          missionSnippet: snippet.isNotEmpty ? snippet : fallback,
        );
      }

      if (!mounted) return;
      if (_isMaintenanceViewer &&
          status == 'COMPLETED' &&
          noteId != null &&
          noteId.isNotEmpty) {
        final snippet = _missionSnippetFromLogs(noteId: noteId);
        final fallback = (_latestMission != null &&
                (_latestMission!['id']?.toString() == noteId ||
                    _latestMission!['_id']?.toString() == noteId))
            ? (_latestMission!['content'] ?? '').toString()
            : '';
        _appendMaintenanceCompletionEcho(
          completionKey: 'note:$noteId',
          missionSnippet: snippet.isNotEmpty ? snippet : fallback,
        );
      }

      if (!mounted) return;
      if (_isMaintenanceViewer) {
        if (status == 'CONFIRMED') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Le technicien a confirmé la mission.',
                style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600),
              ),
              backgroundColor: const Color(0xFFFF6E00),
              duration: const Duration(seconds: 5),
            ),
          );
        } else if (status == 'COMPLETED') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Le technicien a terminé la mission.',
                style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600),
              ),
              backgroundColor: const Color(0xFF2E7D32),
              duration: const Duration(seconds: 6),
            ),
          );
        }
      } else {
        if (status == 'CONFIRMED') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('MISSION CONFIRMÉE / STARTED'), backgroundColor: Colors.cyanAccent),
          );
        } else if (status == 'COMPLETED') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('MISSION TERMINÉE / DONE'), backgroundColor: Colors.greenAccent),
          );
        }
      }
    });

    _socket!.on('diagnostic_message_update', (data) {
      if (!mounted) return;
      if (data['interventionId'].toString() != _interventionId) return;
      final messageId = data['messageId']?.toString();
      final status = data['status']?.toString().toUpperCase().trim() ?? '';
      setState(() {
        for (var log in _logs) {
          if (log['messageId']?.toString() == messageId) {
            log['missionStatus'] = status;
          }
        }
      });
      if (!mounted) return;
      if (_isMaintenanceViewer &&
          (status == 'CONFIRMED' || status == 'STARTED') &&
          messageId != null &&
          messageId.isNotEmpty) {
        final snippet = _missionSnippetFromLogs(messageId: messageId);
        _appendMaintenanceConfirmationEcho(
          confirmationKey: 'confirm-msg:$messageId',
          missionSnippet: snippet,
        );
      }

      if (!mounted) return;
      if (_isMaintenanceViewer &&
          status == 'COMPLETED' &&
          messageId != null &&
          messageId.isNotEmpty) {
        final snippet = _missionSnippetFromLogs(messageId: messageId);
        _appendMaintenanceCompletionEcho(
          completionKey: 'msg:$messageId',
          missionSnippet: snippet,
        );
      }
      if (!mounted) return;
      if (_isMaintenanceViewer) {
        if (status == 'CONFIRMED') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Le technicien a confirmé le message.',
                style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600),
              ),
              backgroundColor: const Color(0xFFFF6E00),
              duration: const Duration(seconds: 5),
            ),
          );
        } else if (status == 'COMPLETED') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Le technicien a terminé : mission / consigne effectuée.',
                style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600),
              ),
              backgroundColor: const Color(0xFF2E7D32),
              duration: const Duration(seconds: 6),
            ),
          );
        }
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

        final mid = (msg['_id'] ?? msg['id'])?.toString();
        setState(() {
          _logs.add({
            'type': 'MAINT_HUB // $author',
            'text': msg['content'],
            'timestamp': msg['createdAt'] != null 
                ? TimeOfDay.fromDateTime(DateTime.parse(msg['createdAt'])).format(context)
                : 'NOW',
            if (mid != null && mid.isNotEmpty) 'messageId': mid,
            'missionStatus': msg['missionStatus'] ?? 'SENT',
          });
        });
        _scrollToBottom();
      }
    });
  }

  String _coordinationTimestampFromNote(Map<String, dynamic> note) {
    final raw = note['createdAt'];
    if (raw != null) {
      final dt = DateTime.tryParse(raw.toString());
      if (dt != null) {
        return TimeOfDay.fromDateTime(dt.toLocal()).format(context);
      }
    }
    return DateTime.now().toLocal().toString().substring(11, 16);
  }

  String _missionSnippetFromLogs({String? noteId, String? messageId}) {
    if (noteId != null && noteId.isNotEmpty) {
      for (final l in _logs) {
        if (l['noteId']?.toString() == noteId && l['isMission'] == true) {
          return (l['text'] ?? '').toString();
        }
      }
    }
    if (messageId != null && messageId.isNotEmpty) {
      for (final l in _logs) {
        if (l['messageId']?.toString() == messageId) {
          return (l['text'] ?? '').toString();
        }
      }
    }
    return '';
  }

  /// Message visible côté maintenance quand le technicien clôt la mission (fil type chat).
  void _appendMaintenanceCompletionEcho({
    required String completionKey,
    required String missionSnippet,
  }) {
    if (!_isMaintenanceViewer) return;
    if (_logs.any((l) => l['completionEchoKey']?.toString() == completionKey)) return;

    final ts = TimeOfDay.fromDateTime(DateTime.now()).format(context);
    final trimmed = missionSnippet.trim();
    final body = trimmed.isEmpty
        ? 'Le technicien a terminé le contrôle. Mission clôturée.'
        : 'Contrôle terminé : « $trimmed » — mission clôturée par le technicien.';

    setState(() {
      _logs.add({
        'type': 'TECHNICIEN // TERMINÉ',
        'text': body,
        'timestamp': ts,
        'skipAck': true,
        'completionEchoKey': completionKey,
      });
      if (_logs.length > 50) _logs.removeAt(0);
    });
    _scrollToBottom();
  }

  /// Message visible côté maintenance quand le technicien confirme la mission (fil type chat).
  void _appendMaintenanceConfirmationEcho({
    required String confirmationKey,
    required String missionSnippet,
  }) {
    if (!_isMaintenanceViewer) return;
    if (_logs.any((l) => l['completionEchoKey']?.toString() == confirmationKey)) return;

    final ts = TimeOfDay.fromDateTime(DateTime.now()).format(context);
    final trimmed = missionSnippet.trim();
    final body = trimmed.isEmpty
        ? 'Le technicien a confirmé la mission.'
        : 'Mission confirmée par le technicien — « $trimmed ».';

    setState(() {
      _logs.add({
        'type': 'TECHNICIEN // CONFIRMÉ',
        'text': body,
        'timestamp': ts,
        'skipAck': true,
        'completionEchoKey': confirmationKey,
      });
      if (_logs.length > 50) _logs.removeAt(0);
    });
    _scrollToBottom();
  }

  /// Note persistée en base (websocket `diagnostic_coordination` ou réponse HTTP) — dédoublonnage par `noteId`.
  void _mergeIncomingCoordinationNote(Map<String, dynamic> note) {
    final nid = (note['id'] ?? note['_id'])?.toString();
    if (nid != null &&
        nid.isNotEmpty &&
        _logs.any((l) => l['noteId']?.toString() == nid)) {
      return;
    }
    if (!mounted) return;

    final isM = note['isMission'] == true ||
        note['isMission'] == 'true' ||
        note['missionStatus'] != null;

    setState(() {
      final upperCoord = (note['content'] ?? '').toString().toUpperCase();
      _latestCoordNote = upperCoord;
      final parsedId = (note['id'] ?? note['_id'])?.toString();
      _latestNoteId = parsedId;

      if (isM) {
        _latestMission = Map<String, dynamic>.from(note);
        _latestMission!['id'] = parsedId;
      }

      final author = (note['authorName'] ?? 'AGENCE').toString().toUpperCase();
      final hubSkip = author == _agentName.toUpperCase();
      final displayMissionAsYou = hubSkip && isM && _isMaintenanceViewer;

      final ts = _coordinationTimestampFromNote(note);

      final mNamePrefix = _machineDisplayName.isNotEmpty ? _machineDisplayName : _resolvedMachineId;
      final prefix = mNamePrefix.isNotEmpty ? '[$mNamePrefix] ' : '';

      _logs.add({
        'type': displayMissionAsYou
            ? 'YOU'
            : (isM ? 'CRITICAL_EVENT' : 'MAINT_HUB // $author'),
        'text': displayMissionAsYou
            ? '$prefix${(note['content'] ?? '').toString()}'
            : '$prefix$upperCoord',
        'timestamp': ts,
        'isMission': isM,
        'noteId': parsedId,
        'machineId': _resolvedMachineId,
        'missionStatus': note['missionStatus'] ?? (hubSkip ? null : 'SENT'),
        if (hubSkip || displayMissionAsYou) 'skipAck': true,
      });
      if (_logs.length > 50) _logs.removeAt(0);
    });

    if (isM && !_isMaintenanceViewer && note['missionStatus'] == 'SENT') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showMissionPopup(note);
      });
    }

    _scrollToBottom();
  }

  Future<void> _sendCommand() async {
    final cmd = _commandController.text.trim();
    if (cmd.isEmpty) return;

    _socket!.emit('mission_control_command', {'command': cmd});

    if (_interventionId == null) {
      if (_isMaintenanceViewer && _technicianNavId.isNotEmpty) {
        try {
          final newIntervention = await ApiService.createDiagnosticIntervention({
            'machineId': _resolvedMachineId,
            'machineName': _machineDisplayName.isNotEmpty ? _machineDisplayName : _resolvedMachineId,
            'technicianId': _technicianNavId,
            'technicianName': _techId,
            'status': 'IN_PROGRESS',
            'severity': 'MEDIUM',
          });
          _interventionId = newIntervention['id']?.toString() ?? newIntervention['_id']?.toString();
        } catch (e) {
          debugPrint('Failed to create intervention: $e');
        }
      }

      if (_interventionId == null) {
        _appendLocalOutgoingChat(cmd);
        return;
      }
    }

    // Mission terrain : persistance `coordinationNotes` + table Mission + diffusion websocket au technicien.
    if (_isMaintenanceViewer && _maintenanceMissionMode) {
      unawaited(_sendMissionCoordinationNote(cmd));
      return;
    }

    ApiService.addDiagnosticMessage(_interventionId!, cmd, authorName: _agentName);
    _appendLocalOutgoingChat(cmd);
  }

  void _appendLocalOutgoingChat(String cmd) {
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

  Future<void> _sendMissionCoordinationNote(String cmd) async {
    final id = _interventionId;
    if (id == null) return;
    try {
      final body = await ApiService.addCoordinationNote(
        id,
        cmd,
        authorName: _agentName,
        isMission: true,
      );
      _commandController.clear();
      final raw = body['note'];
      if (raw is Map) {
        _mergeIncomingCoordinationNote(Map<String, dynamic>.from(raw));
      }
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur envoi mission: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
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

  bool _technicianNeedsAckRow(Map<String, dynamic> log) {
    if (log['skipAck'] == true) return false;
    if (log['type'] == 'YOU') return false;
    final nid = log['noteId']?.toString();
    final mid = log['messageId']?.toString();
    return (nid != null && nid.isNotEmpty) || (mid != null && mid.isNotEmpty);
  }

  bool _maintShowsAckChip(Map<String, dynamic> log) {
    if (!_isMaintenanceViewer) return false;
    if (log['skipAck'] == true || log['type'] == 'YOU') return false;
    final nid = log['noteId']?.toString();
    final mid = log['messageId']?.toString();
    final hasId = (nid != null && nid.isNotEmpty) || (mid != null && mid.isNotEmpty);
    return log['isMission'] == true || hasId;
  }

  String _ackStatus(Map<String, dynamic> log) {
    final raw = log['missionStatus'] ?? log['status'];
    return _normalizeMissionStatusString(raw);
  }

  Future<void> _applyTechnicianAck(Map<String, dynamic> log, String status) async {
    final iid = _interventionId;
    if (iid == null) return;
    final msgId = log['messageId']?.toString();
    final noteId = log['noteId']?.toString();
    final prev = log['missionStatus']?.toString();

    setState(() {
      log['missionStatus'] = status;
      final lnid = noteId;
      if (_latestMission != null &&
          lnid != null &&
          lnid.isNotEmpty &&
          (_latestMission!['id']?.toString() == lnid ||
              _latestMission!['_id']?.toString() == lnid)) {
        _latestMission!['missionStatus'] = status;
      }
    });

    try {
      if (msgId != null && msgId.isNotEmpty) {
        await ApiService.updateDiagnosticMessageStatus(iid, msgId, status);
      } else if (noteId != null && noteId.isNotEmpty) {
        await ApiService.updateMissionStatus(iid, noteId, status);
      } else {
        setState(() => log['missionStatus'] = prev);
      }
    } catch (e) {
      setState(() => log['missionStatus'] = prev);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
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
    final maintenanceUi = _viewerRole == 'maintenance';
    final missionFocus = maintenanceUi && _maintenanceMissionMode;

    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      body: Column(
        children: [
          _buildTopNav(),
          Expanded(
            child: (missionFocus || !_isMaintenanceViewer)
                ? _buildTerminalArea()
                : Row(
                    children: [
                      Expanded(flex: 3, child: _buildTerminalArea()),
                      Expanded(flex: 1, child: _buildTechnicianSidebar()),
                    ],
                  ),
          ),
          if (!missionFocus) _buildBottomStatusBar(),
        ],
      ),
    );
  }

  Widget _buildTopNav() {
    final isMaint = _viewerRole == 'maintenance';
    final machineLabel = _machineDisplayName.isNotEmpty
        ? _machineDisplayName
        : (_resolvedMachineId.isNotEmpty ? _resolvedMachineId : '—');

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: isMaint ? 8 : 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E14),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Ligne 1 : Retour + Titre + Chip maintenance ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white70),
                tooltip: 'Retour',
                onPressed: () => Navigator.of(context).pop(),
              ),
              Tooltip(
                message: 'Vider le fil (historique local uniquement).',
                child: IconButton(
                  icon: const Icon(Icons.layers_clear_rounded, color: Colors.blueGrey),
                  onPressed: () {
                    setState(() => _logs.clear());
                    _scrollToBottom();
                  },
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isMaint
                          ? 'MISSION_CONTROL · $machineLabel'
                          : 'TECH_OS // MISSION_CONTROL // $_agentName',
                      style: GoogleFonts.orbitron(
                        color: isMaint ? const Color(0xFFFF6E00) : Colors.cyanAccent,
                        fontSize: isMaint ? 13 : 15,
                        fontWeight: FontWeight.bold,
                        letterSpacing: isMaint ? 1.2 : 1.8,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (isMaint) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Technicien terrain ↔ Maintenance',
                        style: GoogleFonts.spaceGrotesk(
                          color: Colors.blueGrey,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (isMaint)
                FilterChip(
                  label: Text(
                    'Mode mission',
                    style: GoogleFonts.spaceGrotesk(
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      color: _maintenanceMissionMode ? Colors.black87 : Colors.white,
                    ),
                  ),
                  selected: _maintenanceMissionMode,
                  onSelected: (v) => setState(() => _maintenanceMissionMode = v),
                  selectedColor: const Color(0xFFFF6E00),
                  checkmarkColor: Colors.black87,
                  avatar: Icon(
                    Icons.center_focus_strong_outlined,
                    size: 18,
                    color: _maintenanceMissionMode ? Colors.black87 : const Color(0xFFFF6E00),
                  ),
                ),
            ],
          ),
          // ── Ligne 2 (technicien uniquement) : Onglets de navigation ──
          if (!isMaint)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildNavTab('SYSTEM_HUB', false),
                  _buildNavTab('FLEET_SYNC', true),
                  _buildNavTab('NETWORK_LOGS', false),
                  const SizedBox(width: 12),
                  const Icon(Icons.notifications_none, color: Colors.cyanAccent, size: 20),
                  const SizedBox(width: 12),
                  const Icon(Icons.dashboard_customize_outlined, color: Colors.cyanAccent, size: 20),
                ],
              ),
            ),
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

  Widget _missionReadOnlyBanner({required String title, required String content, required String status}) {
    final st = _normalizeMissionStatusString(status);
    final Color accent = st == 'COMPLETED'
        ? Colors.greenAccent
        : st == 'CONFIRMED' || st == 'STARTED'
            ? Colors.cyanAccent
            : const Color(0xFFFF6E00);
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.06),
        border: Border.all(color: accent.withOpacity(0.85), width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.visibility_outlined, color: accent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.orbitron(color: accent, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: accent.withOpacity(0.5)),
                ),
                child: Text(
                  st == 'SENT' || st == 'PENDING'
                      ? 'ENVOYÉE'
                      : st == 'COMPLETED'
                          ? 'TERMINÉ'
                          : 'EN COURS',
                  style: GoogleFonts.spaceGrotesk(color: accent, fontSize: 9, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            content,
            style: GoogleFonts.spaceGrotesk(color: Colors.white.withOpacity(0.92), fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            'Le technicien confirme et termine depuis son Mission Control.',
            style: GoogleFonts.spaceGrotesk(color: Colors.blueGrey, fontSize: 10, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveMissionHeader() {
    if (_latestMission == null) {
      return const SizedBox.shrink();
    }

    final missionStat = _latestMission!['missionStatus'] ?? _latestMission!['status'];
    final rawStatus = (missionStat ?? 'PENDING').toString();
    final content = (_latestMission!['content'] ?? '').toString().toUpperCase();

    if (_isMaintenanceViewer) {
      return const SizedBox.shrink();
    }

    if (_normalizeMissionStatusString(missionStat) == 'COMPLETED') {
      return const SizedBox.shrink();
    }

    final status = _normalizeMissionStatusString(missionStat ?? rawStatus);
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
            child: _logs.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Fil vide — les nouveaux messages apparaîtront ici.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.spaceGrotesk(
                          color: Colors.blueGrey,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.only(bottom: 20),
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      return _buildLogEntry(_logs[index]);
                    },
                  ),
          ),
          if (_isMaintenanceViewer) _buildCommandInput(),
        ],
      ),
    );
  }

  Widget _buildLogEntry(Map<String, dynamic> log) {
    Color accentColor;
    String type = log['type'];
    bool isMe = type == 'YOU';
    
    if (type.startsWith('TECHNICIEN')) {
      accentColor =
          type.contains('CONFIRM') ? Colors.cyanAccent : Colors.greenAccent;
    } else if (type.startsWith('OP_TECH')) {
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
                  if (_maintShowsAckChip(log)) ...[
                    const SizedBox(height: 15),
                    _MaintenanceMissionStatusChip(status: _ackStatus(log)),
                  ] else if (_technicianNeedsAckRow(log)) ...[
                    const SizedBox(height: 15),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (_ackStatus(log) != 'COMPLETED') ...[
                          ElevatedButton.icon(
                            onPressed: (_ackStatus(log) == 'SENT' || _ackStatus(log) == 'PENDING')
                                ? () => _applyTechnicianAck(log, 'CONFIRMED')
                                : null,
                            icon: Icon(
                              (_ackStatus(log) == 'SENT' || _ackStatus(log) == 'PENDING')
                                  ? Icons.circle_outlined
                                  : Icons.check_circle,
                              size: 12,
                              color: (_ackStatus(log) == 'SENT' || _ackStatus(log) == 'PENDING')
                                  ? Colors.black
                                  : Colors.greenAccent,
                            ),
                            label: Text(
                              (_ackStatus(log) == 'SENT' || _ackStatus(log) == 'PENDING')
                                  ? 'CONFIRMER'
                                  : 'CONFIRMÉ',
                              style: GoogleFonts.orbitron(fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: (_ackStatus(log) == 'SENT' || _ackStatus(log) == 'PENDING')
                                  ? Colors.cyanAccent
                                  : Colors.white.withOpacity(0.05),
                              foregroundColor: (_ackStatus(log) == 'SENT' || _ackStatus(log) == 'PENDING')
                                  ? Colors.black
                                  : Colors.white.withOpacity(0.3),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: (_ackStatus(log) == 'CONFIRMED' || _ackStatus(log) == 'STARTED')
                                ? () => _applyTechnicianAck(log, 'COMPLETED')
                                : null,
                            icon: Icon(
                              Icons.stop_circle_outlined,
                              size: 12,
                              color: (_ackStatus(log) == 'CONFIRMED' || _ackStatus(log) == 'STARTED')
                                  ? Colors.black
                                  : Colors.white.withOpacity(0.2),
                            ),
                            label: Text(
                              'TERMINER',
                              style: GoogleFonts.orbitron(fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: (_ackStatus(log) == 'CONFIRMED' || _ackStatus(log) == 'STARTED')
                                  ? Colors.greenAccent
                                  : Colors.white.withOpacity(0.05),
                              foregroundColor: (_ackStatus(log) == 'CONFIRMED' || _ackStatus(log) == 'STARTED')
                                  ? Colors.black
                                  : Colors.white.withOpacity(0.2),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                        ],
                        if (_ackStatus(log) == 'COMPLETED') ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.greenAccent.withOpacity(0.5)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 14),
                                const SizedBox(width: 6),
                                Text(
                                  'TERMINÉ',
                                  style: GoogleFonts.orbitron(
                                    color: Colors.greenAccent,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (log['machineId'] != null && log['machineId'].toString().isNotEmpty) ...[
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MachineDetailAiPage(machineId: log['machineId'].toString()),
                                ),
                              );
                            },
                            icon: const Icon(Icons.remove_red_eye_outlined, size: 12, color: Colors.black),
                            label: Text('AFFICHER', style: GoogleFonts.orbitron(fontSize: 9, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (_ackStatus(log) == 'SENT' || _ackStatus(log) == 'PENDING') ...[
                      const SizedBox(height: 8),
                      Text(
                        'Confirmer : la maintenance voit que vous avez bien reçu la mission. Terminer : enregistre la fin du contrôle en base.',
                        style: GoogleFonts.spaceGrotesk(
                          color: Colors.white.withOpacity(0.45),
                          fontSize: 10,
                          height: 1.35,
                        ),
                      ),
                    ] else if (_ackStatus(log) == 'CONFIRMED' || _ackStatus(log) == 'STARTED') ...[
                      const SizedBox(height: 8),
                      Text(
                        'Quand le contrôle est terminé, appuyez sur Terminer — la maintenance le verra et les données seront stockées.',
                        style: GoogleFonts.spaceGrotesk(
                          color: Colors.white.withOpacity(0.45),
                          fontSize: 10,
                          height: 1.35,
                        ),
                      ),
                    ],
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
    final maintMission = _maintenanceMissionMode;
    final hint = maintMission
        ? 'Message au technicien (mission)…'
        : 'Message au technicien…';

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1322),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: maintMission
              ? const Color(0xFFFF6E00).withOpacity(0.35)
              : Colors.white.withOpacity(0.05),
        ),
      ),
      child: Row(
        children: [
          Text(
            maintMission ? '>>' : '>_',
            style: TextStyle(
              color: maintMission ? const Color(0xFFFF6E00) : Colors.cyanAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: TextField(
              controller: _commandController,
              onSubmitted: (_) => _sendCommand(),
              style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: GoogleFonts.jetBrainsMono(color: Colors.blueGrey, fontSize: 14),
                border: InputBorder.none,
              ),
            ),
          ),
          TextButton(
            onPressed: _sendCommand,
            style: TextButton.styleFrom(
              backgroundColor: maintMission
                  ? const Color(0xFFFF6E00).withOpacity(0.9)
                  : Colors.cyanAccent.withOpacity(0.8),
            ),
            child: Text(
              'ENVOYER',
              style: GoogleFonts.orbitron(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTechnicianSidebar() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF090D18),
        border: Border(left: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('TECHNICIENS_DISPONIBLES'),
          const SizedBox(height: 14),
          if (_isLoadingTechnicians)
            const Center(child: CircularProgressIndicator(color: Color(0xFF00FFCC)))
          else if (_technicians.isEmpty)
            Text('Aucun technicien trouvé.',
                style: GoogleFonts.spaceGrotesk(color: Colors.white54, fontSize: 13))
          else
            Expanded(
              child: ListView.builder(
                itemCount: _technicians.length,
                itemBuilder: (context, index) {
                  final t = _technicians[index];
                  final name = (t['name'] ?? '').toString();
                  final tId = (t['_id'] ?? t['id'] ?? '').toString();
                  final isSelected = _technicianNavId == tId;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF00FFCC).withOpacity(0.15)
                          : Colors.white.withOpacity(0.02),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF00FFCC)
                            : Colors.white.withOpacity(0.05),
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        iconColor: isSelected ? const Color(0xFF00FFCC) : Colors.white70,
                        collapsedIconColor: isSelected ? const Color(0xFF00FFCC) : Colors.white70,
                        title: Text(
                          name.toUpperCase(),
                          style: GoogleFonts.spaceGrotesk(
                            color: isSelected ? const Color(0xFF00FFCC) : Colors.white70,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          'ID: $tId',
                          style: GoogleFonts.spaceGrotesk(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                        onExpansionChanged: (expanded) {
                          // No dynamic fetching needed anymore
                        },
                        children: [
                          if (_isLoadingMachines)
                            const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(color: Color(0xFF00FFCC), strokeWidth: 2),
                                ),
                              ),
                            )
                          else if (_allMachines.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text('Aucune machine trouvée', style: GoogleFonts.spaceGrotesk(color: Colors.white54, fontSize: 11)),
                            )
                          else
                            ...(_allMachines.map((m) {
                              final mId = (m['_id'] ?? m['id'] ?? '').toString();
                              final mName = (m['name'] ?? m['machineName'] ?? mId).toString();
                              final isMachineSelected = isSelected && _resolvedMachineId == mId;
                              return ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
                                leading: Icon(Icons.precision_manufacturing, color: isMachineSelected ? Colors.cyanAccent : Colors.white54, size: 16),
                                title: Text(
                                  mName,
                                  style: GoogleFonts.spaceGrotesk(
                                    color: isMachineSelected ? Colors.cyanAccent : Colors.white70,
                                    fontSize: 12,
                                    fontWeight: isMachineSelected ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                                onTap: () async {
                                  setState(() {
                                    _technicianNavId = tId;
                                    _techId = name.toUpperCase();
                                    _resolvedMachineId = mId;
                                    _machineDisplayName = mName;
                                    _interventionLogsLoaded = false;
                                    _logs.clear();
                                    _interventionId = null;
                                  });
                                  await _findActiveIntervention();
                                  
                                  // Pré-remplir le champ de texte avec le nom de la machine
                                  _commandController.text = '$mName : ';
                                },
                              );
                            }).toList()),
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

  Widget _buildMetricsPanel() {
    List<Map<String, dynamic>> displayedMachines = _allMachines;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF090D18),
        border: Border(left: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Override box removed as requested
          _buildSectionHeader('MACHINES ASSIGNÉES'),
          const SizedBox(height: 20),
          if (_isLoadingMachines)
            const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
          else if (displayedMachines.isEmpty)
            Text('Aucune machine trouvée', style: GoogleFonts.inter(color: Colors.blueGrey))
          else
            Expanded(
              child: ListView.builder(
                itemCount: displayedMachines.length,
                itemBuilder: (context, index) {
                  final m = displayedMachines[index];
                  final mId = m['id']?.toString() ?? m['_id']?.toString() ?? '';
                  final mName = m['name']?.toString() ?? m['reference'] ?? 'Machine $mId';
                  final isSelected = _resolvedMachineId == mId;
                  
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.cyanAccent.withOpacity(0.1) : const Color(0xFF161B28),
                      border: Border.all(color: isSelected ? Colors.cyanAccent : Colors.white10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListTile(
                      leading: Icon(Icons.precision_manufacturing, color: isSelected ? Colors.cyanAccent : Colors.white54, size: 20),
                      title: Text(
                        mName,
                        style: GoogleFonts.spaceGrotesk(
                          color: isSelected ? Colors.cyanAccent : Colors.white,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        'ID: $mId',
                        style: GoogleFonts.inter(color: Colors.blueGrey, fontSize: 10),
                      ),
                      onTap: () {
                        setState(() {
                          _resolvedMachineId = mId;
                          _machineDisplayName = mName;
                          _logs.clear();
                          _interventionId = null;
                        });
                        _findActiveIntervention();
                        _commandController.text = '$mName : ';
                      },
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        Flexible(
          child: Text(
            title,
            style: GoogleFonts.orbitron(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        const SizedBox(width: 8),
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
    final status = _normalizeMissionStatusString(
      _latestMission?['missionStatus'] ?? _latestMission?['status'] ?? 'SENT',
    );
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(hasMission ? Icons.assignment_late : Icons.security, color: hasMission ? Colors.orangeAccent : Colors.cyanAccent, size: 18),
                  if (hasMission)
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: status == 'COMPLETED' ? Colors.greenAccent.withOpacity(0.1) : Colors.orangeAccent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            status == 'COMPLETED' ? 'TERMINÉ' : status,
                            style: GoogleFonts.spaceGrotesk(
                              color: status == 'COMPLETED' ? Colors.greenAccent : Colors.orangeAccent,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                hasMission ? 'ACTIVE MISSION PROTOCOL' : 'SYSTEM OVERRIDE PROTOCOL',
                style: GoogleFonts.orbitron(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                _latestCoordNote,
                style: GoogleFonts.spaceGrotesk(color: hasMission ? Colors.orangeAccent : Colors.cyanAccent, fontSize: 8, fontWeight: FontWeight.bold),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          const SizedBox(height: 15),
          if (hasMission && !_isMaintenanceViewer) ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton(
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
                  style: ElevatedButton.styleFrom(
                    backgroundColor: status == 'SENT' ? Colors.cyanAccent.withOpacity(0.8) : Colors.white.withOpacity(0.05),
                    disabledBackgroundColor: Colors.white.withOpacity(0.05),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _isSendingMission && status == 'SENT'
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : Icon(status == 'SENT' ? Icons.circle_outlined : Icons.check_circle, size: 14, color: status == 'SENT' ? Colors.black : Colors.greenAccent),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _isSendingMission && status == 'SENT' ? '...' : (status == 'SENT' ? 'CONFIRMER' : 'CONFIRMÉ'),
                          style: GoogleFonts.orbitron(fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
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
                  style: ElevatedButton.styleFrom(
                    backgroundColor: (status == 'CONFIRMED' || status == 'STARTED') ? Colors.greenAccent.withOpacity(0.8) : Colors.white.withOpacity(0.05),
                    disabledBackgroundColor: Colors.white.withOpacity(0.05),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _isSendingMission && (status == 'CONFIRMED' || status == 'STARTED')
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : Icon(Icons.stop_circle_outlined, size: 14, color: (status == 'CONFIRMED' || status == 'STARTED') ? Colors.black : Colors.white.withOpacity(0.2)),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _isSendingMission && (status == 'CONFIRMED' || status == 'STARTED') ? '...' : 'TERMINER',
                          style: GoogleFonts.orbitron(fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ] else if (hasMission && _isMaintenanceViewer) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: _MaintenanceMissionStatusChip(status: status.toString()),
            ),
          ] else if (!_isMaintenanceViewer)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.blueGrey),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text('DISMISS', style: GoogleFonts.orbitron(color: Colors.blueGrey, fontSize: 10)),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
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
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF05080E),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStatusInfo('SERVER_STATUS: OPERATIONAL'),
            const SizedBox(width: 16),
            _buildStatusInfo('UPTIME: 1,442 HOURS'),
            const SizedBox(width: 24),
            Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.cyanAccent, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            _buildStatusInfo('SYNC_ACTIVE'),
            const SizedBox(width: 16),
            _buildStatusInfo('OS_VERSION: 4.2.0_STABLE'),
          ],
        ),
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

/// Badge de statut pour l’agent maintenance (pas d’actions terrain).
class _MaintenanceMissionStatusChip extends StatelessWidget {
  const _MaintenanceMissionStatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final st = _normalizeMissionStatusString(status);
    final label = st == 'COMPLETED'
        ? 'TERMINÉ'
        : (st == 'CONFIRMED' || st == 'STARTED')
            ? 'EN COURS (TECH)'
            : 'ENVOYÉE AU TECHNICIEN';
    final color = st == 'COMPLETED'
        ? Colors.greenAccent
        : (st == 'CONFIRMED' || st == 'STARTED')
            ? Colors.cyanAccent
            : const Color(0xFFFF6E00);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            st == 'COMPLETED' ? Icons.check_circle_outline : Icons.hourglass_top_rounded,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: GoogleFonts.orbitron(color: color, fontSize: 9, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
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
