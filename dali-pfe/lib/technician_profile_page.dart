import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'services/api_service.dart';
import 'machine_detail_ai_page.dart';
import 'mission_control_page.dart';
import 'control_calendar_page.dart';
import 'control_reports_history_page.dart';

enum _TechnicianEmbedPanel { none, calendar, history }

class TechnicianProfilePage extends StatefulWidget {
  const TechnicianProfilePage({super.key});

  @override
  State<TechnicianProfilePage> createState() => _TechnicianProfilePageState();
}

class _TechnicianProfilePageState extends State<TechnicianProfilePage> {
  /// Les comptes User CONCEPTION doivent utiliser [ConceptionObservatoryPage], pas ce profil « technicien ».
  bool _conceptionRedirectScheduled = false;

  IO.Socket? _chatSocket;
  IO.Socket? _notifSocket; // ← socket dédié aux notifications contrôle
  bool _chatInitialized = false;
  String _chatRoomId = '';
  String _chatSenderName = 'Technicien';
  String _technicianId = '';
  String _clientId = '';
  final TextEditingController _chatInputController = TextEditingController();
  final List<Map<String, dynamic>> _chatMessages = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _chatConversations = <Map<String, dynamic>>[];
  int _unreadChatCount = 0;
  final Set<String> _criticalAlertSentMachineIds = <String>{};
  final Set<String> _shownControleIds = <String>{}; // évite les doublons
  int _machinesSectionVersion = 0;
  /// Recharge la bande « contrôles ouverts » (API) après marche / notification.
  int _controlesPreviewVersion = 0;
  final Set<String> _startingMarcheIds = <String>{};
  final Set<String> _stoppingMarcheIds = <String>{};
  /// Début de session aligné sur la réponse API (chrono immédiat après clic).
  final Map<String, DateTime> _sessionDebutByMachineId = <String, DateTime>{};
  /// Pour navigation (calendrier / mission control) : préfère `_id` Mongo si présent dans les args de login.
  String _navTechnicianForCalendar = '';
  /// Incrémenté au retour du calendrier pour recharger « Comptes rendus — contrôles terminés ».
  int _completedControlesRefreshGen = 0;
  /// Panneau embarqué à droite de la sidebar (sans [Navigator.pushNamed]).
  _TechnicianEmbedPanel _embedPanel = _TechnicianEmbedPanel.none;
  Map<String, dynamic> _inlineCalendarArgs = <String, dynamic>{};
  Key _inlineCalendarKey = const ValueKey<String>('cal_embed');
  Map<String, dynamic> _inlineHistoryArgs = <String, dynamic>{};
  Key _inlineHistoryKey = const ValueKey<String>('hist_embed');
  final Map<String, dynamic> _profileOverrides = <String, dynamic>{};

  static const _bg = Color(0xFF10102B);
  static const _surfaceContainerLow = Color(0xFF191934);
  static const _surfaceContainer = Color(0xFF1D1D38);
  static const _surfaceContainerHigh = Color(0xFF272743);
  static const _surfaceContainerHighest = Color(0xFF32324E);
  static const _primary = Color(0xFFFFB692);
  static const _primaryContainer = Color(0xFFFF6E00);
  static const _secondary = Color(0xFF75D1FF);
  static const _tertiary = Color(0xFFEFB1F9);
  static const _onSurface = Color(0xFFE2DFFF);
  static const _onSurfaceVariant = Color(0xFFE2BFB0);
  static const _outlineVariant = Color(0xFF594136);
  static const _error = Color(0xFFFFB4AB);
  static const _green = Color(0xFF66BB6A);
  /// Photo locale lorsqu’aucune URL distante n’est fournie (OAuth / API).
  static const _defaultTechnicianImageAsset = 'asset:assets/images/technician_profile_photo.png';

  @override
  void dispose() {
    _chatInputController.dispose();
    _chatSocket?.dispose();
    _notifSocket?.dispose();
    super.dispose();
  }

  bool _technicianMeSynced = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncTechnicianProfileFromApiIfNeeded();
      // Seconde tentative : après OAuth web / restauration SharedPreferences, le jeton peut arriver un peu plus tard.
      Future<void>.delayed(const Duration(milliseconds: 650), () {
        if (!mounted || _technicianMeSynced) return;
        _syncTechnicianProfileFromApiIfNeeded();
      });
    });
  }

  /// Recharge `imageUrl` / nom depuis Mongo pour le technicien connecté (évite avatar vide après F5).
  Future<void> _syncTechnicianProfileFromApiIfNeeded() async {
    if (_technicianMeSynced) return;
    if ((ApiService.savedUserRole ?? '').toLowerCase() != 'technician') return;
    await ApiService.ensureAuthTokenLoaded();
    if ((ApiService.authToken ?? '').isEmpty) return;
    try {
      final me = await ApiService.getMyTechnicianProfile();
      if (!mounted) return;
      _technicianMeSynced = true;
      setState(() {
        _profileOverrides.addAll(Map<String, dynamic>.from(me));
      });
      final raw = ModalRoute.of(context)?.settings.arguments;
      Map<String, dynamic>? routeArgs;
      if (raw is Map) routeArgs = Map<String, dynamic>.from(raw);
      await ApiService.saveTechnicianSession(_mergeTechnicianProfileArgs(routeArgs));
    } catch (_) {
      // Pas connecté en technicien ou API indisponible.
    }
  }

  void _applyTechnicianProfileOverlay(Map<String, dynamic> merged, Map<String, dynamic> overlay) {
    const photoKeys = <String>{
      'imageUrl',
      'photoUrl',
      'avatarUrl',
      'profilePhotoUrl',
      'image',
      'photo',
      'avatar',
      'picture',
      'photoURL',
    };
    for (final e in overlay.entries) {
      final k = e.key.toString();
      final v = e.value;
      if (photoKeys.contains(k)) {
        final next = v?.toString().trim() ?? '';
        final prev = merged[k]?.toString().trim() ?? '';
        if (next.isEmpty && prev.isNotEmpty) continue;
      }
      merged[k] = v;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_conceptionRedirectScheduled) return;
    final raw = ModalRoute.of(context)?.settings.arguments;
    if (raw is! Map) return;
    final vr = (raw['viewerRole'] ?? '').toString().toLowerCase();
    if (vr != 'conception') return;
    _conceptionRedirectScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(
        '/conception-observatory',
        arguments: Map<String, dynamic>.from(raw),
      );
    });
  }

  /// Calendrier dans la colonne principale : la sidebar profil reste visible ([Navigator.pushNamed] évité).
  void _openControlCalendarFromProfile(Map<String, dynamic> arguments) {
    setState(() {
      _embedPanel = _TechnicianEmbedPanel.calendar;
      _inlineCalendarArgs = Map<String, dynamic>.from(arguments);
      _inlineCalendarKey = UniqueKey();
    });
  }

  void _openControlHistoryFromProfile(Map<String, dynamic> arguments) {
    setState(() {
      _embedPanel = _TechnicianEmbedPanel.history;
      _inlineHistoryArgs = Map<String, dynamic>.from(arguments);
      _inlineHistoryKey = UniqueKey();
    });
  }

  void _closeEmbedPanel() {
    if (!mounted) return;
    setState(() {
      _embedPanel = _TechnicianEmbedPanel.none;
      _inlineCalendarArgs = <String, dynamic>{};
      _inlineHistoryArgs = <String, dynamic>{};
      _completedControlesRefreshGen++;
    });
  }

  /// Confirme et déconnecte le technicien : efface jeton + cache profil, retour route racine ([SessionEntry]).
  Future<void> _logoutTechnician() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            const Icon(Icons.logout, color: _error),
            const SizedBox(width: 8),
            Text(
              'Déconnexion',
              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: Text(
          'Voulez-vous vraiment vous déconnecter ?',
          style: GoogleFonts.inter(color: _onSurfaceVariant, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Annuler', style: GoogleFonts.inter(color: _onSurfaceVariant)),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _error, foregroundColor: Colors.white),
            icon: const Icon(Icons.logout, size: 18),
            label: Text('Se déconnecter', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    _chatSocket?.dispose();
    _notifSocket?.dispose();
    _chatSocket = null;
    _notifSocket = null;
    await ApiService.clearAuth();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  Map<String, dynamic> _mergeTechnicianProfileArgs(Map<String, dynamic>? routeArgs) {
    final merged = <String, dynamic>{};
    final saved = ApiService.savedTechnicianProfile;
    if (saved != null) merged.addAll(saved);
    if (routeArgs != null && routeArgs.isNotEmpty) {
      _applyTechnicianProfileOverlay(merged, Map<String, dynamic>.from(routeArgs));
    }
    if (_profileOverrides.isNotEmpty) {
      _applyTechnicianProfileOverlay(merged, _profileOverrides);
    }
    return merged;
  }

  /// Liste normalisée depuis List, chaîne unique ou liste séparée par virgules (OAuth / routes legacy).
  List<String> _coerceMachineIds(dynamic raw) {
    final out = <String>{};
    void addOne(String s) {
      final t = s.trim();
      if (t.isNotEmpty) out.add(t);
    }

    if (raw == null) return [];
    if (raw is List) {
      for (final e in raw) {
        addOne(e.toString());
      }
      return out.toList();
    }
    final str = raw.toString().trim();
    if (str.isEmpty) return [];
    if (str.contains(',')) {
      for (final part in str.split(',')) {
        addOne(part);
      }
      return out.toList();
    }
    addOne(str);
    return out.toList();
  }

  bool _isViewingOwnTechnicianProfile(Map<String, dynamic> args) {
    if ((ApiService.savedUserRole ?? '').toLowerCase() != 'technician') return false;
    final saved = ApiService.savedTechnicianProfile;
    if (saved == null) return false;
    final sid = (saved['technicianId'] ?? saved['id'] ?? '').toString().trim();
    final vid = (args['technicianId'] ?? args['id'] ?? '').toString().trim();
    return sid.isNotEmpty && vid.isNotEmpty && sid == vid;
  }

  Set<String> _machineIdCandidatesFromDoc(Map<String, dynamic> m) {
    final c = <String>{
      _machineIdFromDoc(m),
      (m['_id'] ?? '').toString(),
      (m['id'] ?? '').toString(),
      (m['machineId'] ?? '').toString(),
    }.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    return c;
  }

  bool _assignedMachineMatches(Map<String, dynamic> m, Set<String> assigned) {
    final candidates = _machineIdCandidatesFromDoc(m);
    for (final a in assigned) {
      if (candidates.contains(a)) return true;
    }
    return false;
  }

  Future<void> _showQuickProfileEditDialog({
    required Map<String, dynamic> rawArgs,
    required String currentName,
    required String currentImageUrl,
  }) async {
    final nameParts = currentName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initialFirstName = nameParts.isNotEmpty ? nameParts.first : '';
    final initialLastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

    final firstNameController = TextEditingController(text: initialFirstName);
    final lastNameController = TextEditingController(text: initialLastName);
    final photoUrlController = TextEditingController(text: currentImageUrl);

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: _surfaceContainerLow,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Modifier le profil',
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: photoUrlController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'URL photo'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: firstNameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Prénom'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: lastNameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Nom'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Annuler', style: GoogleFonts.inter(color: _onSurfaceVariant)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: _primaryContainer),
              child: const Text('Enregistrer'),
            ),
          ],
        );
      },
    );

    if (updated != true || !mounted) return;

    final firstName = firstNameController.text.trim();
    final lastName = lastNameController.text.trim();
    final fullName = [firstName, lastName].where((p) => p.isNotEmpty).join(' ').trim();
    final photoUrl = photoUrlController.text.trim();

    if (fullName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez renseigner au moins un prénom ou un nom.'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    if (photoUrl.isNotEmpty) {
      final parsed = Uri.tryParse(photoUrl);
      final isValid = parsed != null &&
          (parsed.scheme == 'http' || parsed.scheme == 'https') &&
          (parsed.host.isNotEmpty);
      if (!isValid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('URL photo invalide. Utilisez un lien http(s) valide.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
    }

    final technicianId = (rawArgs['technicianId'] ?? rawArgs['id'] ?? _technicianId).toString().trim();
    final effectivePhotoUrl = photoUrl.isNotEmpty ? photoUrl : currentImageUrl;

    final patch = <String, dynamic>{
      ...rawArgs,
      'firstName': firstName,
      'lastName': lastName,
      'name': fullName,
      'imageUrl': effectivePhotoUrl,
      'photoUrl': effectivePhotoUrl,
      'avatarUrl': effectivePhotoUrl,
    };

    var savedInDb = false;
    String? apiError;
    Map<String, dynamic>? dbProfile;
    try {
      final role = (ApiService.savedUserRole ?? '').toLowerCase();
      if (role == 'technician') {
        dbProfile = await ApiService.updateMyTechnicianProfile({
          'name': fullName,
          'imageUrl': effectivePhotoUrl,
        });
        savedInDb = true;
      } else if (technicianId.isNotEmpty) {
        dbProfile = await ApiService.updateTechnician(technicianId, {
          'name': fullName,
          'imageUrl': effectivePhotoUrl,
        });
        savedInDb = true;
      }
    } catch (e) {
      apiError = e.toString().replaceAll('Exception: ', '');
    }

    if (dbProfile != null && dbProfile!.isNotEmpty) {
      patch.addAll(dbProfile!);
      final img = (dbProfile!['imageUrl'] ?? '').toString().trim();
      if (img.isNotEmpty) {
        patch['imageUrl'] = img;
        patch['photoUrl'] = img;
        patch['avatarUrl'] = img;
      }
    }

    await ApiService.saveTechnicianSession(patch);
    if (!mounted) return;
    setState(() {
      _profileOverrides
        ..clear()
        ..addAll(patch);
    });

    if (savedInDb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil mis à jour en base de données.'), backgroundColor: Colors.green),
      );
    } else {
      final msg = (apiError ?? '').toLowerCase().contains('accès refusé')
          ? 'Photo mise à jour localement. La base de données refuse la modification pour ce rôle.'
          : 'Photo mise à jour localement. Synchronisation base non effectuée (${apiError ?? 'erreur inconnue'}).';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.orange),
      );
    }
  }

  String _resolveTechnicianImageUrl(Map<String, dynamic> args) {
    final saved = ApiService.savedTechnicianProfile;
    final candidates = <String?>[
      args['imageUrl']?.toString(),
      args['photoUrl']?.toString(),
      args['avatarUrl']?.toString(),
      args['profilePhotoUrl']?.toString(),
      args['picture']?.toString(),
      args['photoURL']?.toString(),
      args['image']?.toString(),
      args['photo']?.toString(),
      args['avatar']?.toString(),
      saved?['imageUrl']?.toString(),
      saved?['photoUrl']?.toString(),
      saved?['avatarUrl']?.toString(),
      saved?['picture']?.toString(),
    ];

    for (final value in candidates) {
      final v = _normalizeTechnicianImageUrl((value ?? '').toString());
      if (v.isNotEmpty) return v;
    }
    return _defaultTechnicianImageAsset;
  }

  String _resolveTechnicianEmail(Map<String, dynamic> args) {
    final saved = ApiService.savedTechnicianProfile;
    const keys = <String>['email', 'mail', 'userEmail'];
    for (final k in keys) {
      final v = args[k]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
      final sv = saved?[k]?.toString().trim();
      if (sv != null && sv.isNotEmpty) return sv;
    }
    return '';
  }

  String _resolveClientDisplayCode(Map<String, dynamic> args) {
    final saved = ApiService.savedTechnicianProfile;
    const keys = <String>['companyCode', 'clientCode', 'companyId', 'clientId'];
    for (final k in keys) {
      final v = args[k]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
      final sv = saved?[k]?.toString().trim();
      if (sv != null && sv.isNotEmpty) return sv;
    }
    return '';
  }

  bool _avatarHostMatchesApi(String absoluteUrl) {
    try {
      final u = Uri.parse(absoluteUrl);
      final b = Uri.parse(ApiService.baseUrl);
      return u.hasScheme && b.hasScheme && u.host.toLowerCase() == b.host.toLowerCase();
    } catch (_) {
      return false;
    }
  }

  String _normalizeTechnicianImageUrl(String rawValue) {
    final value = rawValue.trim();
    if (value.isEmpty) return '';
    if (value.startsWith('data:image/')) return value;
    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.hasScheme) return value;
    if (value.startsWith('//')) {
      final apiScheme = Uri.tryParse(ApiService.baseUrl)?.scheme ?? 'http';
      return '$apiScheme:$value';
    }
    final origin = ApiService.socketBaseUrl.replaceAll(RegExp(r'/$'), '');
    if (value.startsWith('/')) return '$origin$value';
    return '$origin/${value.replaceFirst(RegExp(r'^/+'), '')}';
  }

  /// [photoEnhance] : léger gain luminosité/contraste pour la carte profil (photo plus lisible).
  Widget _buildTechnicianAvatar({
    required String imageUrl,
    required double width,
    required double height,
    required BorderRadius borderRadius,
    double iconSize = 42,
    bool photoEnhance = false,
  }) {
    Widget fallback() => Container(
      color: _surfaceContainerHigh,
      alignment: Alignment.center,
      child: Icon(Icons.person, color: _onSurfaceVariant, size: iconSize),
    );

    Widget polishPhoto(Widget img) {
      if (!photoEnhance) return img;
      return ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          1.07, 0, 0, 0, 10,
          0, 1.07, 0, 0, 10,
          0, 0, 1.07, 0, 6,
          0, 0, 0, 1, 0,
        ]),
        child: img,
      );
    }

    final src = imageUrl.trim();
    if (src.startsWith('asset:')) {
      final assetPath = src.substring('asset:'.length);
      return ClipRRect(
        borderRadius: borderRadius,
        child: polishPhoto(
          Image.asset(
            assetPath,
            key: ValueKey<String>(assetPath),
            width: width,
            height: height,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            filterQuality: FilterQuality.high,
            isAntiAlias: true,
            errorBuilder: (_, __, ___) => fallback(),
          ),
        ),
      );
    }
    if (src.startsWith('data:image/')) {
      try {
        final bytes = base64Decode(src.split(',').last);
        return ClipRRect(
          borderRadius: borderRadius,
          child: polishPhoto(
            Image.memory(
              bytes,
              width: width,
              height: height,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              isAntiAlias: true,
              errorBuilder: (_, __, ___) => fallback(),
            ),
          ),
        );
      } catch (_) {
        return ClipRRect(borderRadius: borderRadius, child: fallback());
      }
    }

    if (src.isEmpty) {
      return ClipRRect(borderRadius: borderRadius, child: fallback());
    }

    final normalizedSrc = _normalizeTechnicianImageUrl(src);
    final authHeaders =
        _avatarHostMatchesApi(normalizedSrc) ? ApiService.bearerHeadersForNetworkImage() : null;

    return ClipRRect(
      borderRadius: borderRadius,
      child: polishPhoto(
        Image.network(
          normalizedSrc,
          key: ValueKey(normalizedSrc),
          width: width,
          height: height,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          filterQuality: FilterQuality.high,
          isAntiAlias: true,
          headers: authHeaders,
          errorBuilder: (_, __, ___) => fallback(),
        ),
      ),
    );
  }

  Future<void> _ensureTechnicianChat(Map<String, dynamic> args, String technicianName) async {
    if (_chatInitialized) return;
    final techId = (args['technicianId'] ?? args['id'] ?? '').toString();
    final clientId = (args['companyId'] ?? args['clientId'] ?? '').toString();
    _navTechnicianForCalendar = (args['_id'] ?? args['technicianId'] ?? args['id'] ?? '').toString().trim();
    _technicianId = techId;
    _clientId = clientId;
    if (techId.isEmpty || clientId.isEmpty) return;

    _chatConversations = await ApiService.getTechnicianConversations(techId);
    if (_chatConversations.isNotEmpty) {
      _chatRoomId = (_chatConversations.first['roomId'] ?? '').toString();
    } else {
      _chatRoomId = 'chat_${clientId}_$techId';
    }
    _chatSenderName = technicianName.trim().isEmpty ? 'Technicien' : technicianName.trim();
    try {
      final history = await ApiService.getChatMessages(_chatRoomId, limit: 200);
      _chatMessages
        ..clear()
        ..addAll(history);
    } catch (_) {}

    final socket = IO.io(ApiService.socketBaseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });
    _chatSocket = socket;

    socket.onConnect((_) {
      socket.emit('join_chat_room', {'roomId': _chatRoomId});
    });

    socket.on('chat_message', (raw) {
      try {
        final data = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
        if (data['roomId']?.toString() != _chatRoomId) return;
        if (!mounted) return;
        setState(() {
          _chatMessages.add(data);
          final senderName = (data['senderName'] ?? '').toString();
          if (senderName != _chatSenderName) {
            _unreadChatCount += 1;
          }
        });
      } catch (_) {}
    });

    _chatInitialized = true;

    // ── Notification temps réel : nouveau contrôle automatique ──────────────
    final notifSocket = IO.io(ApiService.socketBaseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });
    _notifSocket = notifSocket;

    notifSocket.on('nouveau_controle', (raw) {
      try {
        if (!mounted) return;
        final data = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
        final controleId = (data['controleId'] ?? '').toString();
        if (controleId.isNotEmpty && _shownControleIds.contains(controleId)) return;
        if (controleId.isNotEmpty) _shownControleIds.add(controleId);
        if (mounted) {
          setState(() => _controlesPreviewVersion++);
        }
        _showNouveauControleAlert(data);
      } catch (_) {}
    });

    // ── controle_urgent : alerte rouge immédiate ──────────────────────────────
    notifSocket.on('controle_urgent', (raw) {
      try {
        if (!mounted) return;
        final data = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
        final controleId = (data['controleId'] ?? '').toString();
        if (controleId.isNotEmpty && _shownControleIds.contains(controleId)) return;
        if (controleId.isNotEmpty) _shownControleIds.add(controleId);
        _showControleUrgentAlert(data);
      } catch (_) {}
    });

    // ── machine_status : bandeau discret ─────────────────────────────────────
    notifSocket.on('machine_status', (raw) {
      try {
        if (!mounted) return;
        final data = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
        final nom    = (data['machineName'] ?? 'Machine').toString();
        final statut = (data['status'] ?? '').toString();
        final couleur = statut == 'RUNNING'
            ? Colors.green
            : statut == 'STOPPED'
                ? Colors.redAccent
                : Colors.orange;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '⚙️ $nom → $statut',
              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            backgroundColor: couleur.withOpacity(0.85),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      } catch (_) {}
    });

    // ── temps_marche_update : mise à jour silencieuse (pas d'alerte visuelle) ─
    notifSocket.on('temps_marche_update', (raw) {
      // Les données sont disponibles pour d'éventuels widgets de suivi en temps réel.
      // Aucun dialog : évite de perturber le technicien toutes les minutes.
      try {
        if (!mounted) return;
        // Exemple : setState(() => _machinesHeures = List.from(raw));
        // À brancher sur un widget dédié si besoin.
      } catch (_) {}
    });

    /// Mission maintenance / coordination diagnostic → recharge les cartes machine (bordure rouge).
    void bumpMachinesForMission() {
      if (!mounted) return;
      setState(() => _machinesSectionVersion++);
    }

    notifSocket.on('diagnostic_coordination', (_) => bumpMachinesForMission());
    notifSocket.on('diagnostic_coordination_update', (_) => bumpMachinesForMission());
    notifSocket.on('diagnostic_message', (_) => bumpMachinesForMission());
    notifSocket.on('diagnostic_message_update', (_) => bumpMachinesForMission());
    // ────────────────────────────────────────────────────────────────────────


    if (mounted) {
      setState(() {});
      _checkPendingInterventions(techId);
    }
  }

  // ── Alerte : nouveau contrôle généré automatiquement ─────────────────────
  void _showNouveauControleAlert(Map<String, dynamic> data) {
    if (!mounted) return;
    final machineName  = (data['machineName']  ?? 'Machine').toString();
    final typeControle = (data['typeControle'] ?? 'Contrôle').toString();
    final heures       = data['heures'] is num ? (data['heures'] as num).toStringAsFixed(0) : '?';
    final prioriteLabel = (data['prioriteLabel'] ?? data['priorite'] ?? 'NORMALE').toString();
    final controleId   = (data['controleId'] ?? '').toString();

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFFF6E00), width: 2),
        ),
        title: Row(
          children: [
            const Text('🔔', style: TextStyle(fontSize: 24)),
            const SizedBox(width: 10),
            Text(
              'Nouveau contrôle !',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Machine
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _surfaceContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.precision_manufacturing, color: Color(0xFF75D1FF), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      machineName,
                      style: GoogleFonts.spaceGrotesk(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Type de contrôle
            Row(
              children: [
                const Icon(Icons.build_circle_outlined, color: Color(0xFFFFB692), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '→ $typeControle ($heures h)',
                    style: GoogleFonts.inter(color: _onSurface, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Priorité
            Row(
              children: [
                const Icon(Icons.flag_outlined, size: 18, color: Color(0xFFFFB4AB)),
                const SizedBox(width: 8),
                Text(
                  'Priorité : $prioriteLabel',
                  style: GoogleFonts.inter(
                    color: _onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Ignorer', style: GoogleFonts.inter(color: _onSurfaceVariant)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.calendar_month_outlined, size: 18),
            label: Text('Voir calendrier', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6E00),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _openControlCalendarFromProfile({
                'technicianName': _chatSenderName,
                'technicianId': _technicianId,
                'machineIds': <String>[],
                if (_clientId.isNotEmpty) 'companyId': _clientId,
              });
            },
          ),
        ],
      ),
    );
  }
  // ─────────────────────────────────────────────────────────────────────────

  // ── Alerte URGENTE : contrôle critique immédiat ───────────────────────────
  void _showControleUrgentAlert(Map<String, dynamic> data) {
    if (!mounted) return;
    final machineName  = (data['machineName']  ?? 'Machine').toString();
    final typeControle = (data['typeControle'] ?? 'Contrôle').toString();
    final heures = data['heures'] is num
        ? (data['heures'] as num).toStringAsFixed(0)
        : '?';

    showDialog(
      context: context,
      barrierDismissible: false, // Le technicien DOIT agir
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A0A0A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.redAccent, width: 2.5),
        ),
        title: Row(
          children: [
            const Icon(Icons.warning_rounded, color: Colors.redAccent, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '🚨 CONTRÔLE URGENT !',
                style: GoogleFonts.inter(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.precision_manufacturing, color: Colors.redAccent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      machineName,
                      style: GoogleFonts.spaceGrotesk(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.build_circle, color: Colors.redAccent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '→ $typeControle ($heures h)',
                    style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.flag, size: 18, color: Colors.redAccent),
                const SizedBox(width: 8),
                Text(
                  'Priorité : URGENTE 🔴',
                  style: GoogleFonts.inter(
                    color: Colors.redAccent,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Plus tard', style: GoogleFonts.inter(color: Colors.white38)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: Text('Prendre en charge', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _openControlCalendarFromProfile({
                'technicianName': _chatSenderName,
                'technicianId': _technicianId,
                'machineIds': <String>[],
                if (_clientId.isNotEmpty) 'companyId': _clientId,
              });
            },
          ),
        ],
      ),
    );
  }
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _checkPendingInterventions(String techId) async {
    try {
      final interventions = await ApiService.getDiagnosticInterventions();
      // On cherche une intervention OPEN assignée à ce tech
      final pending = interventions.where((i) => 
        i['technicianId']?.toString() == techId && 
        i['status'] == 'OPEN'
      ).toList();

      if (pending.isNotEmpty && mounted) {
        final last = pending.first;
        _showAcceptAssignmentDialog(last);
      }
    } catch (e) {
      debugPrint('Error checking interventions: $e');
    }
  }

  void _showAcceptAssignmentDialog(Map<String, dynamic> intervention) {
    final machineId = (intervention['machineId'] ?? '').toString();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: _primaryContainer, width: 2)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: _primaryContainer, size: 28),
            const SizedBox(width: 12),
            Text('NOUVELLE MISSION', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w900)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vous avez été assigné à une maintenance critique sur la machine :',
              style: GoogleFonts.inter(color: _onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _surfaceContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.precision_manufacturing, color: _secondary, size: 20),
                  const SizedBox(width: 10),
                  Text(machineId, style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Résumé : ${intervention['summary'] ?? 'Contrôle de panne immédiat'}',
              style: GoogleFonts.inter(color: _onSurface, fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('PLUS TARD', style: GoogleFonts.inter(color: _onSurfaceVariant)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              // Optionnel: on pourrait passer le status en 'ACCEPTED' ici
              // Mais pour l'instant on ouvre directement la page de la machine
              if (mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MachineDetailAiPage(
                      machineId: machineId,
                      viewerRole: 'technician',
                      viewerName: _chatSenderName,
                    ),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryContainer,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: Text('ACCEPTER & OUVRIR', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _openTechnicianChatDialog() {
    if (_chatRoomId.isEmpty) return;
    setState(() => _unreadChatCount = 0);
    _chatSocket?.emit('join_chat_room', {'roomId': _chatRoomId});

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _surfaceContainerLow,
        title: Text(
          'Messages Client ↔ Technicien',
          style: GoogleFonts.inter(color: _onSurface),
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 220,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _surfaceContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView(
                  children: _chatMessages
                      .map(
                        (m) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            '${m['senderName'] ?? 'User'}: ${m['text'] ?? ''}',
                            style: GoogleFonts.inter(color: _onSurface, fontSize: 12),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _chatInputController,
                style: GoogleFonts.inter(color: _onSurface),
                decoration: const InputDecoration(
                  hintText: 'Écrire un message...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
          ElevatedButton(
            onPressed: () {
              final text = _chatInputController.text.trim();
              if (text.isEmpty || _chatRoomId.isEmpty) return;
              _chatSocket?.emit('chat_message', {
                'roomId': _chatRoomId,
                'from': 'technician',
                'senderName': _chatSenderName,
                'text': text,
              });
              _chatInputController.clear();
            },
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 992;

    final routeArgs = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final Map<String, dynamic> args = _mergeTechnicianProfileArgs(routeArgs);
    final viewerRoleRaw = (args['viewerRole'] ??
            args['role'] ??
            ApiService.savedUserRole ??
            '')
        .toString()
        .toLowerCase();
    final isSuperAdminViewer = ApiService.canManageFleet ||
        viewerRoleRaw == 'superadmin' ||
        viewerRoleRaw == 'admin' ||
        viewerRoleRaw == 'company_admin';
    final isTechnicianViewer = viewerRoleRaw == 'technician';
    final isConceptionViewer = viewerRoleRaw == 'conception';
    final canViewProfile = isSuperAdminViewer || isTechnicianViewer || isConceptionViewer;

    if (!canViewProfile) {
      return Scaffold(
        backgroundColor: _bg,
        body: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 560),
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: _surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _outlineVariant.withOpacity(0.3)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, color: _error, size: 36),
                const SizedBox(height: 12),
                Text(
                  'Accès réservé',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Cette page est réservée aux comptes autorisés (technicien connecté, concepteur ou administrateur).',
                  style: GoogleFonts.inter(
                    color: _onSurfaceVariant,
                    fontSize: 13,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Retour'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryContainer,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final String name = args['name'] ?? 'Marc Lefebvre';
    final String id = args['id'] ?? 'TC-9942-B';
    final String specialization = args['specialization'] ?? 'Senior Technician — Industrial Systems & Robotics';
    final String statusLabel = args['status'] ?? 'EN SERVICE';
    final String imageUrl = _resolveTechnicianImageUrl(args);
    final String email = _resolveTechnicianEmail(args);
    final String clientDisplayCode = _resolveClientDisplayCode(args);
    final List<String> assignedMachineIds = _coerceMachineIds(args['machineIds']);
    final int monitoredMachineCount = assignedMachineIds.length;
    final String companyIdForMachines = (args['companyId'] ?? '').toString().trim();
    final String calendarTechId =
        (args['_id'] ?? args['technicianId'] ?? args['id'] ?? '').toString().trim();
    _ensureTechnicianChat(args, name);

    return Scaffold(
      backgroundColor: _bg,
      body: Row(
        children: [
          if (isDesktop) _buildSidebar(name, email, imageUrl, assignedMachineIds, companyIdForMachines),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child:
                      _embedPanel == _TechnicianEmbedPanel.calendar
                          ? ClipRect(
                            child: ControlCalendarPage(
                              key: _inlineCalendarKey,
                              initialArguments: _inlineCalendarArgs.isNotEmpty ? _inlineCalendarArgs : null,
                              onClose: _closeEmbedPanel,
                            ),
                          )
                          : _embedPanel == _TechnicianEmbedPanel.history
                          ? ClipRect(
                            child: ControlReportsHistoryPage(
                              key: _inlineHistoryKey,
                              initialArguments: _inlineHistoryArgs.isNotEmpty ? _inlineHistoryArgs : null,
                              onClose: _closeEmbedPanel,
                            ),
                          )
                          : Column(
                            children: [
                              _buildTopHeader(args),
                              Expanded(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.all(24),
                                  child: Center(
                                    child: Container(
                                      constraints: const BoxConstraints(maxWidth: 1200),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          _buildProfileHeader(
                                            context,
                                            isDesktop,
                                            name,
                                            id,
                                            specialization,
                                            statusLabel,
                                            imageUrl,
                                            args,
                                            email,
                                            clientDisplayCode,
                                            monitoredMachineCount,
                                            canManageTechnician: isSuperAdminViewer,
                                          ),
                                          const SizedBox(height: 40),
                                          _buildMainGrid(
                                            isDesktop,
                                            context,
                                            id,
                                            name,
                                            assignedMachineIds,
                                            companyIdForMachines,
                                            isConceptionViewer,
                                            calendarTechId,
                                            args,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                ),
                if (_embedPanel == _TechnicianEmbedPanel.none)
                  SafeArea(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Container(
                        margin: const EdgeInsets.only(left: 10, top: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0D9B5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1A1A)),
                          onPressed: () => Navigator.maybePop(context),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: null,
    );
  }

  Future<void> _showMachineFleetList(
    String technicianDisplayName,
    List<String> assignedMachineIds,
    String companyIdForMachines,
  ) async {
    final hostContext = context;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _surfaceContainerLow,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.precision_manufacturing_outlined, color: _secondary, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Machine Fleet',
                  style: GoogleFonts.spaceGrotesk(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 440,
            height: 400,
            child: FutureBuilder<({List<String> ids, List<Map<String, dynamic>> machines})>(
              future: _loadMachinesForProfileSection(assignedMachineIds, companyIdForMachines, null),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                }
                if (snapshot.hasError) {
                  return Text(
                    'Impossible de charger la liste.',
                    style: GoogleFonts.inter(color: _error),
                  );
                }
                final machines = snapshot.data?.machines ?? const <Map<String, dynamic>>[];
                if (machines.isEmpty) {
                  return Center(
                    child: Text(
                      'Aucune machine assignée à ce périmètre.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(color: _onSurfaceVariant, height: 1.4),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: machines.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: Colors.white.withOpacity(0.08)),
                  itemBuilder: (context, i) {
                    final m = machines[i];
                    final machineId = _machineIdFromDoc(m);
                    final machineName = (m['name'] ?? machineId).toString();
                    final status = (m['status'] ?? '—').toString();
                    final client = (m['companyId'] ?? '').toString();
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.precision_manufacturing, color: _secondary, size: 22),
                      ),
                      title: Text(
                        machineName,
                        style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      subtitle: Text(
                        [if (machineId.isNotEmpty) machineId, status, if (client.isNotEmpty) client].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(color: _onSurfaceVariant, fontSize: 11),
                      ),
                      onTap: () {
                        Navigator.pop(dialogContext);
                        if (machineId.isEmpty || !mounted) return;
                        Navigator.pushNamed(
                          hostContext,
                          '/mission-control',
                          arguments: {
                            'machineId': machineId,
                            'techId': machineId,
                            'name': technicianDisplayName,
                            'machineName': machineName,
                            'technicianId': _navTechnicianForCalendar.isNotEmpty
                                ? _navTechnicianForCalendar
                                : _technicianId,
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('Fermer', style: GoogleFonts.inter(color: _onSurfaceVariant)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showMachineDetailsDialog({
    required String machineId,
    required String fallbackMachineName,
  }) async {
    if (machineId.trim().isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _surfaceContainerLow,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.precision_manufacturing, color: _secondary, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Détails machine',
                  style: GoogleFonts.spaceGrotesk(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: FutureBuilder<({Map<String, dynamic> info, Map<String, dynamic>? telemetry})>(
              future: () async {
                final info = await ApiService.getMachineInfo(machineId);
                Map<String, dynamic>? telemetry;
                try {
                  telemetry = await ApiService.getLatestTelemetry(machineId);
                } catch (_) {
                  telemetry = null;
                }
                return (info: info, telemetry: telemetry);
              }(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                }
                if (snapshot.hasError) {
                  return Text(
                    'Impossible de charger les détails (${snapshot.error}).',
                    style: GoogleFonts.inter(color: _error, fontSize: 12, height: 1.35),
                  );
                }
                final data = snapshot.data?.info ?? const <String, dynamic>{};
                final telemetry = snapshot.data?.telemetry ?? const <String, dynamic>{};
                String readAny(List<String> keys, {String fallback = '—'}) {
                  for (final k in keys) {
                    final v = data[k];
                    if (v == null) continue;
                    final s = v.toString().trim();
                    if (s.isNotEmpty) return s;
                  }
                  return fallback;
                }

                final name = readAny(['name', 'machineName'], fallback: fallbackMachineName);
                final id = readAny(['id', '_id', 'machineId'], fallback: machineId);
                final status = readAny(['status']);
                final client = readAny(['companyId', 'clientId']);
                final type = readAny(['type', 'category']);
                final location = readAny(['location', 'position']);
                String sensor(List<String> keys, {String unit = ''}) {
                  for (final k in keys) {
                    final v = telemetry[k];
                    if (v == null) continue;
                    if (v is num) return unit.isEmpty ? '$v' : '$v $unit';
                    final s = v.toString().trim();
                    if (s.isNotEmpty) return unit.isEmpty ? s : '$s $unit';
                  }
                  return '—';
                }

                Widget line(String label, String value) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 90,
                          child: Text(
                            '$label:',
                            style: GoogleFonts.inter(
                              color: _onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            value,
                            style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      line('Nom', name),
                      line('ID', id),
                      line('Statut', status),
                      line('Client', client),
                      line('Type', type),
                      line('Localisation', location),
                      const SizedBox(height: 8),
                      Text(
                        'Valeurs capteurs',
                        style: GoogleFonts.spaceGrotesk(
                          color: _secondary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      line('Température', sensor(['temperature', 'thermal'], unit: '°C')),
                      line('Pression', sensor(['pressure'], unit: 'bar')),
                      line('Vibration', sensor(['vibration', 'vibrationRms'], unit: 'mm/s')),
                      line('Vitesse', sensor(['rpm', 'speed'], unit: 'rpm')),
                      line('Courant', sensor(['current', 'ampere'], unit: 'A')),
                      line('Tension', sensor(['voltage'], unit: 'V')),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('Fermer', style: GoogleFonts.inter(color: _onSurfaceVariant)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSidebar(
    String name,
    String email,
    String imageUrl,
    List<String> assignedMachineIds,
    String companyIdForMachines,
  ) {
    return Container(
      width: 256,
      color: _surfaceContainerLow,
      child: Column(
        children: [
          // Profile section in sidebar
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                _buildTechnicianAvatar(
                  imageUrl: imageUrl,
                  width: 48,
                  height: 48,
                  borderRadius: BorderRadius.circular(100),
                  iconSize: 24,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.spaceGrotesk(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (email.isNotEmpty)
                        Text(
                          email,
                          style: GoogleFonts.spaceGrotesk(
                            color: _onSurfaceVariant.withOpacity(0.85),
                            fontSize: 11,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        )
                      else
                        Text(
                          'Technicien',
                          style: GoogleFonts.spaceGrotesk(
                            color: _onSurfaceVariant.withOpacity(0.7),
                            fontSize: 10,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white10),
          _buildSidebarTile(
            Icons.person_outline,
            'Profil',
            isActive: _embedPanel == _TechnicianEmbedPanel.none,
            onTap: () {
              if (_embedPanel != _TechnicianEmbedPanel.none) _closeEmbedPanel();
            },
          ),
          _buildSidebarTile(
            Icons.calendar_month_outlined,
            'Calendrier de Contrôle',
            isActive: _embedPanel == _TechnicianEmbedPanel.calendar,
            onTap: () {
              final techId =
                  _navTechnicianForCalendar.isNotEmpty ? _navTechnicianForCalendar : _technicianId;
              _openControlCalendarFromProfile({
                'technicianName': name,
                'technicianId': techId,
                'machineIds': assignedMachineIds,
                if (companyIdForMachines.isNotEmpty) 'companyId': companyIdForMachines,
              });
            },
          ),
          _buildSidebarTile(
            Icons.assignment_turned_in_outlined,
            'Historique des contrôles',
            isActive: _embedPanel == _TechnicianEmbedPanel.history,
            onTap: () {
              final techId =
                  _navTechnicianForCalendar.isNotEmpty ? _navTechnicianForCalendar : _technicianId;
              _openControlHistoryFromProfile({
                'technicianName': name,
                'technicianId': techId,
                'historyMode': 'all_controls',
              });
            },
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildSidebarTile(IconData icon, String label, {bool isActive = false, bool isSmall = false, VoidCallback? onTap}) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: isActive ? _surfaceContainerHighest : Colors.transparent,
        borderRadius: const BorderRadius.only(topRight: Radius.circular(24), bottomRight: Radius.circular(24)),
      ),
      child: ListTile(
        leading: Icon(icon, color: isActive ? Colors.white : _onSurfaceVariant.withOpacity(0.7), size: isSmall ? 18 : 22),
        title: Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            color: isActive ? Colors.white : _onSurfaceVariant.withOpacity(0.7),
            fontSize: isSmall ? 12 : 14,
          ),
        ),
        onTap: onTap ?? () {},
        dense: isSmall,
      ),
    );
  }

  Widget _buildTopHeader(Map<String, dynamic>? args) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      color: _bg,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 190,
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Image.asset(
              'assets/images/abbk_logo.png',
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
          const SizedBox.shrink(),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(
    BuildContext context,
    bool isDesktop,
    String name,
    String id,
    String specialization,
    String statusLabel,
    String imageUrl,
    Map<String, dynamic> rawArgs,
    String email,
    String clientDisplayCode,
    int monitoredMachineCount, {
    required bool canManageTechnician,
  }) {
    final double avatarSize = isDesktop ? 64 : 56;
    final BoxDecoration cardDecoration = BoxDecoration(
      color: _surfaceContainer,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withOpacity(0.08)),
    );

    Widget profileStatCard({
      required IconData icon,
      required String label,
      required String value,
    }) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 18 : 14,
          vertical: isDesktop ? 16 : 14,
        ),
        decoration: cardDecoration,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: _primaryContainer, size: isDesktop ? 26 : 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      color: _onSurfaceVariant.withOpacity(0.75),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    value,
                    style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontSize: isDesktop ? 16 : 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final String emailDisplay = email.isNotEmpty ? email : '—';
    final String clientDisplay = clientDisplayCode.isNotEmpty ? clientDisplayCode : '—';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: EdgeInsets.all(isDesktop ? 18 : 14),
              decoration: cardDecoration,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildTechnicianAvatar(
                    imageUrl: imageUrl,
                    width: avatarSize,
                    height: avatarSize,
                    borderRadius: BorderRadius.circular(avatarSize / 2),
                    iconSize: 28,
                    photoEnhance: true,
                  ),
                  SizedBox(height: isDesktop ? 16 : 14),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Text(
                        name,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.spaceGrotesk(
                          color: Colors.white,
                          fontSize: isDesktop ? 20 : 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFF69F0AE),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              statusLabel.toUpperCase(),
                              style: GoogleFonts.spaceGrotesk(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    emailDisplay,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: Colors.white.withOpacity(0.92),
                      fontSize: isDesktop ? 14 : 13,
                    ),
                  ),
                  if (specialization.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      specialization,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: _onSurfaceVariant.withOpacity(0.88),
                        fontSize: 12,
                        height: 1.3,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(height: isDesktop ? 12 : 10),
            profileStatCard(
              icon: Icons.badge_outlined,
              label: 'Identifiant agent',
              value: id,
            ),
            SizedBox(height: isDesktop ? 12 : 10),
            profileStatCard(
              icon: Icons.business_outlined,
              label: 'Client / société',
              value: clientDisplay,
            ),
            SizedBox(height: isDesktop ? 12 : 10),
            profileStatCard(
              icon: Icons.precision_manufacturing_outlined,
              label: 'Machines suivies',
              value: '$monitoredMachineCount',
            ),
            SizedBox(height: isDesktop ? 22 : 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                InkWell(
                  onTap: () async {
                    await _showQuickProfileEditDialog(
                      rawArgs: rawArgs,
                      currentName: name,
                      currentImageUrl: imageUrl.startsWith('asset:') ? '' : imageUrl,
                    );
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [_secondary.withOpacity(0.22), _secondary.withOpacity(0.08)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _secondary.withOpacity(0.45)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_outlined, color: _secondary, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          'Modifier le profil',
                          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
                if (canManageTechnician)
                  InkWell(
                    onTap: () => _confirmDelete(context, id, name),
                    borderRadius: BorderRadius.circular(10),
                    child: _buildActionButton(Icons.delete_outline, 'Supprimer', _error.withOpacity(0.1), _error, isBordered: true),
                  ),
                InkWell(
                  onTap: _logoutTechnician,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                    decoration: BoxDecoration(
                      color: _error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _error.withOpacity(0.45)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.logout, color: _error, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          'Déconnexion',
                          style: GoogleFonts.inter(color: _error, fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, String techId, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceContainerLow,
        title: Text('Supprimer $name ?', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Cette action est irréversible. Voulez-vous continuer ?', style: GoogleFonts.spaceGrotesk(color: _onSurfaceVariant)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Annuler', style: GoogleFonts.inter(color: _onSurfaceVariant)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx); // close dialog
              try {
                await ApiService.deleteTechnician(techId);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('$name supprimé avec succès.', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                    backgroundColor: _green,
                    behavior: SnackBarBehavior.floating,
                  ));
                  Navigator.pop(context, true); // back to list + refresh
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Erreur: $e', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                    backgroundColor: Colors.redAccent,
                    behavior: SnackBarBehavior.floating,
                  ));
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: _error),
            child: Text('Supprimer', style: GoogleFonts.inter(color: Colors.black87, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, Color bgColor, Color textColor, {bool isBordered = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: isBordered ? Border.all(color: textColor.withOpacity(0.3)) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: textColor, size: 20),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.inter(color: textColor, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildMainGrid(
    bool isDesktop,
    BuildContext context,
    String technicianId,
    String technicianName,
    List<String> assignedMachineIds,
    String companyIdForMachines,
    bool isConceptionProfile,
    String calendarTechId,
    Map<String, dynamic> mergedProfileArgs,
  ) {
    return _buildMachinesSection(
      context,
      assignedMachineIds,
      companyIdForMachines,
      isConceptionProfile,
      technicianId,
      technicianName,
      mergedProfileArgs,
    );
  }

  String _machineIdFromDoc(Map<String, dynamic> m) {
    return (m['id'] ?? m['_id'] ?? m['machineId'] ?? '').toString();
  }

  /// Identifiants machines (Mongo `id` / `_id`) : explicites sur le technicien, sinon tout le parc du client.
  Future<List<String>> _resolveAssignedMachineIds(
    List<String> fromArgs,
    String companyId, [
    Map<String, dynamic>? routeArgsForSelfCheck,
  ]) async {
    final ids = <String>{};
    for (final x in fromArgs) {
      final t = x.trim();
      if (t.isNotEmpty) ids.add(t);
    }
    final argsMap = routeArgsForSelfCheck;
    if (argsMap != null && _isViewingOwnTechnicianProfile(argsMap)) {
      for (final id in _coerceMachineIds(ApiService.savedTechnicianProfile?['machineIds'])) {
        ids.add(id);
      }
      try {
        await ApiService.ensureAuthTokenLoaded();
        if ((ApiService.authToken ?? '').isNotEmpty) {
          final me = await ApiService.getMyTechnicianProfile();
          for (final id in _coerceMachineIds(me['machineIds'])) {
            ids.add(id);
          }
        }
      } catch (_) {}
    }
    if (ids.isNotEmpty) return ids.toList();
    if (companyId.isEmpty) return [];
    try {
      final cm = await ApiService.getMachinesForClient(companyId);
      final fromClient = cm.map(_machineIdFromDoc).where((e) => e.isNotEmpty).toList();
      if (fromClient.isNotEmpty) return fromClient;
    } catch (_) {}
    bool sameCompany(Map<String, dynamic> m) =>
        (m['companyId'] ?? '').toString().trim() == companyId;
    try {
      final all = await ApiService.getAllMachinesFromMongo();
      final fromAll = all.where(sameCompany).map(_machineIdFromDoc).where((e) => e.isNotEmpty).toList();
      if (fromAll.isNotEmpty) return fromAll;
    } catch (_) {}
    try {
      final std = await ApiService.getMachines();
      return std.where(sameCompany).map(_machineIdFromDoc).where((e) => e.isNotEmpty).toList();
    } catch (_) {
      return ids.toList();
    }
  }

  Future<({List<String> ids, List<Map<String, dynamic>> machines})> _loadMachinesForProfileSection(
    List<String> assignedMachineIds,
    String companyId,
    Map<String, dynamic>? mergedProfileArgs,
  ) async {
    final machines = await _loadAssignedMachinesWithRisk(assignedMachineIds, companyId, mergedProfileArgs);
    final ids = machines.map((m) => _machineIdFromDoc(m)).where((e) => e.isNotEmpty).toList();
    return (ids: ids, machines: machines);
  }

  /// Ordre et liste alignés sur Mongo (`Technician.machineIds`) plutôt que sur le cache catalogue.
  Future<List<Map<String, dynamic>>?> _fetchTechnicianMachinesFromApi(
    Map<String, dynamic>? mergedProfileArgs,
  ) async {
    try {
      await ApiService.ensureAuthTokenLoaded();
      if ((ApiService.authToken ?? '').isEmpty) return null;
      final role = (ApiService.savedUserRole ?? '').toLowerCase();
      if (role == 'technician') {
        if (mergedProfileArgs == null || _isViewingOwnTechnicianProfile(mergedProfileArgs)) {
          return await ApiService.getMyTechnicianMachines();
        }
        return null;
      }
      final tid =
          (mergedProfileArgs?['technicianId'] ?? mergedProfileArgs?['id'] ?? '').toString().trim();
      if (tid.isEmpty) return null;
      final canFleet =
          ApiService.isSuperAdmin || ApiService.canManageFleet || role == 'conception';
      if (!canFleet) return null;
      return await ApiService.getTechnicianMachinesByTechnicianId(tid);
    } catch (_) {
      return null;
    }
  }

  DateTime? _parseControlDate(Map<String, dynamic> c) {
    for (final k in ['datePrevue', 'dateControle', 'createdAt']) {
      final v = c[k];
      if (v == null) continue;
      final d = DateTime.tryParse(v.toString());
      if (d != null) return d.toLocal();
    }
    return null;
  }

  bool _isOpenControleStatut(String raw) {
    final s = raw.toLowerCase().trim().replaceAll(' ', '_');
    const open = {
      'en_attente',
      'assignée',
      'assignee',
      'planifié',
      'planifie',
      'en_cours',
    };
    return open.contains(s);
  }

  /// Aligné sur le calendrier : pas d’aperçu « mission ouverte » si la machine n’est pas RUNNING.
  bool _openControleMachineRunning(Map<String, dynamic> c) {
    final st = (c['machineStatus'] ?? '').toString().trim().toUpperCase();
    if (c['machineEnMarche'] == true || st == 'RUNNING') return true;
    if (c['machineEnMarche'] == false || st == 'STOPPED' || st == 'MAINTENANCE') return false;
    return true;
  }

  Future<List<Map<String, dynamic>>> _loadOpenControlesForProfile(String techLookupId) async {
    if (techLookupId.isEmpty) return [];
    try {
      final list = await ApiService.getControlesForTechnician(techLookupId, days: 90);
      final filtered = list
          .where((c) => _isOpenControleStatut((c['statut'] ?? '').toString()))
          .where(_openControleMachineRunning)
          .toList();
      filtered.sort((a, b) {
        final da = _parseControlDate(a);
        final db = _parseControlDate(b);
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return da.compareTo(db);
      });
      return filtered;
    } catch (_) {
      return [];
    }
  }

  Widget _buildUpcomingControlesSection(
    BuildContext context,
    String calendarTechId,
    bool isConceptionProfile,
    List<String> assignedMachineIds,
    String technicianName,
    String technicianDisplayId,
    String companyIdForMachines,
  ) {
    if (isConceptionProfile || calendarTechId.isEmpty) {
      return const SizedBox.shrink();
    }
    final techForCalendar =
        _navTechnicianForCalendar.isNotEmpty ? _navTechnicianForCalendar : technicianDisplayId;

    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey<String>('upcoming_controles_v$_controlesPreviewVersion'),
      future: _loadOpenControlesForProfile(calendarTechId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: _secondary.withOpacity(0.85)),
              ),
            ),
          );
        }
        final items = snapshot.data ?? const <Map<String, dynamic>>[];
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _surfaceContainer,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _outlineVariant.withOpacity(0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.event_note_outlined, color: _secondary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'CALENDRIER DE CONTRÔLE — À TRAITER',
                      style: GoogleFonts.spaceGrotesk(
                        color: _tertiary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      _openControlCalendarFromProfile(<String, dynamic>{
                        'technicianName': technicianName,
                        'technicianId': techForCalendar,
                        'machineIds': assignedMachineIds,
                        if (companyIdForMachines.isNotEmpty) 'companyId': companyIdForMachines,
                      });
                    },
                    child: Text('Ouvrir le calendrier', style: GoogleFonts.inter(color: _secondary, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Maintenance préventive par temps de marche : condensateurs tous les 3 j (72 h cumulées), contrôle moteur/capteurs chaque semaine (168 h). Valider → compte-rendu → Terminer.',
                style: GoogleFonts.inter(color: _onSurfaceVariant, fontSize: 11, height: 1.35),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                Text(
                  'Aucun contrôle ouvert. Quand le temps de marche cumulé atteint les seuils (72 h ou 168 h selon le type), une mission apparaît ici et dans le calendrier.',
                  style: GoogleFonts.inter(color: _onSurfaceVariant.withOpacity(0.95), fontSize: 12, height: 1.4),
                )
              else
                ...items.take(8).map((c) {
                  final name = (c['machineName'] ?? 'Machine').toString();
                  final type = (c['typeControle'] ?? 'Contrôle').toString();
                  final st = (c['statut'] ?? '').toString();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          _openControlCalendarFromProfile(<String, dynamic>{
                            'technicianName': technicianName,
                            'technicianId': techForCalendar,
                            'machineIds': assignedMachineIds,
                            if (companyIdForMachines.isNotEmpty) 'companyId': companyIdForMachines,
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                          child: Row(
                            children: [
                              Icon(Icons.precision_manufacturing_outlined, size: 18, color: _onSurfaceVariant),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: GoogleFonts.inter(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      '$type · $st',
                                      style: GoogleFonts.inter(color: _onSurfaceVariant, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right, color: _onSurfaceVariant.withOpacity(0.7), size: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              if (items.length > 8)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '+ ${items.length - 8} autre(s) — voir le calendrier complet',
                    style: GoogleFonts.inter(color: _secondary, fontSize: 11),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMachinesSection(
    BuildContext context,
    List<String> assignedMachineIds,
    String companyIdForMachines,
    bool isConceptionProfile,
    String technicianId,
    String technicianName,
    Map<String, dynamic> mergedProfileArgs,
  ) {
    return FutureBuilder<({List<String> ids, List<Map<String, dynamic>> machines})>(
      key: ValueKey<String>('machines_section_v$_machinesSectionVersion'),
      future: _loadMachinesForProfileSection(assignedMachineIds, companyIdForMachines, mergedProfileArgs),
      builder: (context, snapshot) {
        final controlledMachines = snapshot.data?.machines ?? const <Map<String, dynamic>>[];
        final resolvedIds = snapshot.data?.ids ?? assignedMachineIds;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (snapshot.connectionState == ConnectionState.waiting)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (snapshot.hasError)
              Text(
                'Impossible de charger les machines assignées',
                style: GoogleFonts.inter(color: _error),
              )
            else if (controlledMachines.isEmpty)
              Text(
                isConceptionProfile
                    ? 'Aucune machine actuellement assignée à ce concepteur.'
                    : 'Aucune machine actuellement assignée à ce technicien.',
                style: GoogleFonts.inter(color: _onSurfaceVariant),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      children: [
                        const Icon(Icons.hub_outlined, color: _secondary, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${controlledMachines.length} machine${controlledMachines.length != 1 ? 's' : ''} affichée${controlledMachines.length != 1 ? 's' : ''}'
                            '${resolvedIds.length != controlledMachines.length ? ' (${resolvedIds.length} référence${resolvedIds.length != 1 ? 's' : ''})' : ''}',
                            style: GoogleFonts.spaceGrotesk(
                              color: _onSurface,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildMachinesGridContent(
                    context,
                    controlledMachines,
                    technicianId,
                    technicianName,
                    isConceptionProfile,
                    assignedMachineIds,
                    companyIdForMachines,
                  ),
                ],
              ),
          ],
        );
      },
    );
  }

  Future<void> _handleStartMachineMarche({
    required BuildContext context,
    required String machineId,
    required String machineName,
    required String technicianId,
    required String technicianName,
    required List<String> assignedMachineIds,
    required String companyIdForMachines,
  }) async {
    if (machineId.isEmpty) return;
    setState(() => _startingMarcheIds.add(machineId));
    try {
      final res = await ApiService.startMachineMarche(machineId);
      if (!mounted) return;
      DateTime? debut;
      final iso = res['debutSessionMarche'];
      if (iso != null) {
        debut = DateTime.tryParse(iso.toString())?.toLocal();
      }
      debut ??= DateTime.now();
      setState(() {
        _startingMarcheIds.remove(machineId);
        _sessionDebutByMachineId[machineId] = debut!;
        _machinesSectionVersion++;
        _controlesPreviewVersion++;
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _surfaceContainerHigh,
          content: Text(
            '« $machineName » est en marche. Le temps de fonctionnement est enregistré ; les contrôles à prévoir s’affichent dans le calendrier.',
            style: GoogleFonts.inter(color: Colors.white),
          ),
          action: SnackBarAction(
            textColor: _secondary,
            label: 'Calendrier contrôle',
            onPressed: () {
              if (!context.mounted) return;
              _openControlCalendarFromProfile(<String, dynamic>{
                'technicianName': technicianName,
                'technicianId': technicianId,
                'machineIds': assignedMachineIds,
                if (companyIdForMachines.isNotEmpty) 'companyId': companyIdForMachines,
              });
            },
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _startingMarcheIds.remove(machineId);
          _sessionDebutByMachineId.remove(machineId);
        });
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: _error.withOpacity(0.9),
            content: Text(e.toString().replaceFirst('Exception: ', ''), style: GoogleFonts.inter(color: Colors.white)),
          ),
        );
      }
    }
  }

  /// Arrête la machine côté backend ([POST /api/machines/:id/stop]) et nettoie le chrono local.
  Future<void> _handleStopMachineMarche({
    required BuildContext context,
    required String machineId,
    required String machineName,
    required String technicianName,
  }) async {
    if (machineId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: _surfaceContainerLow,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Row(
            children: [
              const Icon(Icons.stop_circle_outlined, color: _error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Arrêter « $machineName » ?',
                  style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          content: Text(
            'La session de marche sera clôturée et le compteur de temps de fonctionnement figé.',
            style: GoogleFonts.inter(color: _onSurfaceVariant, height: 1.35),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Annuler', style: GoogleFonts.inter(color: _onSurfaceVariant)),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _error, foregroundColor: Colors.white),
              icon: const Icon(Icons.stop_circle_outlined, size: 18),
              label: Text('Arrêter', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _stoppingMarcheIds.add(machineId));
    try {
      await ApiService.stopMachine(
        machineId,
        reason: 'Arrêt manuel depuis le profil technicien',
        stoppedBy: technicianName.isNotEmpty ? technicianName : 'Technicien',
      );
      if (!mounted) return;
      setState(() {
        _stoppingMarcheIds.remove(machineId);
        _sessionDebutByMachineId.remove(machineId);
        _machinesSectionVersion++;
        _controlesPreviewVersion++;
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _surfaceContainerHigh,
          content: Text(
            '« $machineName » est arrêtée. La session de marche est clôturée.',
            style: GoogleFonts.inter(color: Colors.white),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _stoppingMarcheIds.remove(machineId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _error.withOpacity(0.9),
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
            style: GoogleFonts.inter(color: Colors.white),
          ),
        ),
      );
    }
  }

  Widget _buildMachinesGridContent(
    BuildContext context,
    List<Map<String, dynamic>> controlledMachines,
    String technicianId,
    String technicianName,
    bool isConceptionProfile,
    List<String> assignedMachineIds,
    String companyIdForMachines,
  ) {
    final critical = controlledMachines.where((m) {
      final risk = (m['_riskPercent'] as int?) ?? 0;
      final status = (m['status'] ?? '').toString().toUpperCase();
      final requiresStop = m['_requiresStop'] == true;
      return requiresStop || risk > 60 || status == 'PANNE';
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (critical.isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _error.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _error.withOpacity(0.45)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: _error, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Notification panne: ${critical.length} machine(s) en alerte (IA > 60% ou panne détectée).',
                    style: GoogleFonts.inter(color: _error, fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: constraints.maxWidth > 600 ? 2 : 1,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: isConceptionProfile
                  ? 1.5
                  : (controlledMachines.any((m) {
                        final st = (m['status'] ?? '').toString().toUpperCase();
                        if (st == 'RUNNING') return true;
                        return _machineMissionNeedsAck(m);
                      })
                      ? 1.35
                      : 1.6),
              children: controlledMachines.map((m) {
                final machineId = _machineIdFromDoc(m);
                final machineName = (m['name'] ?? 'Machine').toString();
                final status = (m['status'] ?? '').toString();
                final risk = (m['_riskPercent'] as int?) ?? _machineHealthFromStatus(status);
                final requiresStop = m['_requiresStop'] == true;
                final isAlert = requiresStop || risk > 60 || status.toUpperCase() == 'PANNE';
                final riskNote = (m['_riskLabel'] ?? '').toString();
                final running = status.toUpperCase() == 'RUNNING';
                final sessionDebut = _effectiveDebutSession(machineId, m);
                final sessionLive = running && sessionDebut != null;
                final missionAwaiting = _machineMissionNeedsAck(m);

                return _buildMachineCard(
                  Icons.precision_manufacturing,
                  machineName,
                  (m['companyId'] ?? 'Client').toString(),
                  risk,
                  missionAwaiting
                      ? _error
                      : (sessionLive
                          ? _green
                          : (isAlert ? _error : (running ? _secondary : _error))),
                  isAlert: isAlert,
                  alertText: riskNote,
                  sessionActiveVisual: sessionLive,
                  missionAwaitingAck: missionAwaiting,
                  onTap: () {
                    if (machineId.isEmpty) return;

                    Navigator.pushNamed(
                      context,
                      '/mission-control',
                      arguments: {
                        'machineId': machineId,
                        'techId': machineId,
                        'name': technicianName,
                        'machineName': machineName,
                        'technicianId': technicianId,
                      },
                    );
                  },
                  actionFooter: isConceptionProfile
                      ? null
                      : _buildMachineMarcheButton(
                          context,
                          machineId: machineId,
                          machineName: machineName,
                          status: status,
                          technicianId: technicianId,
                          technicianName: technicianName,
                          assignedMachineIds: assignedMachineIds,
                          companyIdForMachines: companyIdForMachines,
                          onViewDetails: () {
                            if (machineId.isEmpty) return;
                            showDialog<void>(
                              context: context,
                              barrierDismissible: true,
                              builder: (dialogContext) => Dialog(
                                backgroundColor: Colors.transparent,
                                insetPadding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 18,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: SizedBox(
                                    width: 1200,
                                    height: MediaQuery.of(dialogContext).size.height * 0.9,
                                    child: MachineDetailAiPage(
                                      machineId: machineId,
                                      viewerRole: 'technician',
                                      viewerName: technicianName,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                          onMissionMessage: () {
                            if (machineId.isEmpty) return;
                            showDialog<void>(
                              context: context,
                              barrierDismissible: true,
                              builder:
                                  (dialogContext) => Dialog(
                                    backgroundColor: Colors.transparent,
                                    insetPadding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 14,
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: SizedBox(
                                        width: 1320,
                                        height:
                                            MediaQuery.of(
                                              dialogContext,
                                            ).size.height *
                                            0.92,
                                        child: MissionControlPage(
                                          initialArgs: {
                                            'machineId': machineId,
                                            'techId': machineId,
                                            'name': technicianName,
                                            'machineName': machineName,
                                            'technicianId': technicianId,
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                            );
                          },
                          debutSessionMarche: sessionDebut,
                        ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Future<List<Map<String, dynamic>>> _loadAssignedMachinesWithRisk(
    List<String> assignedMachineIds,
    String companyId,
    Map<String, dynamic>? mergedProfileArgs,
  ) async {
    final mergedById = <String, Map<String, dynamic>>{};
    void mergeIn(List<Map<String, dynamic>> list) {
      const missionKeys = <String>[
        'missionStatus',
        'missionCompletedAt',
        'missionConfirmedAt',
        'missionNeedsTechnicianAck',
      ];
      for (final m in list) {
        final id = _machineIdFromDoc(m);
        if (id.isEmpty) continue;
        final prev = mergedById[id];
        final next = Map<String, dynamic>.from(m);
        if (prev != null) {
          for (final k in missionKeys) {
            final pv = prev[k];
            final nv = next[k];
            final prevOk = pv != null && pv.toString().trim().isNotEmpty;
            final nextOk = nv != null && nv.toString().trim().isNotEmpty;
            if (!nextOk && prevOk) {
              next[k] = pv;
            }
          }
        }
        mergedById[id] = next;
      }
    }

    final orderedFromDb = await _fetchTechnicianMachinesFromApi(mergedProfileArgs);
    if (orderedFromDb != null && orderedFromDb.isNotEmpty) {
      mergeIn(orderedFromDb);
    }

    try {
      mergeIn(await ApiService.getAllMachinesFromMongo());
    } catch (_) {}
    try {
      mergeIn(await ApiService.getMachines());
    } catch (_) {}

    final assignedResolved =
        await _resolveAssignedMachineIds(assignedMachineIds, companyId, mergedProfileArgs);
    final assignedSet = assignedResolved.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();

    late final List<Map<String, dynamic>> controlledMachines;
    if (orderedFromDb != null && orderedFromDb.isNotEmpty) {
      controlledMachines = orderedFromDb.map((d) {
        final id = _machineIdFromDoc(d);
        return mergedById[id] ?? d;
      }).toList();
    } else {
      final allMachines = mergedById.values.toList();
      controlledMachines = allMachines.where((m) => _assignedMachineMatches(m, assignedSet)).toList();
    }

    for (final m in controlledMachines) {
      final machineId = _machineIdFromDoc(m);
      if (machineId.isEmpty) continue;
      try {
        final latest = await ApiService.getLatestTelemetry(machineId);
        final riskRaw = latest?['prob_panne'] ?? latest?['panne_probability'] ?? latest?['scenarioProbPanne'];
        final num? riskNum = riskRaw is num ? riskRaw : num.tryParse(riskRaw?.toString() ?? '');
        final int riskPercent = riskNum == null ? 0 : (riskNum <= 1 ? (riskNum * 100).round() : riskNum.round());
        m['_riskPercent'] = riskPercent.clamp(0, 100);
        m['_requiresStop'] = latest?['requires_stop'] == true;
        m['_riskLabel'] = riskPercent > 60
            ? 'Risque IA ${riskPercent}%'
            : (latest?['notification_message'] ?? '').toString();
        final status = (m['status'] ?? '').toString().toUpperCase();
        final critical = (m['_requiresStop'] == true) || riskPercent > 60 || status == 'PANNE';
        if (critical && !_criticalAlertSentMachineIds.contains(machineId)) {
          final reason = status == 'PANNE'
              ? 'Panne détectée sur la machine.'
              : 'Risque de panne élevé détecté par IA.';
          _sendCriticalAlertToClient(
            machineId: machineId,
            riskPercent: riskPercent,
            reason: reason,
          );
          _criticalAlertSentMachineIds.add(machineId);
        } else if (!critical) {
          _criticalAlertSentMachineIds.remove(machineId);
        }
      } catch (_) {
        m['_riskPercent'] = _machineHealthFromStatus((m['status'] ?? '').toString());
        m['_requiresStop'] = false;
        m['_riskLabel'] = '';
        _criticalAlertSentMachineIds.remove(machineId);
      }
    }
    return controlledMachines;
  }

  int _machineHealthFromStatus(String status) {
    final s = status.toUpperCase();
    if (s == 'RUNNING') return 92;
    if (s == 'STOPPED') return 58;
    return 75;
  }

  /// Mission envoyée par la maintenance et encore en attente côté terrain (API ou statut dérivé).
  bool _machineMissionNeedsAck(Map<String, dynamic> m) {
    if (m['missionNeedsTechnicianAck'] == true) return true;
    final s = (m['missionStatus'] ?? '').toString().toUpperCase().trim();
    return s == 'SENT' || s == 'PENDING' || s == 'STARTED';
  }

  Widget _buildTechnicianHistorySection(
    List<String> assignedMachineIds,
    String companyIdForMachines,
    String calendarTechId,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _outlineVariant.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'HISTORIQUE DES VALEURS MACHINES',
                style: GoogleFonts.spaceGrotesk(
                  color: _secondary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.4,
                ),
              ),
              const Spacer(),
              FutureBuilder<List<String>>(
                future: _resolveAssignedMachineIds(assignedMachineIds, companyIdForMachines),
                builder: (context, snap) {
                  final n = snap.data?.length ?? assignedMachineIds.length;
                  return Text(
                    '$n machine(s) liées',
                    style: GoogleFonts.inter(color: _onSurfaceVariant, fontSize: 11),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _resolveAssignedMachineIds(assignedMachineIds, companyIdForMachines)
                .then(_loadTechnicianHistoryRows),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(14),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              if (snapshot.hasError) {
                return Text(
                  'Erreur chargement historique',
                  style: GoogleFonts.inter(color: _error),
                );
              }
              final rows = snapshot.data ?? const <Map<String, dynamic>>[];
              if (rows.isEmpty) {
                return Text(
                  'Pas encore de mesures historiques pour ces machines.',
                  style: GoogleFonts.inter(color: _onSurfaceVariant),
                );
              }
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingTextStyle: GoogleFonts.spaceGrotesk(color: _onSurfaceVariant, fontSize: 10),
                  dataTextStyle: GoogleFonts.inter(color: _onSurface, fontSize: 12),
                  columns: const [
                    DataColumn(label: Text('Machine')),
                    DataColumn(label: Text('Heure')),
                    DataColumn(label: Text('Temp °C')),
                    DataColumn(label: Text('Pression')),
                    DataColumn(label: Text('Puissance')),
                    DataColumn(label: Text('Risque IA %')),
                  ],
                  rows: rows.map((r) {
                    final machineId = (r['_machineId'] ?? '').toString();
                    final dt = _fmtDate((r['createdAt'] ?? '').toString());
                    final temp = _n(r['temperature'] ?? r['thermal']);
                    final pressure = _n(r['pressure']);
                    final power = _n(r['power']);
                    final riskRaw = r['prob_panne'] ?? r['panne_probability'] ?? r['scenarioProbPanne'] ?? 0;
                    final risk = _riskPercent(riskRaw);
                    return DataRow(cells: [
                      DataCell(Text(machineId)),
                      DataCell(Text(dt)),
                      DataCell(Text(temp.toStringAsFixed(1))),
                      DataCell(Text(pressure.toStringAsFixed(2))),
                      DataCell(Text(power.toStringAsFixed(2))),
                      DataCell(Text('$risk')),
                    ]);
                  }).toList(),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Text(
            'COMPTES RENDUS — CONTRÔLES TERMINÉS',
            style: GoogleFonts.spaceGrotesk(
              color: _tertiary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Saisies depuis le calendrier (Valider) et clôtures de missions.',
            style: GoogleFonts.inter(color: _onSurfaceVariant, fontSize: 11),
          ),
          const SizedBox(height: 10),
          FutureBuilder<List<Map<String, dynamic>>>(
            key: ValueKey<int>(_completedControlesRefreshGen),
            future: _loadCompletedControlesHistory(calendarTechId),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _secondary),
                    ),
                  ),
                );
              }
              final list = snap.data ?? const <Map<String, dynamic>>[];
              if (list.isEmpty) {
                return Text(
                  'Aucun contrôle terminé enregistré. Après validation sur le calendrier, le compte-rendu apparaît ici.',
                  style: GoogleFonts.inter(color: _onSurfaceVariant, fontSize: 12, height: 1.35),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: list.map((c) {
                  final mname = (c['machineName'] ?? c['machineId'] ?? '—').toString();
                  final type = (c['typeControle'] ?? 'Contrôle').toString();
                  final notes = (c['notes'] ?? '').toString().trim();
                  final techNom = (c['technicienNom'] ?? c['technicianName'] ?? '').toString().trim();
                  final when = _fmtDate((c['dateRealisation'] ?? c['completedAt'] ?? c['updatedAt'] ?? c['dateControle'] ?? '').toString());
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _surfaceContainer,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _outlineVariant.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mname,
                          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          type,
                          style: GoogleFonts.inter(color: _secondary, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        if (notes.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            notes,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(color: _onSurfaceVariant, fontSize: 12, height: 1.3),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          techNom.isNotEmpty ? 'Terminé · $techNom · $when' : 'Terminé · $when',
                          style: GoogleFonts.inter(color: _onSurfaceVariant.withOpacity(0.85), fontSize: 10),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _loadCompletedControlesHistory(String technicianLookupId) async {
    final id = technicianLookupId.trim();
    if (id.isEmpty) return [];
    try {
      final list = await ApiService.getControlesForTechnician(id, days: 180);
      final done = list.where((c) {
        final s = (c['statut'] ?? '').toString().toLowerCase().replaceAll(' ', '_').replaceAll('é', 'e');
        return s == 'termine' || s == 'terminé';
      }).toList();
      done.sort((a, b) {
        DateTime? pd(dynamic x) => DateTime.tryParse((x ?? '').toString());
        final da = pd(a['dateRealisation']) ??
            pd(a['completedAt']) ??
            pd(a['updatedAt']) ??
            pd(a['dateControle']) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final db = pd(b['dateRealisation']) ??
            pd(b['completedAt']) ??
            pd(b['updatedAt']) ??
            pd(b['dateControle']) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return db.compareTo(da);
      });
      return done.take(25).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _loadTechnicianHistoryRows(List<String> machineIds) async {
    final rows = <Map<String, dynamic>>[];
    for (final id in machineIds) {
      if (id.isEmpty) continue;
      try {
        final hist = await ApiService.getTelemetryHistory(id, limit: 8);
        for (final item in hist) {
          final map = Map<String, dynamic>.from(item);
          map['_machineId'] = id;
          rows.add(map);
        }
      } catch (_) {}
    }
    rows.sort((a, b) {
      final ad = DateTime.tryParse((a['createdAt'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = DateTime.tryParse((b['createdAt'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });
    if (rows.length > 25) return rows.take(25).toList();
    return rows;
  }

  double _n(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  int _riskPercent(dynamic riskRaw) {
    final n = riskRaw is num ? riskRaw.toDouble() : double.tryParse(riskRaw?.toString() ?? '') ?? 0;
    final p = n <= 1 ? (n * 100) : n;
    return p.round().clamp(0, 100);
  }

  String _fmtDate(String raw) {
    if (raw.isEmpty) return '--';
    final d = DateTime.tryParse(raw)?.toLocal();
    if (d == null) return raw;
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return '$dd/$mm $hh:$mi';
  }

  Widget _buildClientTechnicianMessengerZone() {
    final sortedMessages = [..._chatMessages]
      ..sort((a, b) {
        final ad = DateTime.tryParse((a['createdAt'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bd = DateTime.tryParse((b['createdAt'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return ad.compareTo(bd);
      });

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _outlineVariant.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.forum_outlined, color: _secondary, size: 18),
              const SizedBox(width: 8),
              Text(
                'MESSAGERIE CLIENT ↔ TECHNICIEN',
                style: GoogleFonts.spaceGrotesk(
                  color: _secondary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              if (_chatRoomId.isNotEmpty)
                Text(
                  _chatRoomId,
                  style: GoogleFonts.inter(color: _onSurfaceVariant, fontSize: 10),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: _surfaceContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 220,
                  height: 350,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _surfaceContainerHighest.withOpacity(0.25),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DISCUSSIONS RÉCENTES',
                        style: GoogleFonts.spaceGrotesk(
                          color: _onSurfaceVariant,
                          fontSize: 10,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: _chatConversations.isEmpty
                            ? Center(
                                child: Text(
                                  'Aucun client',
                                  style: GoogleFonts.inter(color: _onSurfaceVariant, fontSize: 11),
                                ),
                              )
                            : ListView.builder(
                                itemCount: _chatConversations.length,
                                itemBuilder: (context, index) {
                                  final c = _chatConversations[index];
                                  final room = (c['roomId'] ?? '').toString();
                                  final active = room == _chatRoomId;
                                  final clientName = (c['clientName'] ?? 'Client').toString();
                                  final lastText = (c['lastText'] ?? '').toString();
                                  return InkWell(
                                    onTap: () async {
                                      if (room.isEmpty) return;
                                      setState(() => _chatRoomId = room);
                                      _chatSocket?.emit('join_chat_room', {'roomId': room});
                                      try {
                                        final history = await ApiService.getChatMessages(room, limit: 200);
                                        if (!mounted) return;
                                        setState(() {
                                          _chatMessages
                                            ..clear()
                                            ..addAll(history);
                                        });
                                      } catch (_) {}
                                    },
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: active ? _surfaceContainerHighest : _surfaceContainer,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: active
                                              ? _secondary.withOpacity(0.45)
                                              : Colors.transparent,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            clientName,
                                            style: GoogleFonts.inter(
                                              color: _onSurface,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            lastText.isEmpty ? 'Aucun message' : lastText,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.inter(
                                              color: _onSurfaceVariant,
                                              fontSize: 10,
                                            ),
                                          ),
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
                  child: SizedBox(
                    height: 350,
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: _surfaceContainerHighest.withOpacity(0.55),
                            borderRadius: const BorderRadius.only(
                              topRight: Radius.circular(12),
                            ),
                          ),
                          child: Row(
                            children: [
                              const CircleAvatar(
                                radius: 15,
                                backgroundColor: _primaryContainer,
                                child: Icon(Icons.engineering, color: Colors.white, size: 14),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _chatSenderName,
                                style: GoogleFonts.inter(
                                  color: _onSurface,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _primaryContainer.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'TECHNICIEN',
                                  style: GoogleFonts.spaceGrotesk(
                                    color: _primary,
                                    fontSize: 9,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: sortedMessages.isEmpty
                                ? Center(
                                    child: Text(
                                      'Aucun message pour le moment.',
                                      style: GoogleFonts.inter(color: _onSurfaceVariant),
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: sortedMessages.length,
                                    itemBuilder: (context, i) {
                                      final m = sortedMessages[i];
                                      final sender = (m['senderName'] ?? 'User').toString();
                                      final text = (m['text'] ?? '').toString();
                                      final mine = sender == _chatSenderName;
                                      final isCritical =
                                          sender.toLowerCase().contains('alerte') ||
                                          text.toLowerCase().contains('alerte critique');
                                      return Align(
                                        alignment:
                                            mine ? Alignment.centerRight : Alignment.centerLeft,
                                        child: Container(
                                          constraints: const BoxConstraints(maxWidth: 420),
                                          margin: const EdgeInsets.symmetric(vertical: 5),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isCritical
                                                ? _error.withOpacity(0.2)
                                                : (mine
                                                    ? _primaryContainer.withOpacity(0.88)
                                                    : _surfaceContainerHighest),
                                            borderRadius: BorderRadius.circular(10),
                                            border: isCritical
                                                ? Border.all(color: _error.withOpacity(0.7))
                                                : null,
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              if (!mine)
                                                Text(
                                                  sender,
                                                  style: GoogleFonts.inter(
                                                    color: _onSurfaceVariant,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              Text(
                                                text,
                                                style: GoogleFonts.inter(
                                                  color: _onSurface,
                                                  fontSize: 12,
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
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatInputController,
                  style: GoogleFonts.inter(color: _onSurface),
                  decoration: const InputDecoration(
                    hintText: 'Écrire un message au client...',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  maxLines: 2,
                  minLines: 1,
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: _sendTechnicianMessage,
                icon: const Icon(Icons.send, size: 16),
                label: const Text('Envoyer'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _sendTechnicianMessage() {
    final text = _chatInputController.text.trim();
    if (text.isEmpty || _chatRoomId.isEmpty) return;
    _chatSocket?.emit('chat_message', {
      'roomId': _chatRoomId,
      'from': 'technician',
      'senderName': _chatSenderName,
      'text': text,
    });
    _chatInputController.clear();
  }

  void _sendCriticalAlertToClient({
    required String machineId,
    required int riskPercent,
    required String reason,
  }) {
    if (_chatRoomId.isEmpty) return;
    final alertText =
        'ALERTE CRITIQUE : $machineId\n$reason\nRisque IA: $riskPercent%.\nAction immédiate recommandée.';
    _chatSocket?.emit('chat_message', {
      'roomId': _chatRoomId,
      'from': 'system',
      'senderName': 'Alerte Système',
      'text': alertText,
    });
  }

  Widget _buildMachineMarcheButton(
    BuildContext context, {
    required String machineId,
    required String machineName,
    required String status,
    required String technicianId,
    required String technicianName,
    required List<String> assignedMachineIds,
    required String companyIdForMachines,
    required VoidCallback onViewDetails,
    required VoidCallback onMissionMessage,
    DateTime? debutSessionMarche,
  }) {
    final running = status.toUpperCase() == 'RUNNING';
    final busy = _startingMarcheIds.contains(machineId);
    final stopping = _stoppingMarcheIds.contains(machineId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (running)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.bolt, color: _green, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: debutSessionMarche != null
                      ? _MarcheElapsedLive(
                          debut: debutSessionMarche,
                          captionStyle: GoogleFonts.inter(color: _green, fontSize: 10, fontWeight: FontWeight.w600),
                          timerStyle: GoogleFonts.jetBrainsMono(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        )
                      : Text(
                          'En marche — en attente de l’horodatage serveur…',
                          style: GoogleFonts.inter(color: _green, fontSize: 10, height: 1.25),
                        ),
                ),
              ],
            ),
          ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: _primaryContainer,
            foregroundColor: Colors.black87,
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
          onPressed: (busy || stopping)
              ? null
              : () => _handleStartMachineMarche(
                    context: context,
                    machineId: machineId,
                    machineName: machineName,
                    technicianId: technicianId,
                    technicianName: technicianName,
                    assignedMachineIds: assignedMachineIds,
                    companyIdForMachines: companyIdForMachines,
                  ),
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54),
                )
              : const Icon(Icons.play_circle_outline, size: 20),
          label: Text(
            running ? 'Actualiser début de session' : 'Machine en marche',
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ),
        if (running) ...[
          const SizedBox(height: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _error,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            onPressed: (stopping || busy)
                ? null
                : () => _handleStopMachineMarche(
                      context: context,
                      machineId: machineId,
                      machineName: machineName,
                      technicianName: technicianName,
                    ),
            icon: stopping
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                  )
                : const Icon(Icons.stop_circle_outlined, size: 20),
            label: Text(
              stopping ? 'Arrêt en cours…' : 'Machine en stop',
              style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withOpacity(0.25)),
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
          onPressed: onViewDetails,
          icon: const Icon(Icons.open_in_new, size: 18),
          label: Text(
            'Voir le détail machine',
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: _secondary,
            side: BorderSide(color: _secondary.withOpacity(0.35)),
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
          onPressed: onMissionMessage,
          icon: const Icon(Icons.chat_bubble_outline, size: 18),
          label: Text(
            'Message mission',
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildMachineCard(
    IconData icon,
    String name,
    String client,
    int score,
    Color color, {
    VoidCallback? onTap,
    bool isAlert = false,
    String alertText = '',
    Widget? actionFooter,
    bool sessionActiveVisual = false,
    bool missionAwaitingAck = false,
  }) {
    final useMissionChrome = missionAwaitingAck;
    final useSessionChrome = sessionActiveVisual && !useMissionChrome;
    final barColor = useMissionChrome
        ? _error
        : (useSessionChrome ? _green : color);
    final iconBg = useMissionChrome
        ? _error.withOpacity(0.2)
        : (useSessionChrome ? _green.withOpacity(0.18) : _surfaceContainerLow);

    Widget card(double pulse) => Material(
          color: useMissionChrome
              ? const Color(0xFF2A1518).withOpacity(0.96)
              : (useSessionChrome
                  ? const Color(0xFF152A22).withOpacity(0.95)
                  : (isAlert ? _error.withOpacity(0.07 + (0.08 * pulse)) : _surfaceContainerHigh)),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: useMissionChrome
                      ? _error.withOpacity(0.65 + (0.25 * pulse))
                      : (useSessionChrome
                          ? _green.withOpacity(0.75)
                          : (isAlert ? _error.withOpacity(0.45 + (0.45 * pulse)) : Colors.transparent)),
                  width: (useMissionChrome || useSessionChrome || isAlert) ? 1.8 : 0,
                ),
                boxShadow: useMissionChrome
                    ? [
                        BoxShadow(
                          color: _error.withOpacity(0.28),
                          blurRadius: 20,
                          spreadRadius: 0,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : useSessionChrome
                        ? [
                            BoxShadow(
                              color: _green.withOpacity(0.22),
                              blurRadius: 18,
                              spreadRadius: 0,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
              ),
              child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: useMissionChrome ? _error : (useSessionChrome ? _green : color), size: 20),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: '$score',
                          style: GoogleFonts.spaceGrotesk(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        TextSpan(
                          text: '%',
                          style: GoogleFonts.spaceGrotesk(fontSize: 12, color: _onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Text('HEALTH SCORE', style: GoogleFonts.spaceGrotesk(fontSize: 8, color: _onSurfaceVariant, letterSpacing: 1)),
                ],
              ),
            ],
          ),
          if (actionFooter == null) const Spacer(),
          if (actionFooter != null) const SizedBox(height: 10),
          Text(name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          Text('Client: $client', style: TextStyle(color: _onSurfaceVariant, fontSize: 12)),
          if (missionAwaitingAck) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.mark_email_unread_outlined, color: _error, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Mission maintenance — action requise',
                    style: GoogleFonts.inter(color: _error, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
          if (isAlert) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.notifications_active, color: _error, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    alertText.isEmpty ? 'Alerte panne détectée' : alertText,
                    style: GoogleFonts.inter(color: _error, fontSize: 11, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (actionFooter != null) ...[
            const SizedBox(height: 10),
            actionFooter,
          ],
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: score / 100,
              backgroundColor: _surfaceContainerLow,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
              minHeight: 2,
            ),
          ),
        ],
      ),
            ),
          ),
        );

    if (!isAlert && !missionAwaitingAck) {
      return card(0);
    }

    return StreamBuilder<int>(
      stream: Stream.periodic(const Duration(milliseconds: 550), (x) => x),
      builder: (context, snapshot) {
        final pulse = ((snapshot.data ?? 0) % 2 == 0) ? 0.15 : 1.0;
        return card(pulse);
      },
    );
  }

  Widget _buildAddMachineCard() {
    return Container(
      decoration: BoxDecoration(
        color: _surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white10, style: BorderStyle.none), // dashed in CSS
              ),
              child: const Icon(Icons.add, color: _onSurfaceVariant, size: 32),
            ),
            const SizedBox(height: 12),
            const Text('Assigner Nouvelle Machine', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            Text('Mise à jour du protocole requis', style: TextStyle(color: _onSurfaceVariant, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildPerformanceSection() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: _surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          Positioned(
            right: 0,
            top: 0,
            child: Icon(Icons.query_stats, size: 100, color: Colors.white.withOpacity(0.05)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Performance Hebdomadaire', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildStatItem('24', 'Interventions', _secondary),
                  _buildStatItem('98.2%', 'Taux Succès', _primaryContainer),
                  _buildStatItem('02h', 'Délai Moyen', _tertiary),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String val, String label, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(val, style: GoogleFonts.spaceGrotesk(fontSize: 32, fontWeight: FontWeight.bold, color: color)),
        Text(label.toUpperCase(), style: GoogleFonts.spaceGrotesk(fontSize: 9, color: _onSurfaceVariant, letterSpacing: 1.5)),
      ],
    );
  }

  Widget _buildMobileBottomNav() {
    return Container(
      height: 72,
      decoration: const BoxDecoration(
        color: _surfaceContainerLow,
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildMobileNavIcon(Icons.analytics_outlined, 'Overview'),
          _buildMobileNavIcon(Icons.route_outlined, 'Location'),
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(color: _primaryContainer, shape: BoxShape.circle),
            child: const Icon(Icons.person, color: Colors.black87),
          ),
          _buildMobileNavIcon(Icons.precision_manufacturing_outlined, 'Fleet'),
          _buildMobileNavIcon(Icons.description_outlined, 'Docs'),
        ],
      ),
    );
  }

  Widget _buildMobileNavIcon(IconData icon, String label) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: _onSurfaceVariant, size: 20),
        const SizedBox(height: 4),
        Text(label, style: GoogleFonts.spaceGrotesk(color: _onSurfaceVariant, fontSize: 9)),
      ],
    );
  }

  /// Extrait `tempsMarche.debutSessionMarche` renvoyé par l’API (Mongo).
  DateTime? _parseDebutSessionMarche(Map<String, dynamic> m) {
    final tm = m['tempsMarche'];
    if (tm is! Map) return null;
    final raw = tm['debutSessionMarche'];
    if (raw == null) return null;
    if (raw is DateTime) return raw.toLocal();
    final parsed = DateTime.tryParse(raw.toString());
    return parsed?.toLocal();
  }

  /// Chrono : préfère Mongo après reload, sinon début renvoyé par POST start-marche au clic.
  DateTime? _effectiveDebutSession(String machineId, Map<String, dynamic> m) {
    final st = (m['status'] ?? '').toString().toUpperCase();
    if (st != 'RUNNING') return null;
    return _parseDebutSessionMarche(m) ?? _sessionDebutByMachineId[machineId];
  }
}

/// Durée écoulée depuis le début de session RUNNING : `01jr:06h:30min` (mis à jour chaque seconde).
String _formatMarcheElapsed(Duration d) {
  if (d.isNegative) return '00jr:00h:00min';
  final days = d.inDays;
  final hours = d.inHours.remainder(24);
  final minutes = d.inMinutes.remainder(60);
  final dayStr = days >= 100 ? '$days' : days.toString().padLeft(2, '0');
  return '${dayStr}jr:${hours.toString().padLeft(2, '0')}h:${minutes.toString().padLeft(2, '0')}min';
}

class _MarcheElapsedLive extends StatefulWidget {
  const _MarcheElapsedLive({
    required this.debut,
    required this.captionStyle,
    required this.timerStyle,
  });

  final DateTime debut;
  final TextStyle captionStyle;
  final TextStyle timerStyle;

  @override
  State<_MarcheElapsedLive> createState() => _MarcheElapsedLiveState();
}

class _MarcheElapsedLiveState extends State<_MarcheElapsedLive> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final elapsed = now.difference(widget.debut.toLocal());
    final line = _formatMarcheElapsed(elapsed);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Machine active — durée de session', style: widget.captionStyle),
        const SizedBox(height: 4),
        Text(line, style: widget.timerStyle),
      ],
    );
  }
}
