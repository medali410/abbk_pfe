import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'services/api_service.dart';
import 'utils/app_layout.dart';
import 'machine_detail_ai_page.dart';
import 'add_machine_page.dart';
import 'add_client_page.dart';
import 'add_technician_page.dart';
import 'add_maintenance_agent_page.dart';
import 'utils/form_validators.dart';
import 'widgets/message_equipe_view.dart';


class ConcepteurDashboardPage extends StatefulWidget {
  const ConcepteurDashboardPage({super.key});

  @override
  State<ConcepteurDashboardPage> createState() =>
      _ConcepteurDashboardPageState();
}

class _ConcepteurDashboardPageState extends State<ConcepteurDashboardPage> {
  // Theme Colors
  static const Color bgColor = Color(0xFF0A0A1B);
  static const Color sidebarColor = Color(0xFF111122);
  static const Color cardColor = Color(0xFF1A1A2E);
  static const Color primaryColor = Color(0xFFFF9F64);
  static const Color accentColor = Color(0xFF7B61FF);
  static const Color textColor = Color(0xFFF4F4F9);
  static const Color mutedTextColor = Color(0xFF9E9EAE);
  static const Color successColor = Color(0xFF4CAF50);
  static const Color alertColor = Color(0xFFFF4B4B);
  static const int _maxPickedImageBytes = 12 * 1024 * 1024;
  static const int _targetUploadImageBytes = 60 * 1024;
  static const int _hardUploadImageBytes = 75 * 1024;
  static const int _maxImageDimension = 900;

  String selectedMenu = 'DASHBOARD';

  // State variables
  List<Map<String, dynamic>> _allMachines = [];
  List<Map<String, dynamic>> _purchaseRequests = [];
  final Set<String> _reviewedRequestIds = <String>{};
  final Map<String, String> _machineTokensById = <String, String>{};
  final List<Map<String, String>> _machineNotifications =
      <Map<String, String>>[];
  bool _machineSnapshotInitialized = false;
  int _unreadMachineNotifications = 0;
  Future<List<Map<String, dynamic>>>? _clientsFuture;
  Future<List<Map<String, dynamic>>>? _selectedClientMachinesFuture;
  String? _selectedCatalogClientId;
  final TextEditingController _clientSearchController = TextEditingController();
  String _clientSearchQuery = '';
  Future<List<Map<String, dynamic>>>? _techniciansFuture;
  String? _selectedTechnicianId;
  final TextEditingController _technicianSearchController =
      TextEditingController();
  String _technicianSearchQuery = '';
  Future<List<Map<String, dynamic>>>? _maintenanceAgentsFuture;
  Future<Map<String, dynamic>>? _clientLoginSurveyFuture;
  String? _selectedMaintenanceAgentId;
  final TextEditingController _maintenanceSearchController =
      TextEditingController();
  String _maintenanceSearchQuery = '';
  bool _loading = true;
  bool _loadingRequests = false;
  bool _showAllPurchaseRequests = false;
  bool _showAllTechnicianRequests = false;
  String? _error;
  bool _hasFleetSession = true;
  bool _silentRecoveryTried = false;
  String? _profileExpandedFilter;

  /// Écoute missions / messages diagnostic pour notifier le concepteur (ex. technicien confirme).
  IO.Socket? _missionAckSocket;

  /// ── Live telemetry polling (1s) ───────────────────────────────────────────
  final Map<String, Map<String, dynamic>> _liveTelemetryByMachineId = <String, Map<String, dynamic>>{};
  final Set<String> _polledMachineIds = <String>{};
  Timer? _liveTelemetryTimer;
  /// Notifies listeners every time telemetry is fetched to avoid global setState rebuilds
  final ValueNotifier<int> _telemetryTick = ValueNotifier<int>(0);
  /// Tracks the last risk level that triggered a toast to avoid spam.
  final Map<String, String> _lastNotifiedRiskById = <String, String>{};

  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'Toutes les catégories';
  String _selectedStatus = 'Tous';
  String _profileDisplayName = '';
  bool _profileLoading = false;
  String? _profileLoadError;
  static const String _defaultProfilePhotoUrl = '';
  String _profilePhotoUrl = _defaultProfilePhotoUrl;
  String _profileEmail = '';
  String _concepteurProfileId = '';
  Map<String, dynamic> _concepteurProfileData = const <String, dynamic>{};
  Map<String, dynamic>? _concepteurProjectTeam;

  bool _looksLikeNetworkImage(String value) {
    final v = value.trim().toLowerCase();
    return v.startsWith('http://') || v.startsWith('https://');
  }

  bool _looksLikeDataImage(String value) {
    final v = value.trim().toLowerCase();
    return v.startsWith('data:image/');
  }

  String _normalizeMachineImageValue(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    if (_looksLikeNetworkImage(trimmed) || _looksLikeDataImage(trimmed)) {
      return trimmed;
    }

    final hasExtension = RegExp(
      r'\.[a-z0-9]{2,5}$',
      caseSensitive: false,
    ).hasMatch(trimmed);
    return hasExtension ? trimmed : '$trimmed.png';
  }

  String _toEditImageValue(String value) {
    final trimmed = value.trim();
    if (trimmed.toLowerCase().endsWith('.png') &&
        !_looksLikeNetworkImage(trimmed) &&
        !_looksLikeDataImage(trimmed)) {
      return trimmed.substring(0, trimmed.length - 4);
    }
    return trimmed;
  }

  bool _looksLikeLocalFilePath(String value) {
    final v = value.trim();
    if (v.isEmpty) return false;
    return RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(v) ||
        v.startsWith(r'\\') ||
        v.startsWith('/');
  }

  String _formatDateTime(dynamic value) {
    final s = value?.toString().trim() ?? '';
    if (s.isEmpty) return '';
    final dt = DateTime.tryParse(s);
    if (dt == null) return s;
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  String _clientIdOf(Map<String, dynamic> c) =>
      (c['clientId'] ?? c['id'] ?? c['_id'] ?? '').toString();

  String _clientNameOf(Map<String, dynamic> c) =>
      (c['name'] ?? c['clientName'] ?? 'Client').toString();

  String _entityAvatarUrlOf(Map<String, dynamic> data) {
    for (final key in const [
      'avatarUrl',
      'photoUrl',
      'profilePhotoUrl',
      'imageUrl',
      'image',
      'avatar',
      'photo',
      'profileImage',
    ]) {
      final value = (data[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _initialsFromName(String name) {
    final parts =
        name
            .trim()
            .split(RegExp(r'\s+'))
            .where((e) => e.trim().isNotEmpty)
            .toList();
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  Widget _entityAvatar(
    Map<String, dynamic> data,
    String displayName, {
    double radius = 18,
  }) {
    final imageValue = _entityAvatarUrlOf(data);
    final size = radius * 2;
    final initials = _initialsFromName(displayName);
    final fallback = Container(
      height: size,
      width: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2D),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF222233)),
      ),
      child: Text(
        initials,
        style: GoogleFonts.inter(
          color: primaryColor,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.72,
        ),
      ),
    );
    if (imageValue.isEmpty) return fallback;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: _buildMachineImageWidget(
          imageValue,
          height: size,
          width: size,
          fit: BoxFit.cover,
          fallback: fallback,
        ),
      ),
    );
  }

  Set<String> _clientLinkedIdKeys(Map<String, dynamic> client) {
    final s = <String>{};
    for (final k in ['clientId', 'id', '_id']) {
      final v = (client[k] ?? '').toString().trim();
      if (v.isNotEmpty) s.add(v);
    }
    final id = _clientIdOf(client);
    if (id.isNotEmpty) s.add(id);
    return s;
  }

  bool _linkedIdMatches(String a, String b) {
    final x = a.trim();
    final y = b.trim();
    if (x.isEmpty || y.isEmpty) return false;
    if (x == y) return true;
    if (x.length >= 12 && y.length >= 12 && (x.contains(y) || y.contains(x))) {
      return true;
    }
    return false;
  }

  List<Map<String, dynamic>> _techniciansForClientKeys(
    List<Map<String, dynamic>> techs,
    Set<String> clientKeys,
  ) {
    return techs.where((t) {
      final comp = (t['companyId'] ?? '').toString().trim();
      if (comp.isEmpty) return false;
      for (final k in clientKeys) {
        if (_linkedIdMatches(comp, k)) return true;
      }
      return false;
    }).toList();
  }

  List<Map<String, dynamic>> _maintenanceAgentsForClientKeys(
    List<Map<String, dynamic>> agents,
    Set<String> clientKeys,
  ) {
    return agents.where((a) {
      final aid = (a['clientId'] ?? '').toString().trim();
      if (aid.isEmpty) return false;
      for (final k in clientKeys) {
        if (_linkedIdMatches(aid, k)) return true;
      }
      return false;
    }).toList();
  }

  List<Map<String, dynamic>> _concepteursForClientKeys(
    List<Map<String, dynamic>> concepteurs,
    Set<String> clientKeys,
  ) {
    return concepteurs.where((c) {
      final companyId =
          (c['companyId'] ?? c['clientId'] ?? '').toString().trim();
      if (companyId.isEmpty) return false;
      for (final k in clientKeys) {
        if (_linkedIdMatches(companyId, k)) return true;
      }
      return false;
    }).toList();
  }

  Widget _catalogEditDeleteRow({
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
      child: Material(
        color: Colors.transparent,
        child: Row(
          children: [
            OutlinedButton(
              onPressed: onDelete,
              style: OutlinedButton.styleFrom(
                foregroundColor: alertColor,
                side: BorderSide(color: alertColor.withOpacity(0.65)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                minimumSize: const Size(72, 36),
                tapTargetSize: MaterialTapTargetSize.padded,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(
                'Effacer',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmDeleteDialog(String title, String body) async {
    final r = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: sidebarColor,
            title: Text(
              title,
              style: GoogleFonts.inter(
                color: textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Text(
              body,
              style: GoogleFonts.inter(color: mutedTextColor, fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  'Annuler',
                  style: GoogleFonts.inter(color: mutedTextColor),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  'Effacer',
                  style: GoogleFonts.inter(
                    color: alertColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
    );
    return r == true;
  }

  Future<void> _reloadClientsTechniciansMaintenance() async {
    if (!mounted) return;
    setState(() {
      _clientsFuture = ApiService.getClients();
      _techniciansFuture = ApiService.getTechnicians();
      _maintenanceAgentsFuture = ApiService.getMaintenanceAgents();
    });
  }

  Future<void> _openEditClient(Map<String, dynamic> c) async {
    final r = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder:
            (ctx) => AddClientPage(
              initialData: Map<String, dynamic>.from(c),
              onBack: () => Navigator.of(ctx).pop(true),
            ),
      ),
    );
    if (r == true && mounted) await _reloadClientsTechniciansMaintenance();
  }

  Future<void> _deleteClientEntity(Map<String, dynamic> c) async {
    final id = _clientIdOf(c);
    if (id.isEmpty) return;
    final name = _clientNameOf(c);
    final ok = await _confirmDeleteDialog(
      'Supprimer le client ?',
      'Le client « $name » ($id) sera supprimé définitivement. Continuer ?',
    );
    if (!ok || !mounted) return;
    try {
      await ApiService.deleteClient(id);
      if (!mounted) return;
      if (_selectedCatalogClientId == id) {
        setState(() {
          _selectedCatalogClientId = null;
          _selectedClientMachinesFuture = null;
        });
      }
      await _reloadClientsTechniciansMaintenance();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Client supprimé : $name'),
          backgroundColor: successColor,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Suppression impossible: $e'),
          backgroundColor: alertColor,
        ),
      );
    }
  }

  Future<void> _openEditTechnician(Map<String, dynamic> t) async {
    final r = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder:
            (ctx) => AddTechnicianPage(
              initialData: Map<String, dynamic>.from(t),
              onBack: () => Navigator.of(ctx).pop(true),
            ),
      ),
    );
    if (r == true && mounted) await _reloadClientsTechniciansMaintenance();
  }

  Future<void> _openAddTechnician({String? clientId}) async {
    final cid = (clientId ?? '').trim();
    final Map<String, dynamic>? initialData =
        cid.isEmpty ? null : <String, dynamic>{'companyId': cid};
    final r = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        final dialogWidth =
            size.width * 0.94 > 1320 ? 1320.0 : size.width * 0.94;
        final dialogHeight =
            size.height * 0.94 > 920 ? 920.0 : size.height * 0.94;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: dialogWidth,
              height: dialogHeight,
              child: AddTechnicianPage(
                initialData: initialData,
                onBack: () => Navigator.of(ctx).pop(true),
              ),
            ),
          ),
        );
      },
    );
    if (r == true && mounted) {
      await _reloadClientsTechniciansMaintenance();
      final selectedCid = (_selectedCatalogClientId ?? '').trim();
      if (selectedCid.isNotEmpty) {
        setState(() {
          _selectedClientMachinesFuture = ApiService.getMachinesForClient(
            selectedCid,
          );
        });
      }
    }
  }

  Future<void> _deleteTechnicianEntity(Map<String, dynamic> t) async {
    final id = _technicianIdOf(t);
    if (id.isEmpty) return;
    final name = _technicianNameOf(t);
    final ok = await _confirmDeleteDialog(
      'Supprimer le technicien ?',
      '« $name » ($id) sera supprimé définitivement.',
    );
    if (!ok || !mounted) return;
    try {
      await ApiService.deleteTechnician(id);
      if (!mounted) return;
      if (_selectedTechnicianId == id) {
        setState(() => _selectedTechnicianId = null);
      }
      await _reloadClientsTechniciansMaintenance();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Technicien supprimé : $name'),
          backgroundColor: successColor,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Suppression impossible: $e'),
          backgroundColor: alertColor,
        ),
      );
    }
  }

  bool _isPendingTechnician(Map<String, dynamic> t) {
    final approval =
        (t['approvalStatus'] ?? '').toString().toUpperCase().trim();
    final status = (t['status'] ?? '').toString().toLowerCase().trim();
    return approval == 'PENDING' ||
        status == 'en attente' ||
        status == 'pending';
  }

  Future<void> _approvePendingTechnician(Map<String, dynamic> t) async {
    final id = _technicianIdOf(t);
    if (id.isEmpty) return;
    try {
      await ApiService.updateTechnician(id, {
        'status': 'Disponible',
        'approvalStatus': 'APPROVED',
      });
      if (!mounted) return;
      await _reloadClientsTechniciansMaintenance();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Demande technicien validée par le concepteur.'),
          backgroundColor: successColor,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Validation impossible: $e'),
          backgroundColor: alertColor,
        ),
      );
    }
  }

  Future<void> _rejectPendingTechnician(Map<String, dynamic> t) async {
    final id = _technicianIdOf(t);
    if (id.isEmpty) return;
    try {
      await ApiService.updateTechnician(id, {
        'status': 'Rejeté',
        'approvalStatus': 'REJECTED',
      });
      if (!mounted) return;
      await _reloadClientsTechniciansMaintenance();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Demande technicien refusée.'),
          backgroundColor: alertColor,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Refus impossible: $e'),
          backgroundColor: alertColor,
        ),
      );
    }
  }

  Future<void> _openEditMaintenanceAgent(Map<String, dynamic> a) async {
    final r = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder:
            (ctx) => AddMaintenanceAgentPage(
              initialData: Map<String, dynamic>.from(a),
              onEmbeddedBack: () => Navigator.of(ctx).pop(true),
            ),
      ),
    );
    if (r == true && mounted) await _reloadClientsTechniciansMaintenance();
  }

  Future<void> _openAddMaintenanceAgent({String? clientId}) async {
    final cid = (clientId ?? '').trim();
    final Map<String, dynamic>? initialData =
        cid.isEmpty ? null : <String, dynamic>{'clientId': cid};
    final r = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder:
            (ctx) => AddMaintenanceAgentPage(
              initialData: initialData,
              onEmbeddedBack: () => Navigator.of(ctx).pop(true),
            ),
      ),
    );
    if (r == true && mounted) {
      await _reloadClientsTechniciansMaintenance();
      final selectedCid = (_selectedCatalogClientId ?? '').trim();
      if (selectedCid.isNotEmpty) {
        setState(() {
          _selectedClientMachinesFuture = ApiService.getMachinesForClient(
            selectedCid,
          );
        });
      }
    }
  }

  Future<void> _deleteMaintenanceAgentEntity(Map<String, dynamic> a) async {
    final id = _maintenanceAgentIdOf(a);
    if (id.isEmpty) return;
    final name = _maintenanceAgentNameOf(a);
    final ok = await _confirmDeleteDialog(
      'Supprimer l\'agent maintenance ?',
      '« $name » ($id) sera supprimé définitivement.',
    );
    if (!ok || !mounted) return;
    try {
      await ApiService.deleteMaintenanceAgent(id);
      if (!mounted) return;
      if (_selectedMaintenanceAgentId == id) {
        setState(() => _selectedMaintenanceAgentId = null);
      }
      await _reloadClientsTechniciansMaintenance();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Agent supprimé : $name'),
          backgroundColor: successColor,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Suppression impossible: $e'),
          backgroundColor: alertColor,
        ),
      );
    }
  }

  String _machineIdOf(Map<String, dynamic> m) =>
      (m['machineId'] ?? m['id'] ?? m['_id'] ?? '').toString();

  String _machineNameOf(Map<String, dynamic> m) =>
      (m['name'] ?? 'Machine').toString();

  String _machineTokenOf(Map<String, dynamic> m) {
    final values = <String>[
      _machineIdOf(m),
      _machineNameOf(m),
      (m['status'] ?? '').toString(),
      (m['isPublic'] ?? '').toString(),
      (m['type'] ?? m['category'] ?? '').toString(),
      (m['location'] ?? m['googleMapsUrl'] ?? '').toString(),
      (m['updatedAt'] ?? '').toString(),
      (m['createdAt'] ?? m['dateAjout'] ?? '').toString(),
      (m['temperature'] ?? '').toString(),
      (m['vibration'] ?? '').toString(),
      (m['riskLevel'] ?? m['risk'] ?? '').toString(),
    ];
    return values.join('|');
  }

  void _appendMachineNotification({
    required String title,
    required String machineName,
  }) {
    final nowIso = DateTime.now().toIso8601String();
    _machineNotifications.insert(0, {
      'title': title,
      'machineName': machineName,
      'at': nowIso,
    });
    if (_machineNotifications.length > 80) {
      _machineNotifications.removeRange(80, _machineNotifications.length);
    }
  }

  void _showMachineNotificationsDialog() {
    setState(() => _unreadMachineNotifications = 0);
    showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: sidebarColor,
            title: Text(
              'Notifications machines',
              style: GoogleFonts.inter(color: textColor),
            ),
            content: SizedBox(
              width: 560,
              child:
                  _machineNotifications.isEmpty
                      ? Text(
                        'Aucun changement détecté pour le moment.',
                        style: GoogleFonts.inter(color: mutedTextColor),
                      )
                      : ListView.separated(
                        shrinkWrap: true,
                        itemCount: _machineNotifications.length,
                        separatorBuilder:
                            (_, __) => Divider(
                              color: Colors.white.withOpacity(0.08),
                              height: 12,
                            ),
                        itemBuilder: (_, i) {
                          final n = _machineNotifications[i];
                          final at = _formatDateTime(n['at']);
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              n['title'] ?? 'Changement machine',
                              style: GoogleFonts.inter(
                                color: textColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              '${n['machineName'] ?? 'Machine'}${at.isNotEmpty ? ' • $at' : ''}',
                              style: GoogleFonts.inter(
                                color: mutedTextColor,
                                fontSize: 12,
                              ),
                            ),
                          );
                        },
                      ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Fermer'),
              ),
            ],
          ),
    );
  }

  Widget _buildMachineImageWidget(
    String rawImageValue, {
    required double height,
    double width = double.infinity,
    BoxFit fit = BoxFit.cover,
    Widget? fallback,
  }) {
    final normalized = ApiService.fullUrl(rawImageValue);
    final fallbackWidget =
        fallback ??
        Container(
          height: height,
          width: width,
          color: cardColor,
          alignment: Alignment.center,
          child: const Icon(
            Icons.precision_manufacturing,
            color: mutedTextColor,
            size: 36,
          ),
        );

    if (normalized.isEmpty) return fallbackWidget;

    if (_looksLikeDataImage(normalized)) {
      try {
        final bytes = base64Decode(normalized.split(',').last);
        return Image.memory(
          bytes,
          height: height,
          width: width,
          fit: fit,
          errorBuilder: (_, __, ___) => fallbackWidget,
        );
      } catch (_) {
        return fallbackWidget;
      }
    }

    if (_looksLikeNetworkImage(normalized)) {
      return Image.network(
        normalized,
        height: height,
        width: width,
        fit: fit,
        errorBuilder: (_, __, ___) => fallbackWidget,
      );
    }

    return fallbackWidget;
  }

  Future<Uint8List> _optimizeImageForUpload(Uint8List bytes) async {
    if (bytes.length <= _targetUploadImageBytes) return bytes;

    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;

    img.Image working = decoded;
    if (working.width > _maxImageDimension ||
        working.height > _maxImageDimension) {
      working = img.copyResize(
        working,
        width: working.width >= working.height ? _maxImageDimension : null,
        height: working.height > working.width ? _maxImageDimension : null,
        interpolation: img.Interpolation.average,
      );
    }

    Uint8List best = Uint8List.fromList(img.encodeJpg(working, quality: 85));
    const qualities = <int>[72, 64, 56, 48, 40, 34, 28, 24];
    for (final q in qualities) {
      final candidate = Uint8List.fromList(img.encodeJpg(working, quality: q));
      if (candidate.length < best.length) best = candidate;
      if (candidate.length <= _targetUploadImageBytes) return candidate;
    }
    return best;
  }

  Future<String?> _pickImageAsDataUrl() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
      allowMultiple: false,
    );
    if (picked == null || picked.files.isEmpty) return null;
    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) return null;

    if (bytes.length > _maxPickedImageBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image source trop volumineuse (max 12 Mo).'),
            backgroundColor: alertColor,
          ),
        );
      }
      return null;
    }

    final optimizedBytes = await _optimizeImageForUpload(bytes);
    if (optimizedBytes.length > _hardUploadImageBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Image encore trop lourde apres compression (max 2 Mo).',
            ),
            backgroundColor: alertColor,
          ),
        );
      }
      return null;
    }

    final ext = (file.extension ?? '').toLowerCase();
    String mime = 'image/jpeg';
    final wasCompressed = optimizedBytes.length != bytes.length;
    if (!wasCompressed) {
      if (ext == 'png') mime = 'image/png';
      if (ext == 'gif') mime = 'image/gif';
      if (ext == 'webp') mime = 'image/webp';
    }
    final b64 = base64Encode(optimizedBytes);
    return 'data:$mime;base64,$b64';
  }

  @override
  void initState() {
    super.initState();
    _bootstrapDashboard();
  }

  @override
  void dispose() {
    _liveTelemetryTimer?.cancel();
    _telemetryTick.dispose();
    _missionAckSocket?.dispose();
    super.dispose();
  }

  void _initConcepteurMissionAckSocket() {
    try {
      _missionAckSocket?.dispose();
      _missionAckSocket = IO.io(ApiService.socketBaseUrl, <String, dynamic>{
        'transports': <String>['websocket'],
        'autoConnect': true,
      });

      void onConfirmed(Map<String, dynamic> data) {
        if (!mounted) return;
        final status = (data['status'] ?? '').toString().toUpperCase();
        if (status != 'CONFIRMED') return;
        final machineLabel =
            (data['machineName'] ?? '').toString().trim().isNotEmpty
                ? (data['machineName'] ?? '').toString().trim()
                : (data['machineId'] ?? data['interventionId'] ?? '')
                    .toString();
        final iv = (data['interventionId'] ?? '').toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              machineLabel.isNotEmpty
                  ? 'Le technicien a confirmé la mission · $machineLabel'
                  : 'Le technicien a confirmé la mission (intervention $iv).',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
            backgroundColor: successColor,
            duration: const Duration(seconds: 6),
          ),
        );
        setState(() {
          _appendMachineNotification(
            title: 'Technicien — mission confirmée',
            machineName:
                machineLabel.isNotEmpty ? machineLabel : 'Intervention $iv',
          );
          _unreadMachineNotifications++;
        });
      }

      _missionAckSocket!.on('diagnostic_coordination_update', (data) {
        if (data is Map) onConfirmed(Map<String, dynamic>.from(data));
      });
      _missionAckSocket!.on('diagnostic_message_update', (data) {
        if (data is Map) onConfirmed(Map<String, dynamic>.from(data));
      });
    } catch (e) {
      debugPrint('[ConcepteurDashboard] mission ack socket: $e');
    }
  }

  Future<void> _bootstrapDashboard() async {
    try {
      await ApiService.ensureAuthTokenLoaded();
    } catch (_) {}
    var token = (ApiService.authToken ?? '').trim();
    if (token.isEmpty && !_silentRecoveryTried) {
      _silentRecoveryTried = true;
      token = await _trySilentSessionRecovery();
    }
    if (token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _hasFleetSession = false;
        _loading = false;
        _error =
            'Session concepteur expirée. Reconnectez-vous pour afficher le catalogue et les machines.';
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _hasFleetSession = true;
      _clientsFuture = ApiService.getClients();
      _techniciansFuture = ApiService.getTechnicians();
      _maintenanceAgentsFuture = ApiService.getMaintenanceAgents();
    });
    await _loadConcepteurProfileFromBackend();
    _fetchMachines();
    _fetchPurchaseRequests();
    _initConcepteurMissionAckSocket();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  LIVE TELEMETRY POLLING + RISK TOAST NOTIFICATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Starts 1-second polling for all machines currently in [_polledMachineIds].
  void _startLiveTelemetryPolling() {
    if (_liveTelemetryTimer != null) return; // already running
    _liveTelemetryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _refreshAllLiveTelemetry();
    });
  }

  /// Registers all current machines for telemetry polling.
  void _registerMachinesForTelemetryPolling() {
    for (final m in _allMachines) {
      final id = _machineIdOf(m).trim();
      if (id.isNotEmpty) _polledMachineIds.add(id);
    }
    _startLiveTelemetryPolling();
  }

  /// Fetches latest telemetry for every polled machine, stores it, and
  /// evaluates risk for toast notifications.
  Future<void> _refreshAllLiveTelemetry() async {
    if (!mounted || _polledMachineIds.isEmpty) return;
    for (final machineId in _polledMachineIds) {
      try {
        final tel = await ApiService.getLatestTelemetry(machineId);
        if (tel != null && mounted) {
          _liveTelemetryByMachineId[machineId] = tel;
          // Evaluate risk
          final risk = _computeRiskFromTelemetry(tel);
          final prev = _lastNotifiedRiskById[machineId] ?? 'NORMAL';
          if (risk != 'NORMAL' && risk != prev) {
            _lastNotifiedRiskById[machineId] = risk;
            final name = _allMachines.firstWhere(
              (m) => _machineIdOf(m) == machineId,
              orElse: () => <String, dynamic>{},
            );
            final mName = _machineNameOf(name.isEmpty ? {'name': machineId} : name);
            _showRiskToast(
              machineId: machineId,
              machineName: mName,
              riskLevel: risk,
              telemetry: tel,
            );
          } else if (risk == 'NORMAL') {
            _lastNotifiedRiskById[machineId] = 'NORMAL';
          }
        }
      } catch (_) {
        // Silently skip failed fetches
      }
    }
    if (mounted) _telemetryTick.value++;
  }

  /// Computes overall risk label from raw telemetry map.
  String _computeRiskFromTelemetry(Map<String, dynamic> tel) {
    double? parseVal(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }
    final temp = parseVal(tel['temperature'] ?? tel['temp']);
    final vib = parseVal(tel['vibration']);

    bool isDanger = false;
    bool isRisk = false;

    if (temp != null) {
      if (temp > 75) isDanger = true;
      else if (temp >= 55) isRisk = true;
    }
    if (vib != null) {
      if (vib > 12) isDanger = true;
      else if (vib >= 7) isRisk = true;
    }

    if (isDanger) return 'DANGER';
    if (isRisk) return 'RISQUE';
    return 'NORMAL';
  }

  /// Returns a human-readable description of the risk factors.
  String _riskTypeDescription(Map<String, dynamic> tel) {
    double? parseVal(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }
    final parts = <String>[];
    final temp = parseVal(tel['temperature'] ?? tel['temp']);
    final vib = parseVal(tel['vibration']);
    if (temp != null && temp > 75) parts.add('Température critique ${temp.toStringAsFixed(1)}°C');
    else if (temp != null && temp >= 55) parts.add('Température élevée ${temp.toStringAsFixed(1)}°C');
    if (vib != null && vib > 12) parts.add('Vibration critique ${vib.toStringAsFixed(1)} mm/s');
    else if (vib != null && vib >= 7) parts.add('Vibration élevée ${vib.toStringAsFixed(1)} mm/s');
    return parts.isNotEmpty ? parts.join(' · ') : 'Paramètres hors seuils';
  }

  /// Shows a styled risk toast (SnackBar) with an AFFICHER action.
  void _showRiskToast({
    required String machineId,
    required String machineName,
    required String riskLevel,
    required Map<String, dynamic> telemetry,
  }) {
    if (!mounted) return;
    final isDanger = riskLevel == 'DANGER';
    final color = isDanger ? const Color(0xFFF44336) : const Color(0xFFFF9800);
    final icon = isDanger ? Icons.error_outline : Icons.warning_amber_rounded;
    final desc = _riskTypeDescription(telemetry);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color,
        duration: const Duration(seconds: 8),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 24, left: 24, right: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$riskLevel — $machineName',
                    style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: GoogleFonts.inter(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'AFFICHER',
          textColor: Colors.white,
          onPressed: () {
            _openDetails(machineId);
          },
        ),
      ),
    );
  }

  Future<String> _trySilentSessionRecovery() async {
    try {
      await ApiService.loadSavedAuth();
    } catch (_) {}
    return (ApiService.authToken ?? '').trim();
  }

  void _showMachineMiniDetails(BuildContext context, Map<String, dynamic> m) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E2030),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(Icons.precision_manufacturing, color: primaryColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _machineNameOf(m),
                  style: GoogleFonts.spaceGrotesk(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: FutureBuilder<Map<String, dynamic>?>(
            future: ApiService.getLatestTelemetry(
              _machineIdOf(m),
            ).catchError((_) => null),
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 100,
                  child: Center(
                    child: CircularProgressIndicator(color: primaryColor),
                  ),
                );
              }
              final data = snap.data;
              final status =
                  (m['status'] ?? 'Inconnu').toString().toUpperCase();
              final isRunning = status == 'RUNNING';

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isRunning ? Icons.play_circle_fill : Icons.stop_circle,
                        color:
                            isRunning
                                ? const Color(0xFF66BB6A)
                                : const Color(0xFFFFB4AB),
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'État : $status',
                        style: GoogleFonts.inter(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (data != null) ...[
                    _miniStatRow(
                      'Température',
                      '${data['temperature'] ?? '--'} °C',
                      Icons.thermostat,
                    ),
                    const SizedBox(height: 8),
                    _miniStatRow(
                      'Pression',
                      '${data['pressure'] ?? '--'} bar',
                      Icons.speed,
                    ),
                    const SizedBox(height: 8),
                    _miniStatRow(
                      'Vibration',
                      '${data['vibration'] ?? '--'} mm/s',
                      Icons.waves,
                    ),
                    const SizedBox(height: 8),
                    _miniStatRow(
                      'RPM',
                      '${data['rpm'] ?? '--'} tr/min',
                      Icons.rotate_right,
                    ),
                    const SizedBox(height: 8),
                    _miniStatRow(
                      'Risque panne',
                      '${data['prob_panne'] ?? data['panne_probability'] ?? '--'} %',
                      Icons.warning_amber,
                    ),
                  ] else
                    Text(
                      'Aucune donnée de télémétrie récente.',
                      style: GoogleFonts.inter(
                        color: Colors.white30,
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Fermer',
                style: GoogleFonts.inter(color: mutedTextColor),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _openMachineDetail(m);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.black,
              ),
              child: Text(
                'Ouvrir détails',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _miniStatRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: primaryColor.withOpacity(0.8), size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.inter(color: mutedTextColor, fontSize: 12),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  void _openMachineDetail(Map<String, dynamic> m) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => MachineDetailAiPage(
              machineId: _machineIdOf(m),
              machineName: _machineNameOf(m),
              clientId: (m['clientId'] ?? m['companyId'] ?? '').toString(),
              location: (m['location'] ?? '').toString(),
              viewerRole: ApiService.savedUserRole,
              viewerName: _profileDisplayName,
            ),
      ),
    );
  }

  String _pickFirstString(Map<String, dynamic> src, List<String> keys) {
    for (final k in keys) {
      final v = (src[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  String _pickProfilePhotoFromWorkspace(
    Map<String, dynamic> workspace,
    Map<String, dynamic> profile,
  ) {
    const photoKeys = [
      'photoUrl',
      'avatarUrl',
      'profilePhotoUrl',
      'image',
      'photo',
      'avatar',
      'profileImage',
      'picture',
      'imageUrl',
    ];

    final fromProfile = _pickFirstString(profile, photoKeys);
    if (fromProfile.isNotEmpty) return fromProfile;

    final fromWorkspace = _pickFirstString(workspace, photoKeys);
    if (fromWorkspace.isNotEmpty) return fromWorkspace;

    final nestedCandidates = <dynamic>[
      workspace['concepteur'],
      workspace['designer'],
      workspace['profile'],
      workspace['user'],
      workspace['account'],
      workspace['currentUser'],
      workspace['me'],
      workspace['data'],
      profile['user'],
      profile['account'],
      profile['profile'],
    ];
    for (final candidate in nestedCandidates) {
      if (candidate is Map) {
        final found = _pickFirstString(
          Map<String, dynamic>.from(candidate),
          photoKeys,
        );
        if (found.isNotEmpty) return found;
      }
    }
    return '';
  }

  String _normalizeProfilePhotoUrl(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return '';
    final lower = v.toLowerCase();
    if (lower.startsWith('data:image/')) return v;
    if (lower.startsWith('http://') || lower.startsWith('https://')) return v;
    if (v.startsWith('//')) return 'https:$v';
    if (v.startsWith('/')) {
      final socketBase = ApiService.socketBaseUrl;
      return '$socketBase$v';
    }
    if (v.startsWith('./')) {
      final socketBase = ApiService.socketBaseUrl;
      return '$socketBase/${v.substring(2)}';
    }
    if (v.startsWith('../')) {
      final socketBase = ApiService.socketBaseUrl;
      return '$socketBase/${v.replaceFirst(RegExp(r'^\.\./+'), '')}';
    }
    if (v.contains('/')) {
      // Chemin relatif API fréquent: "uploads/xxx.jpg".
      final socketBase = ApiService.socketBaseUrl;
      return '$socketBase/$v';
    }
    // Cas fréquent: "cdn.site.com/image.jpg" sans schéma.
    return 'https://$v';
  }

  Map<String, dynamic> _extractConcepteurProfileMap(
    Map<String, dynamic> workspace,
  ) {
    final candidates = <dynamic>[
      workspace['concepteur'],
      workspace['designer'],
      workspace['profile'],
      workspace['user'],
      workspace['account'],
      workspace['currentUser'],
      workspace['me'],
      workspace['data'],
    ];
    for (final c in candidates) {
      if (c is Map) return Map<String, dynamic>.from(c);
    }
    final rootId = _pickFirstString(workspace, const [
      'concepteurId',
      'id',
      '_id',
    ]);
    if (rootId.isNotEmpty) return Map<String, dynamic>.from(workspace);
    return <String, dynamic>{};
  }

  void _applyConcepteurProfileData(Map<String, dynamic> data) {
    final nextId = _pickFirstString(data, const [
      'concepteurId',
      'id',
      '_id',
      'userId',
    ]);
    final nextName = _pickFirstString(data, const [
      'name',
      'nom',
      'fullName',
      'displayName',
      'username',
    ]);
    final nextPhoto = _pickFirstString(data, const [
      'imageUrl',
      'photoUrl',
      'avatarUrl',
      'photo',
    ]);
    final nextEmail = _pickFirstString(data, const ['email', 'mail']);
    final nextAddress = _pickFirstString(data, const [
      'adresse',
      'address',
      'location',
      'street',
    ]);

    final normalized = <String, dynamic>{
      ...data,
      'name': nextName,
      'nom': nextName,
      'displayName': nextName,
      'email': nextEmail,
      'mail': nextEmail,
      'address': nextAddress,
      'adresse': nextAddress,
      'location': nextAddress,
      'street': nextAddress,
      if (nextPhoto.isNotEmpty) 'imageUrl': nextPhoto,
      if (nextPhoto.isNotEmpty) 'photoUrl': nextPhoto,
    };

    final projectTeam = data['projectTeam'];
    if (!mounted) return;
    setState(() {
      _concepteurProfileData = normalized;
      if (nextId.isNotEmpty) _concepteurProfileId = nextId;
      if (nextName.isNotEmpty) _profileDisplayName = nextName;
      if (nextEmail.isNotEmpty) _profileEmail = nextEmail;
      if (nextPhoto.isNotEmpty) {
        _profilePhotoUrl = _normalizeProfilePhotoUrl(nextPhoto);
      }
      if (projectTeam is Map) {
        _concepteurProjectTeam = Map<String, dynamic>.from(projectTeam);
      }
    });
  }

  Future<void> _loadConcepteurProfileFromBackend() async {
    if (!mounted) return;
    setState(() {
      _profileLoading = true;
      _profileLoadError = null;
    });

    final saved = ApiService.savedConcepteurProfile;
    if (saved != null && saved.isNotEmpty) {
      _applyConcepteurProfileData(saved);
    }

    try {
      final profileData = await ApiService.getMyConcepteurProfile();
      final Map<String, dynamic> data = profileData;
      if (!mounted) return;
      _applyConcepteurProfileData(data);
      await ApiService.saveConcepteurSession(data);
      if (!mounted) return;
      setState(() {
        _profileLoading = false;
        _profileLoadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _profileLoading = false;
        if (_concepteurProfileData.isEmpty) {
          _profileLoadError = 'Impossible de charger le profil: $e';
        }
      });
    }
  }

  void _onSidebarSelect(String title) {
    if (!_hasFleetSession &&
        (title == 'PROJET' ||
            title == 'CLIENT CATALOG' ||
            title == 'TECHNICIANS' ||
            title == 'MAINTENANCE' ||
            title == 'MESSAGERIE')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Session expirée. Reconnectez-vous pour afficher ces données.',
          ),
          backgroundColor: alertColor,
        ),
      );
      return;
    }
    setState(() {
      selectedMenu = title;
      if (title == 'TECHNICIANS') {
        _techniciansFuture = ApiService.getTechnicians();
      } else if (title == 'MAINTENANCE') {
        _maintenanceAgentsFuture = ApiService.getMaintenanceAgents();
      } else if (title == 'PROJET') {
        _clientsFuture = ApiService.getClients();
        _techniciansFuture = ApiService.getTechnicians();
        _maintenanceAgentsFuture = ApiService.getMaintenanceAgents();
      } else if (title == 'CLIENT CATALOG') {
        _clientsFuture = ApiService.getClients();
        _techniciansFuture = ApiService.getTechnicians();
        _maintenanceAgentsFuture = ApiService.getMaintenanceAgents();
      } else if (title == 'MESSAGERIE') {
        // Chat ne nécessite pas de chargement futur spécifique ici
      } else if (title == 'PROFILE') {
        _loadConcepteurProfileFromBackend();
      }
    });
  }

  String _technicianIdOf(Map<String, dynamic> t) =>
      (t['technicianId'] ?? t['id'] ?? t['_id'] ?? '').toString();

  String _technicianNameOf(Map<String, dynamic> t) =>
      (t['name'] ?? 'Technicien').toString();

  bool _machineMatchesAssignedId(Map<String, dynamic> m, String assignedId) {
    final n = assignedId.trim();
    if (n.isEmpty) return false;
    for (final key in ['machineId', 'id', '_id']) {
      final v = (m[key] ?? '').toString().trim();
      if (v.isNotEmpty && v == n) return true;
    }
    return false;
  }

  List<Map<String, dynamic>> _machinesForAssignedMachineIds(
    Map<String, dynamic> doc,
  ) {
    final raw = doc['machineIds'];
    final ids = <String>[];
    if (raw is List) {
      for (final e in raw) {
        final s = e.toString().trim();
        if (s.isNotEmpty) ids.add(s);
      }
    } else if (raw is String) {
      try {
        final l = jsonDecode(raw);
        if (l is List) {
          for (final e in l) {
            final s = e.toString().trim();
            if (s.isNotEmpty) ids.add(s);
          }
        }
      } catch (_) {}
    }
    if (ids.isEmpty) return [];
    final matchedAssignedIds = <String>{};
    final resolved = <Map<String, dynamic>>[];
    final seenMachineKeys = <String>{};
    for (final m in _allMachines) {
      for (final id in ids) {
        if (_machineMatchesAssignedId(m, id)) {
          matchedAssignedIds.add(id);
          final key = _machineIdOf(m);
          final dedupe = key.isNotEmpty ? key : id;
          if (!seenMachineKeys.contains(dedupe)) {
            seenMachineKeys.add(dedupe);
            resolved.add(m);
          }
          break;
        }
      }
    }
    for (final id in ids) {
      if (!matchedAssignedIds.contains(id)) {
        resolved.add({
          '_unresolvedMachineId': id,
          'name': 'Machine (réf.)',
          'machineId': id,
        });
      }
    }
    return resolved;
  }

  String _maintenanceAgentIdOf(Map<String, dynamic> a) =>
      (a['maintenanceAgentId'] ?? a['id'] ?? a['_id'] ?? '').toString();

  String _maintenanceAgentNameOf(Map<String, dynamic> a) {
    final explicit = (a['name'] ?? '').toString().trim();
    if (explicit.isNotEmpty) return explicit;
    final full = (a['fullName'] ?? '').toString().trim();
    if (full.isNotEmpty) return full;
    final fn = (a['firstName'] ?? '').toString().trim();
    final ln = (a['lastName'] ?? '').toString().trim();
    final joined = '$fn $ln'.trim();
    return joined.isNotEmpty ? joined : 'Agent maintenance';
  }

  Map<String, dynamic>? _findClientForTechnician(
    List<Map<String, dynamic>> clients,
    Map<String, dynamic> tech,
  ) {
    final companyId = (tech['companyId'] ?? '').toString().trim();
    if (companyId.isEmpty) return null;
    return _findClientForMaintenanceAgent(clients, companyId, '');
  }

  Map<String, dynamic>? _findClientForMaintenanceAgent(
    List<Map<String, dynamic>> clients,
    String clientIdRaw,
    String clientNameHint,
  ) {
    final idRaw = clientIdRaw.trim();
    final nameNorm = clientNameHint.trim().toLowerCase();
    Map<String, dynamic>? nameMatch;
    for (final c in clients) {
      final bid = _clientIdOf(c);
      if (idRaw.isNotEmpty && bid.isNotEmpty && bid == idRaw) return c;
      final oid = (c['_id'] ?? '').toString();
      if (idRaw.isNotEmpty &&
          oid.isNotEmpty &&
          (oid == idRaw || oid.endsWith(idRaw) || idRaw.endsWith(oid))) {
        return c;
      }
      if (idRaw.isNotEmpty &&
          bid.isNotEmpty &&
          (bid.contains(idRaw) || idRaw.contains(bid))) {
        return c;
      }
      if (nameNorm.isNotEmpty) {
        final n = _clientNameOf(c).toLowerCase().trim();
        if (n == nameNorm) nameMatch = c;
      }
    }
    return nameMatch;
  }

  Widget _maintenanceSectionTitle(String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: primaryColor, size: 20),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            color: textColor,
            fontWeight: FontWeight.w800,
            fontSize: 14,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  Widget _maintenanceEmptyPane({
    required IconData icon,
    required String message,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor.withOpacity(0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Icon(icon, color: mutedTextColor.withOpacity(0.5), size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(
                color: mutedTextColor,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _maintenanceClientDetailCard(Map<String, dynamic> client) {
    final cid = _clientIdOf(client);
    final email = (client['email'] ?? '').toString().trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primaryColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _clientNameOf(client),
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'ID: $cid',
            style: GoogleFonts.inter(fontSize: 12, color: mutedTextColor),
          ),
          if (email.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              email,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 12, color: mutedTextColor),
            ),
          ],
        ],
      ),
    );
  }

  Widget _maintenanceClientFallbackCard(String clientId, String clientName) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Référence client',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: mutedTextColor,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          if (clientName.isNotEmpty)
            Text(
              clientName,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          if (clientId.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'ID: $clientId',
              style: GoogleFonts.inter(fontSize: 12, color: mutedTextColor),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Fiche catalogue non résolue (client absent de la liste chargée).',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: mutedTextColor.withOpacity(0.85),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchPurchaseRequests() async {
    setState(() => _loadingRequests = true);
    try {
      final rows = await ApiService.getPurchaseRequests();
      final sortedRows = List<Map<String, dynamic>>.from(rows)..sort((a, b) {
        final aRaw = (a['createdAt'] ?? a['purchaseAt'] ?? '').toString();
        final bRaw = (b['createdAt'] ?? b['purchaseAt'] ?? '').toString();
        final aDate = DateTime.tryParse(aRaw);
        final bDate = DateTime.tryParse(bRaw);

        if (aDate != null && bDate != null) return bDate.compareTo(aDate);
        if (aDate != null) return -1;
        if (bDate != null) return 1;
        return 0;
      });
      if (!mounted) return;
      setState(() {
        _purchaseRequests = sortedRows;
        _showAllPurchaseRequests = false;
        _showAllTechnicianRequests = false;
        final currentIds =
            sortedRows
                .map((r) => (r['id'] ?? r['_id'] ?? '').toString())
                .where((id) => id.isNotEmpty)
                .toSet();
        _reviewedRequestIds.removeWhere((id) => !currentIds.contains(id));
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _purchaseRequests = [];
        _showAllPurchaseRequests = false;
        _showAllTechnicianRequests = false;
        _reviewedRequestIds.clear();
      });
    } finally {
      if (mounted) setState(() => _loadingRequests = false);
    }
  }

  Future<void> _showPurchaseRequestMachinePreview(
    Map<String, dynamic> req,
  ) async {
    final reqId = (req['id'] ?? req['_id'] ?? '').toString();
    if (reqId.isEmpty) return;
    final machineId = (req['machineId'] ?? '').toString();
    final machineName = (req['machineName'] ?? machineId).toString();
    final requester = (req['requesterName'] ?? 'Client').toString();
    final purchaseAtLabel = _formatDateTime(
      req['createdAt'] ?? req['purchaseAt'],
    );

    Map<String, dynamic>? machineInfo;
    if (machineId.isNotEmpty) {
      try {
        machineInfo = await ApiService.getMachineInfo(machineId);
      } catch (_) {
        machineInfo = null;
      }
    }
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: sidebarColor,
            title: Text(
              'Détails de la machine',
              style: GoogleFonts.inter(color: textColor),
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      machineName.isNotEmpty ? machineName : 'Machine',
                      style: GoogleFonts.spaceGrotesk(
                        color: textColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'ID machine: ${machineId.isNotEmpty ? machineId : '—'}',
                      style: GoogleFonts.inter(
                        color: mutedTextColor,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Client: $requester',
                      style: GoogleFonts.inter(
                        color: mutedTextColor,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Date achat: ${purchaseAtLabel.isNotEmpty ? purchaseAtLabel : '—'}',
                      style: GoogleFonts.inter(
                        color: mutedTextColor,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Localisation: ${(req['googleMapsUrl'] ?? req['location'] ?? '—').toString()}',
                      style: GoogleFonts.inter(
                        color: mutedTextColor,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (machineInfo != null) ...[
                      Text(
                        'Type: ${(machineInfo['type'] ?? machineInfo['category'] ?? '—').toString()}',
                        style: GoogleFonts.inter(
                          color: textColor,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Statut: ${(machineInfo['status'] ?? machineInfo['state'] ?? '—').toString()}',
                        style: GoogleFonts.inter(
                          color: textColor,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Description: ${(machineInfo['description'] ?? machineInfo['note'] ?? '—').toString()}',
                        style: GoogleFonts.inter(
                          color: textColor,
                          fontSize: 13,
                        ),
                      ),
                    ] else
                      Text(
                        'Infos complètes non disponibles depuis l\'API. Les données de la commande sont affichées.',
                        style: GoogleFonts.inter(
                          color: mutedTextColor,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _rejectRequest(req);
                },
                style: TextButton.styleFrom(foregroundColor: alertColor),
                child: const Text('Rejeter'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _validateAndProvisionTeam(req, requireManualInputs: false);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.black,
                ),
                child: const Text('Valider'),
              ),
            ],
          ),
    );

    if (!mounted) return;
    setState(() {
      _reviewedRequestIds.add(reqId);
    });
  }

  Future<void> _validateAndProvisionTeam(
    Map<String, dynamic> req, {
    bool requireManualInputs = true,
  }) async {
    final reqId = (req['id'] ?? req['_id'] ?? '').toString();
    if (reqId.isEmpty) return;

    final machineName =
        (req['machineName'] ?? req['machineId'] ?? '').toString();
    final machineId = (req['machineId'] ?? '').toString();
    final purchaseAtLabel = _formatDateTime(
      req['createdAt'] ?? req['purchaseAt'],
    );

    final clientNameCtrl = TextEditingController(
      text: (req['requesterName'] ?? '').toString(),
    );
    final clientEmailCtrl = TextEditingController(
      text: (req['requesterEmail'] ?? '').toString(),
    );
    final clientPwdCtrl = TextEditingController();
    final clientLocCtrl = TextEditingController(
      text: (req['googleMapsUrl'] ?? req['location'] ?? '').toString(),
    );

    final techNameCtrl = TextEditingController(text: 'Technicien Terrain');
    final techPwdCtrl = TextEditingController(text: 'tech123');
    final techLocCtrl = TextEditingController(
      text: (req['googleMapsUrl'] ?? req['location'] ?? '').toString(),
    );

    final maintNameCtrl = TextEditingController(text: 'Maintenance Agent');
    final maintPwdCtrl = TextEditingController(text: 'maint123');
    final maintLocCtrl = TextEditingController(
      text: (req['googleMapsUrl'] ?? req['location'] ?? '').toString(),
    );

    final submit =
        requireManualInputs
            ? await showDialog<bool>(
              context: context,
              builder:
                  (ctx) => AlertDialog(
                    backgroundColor: sidebarColor,
                    title: Text(
                      'Valider la demande',
                      style: GoogleFonts.inter(color: textColor),
                    ),
                    content: SizedBox(
                      width: 520,
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.08),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Machine',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: mutedTextColor,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    machineName.isNotEmpty ? machineName : '—',
                                    style: GoogleFonts.spaceGrotesk(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: textColor,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Date achat: ${purchaseAtLabel.isNotEmpty ? purchaseAtLabel : '—'}',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: textColor.withOpacity(0.9),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'ID machine: ${machineId.isNotEmpty ? machineId : '—'}',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: textColor.withOpacity(0.9),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextField(
                              controller: clientNameCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Client - Nom',
                              ),
                            ),
                            TextField(
                              controller: clientEmailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: 'Client - Email (connexion)',
                                hintText: 'ex: client@domaine.com',
                              ),
                            ),
                            TextField(
                              controller: clientPwdCtrl,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'Client - Mot de passe',
                                hintText:
                                    'Optionnel : vide = mot de passe généré et envoyé par email',
                              ),
                            ),
                            TextField(
                              controller: clientLocCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Client - Localisation / Maps',
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: techNameCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Technicien - Nom complet',
                              ),
                            ),
                            TextField(
                              controller: techPwdCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Technicien - Mot de passe',
                              ),
                            ),
                            TextField(
                              controller: techLocCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Technicien - Localisation',
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: maintNameCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Maintenance - Nom complet',
                              ),
                            ),
                            TextField(
                              controller: maintPwdCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Maintenance - Mot de passe',
                              ),
                            ),
                            TextField(
                              controller: maintLocCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Maintenance - Localisation',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Annuler'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Valider'),
                      ),
                    ],
                  ),
            )
            : true;
    if (submit != true) return;

    final fullMaint = maintNameCtrl.text.trim();
    final parts =
        fullMaint.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    final first = parts.isNotEmpty ? parts.first : '';
    final last = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    if (first.isEmpty || last.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nom maintenance complet requis.')),
      );
      return;
    }

    try {
      final result = await ApiService.provisionPurchaseRequestTeam(reqId, {
        'reviewedByName': 'Concepteur',
        'clientName': clientNameCtrl.text.trim(),
        'clientEmail': clientEmailCtrl.text.trim(),
        'clientPassword': clientPwdCtrl.text.trim(),
        'clientLocation': clientLocCtrl.text.trim(),
        'technicianName': techNameCtrl.text.trim(),
        'technicianPassword': techPwdCtrl.text.trim(),
        'technicianLocation': techLocCtrl.text.trim(),
        'maintenanceFirstName': first,
        'maintenanceLastName': last,
        'maintenancePassword': maintPwdCtrl.text.trim(),
        'maintenanceLocation': maintLocCtrl.text.trim(),
      });
      if (!mounted) return;
      await _fetchPurchaseRequests();
      await _fetchMachines();

      // Après validation, on prépare immédiatement l'écran Client Catalog.
      final clientKey =
          (result['client'] is Map<String, dynamic>
                  ? (result['client']['clientId'] ?? '').toString()
                  : '')
              as String;
      final createdMachineId =
          (result['machine'] is Map<String, dynamic>
                  ? (result['machine']['id'] ??
                          result['machine']['machineId'] ??
                          '')
                      .toString()
                  : '')
              as String;
      if (clientKey.trim().isNotEmpty) {
        setState(() {
          selectedMenu = 'PROJET';
          _clientsFuture = ApiService.getClients();
          _techniciansFuture = ApiService.getTechnicians();
          _maintenanceAgentsFuture = ApiService.getMaintenanceAgents();
          _selectedCatalogClientId = clientKey.trim();
          _selectedClientMachinesFuture = ApiService.getMachinesForClient(
            clientKey.trim(),
          );
        });
      }

      final mail = result['credentialsEmail'];
      final autoPwd = result['clientPasswordAutoGenerated'] == true;
      var mailHint = '';
      if (mail is Map<String, dynamic>) {
        if (mail['sent'] == true) {
          mailHint = ' Identifiants envoyes par email au client.';
        } else if (mail['reason'] == 'smtp_not_configured') {
          mailHint =
              ' SMTP non configure : ajoutez SMTP_* dans .env pour envoyer le mot de passe par email.';
        } else if (mail['reason'] == 'synthetic_email_skip') {
          mailHint =
              ' Email technique (@dali-pfe.local) : renseignez un email reel pour l envoi.';
        } else if (mail['reason'] == 'smtp_credentials_missing') {
          mailHint = ' SMTP incomplet (SMTP_USER / SMTP_PASS).';
        }
      }
      if (autoPwd && mailHint.isEmpty) {
        mailHint =
            ' Mot de passe client genere automatiquement (voir email ou logs serveur si SMTP absent).';
      } else if (autoPwd) {
        mailHint = '$mailHint Mot de passe client genere automatiquement.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Provision terminee: client, technicien et maintenance crees.$mailHint',
          ),
          backgroundColor: Colors.green,
        ),
      );

      // Résumé (pour que le concepteur voie les informations créées)
      final client = result['client'];
      final technician = result['technician'];
      final maintenance = result['maintenance'];
      final clientEmail =
          (client is Map<String, dynamic> ? client['email'] : null)
              ?.toString() ??
          '';
      final techEmail =
          (technician is Map<String, dynamic> ? technician['email'] : null)
              ?.toString() ??
          '';
      final maintEmail =
          (maintenance is Map<String, dynamic> ? maintenance['email'] : null)
              ?.toString() ??
          '';
      final clientNameRes =
          (client is Map<String, dynamic> ? client['name'] : null)
              ?.toString() ??
          '';
      final machineNameRes =
          (result['machine'] is Map<String, dynamic>
                  ? result['machine']['name']
                  : null)
              ?.toString() ??
          '';

      if (clientKey.trim().isNotEmpty &&
          (clientNameRes.isNotEmpty || createdMachineId.isNotEmpty)) {
        await showDialog<void>(
          context: context,
          builder:
              (ctx) => AlertDialog(
                backgroundColor: sidebarColor,
                title: Text(
                  'Provision terminée',
                  style: GoogleFonts.inter(color: textColor),
                ),
                content: SizedBox(
                  width: 520,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Client: $clientNameRes',
                          style: GoogleFonts.inter(
                            color: textColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Email client: ${clientEmail.isNotEmpty ? clientEmail : '—'}',
                          style: GoogleFonts.inter(
                            color: mutedTextColor,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Machine: $machineNameRes',
                          style: GoogleFonts.inter(
                            color: textColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'ID machine: ${createdMachineId.isNotEmpty ? createdMachineId : '—'}',
                          style: GoogleFonts.inter(
                            color: mutedTextColor,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Technicien: ${(technician is Map<String, dynamic> ? technician['name'] : null)?.toString() ?? ''}',
                          style: GoogleFonts.inter(
                            color: textColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Email technicien: ${techEmail.isNotEmpty ? techEmail : '—'}',
                          style: GoogleFonts.inter(
                            color: mutedTextColor,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Maintenance: ${(maintenance is Map<String, dynamic> ? maintenance['firstName'] : null)?.toString() ?? ''} ${(maintenance is Map<String, dynamic> ? maintenance['lastName'] : null)?.toString() ?? ''}',
                          style: GoogleFonts.inter(
                            color: textColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Email maintenance: ${maintEmail.isNotEmpty ? maintEmail : '—'}',
                          style: GoogleFonts.inter(
                            color: mutedTextColor,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('OK'),
                  ),
                ],
              ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Provision impossible: $e')));
    }
  }

  Future<String?> _showEmailCorrectionDialog(String initialEmail, String roleLabel) async {
    final controller = TextEditingController(text: initialEmail);
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: sidebarColor,
        title: Text(
          'Email requis pour le $roleLabel',
          style: GoogleFonts.inter(color: textColor),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Veuillez corriger ou saisir un email valide pour envoyer le mot de passe :',
              style: GoogleFonts.inter(color: mutedTextColor, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: TextStyle(color: textColor),
              decoration: InputDecoration(
                hintText: 'exemple@gmail.com',
                hintStyle: TextStyle(color: mutedTextColor.withOpacity(0.5)),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: primaryColor.withOpacity(0.4)),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: primaryColor),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text('Annuler', style: TextStyle(color: mutedTextColor)),
          ),
          ElevatedButton(
            onPressed: () {
              final val = controller.text.trim();
              if (val.isNotEmpty && val.contains('@')) {
                Navigator.pop(ctx, val);
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Veuillez saisir un email contenant @')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.black,
            ),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }

  Future<void> _validateTechnicianAddRequest(Map<String, dynamic> req) async {
    final reqId = (req['id'] ?? req['_id'] ?? '').toString().trim();
    if (reqId.isEmpty) return;

    final metadataRaw = req['metadata'];
    final metadata =
        metadataRaw is Map
            ? Map<String, dynamic>.from(metadataRaw)
            : <String, dynamic>{};
    final idsFromMeta =
        (metadata['machineIds'] is List)
            ? (metadata['machineIds'] as List)
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
            : <String>[];
    final idsFromRoot =
        (req['requestedMachineIds'] is List)
            ? (req['requestedMachineIds'] as List)
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
            : <String>[];
    final mergedMachineIds = <String>{...idsFromMeta, ...idsFromRoot};
    final machineIdSingle = (req['machineId'] ?? '').toString().trim();
    if (machineIdSingle.isNotEmpty) mergedMachineIds.add(machineIdSingle);
    final machineIds = mergedMachineIds.toList();

    final requestedName = (req['requesterName'] ?? '').toString().trim();
    var realEmail =
        (req['requesterEmail'] ?? '').toString().trim().toLowerCase();
    final linkedClientId = (req['linkedClientId'] ?? '').toString().trim();
    final location = (req['location'] ?? '').toString().trim();
    final specialization =
        (metadata['specialization'] ??
                req['requestedSpecialty'] ??
                'Maintenance terrain')
            .toString()
            .trim();
    final description =
        (metadata['description'] ?? req['note'] ?? '').toString().trim();

    if (linkedClientId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Demande sans client lié : impossible de créer le technicien.',
          ),
          backgroundColor: alertColor,
        ),
      );
      return;
    }

    if (realEmail.isEmpty || !realEmail.contains('@')) {
      final corrected = await _showEmailCorrectionDialog(realEmail, 'technicien');
      if (corrected == null) return; // Annulé par l'utilisateur
      realEmail = corrected;
    }

    final epochSuffix = DateTime.now().millisecondsSinceEpoch.toString();
    final technicianFullName =
        requestedName.isEmpty ? 'Technicien' : requestedName;
    final generatedPassword =
        'Tmp${epochSuffix.substring(epochSuffix.length - 6)}!';

    try {
      final createdTechnician = await ApiService.addTechnician({
        'name': technicianFullName,
        'email': realEmail,
        'phone': (req['requesterPhone'] ?? '').toString().trim(),
        'location': location,
        'specialization': specialization,
        'technicalDescription':
            description.isEmpty
                ? 'Créé automatiquement depuis demande client'
                : description,
        'companyId': linkedClientId,
        'status': 'Disponible',
        'machineIds': machineIds,
        'password': generatedPassword,
      });
      String mailHint = '';
      final mail = createdTechnician['credentialsEmail'];
      if (mail is Map<String, dynamic>) {
        if (mail['sent'] == true) {
          mailHint = ' Identifiants envoyés par email.';
        } else if (mail['reason'] == 'smtp_not_configured') {
          mailHint = ' SMTP non configuré (ajoutez SMTP_* dans .env backend).';
        } else if (mail['reason'] == 'synthetic_email_skip') {
          mailHint = ' Email de destination non réel: envoi auto ignoré.';
        }
      }
      await ApiService.updatePurchaseRequestStatus(
        reqId,
        'VALIDATED',
        reviewedByName: 'Concepteur',
      );
      if (!mounted) return;
      await _fetchPurchaseRequests();
      setState(() {
        _techniciansFuture = ApiService.getTechnicians();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Technicien créé : $realEmail.$mailHint'),
          backgroundColor: successColor,
          duration: const Duration(seconds: 8),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Validation demande technicien impossible: ${e.toString().replaceAll('Exception: ', '')}',
          ),
          backgroundColor: alertColor,
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  Future<void> _validateMaintenanceAddRequest(Map<String, dynamic> req) async {
    final reqId = (req['id'] ?? req['_id'] ?? '').toString().trim();
    if (reqId.isEmpty) return;

    final metadataRaw = req['metadata'];
    final metadata =
        metadataRaw is Map
            ? Map<String, dynamic>.from(metadataRaw)
            : <String, dynamic>{};
    final idsFromMeta =
        (metadata['machineIds'] is List)
            ? (metadata['machineIds'] as List)
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toList()
            : <String>[];
    final idsFromRoot =
        (req['requestedMachineIds'] is List)
            ? (req['requestedMachineIds'] as List)
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toList()
            : <String>[];
    final machineIds = <String>{...idsFromMeta, ...idsFromRoot}.toList();
    final linkedClientId = (req['linkedClientId'] ?? '').toString().trim();
    final fullName = (req['requesterName'] ?? '').toString().trim();
    var email = (req['requesterEmail'] ?? '').toString().trim().toLowerCase();
    final location = (req['location'] ?? '').toString().trim();
    final description =
        (metadata['description'] ?? req['note'] ?? '').toString().trim();

    if (linkedClientId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Demande sans client lié : impossible de créer le maintenance man.',
          ),
          backgroundColor: alertColor,
        ),
      );
      return;
    }
    if (email.isEmpty || !email.contains('@')) {
      final corrected = await _showEmailCorrectionDialog(email, 'maintenance');
      if (corrected == null) return; // Annulé par l'utilisateur
      email = corrected;
    }

    final parts =
        fullName.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    final firstName = parts.isNotEmpty ? parts.first : 'Maintenance';
    final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : 'agent';
    final epochSuffix = DateTime.now().millisecondsSinceEpoch.toString();
    final generatedPassword =
        'Tmp${epochSuffix.substring(epochSuffix.length - 6)}!';

    try {
      final createdMaintenance = await ApiService.addMaintenanceAgent({
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'password': generatedPassword,
        'location': location,
        'address': description,
        'clientId': linkedClientId,
        'machineIds': machineIds,
      });
      await ApiService.updatePurchaseRequestStatus(
        reqId,
        'VALIDATED',
        reviewedByName: 'Concepteur',
      );
      if (!mounted) return;
      await _fetchPurchaseRequests();
      setState(() {
        _maintenanceAgentsFuture = ApiService.getMaintenanceAgents();
      });
      final createdEmail =
          (createdMaintenance['email'] ?? email).toString().trim();
      String mailHint = '';
      final mail = createdMaintenance['credentialsEmail'];
      if (mail is Map<String, dynamic>) {
        if (mail['sent'] == true) {
          mailHint = ' Identifiants envoyés par email.';
        } else if (mail['reason'] == 'smtp_credentials_missing') {
          mailHint = ' SMTP non configuré (ajoutez SMTP_* dans .env backend).';
        } else if (mail['reason'] == 'send_failed') {
          mailHint = ' Échec de l\'envoi de l\'e-mail (vérifiez la configuration SMTP).';
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Maintenance créé : $createdEmail.$mailHint'),
          backgroundColor: successColor,
          duration: const Duration(seconds: 8),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Validation demande maintenance impossible: ${e.toString().replaceAll('Exception: ', '')}',
          ),
          backgroundColor: alertColor,
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  Future<void> _rejectRequest(Map<String, dynamic> req) async {
    final id = (req['id'] ?? req['_id'] ?? '').toString();
    if (id.isEmpty) return;
    try {
      await ApiService.updatePurchaseRequestStatus(
        id,
        'REJECTED',
        reviewedByName: 'Concepteur',
      );
      if (!mounted) return;
      await _fetchPurchaseRequests();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Rejet impossible: $e')));
    }
  }

  Future<void> _fetchMachines() async {
    if (!_hasFleetSession) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _loadMachinesFromBackend();
      if (mounted) {
        final nextTokens = <String, String>{};
        var newNotifications = 0;

        for (final m in data) {
          final id = _machineIdOf(m).trim();
          if (id.isEmpty) continue;
          nextTokens[id] = _machineTokenOf(m);
        }

        if (_machineSnapshotInitialized) {
          for (final m in data) {
            final id = _machineIdOf(m).trim();
            if (id.isEmpty) continue;
            final name = _machineNameOf(m);
            final prev = _machineTokensById[id];
            final curr = nextTokens[id];
            if (prev == null) {
              _appendMachineNotification(
                title: 'Nouvelle machine ajoutée',
                machineName: name,
              );
              newNotifications++;
            } else if (curr != null && prev != curr) {
              _appendMachineNotification(
                title: 'Mise à jour détectée',
                machineName: name,
              );
              newNotifications++;
            }
          }

          for (final previousId in _machineTokensById.keys) {
            if (!nextTokens.containsKey(previousId)) {
              _appendMachineNotification(
                title: 'Machine supprimée',
                machineName: previousId,
              );
              newNotifications++;
            }
          }
        }

        setState(() {
          _allMachines = data;
          _machineTokensById
            ..clear()
            ..addAll(nextTokens);
          _machineSnapshotInitialized = true;
          _unreadMachineNotifications += newNotifications;
          _loading = false;
        });
        // Start 1-second live telemetry polling for all machines
        _registerMachinesForTelemetryPolling();
      }
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (!_silentRecoveryTried &&
          (msg.contains('session non connect') ||
              msg.contains('authentification'))) {
        _silentRecoveryTried = true;
        final token = await _trySilentSessionRecovery();
        if (token.isNotEmpty && mounted) {
          setState(() {
            _hasFleetSession = true;
            _clientsFuture = ApiService.getClients();
            _techniciansFuture = ApiService.getTechnicians();
            _maintenanceAgentsFuture = ApiService.getMaintenanceAgents();
          });
          return _fetchMachines();
        }
      }
      if (mounted) {
        setState(() {
          _hasFleetSession = false;
          _loading = false;
          _error = 'Impossible de charger les machines: $e';
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadMachinesFromBackend() async {
    // Objectif dashboard concepteur: afficher TOUTES les machines visibles.
    // On fusionne la source globale Mongo (/api/machines) + workspace conception.
    final mergedById = <String, Map<String, dynamic>>{};

    try {
      // Filter by concepterId so the designer only sees their own machines in the global list
      final fromMachinesApi = await ApiService.getCatalogMachines(
        concepterId: _concepteurProfileId,
        includeAll: true,
      );
      for (final m in fromMachinesApi) {
        final mm = Map<String, dynamic>.from(m);
        final id =
            (mm['id'] ?? mm['_id'] ?? mm['machineId'] ?? '').toString().trim();
        if (id.isNotEmpty) {
          mm['id'] = id;
          mergedById[id] = mm;
        } else {
          final fallbackKey =
              'name:${(mm['name'] ?? '').toString().trim().toLowerCase()}';
          mergedById[fallbackKey] = mm;
        }
      }
    } catch (_) {}

    try {
      final workspace = await ApiService.getConceptionWorkspace();
      final dynamic rawList =
          workspace['machines'] ?? workspace['data'] ?? workspace['items'];
      if (rawList is List) {
        for (final e in rawList.whereType<Map>()) {
          final mm = Map<String, dynamic>.from(e);
          final id =
              (mm['id'] ?? mm['_id'] ?? mm['machineId'] ?? '')
                  .toString()
                  .trim();
          if (id.isNotEmpty) {
            mm['id'] = id;
          }
          if (id.isNotEmpty) {
            // Évite qu'une version workspace obsolète écrase les données
            // fraîches Mongo (ex: image mise à jour juste après édition).
            if (mergedById.containsKey(id)) {
              mergedById[id] = {...mm, ...mergedById[id]!};
            } else {
              mergedById[id] = mm;
            }
          } else {
            final fallbackKey =
                'name:${(mm['name'] ?? '').toString().trim().toLowerCase()}';
            if (mergedById.containsKey(fallbackKey)) {
              mergedById[fallbackKey] = {...mm, ...mergedById[fallbackKey]!};
            } else {
              mergedById[fallbackKey] = mm;
            }
          }
        }
      }
    } catch (_) {}

    return mergedById.values.toList();
  }

  List<Map<String, dynamic>> get _filteredMachines {
    final query = _searchController.text.toLowerCase();
    return _allMachines.where((m) {
      final name = (m['name'] ?? '').toString().toLowerCase();
      final ref = (m['machineId'] ?? m['id'] ?? '').toString().toLowerCase();
      final cat = (m['type'] ?? m['category'] ?? '').toString();
      final isPublic = m['isPublic'] == true;

      bool matchesSearch = name.contains(query) || ref.contains(query);
      bool matchesCategory =
          _selectedCategory == 'Toutes les catégories' ||
          cat == _selectedCategory;
      bool matchesStatus =
          _selectedStatus == 'Tous' ||
          (_selectedStatus == 'Publié' && isPublic) ||
          (_selectedStatus == 'Non publié' && !isPublic);

      return matchesSearch && matchesCategory && matchesStatus;
    }).toList();
  }

  int get _publishedCount =>
      _allMachines.where((m) => m['isPublic'] == true).length;
  int get _notPublishedCount => _allMachines.length - _publishedCount;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: Column(
        children: [
          _buildTopNavigation(),
          Expanded(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child:
                      _loading
                          ? const Center(
                            child: CircularProgressIndicator(
                              color: primaryColor,
                            ),
                          )
                          : _error != null
                          ? _buildErrorView()
                          : _buildMainContent(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: alertColor, size: 64),
          const SizedBox(height: 16),
          Text(
            _error!,
            style: GoogleFonts.inter(color: textColor, fontSize: 16),
          ),
          const SizedBox(height: 24),
          if (_hasFleetSession)
            ElevatedButton(
              onPressed: _fetchMachines,
              style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
              child: Text(
                'Réessayer',
                style: GoogleFonts.inter(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          else
            ElevatedButton(
              onPressed:
                  () => Navigator.pushReplacementNamed(context, '/login'),
              style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
              child: Text(
                'Se reconnecter',
                style: GoogleFonts.inter(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    if (selectedMenu == 'MESSAGERIE') {
      return const MessageEquipeView(embedded: true);
    }
    return RefreshIndicator(
      onRefresh: () async {
        // Refresh context-aware: machines dashboard vs client catalog.
        if (selectedMenu == 'PROJET') {
          setState(() {
            _clientsFuture = ApiService.getClients();
            _techniciansFuture = ApiService.getTechnicians();
            _maintenanceAgentsFuture = ApiService.getMaintenanceAgents();
          });
          try {
            await _clientsFuture;
          } catch (_) {}
          try {
            await _techniciansFuture;
          } catch (_) {}
          try {
            await _maintenanceAgentsFuture;
          } catch (_) {}
          return;
        }
        if (selectedMenu == 'CLIENT CATALOG') {
          setState(() {
            _clientsFuture = ApiService.getClients();
            _techniciansFuture = ApiService.getTechnicians();
            _maintenanceAgentsFuture = ApiService.getMaintenanceAgents();
          });
          try {
            await _clientsFuture;
          } catch (_) {}
          try {
            await _techniciansFuture;
          } catch (_) {}
          try {
            await _maintenanceAgentsFuture;
          } catch (_) {}
          return;
        }
        if (selectedMenu == 'TECHNICIANS') {
          setState(() {
            _techniciansFuture = ApiService.getTechnicians();
          });
          try {
            await _techniciansFuture;
          } catch (_) {}
          await _fetchMachines();
          return;
        }
        if (selectedMenu == 'MAINTENANCE') {
          setState(() {
            _maintenanceAgentsFuture = ApiService.getMaintenanceAgents();
          });
          try {
            await _maintenanceAgentsFuture;
          } catch (_) {}
          await _fetchMachines();
          return;
        }
        if (selectedMenu == 'PROFILE') return;
        await _fetchMachines();
      },
      color: primaryColor,
      backgroundColor: cardColor,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(isMobileLayout(context) ? 12.0 : 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (selectedMenu == 'PROJET')
              _buildClientCatalogPanel()
            else if (selectedMenu == 'CLIENT CATALOG')
              _buildProjectTeamPanel()
            else if (selectedMenu == 'TECHNICIANS')
              _buildTechniciansPanel()
            else if (selectedMenu == 'MAINTENANCE')
              _buildMaintenanceAgentsPanel()
            else if (selectedMenu == 'PROFILE')
              _buildProfilePanel()
            else ...[
              _buildPurchaseRequestsPanel(),
              const SizedBox(height: 16),
              _buildTechnicianAddRequestsPanel(),
              const SizedBox(height: 20),
              _buildStatsGrid(),
              const SizedBox(height: 32),
              _buildMainSectionHeader(),
              const SizedBox(height: 24),
              _buildFilterBar(),
              const SizedBox(height: 24),
              if (_filteredMachines.isEmpty)
                _buildEmptyView()
              else
                _buildMachineGrid(),
              const SizedBox(height: 32),
              _buildPagination(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildClientLoginSurveyPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sidebarColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user_outlined, color: primaryColor),
              const SizedBox(width: 8),
              Text(
                'Contrôle des connexions clients',
                style: GoogleFonts.spaceGrotesk(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Liste des comptes client : email de login, mot de passe défini, blocage, '
            'et conflits éventuels avec un autre rôle (même email).',
            style: GoogleFonts.inter(color: mutedTextColor, fontSize: 12),
          ),
          const SizedBox(height: 16),
          FutureBuilder<Map<String, dynamic>>(
            future:
                _clientLoginSurveyFuture ?? ApiService.getClientLoginSurvey(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: CircularProgressIndicator(color: primaryColor),
                  ),
                );
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Erreur : ${snapshot.error}',
                    style: GoogleFonts.inter(color: alertColor, fontSize: 13),
                  ),
                );
              }
              final data = snapshot.data ?? {};
              final raw = data['clients'];
              final List<Map<String, dynamic>> rows = [];
              if (raw is List) {
                for (final e in raw) {
                  if (e is Map<String, dynamic>) rows.add(e);
                }
              }
              if (rows.isEmpty) {
                return Text(
                  'Aucun client en base.',
                  style: GoogleFonts.inter(color: mutedTextColor, fontSize: 13),
                );
              }
              String collisionLabel(dynamic v) {
                if (v is! List || v.isEmpty) return '—';
                return v.map((e) => e.toString()).join(', ');
              }

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(cardColor),
                  dataRowMinHeight: 48,
                  columns: [
                    DataColumn(
                      label: Text(
                        'Client',
                        style: GoogleFonts.inter(
                          color: textColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        'ID',
                        style: GoogleFonts.inter(
                          color: textColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        'Email login',
                        style: GoogleFonts.inter(
                          color: textColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        'Mot de passe',
                        style: GoogleFonts.inter(
                          color: textColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        'Blocage',
                        style: GoogleFonts.inter(
                          color: textColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        'Collisions rôles',
                        style: GoogleFonts.inter(
                          color: textColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  rows:
                      rows.map((r) {
                        final name = (r['name'] ?? '').toString();
                        final cid = (r['clientId'] ?? '').toString();
                        final email = (r['email'] ?? '').toString();
                        final hasPw = r['hasLoginPassword'] == true;
                        final disabled = r['loginDisabled'] == true;
                        final col = collisionLabel(r['identityCollisions']);
                        return DataRow(
                          cells: [
                            DataCell(
                              Text(
                                name,
                                style: GoogleFonts.inter(
                                  color: textColor,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                cid,
                                style: GoogleFonts.inter(
                                  color: mutedTextColor,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                email.isEmpty ? '—' : email,
                                style: GoogleFonts.inter(
                                  color: textColor,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                hasPw ? 'Défini' : 'Manquant',
                                style: GoogleFonts.inter(
                                  color: hasPw ? successColor : alertColor,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                disabled ? 'Oui' : 'Non',
                                style: GoogleFonts.inter(
                                  color: disabled ? alertColor : mutedTextColor,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                col,
                                style: GoogleFonts.inter(
                                  color:
                                      col == '—' ? mutedTextColor : alertColor,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildClientCatalogPanel() {
    final width = MediaQuery.of(context).size.width;
    final wide = width >= 1024;
    final xWide = width >= 1480;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: FutureBuilder<List<dynamic>>(
        future: Future.wait<dynamic>([
          _clientsFuture ?? ApiService.getClients(),
          _techniciansFuture ?? ApiService.getTechnicians(),
          (_maintenanceAgentsFuture ?? ApiService.getMaintenanceAgents())
              .catchError((_) => <Map<String, dynamic>>[]),
        ]),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Erreur chargement catalogue: ${snapshot.error}',
                style: GoogleFonts.inter(color: alertColor),
              ),
            );
          }

          final raw = snapshot.data ?? const <dynamic>[];
          final allClients =
              (raw.isNotEmpty ? raw[0] : const <dynamic>[]) as List<dynamic>;
          final allTechs =
              (raw.length > 1 ? raw[1] : const <dynamic>[]) as List<dynamic>;
          final allAgents =
              (raw.length > 2 ? raw[2] : const <dynamic>[]) as List<dynamic>;
          final clientRows = allClients.cast<Map<String, dynamic>>();
          final technicianRows = allTechs.cast<Map<String, dynamic>>();
          final maintenanceRows = allAgents.cast<Map<String, dynamic>>();
          final q = _clientSearchQuery.toLowerCase().trim();

          final filtered =
              clientRows.where((c) {
                if (q.isEmpty) return true;
                final id = _clientIdOf(c).toLowerCase();
                final name = _clientNameOf(c).toLowerCase();
                final email = (c['email'] ?? '').toString().toLowerCase();
                return id.contains(q) || name.contains(q) || email.contains(q);
              }).toList();

          if (filtered.isEmpty) {
            return Center(
              child: Text(
                'Aucun client trouve.',
                style: GoogleFonts.inter(color: mutedTextColor),
              ),
            );
          }

          final selectedName =
              _selectedCatalogClientId == null
                  ? ''
                  : _clientNameOf(
                    clientRows.firstWhere(
                      (c) => _clientIdOf(c) == _selectedCatalogClientId,
                      orElse: () => filtered.first,
                    ),
                  );

          Map<String, dynamic>? selectedClientRow() {
            final sid = _selectedCatalogClientId;
            if (sid == null || sid.isEmpty) return null;
            try {
              return clientRows.firstWhere((c) => _clientIdOf(c) == sid);
            } catch (_) {
              return null;
            }
          }

          Set<String> selectedClientKeys() {
            final sid = (_selectedCatalogClientId ?? '').trim();
            final keys = <String>{};
            if (sid.isNotEmpty) keys.add(sid);
            final row = selectedClientRow();
            if (row != null) {
              keys.addAll(_clientLinkedIdKeys(row));
            }
            return keys;
          }

          Widget clientsList() {
            return ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final c = filtered[i];
                final cid = _clientIdOf(c);
                final selected =
                    cid.isNotEmpty && cid == _selectedCatalogClientId;
                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF14141F),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color:
                          selected
                              ? primaryColor.withOpacity(0.6)
                              : const Color(0xFF222233),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InkWell(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(13),
                        ),
                        onTap: () {
                          if (cid.isEmpty) return;
                          setState(() {
                            _selectedCatalogClientId = cid;
                            _selectedClientMachinesFuture =
                                ApiService.getMachinesForClient(cid);
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _entityAvatar(
                                    c,
                                    _clientNameOf(c),
                                    radius: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _clientNameOf(c),
                                          style: GoogleFonts.inter(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color:
                                                selected
                                                    ? primaryColor
                                                    : textColor,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'ID: $cid',
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            color: mutedTextColor,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        if ((c['email'] ?? '')
                                            .toString()
                                            .trim()
                                            .isNotEmpty)
                                          Text(
                                            (c['email'] ?? '').toString(),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              color: mutedTextColor,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      _catalogEditDeleteRow(
                        onEdit: () => _openEditClient(c),
                        onDelete: () => _deleteClientEntity(c),
                      ),
                    ],
                  ),
                );
              },
            );
          }

          Widget catalogTechBlock(Set<String> keys) {
            final list = _techniciansForClientKeys(technicianRows, keys);
            final selectedCid = (_selectedCatalogClientId ?? '').trim();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _maintenanceSectionTitle(
                        'Techniciens',
                        Icons.tune_rounded,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed:
                          () => _openAddTechnician(clientId: selectedCid),
                      icon: const Icon(Icons.person_add_alt_1, size: 14),
                      label: Text(
                        'Add Technicien',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: bgColor,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (list.isEmpty)
                  _maintenanceEmptyPane(
                    icon: Icons.engineering_outlined,
                    message: 'Aucun technicien lie a ce client.',
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final t = list[i];
                      return Container(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF14141F),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF222233)),
                        ),
                        child: Column(
                          children: [
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: _entityAvatar(
                                t,
                                _technicianNameOf(t),
                                radius: 16,
                              ),
                              title: Text(
                                _technicianNameOf(t),
                                style: GoogleFonts.inter(
                                  color: textColor,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              subtitle: Text(
                                '${_technicianIdOf(t)}\n${(t['email'] ?? '').toString()}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  color: mutedTextColor,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                            _catalogEditDeleteRow(
                              onEdit: () => _openEditTechnician(t),
                              onDelete: () => _deleteTechnicianEntity(t),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            );
          }

          Widget catalogMaintBlock(Set<String> keys) {
            final list = _maintenanceAgentsForClientKeys(maintenanceRows, keys);
            final selectedCid = (_selectedCatalogClientId ?? '').trim();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _maintenanceSectionTitle(
                        'Agents maintenance',
                        Icons.handyman_outlined,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed:
                          () => _openAddMaintenanceAgent(clientId: selectedCid),
                      icon: const Icon(Icons.build_outlined, size: 14),
                      label: Text(
                        'Add Maintenance',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: bgColor,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (list.isEmpty)
                  _maintenanceEmptyPane(
                    icon: Icons.build_circle_outlined,
                    message: 'Aucun agent maintenance lie a ce client.',
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final a = list[i];
                      return Container(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF14141F),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF222233)),
                        ),
                        child: Column(
                          children: [
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: _entityAvatar(
                                a,
                                _maintenanceAgentNameOf(a),
                                radius: 16,
                              ),
                              title: Text(
                                _maintenanceAgentNameOf(a),
                                style: GoogleFonts.inter(
                                  color: textColor,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              subtitle: Text(
                                '${_maintenanceAgentIdOf(a)}\n${(a['email'] ?? '').toString()}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  color: mutedTextColor,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                            _catalogEditDeleteRow(
                              onEdit: () => _openEditMaintenanceAgent(a),
                              onDelete: () => _deleteMaintenanceAgentEntity(a),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            );
          }

          Widget machinesPanel() {
            final cid = _selectedCatalogClientId ?? '';
            if (cid.isEmpty) {
              return _maintenanceEmptyPane(
                icon: Icons.touch_app_outlined,
                message: 'Selectionnez un client pour afficher les machines.',
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _maintenanceSectionTitle(
                  'Machines',
                  Icons.precision_manufacturing_outlined,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 10),
                  child: Text(
                    selectedName.isNotEmpty
                        ? 'Pour $selectedName'
                        : 'Client selectionne',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: mutedTextColor,
                    ),
                  ),
                ),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _selectedClientMachinesFuture,
                  builder: (context, mSnap) {
                    if (mSnap.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 30),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (mSnap.hasError) {
                      return Text(
                        'Erreur machines: ${mSnap.error}',
                        style: GoogleFonts.inter(color: alertColor),
                      );
                    }
                    final machines =
                        mSnap.data ?? const <Map<String, dynamic>>[];
                    if (machines.isEmpty) {
                      return _maintenanceEmptyPane(
                        icon: Icons.precision_manufacturing_outlined,
                        message: 'Aucune machine achetee pour ce client.',
                      );
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: machines.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final m = machines[i];
                        final mid = _machineIdOf(m);
                        final name = _machineNameOf(m);
                        final rawImg =
                            (m['imageUrl'] ?? m['image'] ?? '').toString();
                        return InkWell(
                          onTap: () => _openMachineDetail(m),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF14141F),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFF222233),
                              ),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: SizedBox(
                                    width: 64,
                                    height: 52,
                                    child: _buildMachineImageWidget(
                                      rawImg,
                                      height: 52,
                                      width: 64,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(
                                          color: textColor,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'ID: $mid',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: mutedTextColor,
                                        ),
                                      ),
                                      // ── Live telemetry state display ─────────────────────
                                      ValueListenableBuilder<int>(
                                        valueListenable: _telemetryTick,
                                        builder: (context, _, __) {
                                          final tel = _telemetryTick.value >= 0 ? _liveTelemetryByMachineId[mid] : null;
                                          if (tel == null) {
                                            return Container(
                                              margin: const EdgeInsets.only(top: 6),
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withOpacity(0.04),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(Icons.sensors_off, color: Color(0xFF8A8AA1), size: 12),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    'Capteurs en attente…',
                                                    style: GoogleFonts.inter(color: const Color(0xFF8A8AA1), fontSize: 9),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }
                                          double? parseVal(dynamic v) {
                                            if (v == null) return null;
                                            if (v is num) return v.toDouble();
                                            return double.tryParse(v.toString());
                                          }
                                          final tempVal = parseVal(tel['temperature'] ?? tel['temp']);
                                          final vibVal = parseVal(tel['vibration']);
                                          final risk = _computeRiskFromTelemetry(tel);
                                          final Color stateColor = risk == 'DANGER'
                                              ? const Color(0xFFF44336)
                                              : risk == 'RISQUE'
                                                  ? const Color(0xFFFF9800)
                                                  : const Color(0xFF4CAF50);
                                          final IconData stateIcon = risk == 'DANGER'
                                              ? Icons.error_outline
                                              : risk == 'RISQUE'
                                                  ? Icons.warning_amber_rounded
                                                  : Icons.check_circle_outline;
                                          return Container(
                                            margin: const EdgeInsets.only(top: 6),
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: stateColor.withOpacity(0.08),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: stateColor.withOpacity(0.25)),
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(stateIcon, color: stateColor, size: 12),
                                                    const SizedBox(width: 5),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: stateColor.withOpacity(0.15),
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Text(
                                                        risk,
                                                        style: GoogleFonts.spaceGrotesk(
                                                          color: stateColor,
                                                          fontSize: 8,
                                                          fontWeight: FontWeight.bold,
                                                          letterSpacing: 0.8,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Container(
                                                      width: 5, height: 5,
                                                      decoration: BoxDecoration(color: stateColor, shape: BoxShape.circle),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text('LIVE', style: GoogleFonts.inter(color: stateColor, fontSize: 7, fontWeight: FontWeight.bold)),
                                                  ],
                                                ),
                                                const SizedBox(height: 6),
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.thermostat_outlined, color: stateColor.withOpacity(0.7), size: 11),
                                                    const SizedBox(width: 3),
                                                    Text(
                                                      tempVal != null ? '${tempVal.toStringAsFixed(1)}°C' : '--',
                                                      style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Icon(Icons.vibration, color: stateColor.withOpacity(0.7), size: 11),
                                                    const SizedBox(width: 3),
                                                    Text(
                                                      vibVal != null ? '${vibVal.toStringAsFixed(1)} mm/s' : '--',
                                                      style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            );
          }

          final keys = selectedClientKeys();

          return Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.white.withOpacity(0.08)),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _clientSearchController,
                        onChanged:
                            (v) => setState(() => _clientSearchQuery = v),
                        decoration: InputDecoration(
                          hintText: 'Rechercher par nom, ID ou email...',
                          hintStyle: GoogleFonts.inter(
                            color: mutedTextColor.withOpacity(0.5),
                            fontSize: 13,
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            size: 18,
                            color: primaryColor,
                          ),
                          suffixIcon: _clientSearchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 18, color: Colors.white54),
                                  onPressed: () {
                                    _clientSearchController.clear();
                                    setState(() => _clientSearchQuery = '');
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: const Color(0x11FFFFFF),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: Colors.white.withOpacity(0.08),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: primaryColor,
                              width: 1.2,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                        ),
                        style: GoogleFonts.inter(
                          color: textColor,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (wide) ...[
                      const SizedBox(width: 12),
                      const SizedBox.shrink(),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child:
                    wide
                        ? SizedBox(
                          height: 740,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 320,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10101A),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: const Color(0xFF222233),
                                    ),
                                  ),
                                  padding: const EdgeInsets.all(12),
                                  child: clientsList(),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: SingleChildScrollView(
                                  child: Column(
                                    children: [
                                      if (xWide)
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: catalogTechBlock(keys),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: catalogMaintBlock(keys),
                                            ),
                                          ],
                                        )
                                      else ...[
                                        catalogTechBlock(keys),
                                        const SizedBox(height: 14),
                                        catalogMaintBlock(keys),
                                      ],
                                      const SizedBox(height: 14),
                                      machinesPanel(),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                        : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(height: 440, child: clientsList()),
                            const SizedBox(height: 14),
                            catalogTechBlock(keys),
                            const SizedBox(height: 14),
                            catalogMaintBlock(keys),
                            const SizedBox(height: 14),
                            machinesPanel(),
                          ],
                        ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProjectTeamPanel() {
    if (_profileLoading && _concepteurProjectTeam == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: sidebarColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 42),
          child: Center(child: CircularProgressIndicator(color: primaryColor)),
        ),
      );
    }

    final clients =
        (_concepteurProjectTeam?['clients'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        const <Map<String, dynamic>>[];
    final techs =
        (_concepteurProjectTeam?['technicians'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        const <Map<String, dynamic>>[];
    final agents =
        (_concepteurProjectTeam?['maintenanceAgents'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        const <Map<String, dynamic>>[];

    if (clients.isEmpty) {
      return _maintenanceEmptyPane(
        icon: Icons.business_outlined,
        message: 'Aucun client n\'a encore achete une de vos machines.',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = 3;
        if (constraints.maxWidth < 600)
          crossAxisCount = 1;
        else if (constraints.maxWidth < 1000)
          crossAxisCount = 2;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 0.85,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: clients.length,
          itemBuilder: (context, index) {
            final c = clients[index];
            final clientKeys = _clientLinkedIdKeys(c);
            
            final embeddedTechs = (c['technicians'] as List?)?.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
            final embeddedAgents = (c['maintenanceAgents'] as List?)?.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
            final embeddedMachines = (c['machines'] as List?)?.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
            
            final t = embeddedTechs ?? _techniciansForClientKeys(techs, clientKeys);
            final m = embeddedAgents ?? _maintenanceAgentsForClientKeys(agents, clientKeys);
            final machinesList = embeddedMachines ?? const <Map<String, dynamic>>[];

            return _buildClientGalleryCard(c, machinesList, t, m);
          },
        );
      },
    );
  }

  Widget _buildClientGalleryCard(
    Map<String, dynamic> client,
    List<Map<String, dynamic>> machines,
    List<Map<String, dynamic>> techs,
    List<Map<String, dynamic>> agents,
  ) {
    final cid = _clientIdOf(client);
    final cname = _clientNameOf(client);
    final location = (client['location'] ?? 'Localisation inconnue').toString();
    final email = (client['email'] ?? 'Email non specifie').toString();
    final isActive = client['loginDisabled'] != true;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF171733),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Container(
                height: 154,
                width: double.infinity,
                color: const Color(0xFF1E1E2D),
                alignment: Alignment.center,
                child: _entityAvatar(client, cname, radius: 45),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.15),
                        Colors.black.withOpacity(0.55),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 10,
                left: 10,
                child: Row(
                  children: [
                    _statusBadge(
                      isActive ? 'ACTIF' : 'INACTIF',
                      isActive ? const Color(0xFF4CAF50) : const Color(0xFFE53935),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ID: ' + (cid.isEmpty ? 'INCONNU' : cid.toUpperCase()),
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: primaryColor,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    cname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                      height: 1.0,
                    ),
                  ),
                  Expanded(
                    child: machines.isEmpty
                        ? Center(
                            child: Text(
                              'Aucune machine associée',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: mutedTextColor,
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: machines.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 6),
                            itemBuilder: (context, index) {
                              final m = machines[index];
                              final mName = (m['name'] ?? m['reference'] ?? 'Machine').toString();
                              final isRunning = (m['status'] ?? '').toString().toUpperCase() == 'RUNNING';
                              return GestureDetector(
                                onTap: () {
                                  showDialog(
                                    context: context,
                                    builder: (context) {
                                      final ref = (m['machineId'] ?? m['reference'] ?? 'Non spécifiée').toString();
                                      final type = (m['type'] ?? m['category'] ?? 'Non catégorisée').toString();
                                      final loc = (m['location'] ?? 'Inconnue').toString();
                                      
                                      return AlertDialog(
                                        backgroundColor: const Color(0xFF1E1E2D),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        title: Row(
                                          children: [
                                            const Icon(Icons.info_outline, color: primaryColor),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text('Détails de la machine', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 18)),
                                            ),
                                          ],
                                        ),
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 4),
                                              child: Text('Nom : $mName', style: GoogleFonts.inter(color: Colors.white70)),
                                            ),
                                            Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 4),
                                              child: Text('Référence : $ref', style: GoogleFonts.inter(color: Colors.white70)),
                                            ),
                                            Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 4),
                                              child: Text('Catégorie : $type', style: GoogleFonts.inter(color: Colors.white70)),
                                            ),
                                            Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 4),
                                              child: Text('Localisation : $loc', style: GoogleFonts.inter(color: Colors.white70)),
                                            ),
                                            Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 4),
                                              child: Text('État : ${isRunning ? "En marche" : "Arrêt"}', style: GoogleFonts.inter(color: isRunning ? const Color(0xFF4CAF50) : const Color(0xFFE53935), fontWeight: FontWeight.bold)),
                                            ),
                                          ],
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(context),
                                            child: const Text('FERMER', style: TextStyle(color: primaryColor)),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.03),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isRunning ? Icons.play_circle_filled : Icons.stop_circle,
                                        size: 14,
                                        color: isRunning ? const Color(0xFF4CAF50) : const Color(0xFFE53935),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          mName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        isRunning ? 'En marche' : 'Arrêt',
                                        style: GoogleFonts.inter(
                                          fontSize: 9,
                                          color: isRunning ? const Color(0xFF4CAF50) : const Color(0xFFE53935),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _cardButton(
                          Icons.edit_outlined,
                          'MODIFIER',
                          const Color(0xFF212142),
                          () => _openEditClient(client),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _cardButton(
                          Icons.delete_outline,
                          'EFFACER',
                          const Color(0xFF422121),
                          () => _deleteClientEntity(client),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectTeamClientDetails({
    required List<Map<String, dynamic>> machines,
    required List<Map<String, dynamic>> technicians,
    required List<Map<String, dynamic>> maintenanceAgents,
    required List<Map<String, dynamic>> concepteurs,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Machines (${machines.length})',
          style: GoogleFonts.inter(
            color: primaryColor,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          machines.isEmpty
              ? 'Aucune machine pour ce client.'
              : machines.map((x) => _machineNameOf(x)).join(', '),
          style: GoogleFonts.inter(color: mutedTextColor, fontSize: 12),
        ),
        const SizedBox(height: 10),
        Text(
          'Equipe projet',
          style: GoogleFonts.inter(
            color: primaryColor,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 6),
        if (technicians.isNotEmpty) ...[
          const SizedBox(height: 4),
          ...technicians.map((t) {
            final name = _technicianNameOf(t);
            final loc =
                (t['location'] ??
                        t['address'] ??
                        t['city'] ??
                        'Localisation non spécifiée')
                    .toString();

            // Get all machines associated with this technician
            // First get their machineIds if any
            final raw = t['machineIds'];
            final tIds = <String>[];
            if (raw is List) {
              for (final e in raw) {
                final s = e.toString().trim();
                if (s.isNotEmpty) tIds.add(s);
              }
            } else if (raw is String) {
              try {
                final l = jsonDecode(raw);
                if (l is List) {
                  for (final e in l) {
                    final s = e.toString().trim();
                    if (s.isNotEmpty) tIds.add(s);
                  }
                }
              } catch (_) {}
            }
            // Then find matching machines from the client's machines
            final techM =
                machines.where((m) => tIds.contains(_machineIdOf(m))).toList();
            final displayMachines = techM.isNotEmpty ? techM : machines;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF14141F),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: Row(
                children: [
                  _entityAvatar(t, name, radius: 20),
                  const SizedBox(width: 12),
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
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              color: mutedTextColor,
                              size: 12,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                loc,
                                style: GoogleFonts.inter(
                                  color: mutedTextColor,
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (displayMachines.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children:
                                displayMachines.map((m) {
                                  return InkWell(
                                    onTap:
                                        () =>
                                            _showMachineMiniDetails(context, m),
                                    borderRadius: BorderRadius.circular(16),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: primaryColor.withOpacity(0.1),
                                        border: Border.all(
                                          color: primaryColor.withOpacity(0.3),
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.precision_manufacturing,
                                            size: 12,
                                            color: primaryColor,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _machineNameOf(m),
                                            style: GoogleFonts.inter(
                                              color: primaryColor,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                          ),
                        ] else ...[
                          const SizedBox(height: 8),
                          Text(
                            'Aucune machine assignée',
                            style: GoogleFonts.inter(
                              color: mutedTextColor,
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          const SizedBox(height: 4),
        ] else ...[
          Text(
            'Techniciens: —',
            style: GoogleFonts.inter(color: mutedTextColor, fontSize: 12),
          ),
        ],
        const SizedBox(height: 4),
        Text(
          'Maintenance: ${maintenanceAgents.isEmpty ? '—' : maintenanceAgents.map((e) => _maintenanceAgentNameOf(e)).join(', ')}',
          style: GoogleFonts.inter(color: mutedTextColor, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          'Concepteurs: ${concepteurs.isEmpty ? '—' : concepteurs.map((e) => (e['name'] ?? 'Concepteur').toString()).join(', ')}',
          style: GoogleFonts.inter(color: mutedTextColor, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildTechniciansPanel() {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1050;
    final threeCol = width >= 1240;
    final twoCol = width >= 900;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sidebarColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isMobileLayout(context))
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.people_outline_rounded,
                      color: primaryColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Techniciens',
                        style: GoogleFonts.spaceGrotesk(
                          color: textColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _technicianSearchController,
                  onChanged: (v) => setState(() => _technicianSearchQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Rechercher par nom, ID, email ou réf. client...',
                    hintStyle: GoogleFonts.inter(
                      color: mutedTextColor.withOpacity(0.6),
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: cardColor,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  style: GoogleFonts.inter(color: textColor, fontSize: 13),
                ),
              ],
            )
          else
            Row(
              children: [
                const Icon(Icons.people_outline_rounded, color: primaryColor),
                const SizedBox(width: 8),
                Text(
                  'Techniciens',
                  style: GoogleFonts.spaceGrotesk(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: isDesktop ? 340 : 260,
                  child: TextField(
                    controller: _technicianSearchController,
                    onChanged:
                        (v) => setState(() => _technicianSearchQuery = v),
                    decoration: InputDecoration(
                      hintText:
                          'Rechercher par nom, ID, email ou réf. client...',
                      hintStyle: GoogleFonts.inter(
                        color: mutedTextColor.withOpacity(0.6),
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: cardColor,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    style: GoogleFonts.inter(color: textColor, fontSize: 13),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 16),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _techniciansFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Erreur chargement techniciens: ${snapshot.error}',
                    style: GoogleFonts.inter(color: alertColor),
                  ),
                );
              }

              final allTechs = snapshot.data ?? const <Map<String, dynamic>>[];
              final q = _technicianSearchQuery.toLowerCase().trim();

              final filtered =
                  allTechs.where((t) {
                    if (q.isEmpty) return true;
                    final id = _technicianIdOf(t).toLowerCase();
                    final name = _technicianNameOf(t).toLowerCase();
                    final email = (t['email'] ?? '').toString().toLowerCase();
                    final company =
                        (t['companyId'] ?? '').toString().toLowerCase();
                    return id.contains(q) ||
                        name.contains(q) ||
                        email.contains(q) ||
                        company.contains(q);
                  }).toList();

              if (filtered.isEmpty) {
                return Text(
                  'Aucun technicien trouvé.',
                  style: GoogleFonts.inter(color: mutedTextColor),
                );
              }

              final selectedName =
                  _selectedTechnicianId == null
                      ? ''
                      : _technicianNameOf(
                        allTechs.firstWhere(
                          (t) => _technicianIdOf(t) == _selectedTechnicianId,
                          orElse: () => filtered.first,
                        ),
                      );

              Widget techniciansList() {
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final t = filtered[i];
                    final tid = _technicianIdOf(t);
                    final pending = _isPendingTechnician(t);
                    final selected =
                        tid.isNotEmpty && tid == _selectedTechnicianId;
                    return Container(
                      decoration: BoxDecoration(
                        color:
                            selected
                                ? primaryColor.withOpacity(0.08)
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color:
                              selected
                                  ? primaryColor.withOpacity(0.45)
                                  : Colors.white.withOpacity(0.06),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          InkWell(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(11),
                            ),
                            onTap: () {
                              if (tid.isEmpty) return;
                              setState(() => _selectedTechnicianId = tid);
                            },
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: primaryColor.withOpacity(
                                      0.12,
                                    ),
                                    child: Icon(
                                      Icons.engineering_outlined,
                                      color: primaryColor,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _technicianNameOf(t),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color:
                                                selected
                                                    ? primaryColor
                                                    : textColor,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          tid,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            color: mutedTextColor,
                                          ),
                                        ),
                                        if ((t['email'] ?? '')
                                            .toString()
                                            .trim()
                                            .isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            (t['email'] ?? '').toString(),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              color: mutedTextColor.withOpacity(
                                                0.9,
                                              ),
                                            ),
                                          ),
                                        ],
                                        if (pending) ...[
                                          const SizedBox(height: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(
                                                0xFFFFB86C,
                                              ).withOpacity(0.18),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              border: Border.all(
                                                color: const Color(0xFFFFB86C),
                                              ),
                                            ),
                                            child: Text(
                                              'Demande client en attente',
                                              style: GoogleFonts.inter(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color: const Color(0xFFFFB86C),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (pending)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed:
                                          () => _rejectPendingTechnician(t),
                                      style: OutlinedButton.styleFrom(
                                        side: BorderSide(
                                          color: alertColor.withOpacity(0.65),
                                        ),
                                        foregroundColor: alertColor,
                                      ),
                                      child: const Text('Refuser'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed:
                                          () => _approvePendingTechnician(t),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: successColor,
                                        foregroundColor: Colors.white,
                                      ),
                                      child: const Text('Valider'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          _catalogEditDeleteRow(
                            onEdit: () => _openEditTechnician(t),
                            onDelete: () => _deleteTechnicianEntity(t),
                          ),
                        ],
                      ),
                    );
                  },
                );
              }

              Map<String, dynamic> selectedTechnicianMap() {
                final selId = _selectedTechnicianId ?? '';
                if (selId.isEmpty) return {};
                return allTechs.firstWhere(
                  (x) => _technicianIdOf(x) == selId,
                  orElse: () => <String, dynamic>{},
                );
              }

              Widget clientColumn() {
                final selId = _selectedTechnicianId ?? '';
                if (selId.isEmpty) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _maintenanceSectionTitle(
                        'Client lié',
                        Icons.apartment_outlined,
                      ),
                      const SizedBox(height: 10),
                      _maintenanceEmptyPane(
                        icon: Icons.person_search_outlined,
                        message:
                            'Sélectionnez un technicien pour afficher la fiche client (via companyId).',
                      ),
                    ],
                  );
                }
                final tech = selectedTechnicianMap();
                if (tech.isEmpty) {
                  return const SizedBox.shrink();
                }
                final companyId = (tech['companyId'] ?? '').toString().trim();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _maintenanceSectionTitle(
                      'Client lié',
                      Icons.apartment_outlined,
                    ),
                    const SizedBox(height: 10),
                    if (companyId.isEmpty)
                      _maintenanceEmptyPane(
                        icon: Icons.link_off_outlined,
                        message:
                            'Ce technicien n\'a pas de companyId : impossible de lier un client.',
                      )
                    else
                      FutureBuilder<List<Map<String, dynamic>>>(
                        future: _clientsFuture ?? ApiService.getClients(),
                        builder: (context, snap) {
                          if (snap.connectionState == ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            );
                          }
                          if (snap.hasError) {
                            return Text(
                              'Clients: ${snap.error}',
                              style: GoogleFonts.inter(
                                color: alertColor,
                                fontSize: 12,
                              ),
                            );
                          }
                          final clients =
                              snap.data ?? const <Map<String, dynamic>>[];
                          final match = _findClientForTechnician(clients, tech);
                          if (match != null) {
                            return _maintenanceClientDetailCard(match);
                          }
                          return _maintenanceClientFallbackCard(companyId, '');
                        },
                      ),
                  ],
                );
              }

              Widget machinesColumn() {
                final selId = _selectedTechnicianId ?? '';
                if (selId.isEmpty) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _maintenanceSectionTitle(
                        'Machines',
                        Icons.precision_manufacturing_outlined,
                      ),
                      const SizedBox(height: 10),
                      _maintenanceEmptyPane(
                        icon: Icons.touch_app_outlined,
                        message:
                            'Sélectionnez un technicien pour lister les machines contrôlées.',
                      ),
                    ],
                  );
                }
                final tech = selectedTechnicianMap();
                final machines =
                    tech.isEmpty
                        ? const <Map<String, dynamic>>[]
                        : _machinesForAssignedMachineIds(tech);
                final label =
                    selectedName.isNotEmpty ? selectedName : 'Technicien';

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _maintenanceSectionTitle(
                            'Machines assignées',
                            Icons.precision_manufacturing_outlined,
                          ),
                        ),
                        if (machines.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: primaryColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${machines.length}',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: primaryColor,
                              ),
                            ),
                          ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 10),
                      child: Text(
                        'Pour $label',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: mutedTextColor,
                        ),
                      ),
                    ),
                    if (machines.isEmpty)
                      _maintenanceEmptyPane(
                        icon: Icons.build_outlined,
                        message:
                            'Aucune machine assignée à ce technicien dans la base.',
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: machines.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          final m = machines[i];
                          final mid = _machineIdOf(m);
                          final name = _machineNameOf(m);
                          final location = (m['location'] ?? '').toString();
                          final rawImg =
                              (m['imageUrl'] ?? m['image'] ?? '').toString();
                          final unresolved =
                              (m['_unresolvedMachineId'] ?? '').toString();
                          return InkWell(
                            onTap: () => _openMachineDetail(m),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: cardColor.withOpacity(0.55),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.08),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: SizedBox(
                                      width: 72,
                                      height: 56,
                                      child: _buildMachineImageWidget(
                                        rawImg,
                                        height: 56,
                                        width: 72,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.inter(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: textColor,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'ID: ${mid.isNotEmpty ? mid : unresolved}',
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            color: mutedTextColor,
                                          ),
                                        ),
                                        if (unresolved.isNotEmpty)
                                          Text(
                                            'Réf. base (absente du catalogue chargé)',
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              color: mutedTextColor.withOpacity(
                                                0.85,
                                              ),
                                            ),
                                          ),
                                        if (location.trim().isNotEmpty &&
                                            unresolved.isEmpty)
                                          Text(
                                            location,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              color: mutedTextColor,
                                            ),
                                          ),
                                        // ── Live telemetry state display ─────────────────────
                                        ValueListenableBuilder<int>(
                                          valueListenable: _telemetryTick,
                                          builder: (context, _, __) {
                                            final tel = _telemetryTick.value >= 0 ? _liveTelemetryByMachineId[mid] : null;
                                            if (tel == null) {
                                              return Container(
                                                margin: const EdgeInsets.only(top: 6),
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                                decoration: BoxDecoration(
                                                  color: Colors.white.withOpacity(0.04),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(Icons.sensors_off, color: Color(0xFF8A8AA1), size: 12),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      'Capteurs en attente…',
                                                      style: GoogleFonts.inter(color: const Color(0xFF8A8AA1), fontSize: 9),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }
                                            double? parseVal(dynamic v) {
                                              if (v == null) return null;
                                              if (v is num) return v.toDouble();
                                              return double.tryParse(v.toString());
                                            }
                                            final tempVal = parseVal(tel['temperature'] ?? tel['temp']);
                                            final vibVal = parseVal(tel['vibration']);
                                            final risk = _computeRiskFromTelemetry(tel);
                                            final Color stateColor = risk == 'DANGER'
                                                ? const Color(0xFFF44336)
                                                : risk == 'RISQUE'
                                                    ? const Color(0xFFFF9800)
                                                    : const Color(0xFF4CAF50);
                                            final IconData stateIcon = risk == 'DANGER'
                                                ? Icons.error_outline
                                                : risk == 'RISQUE'
                                                    ? Icons.warning_amber_rounded
                                                    : Icons.check_circle_outline;
                                            return Container(
                                              margin: const EdgeInsets.only(top: 6),
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: stateColor.withOpacity(0.08),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: stateColor.withOpacity(0.25)),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(stateIcon, color: stateColor, size: 12),
                                                      const SizedBox(width: 5),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: stateColor.withOpacity(0.15),
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                        child: Text(
                                                          risk,
                                                          style: GoogleFonts.spaceGrotesk(
                                                            color: stateColor,
                                                            fontSize: 8,
                                                            fontWeight: FontWeight.bold,
                                                            letterSpacing: 0.8,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Container(
                                                        width: 5, height: 5,
                                                        decoration: BoxDecoration(color: stateColor, shape: BoxShape.circle),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text('LIVE', style: GoogleFonts.inter(color: stateColor, fontSize: 7, fontWeight: FontWeight.bold)),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.thermostat_outlined, color: stateColor.withOpacity(0.7), size: 11),
                                                      const SizedBox(width: 3),
                                                      Text(
                                                        tempVal != null ? '${tempVal.toStringAsFixed(1)}°C' : '--',
                                                        style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Icon(Icons.vibration, color: stateColor.withOpacity(0.7), size: 11),
                                                      const SizedBox(width: 3),
                                                      Text(
                                                        vibVal != null ? '${vibVal.toStringAsFixed(1)} mm/s' : '--',
                                                        style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                );
              }

              Widget techniciansStackHeader() {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _maintenanceSectionTitle(
                      'Techniciens',
                      Icons.groups_3_outlined,
                    ),
                    const SizedBox(height: 10),
                    techniciansList(),
                  ],
                );
              }

              if (threeCol) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 292, child: techniciansStackHeader()),
                    const SizedBox(width: 16),
                    SizedBox(width: 320, child: clientColumn()),
                    const SizedBox(width: 16),
                    Expanded(child: machinesColumn()),
                  ],
                );
              }
              if (twoCol) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 280, child: techniciansStackHeader()),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          clientColumn(),
                          const SizedBox(height: 20),
                          machinesColumn(),
                        ],
                      ),
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  techniciansStackHeader(),
                  const SizedBox(height: 18),
                  clientColumn(),
                  const SizedBox(height: 18),
                  machinesColumn(),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMaintenanceAgentsPanel() {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1050;
    final threeCol = width >= 1240;
    final twoCol = width >= 900;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sidebarColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isMobileLayout(context))
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.build_circle_outlined,
                      color: primaryColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Agents maintenance',
                        style: GoogleFonts.spaceGrotesk(
                          color: textColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _maintenanceSearchController,
                  onChanged: (v) => setState(() => _maintenanceSearchQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Rechercher par nom, ID, email ou client...',
                    hintStyle: GoogleFonts.inter(
                      color: mutedTextColor.withOpacity(0.6),
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: cardColor,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  style: GoogleFonts.inter(color: textColor, fontSize: 13),
                ),
              ],
            )
          else
            Row(
              children: [
                const Icon(Icons.build_circle_outlined, color: primaryColor),
                const SizedBox(width: 8),
                Text(
                  'Agents maintenance',
                  style: GoogleFonts.spaceGrotesk(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: isDesktop ? 340 : 260,
                  child: TextField(
                    controller: _maintenanceSearchController,
                    onChanged:
                        (v) => setState(() => _maintenanceSearchQuery = v),
                    decoration: InputDecoration(
                      hintText: 'Rechercher par nom, ID, email ou client...',
                      hintStyle: GoogleFonts.inter(
                        color: mutedTextColor.withOpacity(0.6),
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: cardColor,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    style: GoogleFonts.inter(color: textColor, fontSize: 13),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 16),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _maintenanceAgentsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Erreur chargement agents maintenance: ${snapshot.error}',
                    style: GoogleFonts.inter(color: alertColor),
                  ),
                );
              }

              final allAgents = snapshot.data ?? const <Map<String, dynamic>>[];
              final q = _maintenanceSearchQuery.toLowerCase().trim();

              final filtered =
                  allAgents.where((a) {
                    if (q.isEmpty) return true;
                    final id = _maintenanceAgentIdOf(a).toLowerCase();
                    final name = _maintenanceAgentNameOf(a).toLowerCase();
                    final email = (a['email'] ?? '').toString().toLowerCase();
                    final clientName =
                        (a['clientName'] ?? '').toString().toLowerCase();
                    final clientId =
                        (a['clientId'] ?? '').toString().toLowerCase();
                    return id.contains(q) ||
                        name.contains(q) ||
                        email.contains(q) ||
                        clientName.contains(q) ||
                        clientId.contains(q);
                  }).toList();

              if (filtered.isEmpty) {
                return Text(
                  'Aucun agent de maintenance trouvé.',
                  style: GoogleFonts.inter(color: mutedTextColor),
                );
              }

              final selectedName =
                  _selectedMaintenanceAgentId == null
                      ? ''
                      : _maintenanceAgentNameOf(
                        allAgents.firstWhere(
                          (a) =>
                              _maintenanceAgentIdOf(a) ==
                              _selectedMaintenanceAgentId,
                          orElse: () => filtered.first,
                        ),
                      );

              Widget agentsList() {
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final a = filtered[i];
                    final aid = _maintenanceAgentIdOf(a);
                    final selected =
                        aid.isNotEmpty && aid == _selectedMaintenanceAgentId;
                    return Container(
                      decoration: BoxDecoration(
                        color:
                            selected
                                ? primaryColor.withOpacity(0.08)
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color:
                              selected
                                  ? primaryColor.withOpacity(0.45)
                                  : Colors.white.withOpacity(0.06),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          InkWell(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(11),
                            ),
                            onTap: () {
                              if (aid.isEmpty) return;
                              setState(() => _selectedMaintenanceAgentId = aid);
                            },
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: primaryColor.withOpacity(
                                      0.12,
                                    ),
                                    child: Icon(
                                      Icons.handyman_outlined,
                                      color: primaryColor,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _maintenanceAgentNameOf(a),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color:
                                                selected
                                                    ? primaryColor
                                                    : textColor,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'ID: $aid',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            color: mutedTextColor,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Gmail: ${((a['email'] ?? '').toString().trim().isEmpty) ? '—' : (a['email'] ?? '').toString()}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            color: mutedTextColor.withOpacity(
                                              0.9,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          _catalogEditDeleteRow(
                            onEdit: () => _openEditMaintenanceAgent(a),
                            onDelete: () => _deleteMaintenanceAgentEntity(a),
                          ),
                        ],
                      ),
                    );
                  },
                );
              }

              Map<String, dynamic> selectedAgentMap() {
                final selId = _selectedMaintenanceAgentId ?? '';
                if (selId.isEmpty) return {};
                return allAgents.firstWhere(
                  (x) => _maintenanceAgentIdOf(x) == selId,
                  orElse: () => <String, dynamic>{},
                );
              }

              Widget clientColumn() {
                final selId = _selectedMaintenanceAgentId ?? '';
                if (selId.isEmpty) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _maintenanceSectionTitle(
                        'Client lié',
                        Icons.apartment_outlined,
                      ),
                      const SizedBox(height: 10),
                      _maintenanceEmptyPane(
                        icon: Icons.person_search_outlined,
                        message:
                            'Sélectionnez un agent pour afficher la fiche client.',
                      ),
                    ],
                  );
                }
                final agent = selectedAgentMap();
                if (agent.isEmpty) {
                  return const SizedBox.shrink();
                }
                final cid = (agent['clientId'] ?? '').toString().trim();
                final cname = (agent['clientName'] ?? '').toString().trim();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _maintenanceSectionTitle(
                      'Client lié',
                      Icons.apartment_outlined,
                    ),
                    const SizedBox(height: 10),
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _clientsFuture ?? ApiService.getClients(),
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        }
                        if (snap.hasError) {
                          return Text(
                            'Clients: ${snap.error}',
                            style: GoogleFonts.inter(
                              color: alertColor,
                              fontSize: 12,
                            ),
                          );
                        }
                        final clients =
                            snap.data ?? const <Map<String, dynamic>>[];
                        final match = _findClientForMaintenanceAgent(
                          clients,
                          cid,
                          cname,
                        );
                        if (match != null) {
                          return _maintenanceClientDetailCard(match);
                        }
                        return _maintenanceClientFallbackCard(cid, cname);
                      },
                    ),
                  ],
                );
              }

              Widget machinesColumn() {
                final selId = _selectedMaintenanceAgentId ?? '';
                if (selId.isEmpty) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _maintenanceSectionTitle(
                        'Machines',
                        Icons.precision_manufacturing_outlined,
                      ),
                      const SizedBox(height: 10),
                      _maintenanceEmptyPane(
                        icon: Icons.touch_app_outlined,
                        message:
                            'Sélectionnez un agent pour lister les machines assignées.',
                      ),
                    ],
                  );
                }
                final agent = selectedAgentMap();
                final machines =
                    agent.isEmpty
                        ? const <Map<String, dynamic>>[]
                        : _machinesForAssignedMachineIds(agent);
                final label = selectedName.isNotEmpty ? selectedName : 'Agent';

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _maintenanceSectionTitle(
                            'Machines assignées',
                            Icons.precision_manufacturing_outlined,
                          ),
                        ),
                        if (machines.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: primaryColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${machines.length}',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: primaryColor,
                              ),
                            ),
                          ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 10),
                      child: Text(
                        'Pour $label',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: mutedTextColor,
                        ),
                      ),
                    ),
                    if (machines.isEmpty)
                      _maintenanceEmptyPane(
                        icon: Icons.build_outlined,
                        message:
                            'Aucune machine assignée à cet agent dans la base.',
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: machines.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          final m = machines[i];
                          final mid = _machineIdOf(m);
                          final name = _machineNameOf(m);
                          final location = (m['location'] ?? '').toString();
                          final rawImg =
                              (m['imageUrl'] ?? m['image'] ?? '').toString();
                          final unresolved =
                              (m['_unresolvedMachineId'] ?? '').toString();
                          return InkWell(
                            onTap: () => _openMachineDetail(m),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: cardColor.withOpacity(0.55),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.08),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: SizedBox(
                                      width: 72,
                                      height: 56,
                                      child: _buildMachineImageWidget(
                                        rawImg,
                                        height: 56,
                                        width: 72,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.inter(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: textColor,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'ID: ${mid.isNotEmpty ? mid : unresolved}',
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            color: mutedTextColor,
                                          ),
                                        ),
                                        if (unresolved.isNotEmpty)
                                          Text(
                                            'Réf. base (absente du catalogue chargé)',
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              color: mutedTextColor.withOpacity(
                                                0.85,
                                              ),
                                            ),
                                          ),
                                        if (location.trim().isNotEmpty &&
                                            unresolved.isEmpty)
                                          Text(
                                            location,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              color: mutedTextColor,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                );
              }

              Widget agentsStackHeader() {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _maintenanceSectionTitle('Agents', Icons.groups_3_outlined),
                    const SizedBox(height: 10),
                    agentsList(),
                  ],
                );
              }

              if (threeCol) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 292, child: agentsStackHeader()),
                    const SizedBox(width: 16),
                    SizedBox(width: 320, child: clientColumn()),
                    const SizedBox(width: 16),
                    Expanded(child: machinesColumn()),
                  ],
                );
              }
              if (twoCol) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 280, child: agentsStackHeader()),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          clientColumn(),
                          const SizedBox(height: 20),
                          machinesColumn(),
                        ],
                      ),
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  agentsStackHeader(),
                  const SizedBox(height: 18),
                  clientColumn(),
                  const SizedBox(height: 18),
                  machinesColumn(),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPurchaseRequestsPanel() {
    final isCompact = MediaQuery.of(context).size.width < 720;
    final purchaseOnly =
        _purchaseRequests.where((r) {
          final type = (r['requestType'] ?? '').toString().toUpperCase();
          return type != 'TECHNICIAN_ADD' && type != 'MAINTENANCE_ADD';
        }).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sidebarColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          isCompact
              ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.shopping_cart_checkout,
                        color: primaryColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Demandes d\'achat',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.spaceGrotesk(
                            color: textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: _loadingRequests ? null : _fetchPurchaseRequests,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Actualiser'),
                  ),
                ],
              )
              : Row(
                children: [
                  const Icon(Icons.shopping_cart_checkout, color: primaryColor),
                  const SizedBox(width: 8),
                  Text(
                    'Demandes d\'achat',
                    style: GoogleFonts.spaceGrotesk(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _loadingRequests ? null : _fetchPurchaseRequests,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Actualiser'),
                  ),
                ],
              ),
          const SizedBox(height: 8),
          if (_loadingRequests)
            const Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (purchaseOnly.isEmpty)
            Text(
              'Aucune demande d\'achat en attente.',
              style: GoogleFonts.inter(color: mutedTextColor),
            )
          else ...[
            ...(_showAllPurchaseRequests ? purchaseOnly : purchaseOnly.take(3)).map((
              r,
            ) {
              final status = (r['status'] ?? 'PENDING').toString();
              final pending = status == 'PENDING';
              final reqId = (r['id'] ?? r['_id'] ?? '').toString();
              final viewed =
                  reqId.isNotEmpty && _reviewedRequestIds.contains(reqId);
              return Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    isCompact
                        ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${r['requesterName'] ?? 'Client'} • ${(r['machineName'] ?? r['machineId'] ?? '').toString()}',
                              style: GoogleFonts.inter(
                                color: textColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Localisation: ${(r['googleMapsUrl'] ?? r['location'] ?? '—').toString()}',
                              style: GoogleFonts.inter(
                                color: mutedTextColor,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                _statusBadge(
                                  status,
                                  status == 'VALIDATED'
                                      ? successColor
                                      : (status == 'REJECTED'
                                          ? alertColor
                                          : primaryColor),
                                ),
                                if (pending)
                                  OutlinedButton(
                                    onPressed:
                                        () =>
                                            _showPurchaseRequestMachinePreview(
                                              r,
                                            ),
                                    child: const Text('Voir'),
                                  ),
                              ],
                            ),
                          ],
                        )
                        : Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${r['requesterName'] ?? 'Client'} • ${(r['machineName'] ?? r['machineId'] ?? '').toString()}',
                                    style: GoogleFonts.inter(
                                      color: textColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Localisation: ${(r['googleMapsUrl'] ?? r['location'] ?? '—').toString()}',
                                    style: GoogleFonts.inter(
                                      color: mutedTextColor,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _statusBadge(
                              status,
                              status == 'VALIDATED'
                                  ? successColor
                                  : (status == 'REJECTED'
                                      ? alertColor
                                      : primaryColor),
                            ),
                            const SizedBox(width: 8),
                            if (pending)
                              OutlinedButton(
                                onPressed:
                                    () => _showPurchaseRequestMachinePreview(r),
                                child: const Text('Voir'),
                              ),
                          ],
                        ),
              );
            }),
            if (purchaseOnly.length > 3)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed:
                      () => setState(
                        () =>
                            _showAllPurchaseRequests =
                                !_showAllPurchaseRequests,
                      ),
                  child: Text(
                    _showAllPurchaseRequests ? 'Voir moins' : 'Voir plus',
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildTechnicianAddRequestsPanel() {
    final isCompact = MediaQuery.of(context).size.width < 720;
    final technicianRequests =
        _purchaseRequests.where((r) {
          final type = (r['requestType'] ?? '').toString().toUpperCase();
          return type == 'TECHNICIAN_ADD' || type == 'MAINTENANCE_ADD';
        }).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sidebarColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          isCompact
              ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.engineering_rounded,
                        color: primaryColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Demandes équipe terrain',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.spaceGrotesk(
                            color: textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (technicianRequests
                          .where(
                            (r) =>
                                (r['status'] ?? 'PENDING').toString() ==
                                'PENDING',
                          )
                          .isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: primaryColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: primaryColor.withOpacity(0.4),
                            ),
                          ),
                          child: Text(
                            '${technicianRequests.where((r) => (r['status'] ?? 'PENDING').toString() == 'PENDING').length} en attente',
                            style: GoogleFonts.spaceGrotesk(
                              color: primaryColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: _loadingRequests ? null : _fetchPurchaseRequests,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Actualiser'),
                  ),
                ],
              )
              : Row(
                children: [
                  const Icon(Icons.engineering_rounded, color: primaryColor),
                  const SizedBox(width: 8),
                  Text(
                    'Demandes équipe terrain',
                    style: GoogleFonts.spaceGrotesk(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (technicianRequests
                      .where(
                        (r) =>
                            (r['status'] ?? 'PENDING').toString() == 'PENDING',
                      )
                      .isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: primaryColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: primaryColor.withOpacity(0.4),
                        ),
                      ),
                      child: Text(
                        '${technicianRequests.where((r) => (r['status'] ?? 'PENDING').toString() == 'PENDING').length} en attente',
                        style: GoogleFonts.spaceGrotesk(
                          color: primaryColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _loadingRequests ? null : _fetchPurchaseRequests,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Actualiser'),
                  ),
                ],
              ),
          const SizedBox(height: 8),
          if (_loadingRequests)
            const Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (technicianRequests.isEmpty)
            Text(
              'Aucune demande d\'ajout (technicien / maintenance).',
              style: GoogleFonts.inter(color: mutedTextColor),
            )
          else ...[
            ...(_showAllTechnicianRequests
                    ? technicianRequests
                    : technicianRequests.take(3))
                .map((r) {
                  final status = (r['status'] ?? 'PENDING').toString();
                  final pending = status == 'PENDING';
                  final metadataRaw = r['metadata'];
                  final metadata =
                      metadataRaw is Map
                          ? Map<String, dynamic>.from(metadataRaw)
                          : <String, dynamic>{};
                  final reqType =
                      (r['requestType'] ?? 'TECHNICIAN_ADD')
                          .toString()
                          .toUpperCase();
                  final isMaintenanceReq = reqType == 'MAINTENANCE_ADD';
                  final roleLabel =
                      isMaintenanceReq ? 'Maintenance' : 'Technicien';
                  final specialization =
                      (metadata['specialization'] ??
                              (isMaintenanceReq
                                  ? 'Maintenance opérationnelle'
                                  : 'Maintenance terrain'))
                          .toString();
                  final clientLabel =
                      (r['linkedClientId'] ?? r['clientId'] ?? '—').toString();
                  return Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child:
                        isCompact
                            ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${r['requesterName'] ?? roleLabel} • $specialization',
                                  style: GoogleFonts.inter(
                                    color: textColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Email: ${(r['requesterEmail'] ?? '—').toString()}',
                                  style: GoogleFonts.inter(
                                    color: mutedTextColor,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  'Client: $clientLabel  •  Localisation: ${(r['location'] ?? '—').toString()}',
                                  style: GoogleFonts.inter(
                                    color: mutedTextColor,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    _statusBadge(
                                      status,
                                      status == 'VALIDATED'
                                          ? successColor
                                          : (status == 'REJECTED'
                                              ? alertColor
                                              : primaryColor),
                                    ),
                                    if (pending)
                                      TextButton(
                                        onPressed: () => _rejectRequest(r),
                                        child: const Text('Rejeter'),
                                      ),
                                    if (pending)
                                      ElevatedButton.icon(
                                        onPressed:
                                            () =>
                                                isMaintenanceReq
                                                    ? _validateMaintenanceAddRequest(
                                                      r,
                                                    )
                                                    : _validateTechnicianAddRequest(
                                                      r,
                                                    ),
                                        icon: const Icon(
                                          Icons.check_circle_outline,
                                          size: 16,
                                        ),
                                        label: const Text('Valider'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: primaryColor,
                                          foregroundColor: Colors.black,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            )
                            : Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${r['requesterName'] ?? roleLabel} • $specialization',
                                        style: GoogleFonts.inter(
                                          color: textColor,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Email: ${(r['requesterEmail'] ?? '—').toString()}',
                                        style: GoogleFonts.inter(
                                          color: mutedTextColor,
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        'Client: $clientLabel  •  Localisation: ${(r['location'] ?? '—').toString()}',
                                        style: GoogleFonts.inter(
                                          color: mutedTextColor,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                _statusBadge(
                                  status,
                                  status == 'VALIDATED'
                                      ? successColor
                                      : (status == 'REJECTED'
                                          ? alertColor
                                          : primaryColor),
                                ),
                                const SizedBox(width: 8),
                                if (pending)
                                  TextButton(
                                    onPressed: () => _rejectRequest(r),
                                    child: const Text('Rejeter'),
                                  ),
                                if (pending) const SizedBox(width: 8),
                                if (pending)
                                  ElevatedButton.icon(
                                    onPressed:
                                        () =>
                                            isMaintenanceReq
                                                ? _validateMaintenanceAddRequest(
                                                  r,
                                                )
                                                : _validateTechnicianAddRequest(
                                                  r,
                                                ),
                                    icon: const Icon(
                                      Icons.check_circle_outline,
                                      size: 16,
                                    ),
                                    label: const Text('Valider'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: primaryColor,
                                      foregroundColor: Colors.black,
                                    ),
                                  ),
                              ],
                            ),
                  );
                }),
            if (technicianRequests.length > 3)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed:
                      () => setState(
                        () =>
                            _showAllTechnicianRequests =
                                !_showAllTechnicianRequests,
                      ),
                  child: Text(
                    _showAllTechnicianRequests ? 'Voir moins' : 'Voir plus',
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: sidebarColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.search_off,
            color: mutedTextColor.withOpacity(0.3),
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            'Aucune machine trouvée',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 20,
              color: mutedTextColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Essayez de modifier vos filtres ou votre recherche.',
            style: GoogleFonts.inter(color: mutedTextColor.withOpacity(0.7)),
          ),
        ],
      ),
    );
  }

  Widget _buildTopNavigation() {
    final isCompact = MediaQuery.of(context).size.width < 980;
    return Container(
      height: isCompact ? 84 : 92,
      color: sidebarColor,
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 12 : 24),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pushReplacementNamed(context, '/'),
            child: Container(
              height: 44,
              constraints: const BoxConstraints(maxWidth: 160),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Image.asset(
                'assets/images/abbk_logo.png',
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
          SizedBox(width: isCompact ? 10 : 24),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _topNavItem(Icons.grid_view_rounded, 'DASHBOARD'),
                  _topNavItem(Icons.person_outline_rounded, 'PROFILE'),
                  _topNavItem(Icons.account_tree_outlined, 'CLIENT CATALOG'),
                  _topNavItem(Icons.menu_book_rounded, 'PROJET'),
                  _topNavItem(Icons.chat_bubble_outline_rounded, 'MESSAGERIE'),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          _buildActionIcons(),
        ],
      ),
    );
  }

  Widget _buildActionIcons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          children: [
            IconButton(
              onPressed: _showMachineNotificationsDialog,
              icon: const Icon(
                Icons.notifications_outlined,
                color: Colors.white,
              ),
            ),
            if (_unreadMachineNotifications > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: primaryColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(minWidth: 16),
                  child: Text(
                    _unreadMachineNotifications > 99
                        ? '99+'
                        : _unreadMachineNotifications.toString(),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: Colors.black,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: () {
            ApiService.clearAuth();
            Navigator.of(context).pushReplacementNamed('/');
          },
          icon: const Icon(Icons.logout_rounded, color: alertColor, size: 20),
        ),
      ],
    );
  }

  Widget _topNavItem(IconData icon, String title) {
    bool isSelected = selectedMenu == title;
    String displayTitle = title;
    if (title == 'DASHBOARD') {
      displayTitle = 'TABLEAU DE BORD';
    } else if (title == 'PROFILE') {
      displayTitle = 'PROFIL';
    } else if (title == 'CLIENT CATALOG') {
      displayTitle = 'CATALOGUE CLIENTS';
    } else if (title == 'PROJET') {
      displayTitle = 'PROJET';
    } else if (title == 'MESSAGERIE' || title == 'SETTINGS') {
      displayTitle = 'MESSAGERIE';
    }

    return InkWell(
      onTap: () => _onSidebarSelect(title),
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(
            color:
                isSelected
                    ? primaryColor.withOpacity(0.6)
                    : Colors.white.withOpacity(0.08),
          ),
          borderRadius: BorderRadius.circular(10),
          color:
              isSelected ? primaryColor.withOpacity(0.05) : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? primaryColor : mutedTextColor,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              displayTitle,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? primaryColor : mutedTextColor,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCard() {
    return const SizedBox.shrink();
  }

  // ignore: unused_element
  Widget _buildUserCardOld() {
    final role = (ApiService.savedUserRole ?? 'Concepteur').toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: cardColor.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _profileAvatar(16),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _profileDisplayName,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                role,
                style: GoogleFonts.inter(
                  fontSize: 9,
                  color: mutedTextColor,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProfilePanel() {
    final role = (ApiService.savedUserRole ?? 'Concepteur').toUpperCase();
    String pickProfileValue(List<String> keys) {
      for (final k in keys) {
        final v = (_concepteurProfileData[k] ?? '').toString().trim();
        if (v.isNotEmpty) return v;
      }
      return '';
    }

    final email = pickProfileValue(const ['email', 'mail']);
    final phone = pickProfileValue(const [
      'phone',
      'telephone',
      'mobile',
      'phoneNumber',
    ]);
    final company = pickProfileValue(const [
      'companyName',
      'company',
      'organization',
      'clientName',
    ]);
    final concepteurId =
        _concepteurProfileId.isNotEmpty
            ? _concepteurProfileId
            : pickProfileValue(const ['concepteurId', 'id', '_id', 'userId']);
    final speciality = pickProfileValue(const [
      'speciality',
      'specialty',
      'specialite',
      'poste',
      'title',
      'jobTitle',
    ]);
    final address = pickProfileValue(const ['address', 'adresse', 'street']);
    final city = pickProfileValue(const ['city', 'ville']);
    final country = pickProfileValue(const ['country', 'pays']);
    final status = pickProfileValue(const ['status', 'statut']);
    final websiteUrl = pickProfileValue(const [
      'websiteUrl',
      'siteWeb',
      'website',
      'url',
    ]);
    final profileUrl = pickProfileValue(const [
      'profileUrl',
      'linkedinUrl',
      'portfolioUrl',
    ]);

    final isCompact = MediaQuery.of(context).size.width < 900;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---- Avatar with upload button ----
              GestureDetector(
                onTap: () async {
                  final dataUrl = await _pickImageAsDataUrl();
                  if (dataUrl == null || dataUrl.isEmpty || !mounted) return;
                  final normalized = _normalizeProfilePhotoUrl(dataUrl);
                  setState(() => _profilePhotoUrl = normalized);
                  try {
                    await ApiService.updateMyConcepteurProfile({
                      'imageUrl': normalized,
                    });
                  } catch (_) {}
                },
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 46,
                      backgroundColor: cardColor,
                      backgroundImage:
                          _profilePhotoUrl.isNotEmpty
                              ? (_profilePhotoUrl.toLowerCase().startsWith(
                                        'data:image/',
                                      )
                                      ? MemoryImage(
                                        Uri.parse(
                                          _profilePhotoUrl,
                                        ).data!.contentAsBytes(),
                                      )
                                      : NetworkImage(
                                        ApiService.fullUrl(_profilePhotoUrl),
                                      ))
                                  as ImageProvider
                              : null,
                      child:
                          _profilePhotoUrl.isEmpty
                              ? Icon(
                                Icons.person_outline,
                                size: 46,
                                color: mutedTextColor,
                              )
                              : null,
                    ),
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: primaryColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: cardColor, width: 2),
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        size: 14,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: isCompact ? double.infinity : 420,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_profileLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(
                          color: primaryColor,
                          backgroundColor: Colors.white10,
                        ),
                      ),
                    if (_profileLoadError != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _profileLoadError!,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: alertColor,
                          ),
                        ),
                      ),
                    Text(
                      _profileDisplayName.isNotEmpty
                          ? _profileDisplayName
                          : 'Concepteur',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        if (concepteurId.isNotEmpty)
                          _profileInfoChip('ID', concepteurId),
                        if (email.isNotEmpty) _profileInfoChip('Email', email),
                        if (phone.isNotEmpty) _profileInfoChip('Tel', phone),
                        if (company.isNotEmpty)
                          _profileInfoChip('Societe', company),
                        if (speciality.isNotEmpty)
                          _profileInfoChip('Specialite', speciality),
                        if (address.isNotEmpty)
                          _profileInfoChip('Adresse', address),
                        if (city.isNotEmpty) _profileInfoChip('Ville', city),
                        if (country.isNotEmpty)
                          _profileInfoChip('Pays', country),
                        if (status.isNotEmpty)
                          _profileInfoChip('Statut', status),
                        if (websiteUrl.isNotEmpty)
                          _profileInfoChip('Site web', websiteUrl),
                        if (profileUrl.isNotEmpty)
                          _profileInfoChip('Profil URL', profileUrl),
                      ],
                    ),
                    OutlinedButton.icon(
                      onPressed: _showEditProfileDialog,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('MODIFIER LE PROFIL'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: Colors.white.withOpacity(0.25)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        textStyle: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                if (_profileExpandedFilter == 'public') {
                                  _profileExpandedFilter = null;
                                } else {
                                  _profileExpandedFilter = 'public';
                                }
                              });
                            },
                            icon: Icon(
                              _profileExpandedFilter == 'public'
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              size: 18,
                            ),
                            label: Text('Machine publique ($_publishedCount)'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E293B),
                              foregroundColor: primaryColor,
                              side: BorderSide(
                                color: _profileExpandedFilter == 'public'
                                    ? primaryColor
                                    : const Color(0x33FF9F64),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              textStyle: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                if (_profileExpandedFilter == 'private') {
                                  _profileExpandedFilter = null;
                                } else {
                                  _profileExpandedFilter = 'private';
                                }
                              });
                            },
                            icon: Icon(
                              _profileExpandedFilter == 'private'
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              size: 18,
                            ),
                            label: Text('Machine no public ($_notPublishedCount)'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E293B),
                              foregroundColor: mutedTextColor,
                              side: BorderSide(
                                color: _profileExpandedFilter == 'private'
                                    ? primaryColor
                                    : const Color(0x22FFFFFF),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              textStyle: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_profileExpandedFilter != null) ...[
          const SizedBox(height: 24),
          Row(
            children: [
              Icon(
                _profileExpandedFilter == 'public' ? Icons.public : Icons.public_off,
                color: primaryColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                _profileExpandedFilter == 'public'
                    ? 'LISTE DES MACHINES PUBLIQUES'
                    : 'LISTE DES MACHINES NON PUBLIQUES',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildProfileMachinesList(),
        ],
      ],
    );
  }

  Widget _buildProfileMachinesList() {
    final isPublicFilter = _profileExpandedFilter == 'public';
    final list = _allMachines.where((m) {
      final isPublic = m['isPublic'] == true;
      return isPublicFilter ? isPublic : !isPublic;
    }).toList();

    if (list.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        alignment: Alignment.center,
        child: Text(
          'Aucune machine dans cette catégorie.',
          style: GoogleFonts.inter(color: mutedTextColor),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = 3;
        if (constraints.maxWidth < 600) {
          crossAxisCount = 1;
        } else if (constraints.maxWidth < 1000) {
          crossAxisCount = 2;
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 0.58,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: list.length,
          itemBuilder: (context, index) => _buildMachineGalleryCard(list[index]),
        );
      },
    );
  }

  Widget _profileInfoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: sidebarColor.withOpacity(0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      ),
      child: Text(
        '$label: $value',
        style: GoogleFonts.inter(
          fontSize: 11,
          color: Colors.white.withOpacity(0.92),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _profileInfoRow(String label, String value) {
    final v = value.trim();
    if (v.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.inter(fontSize: 12, color: mutedTextColor),
          children: [
            TextSpan(
              text: '$label: ',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: textColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(text: v),
          ],
        ),
      ),
    );
  }

  Widget _profileAvatar(double radius) {
    final normalized = _normalizeProfilePhotoUrl(_profilePhotoUrl);
    final effectiveUrl =
        normalized.isEmpty ? _defaultProfilePhotoUrl : normalized;
    if (normalized.toLowerCase().startsWith('data:image/')) {
      try {
        final bytes = base64Decode(normalized.split(',').last);
        return CircleAvatar(
          radius: radius,
          backgroundColor: sidebarColor,
          child: ClipOval(
            child: Image.memory(
              bytes,
              width: radius * 2,
              height: radius * 2,
              fit: BoxFit.cover,
              errorBuilder:
                  (_, __, ___) =>
                      Icon(Icons.person, color: mutedTextColor, size: radius),
            ),
          ),
        );
      } catch (_) {}
    }
    final urlCandidates = <String>[
      effectiveUrl,
      // Proxy utile quand certaines sources externes refusent l'affichage direct.
      if (effectiveUrl.contains('pinimg.com'))
        'https://images.weserv.nl/?url=${Uri.encodeComponent(effectiveUrl.replaceFirst(RegExp(r'^https?://'), ''))}',
      'https://i.pravatar.cc/200?u=profile-fallback',
    ];

    Widget buildNetworkCandidate(int index) {
      if (index >= urlCandidates.length) {
        return Icon(Icons.person, color: mutedTextColor, size: radius);
      }
      return Image.network(
        urlCandidates[index],
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => buildNetworkCandidate(index + 1),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: sidebarColor,
      child: ClipOval(child: buildNetworkCandidate(0)),
    );
  }

  Future<void> _showEditProfileDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: _profileDisplayName);
    final urlController = TextEditingController(text: _profilePhotoUrl);
    final emailController = TextEditingController(
      text:
          (_concepteurProfileData['email'] ??
                  _concepteurProfileData['mail'] ??
                  '')
              .toString(),
    );
    final phoneController = TextEditingController(
      text:
          (_concepteurProfileData['phone'] ??
                  _concepteurProfileData['telephone'] ??
                  _concepteurProfileData['mobile'] ??
                  _concepteurProfileData['phoneNumber'] ??
                  '')
              .toString(),
    );
    final companyController = TextEditingController(
      text:
          (_concepteurProfileData['companyName'] ??
                  _concepteurProfileData['company'] ??
                  _concepteurProfileData['organization'] ??
                  _concepteurProfileData['clientName'] ??
                  '')
              .toString(),
    );
    final specialityController = TextEditingController(
      text:
          (_concepteurProfileData['speciality'] ??
                  _concepteurProfileData['specialty'] ??
                  _concepteurProfileData['specialite'] ??
                  _concepteurProfileData['poste'] ??
                  _concepteurProfileData['title'] ??
                  _concepteurProfileData['jobTitle'] ??
                  '')
              .toString(),
    );
    final addressController = TextEditingController(
      text:
          (_concepteurProfileData['address'] ??
                  _concepteurProfileData['adresse'] ??
                  _concepteurProfileData['street'] ??
                  '')
              .toString(),
    );
    final cityController = TextEditingController(
      text:
          (_concepteurProfileData['city'] ??
                  _concepteurProfileData['ville'] ??
                  '')
              .toString(),
    );
    final countryController = TextEditingController(
      text:
          (_concepteurProfileData['country'] ??
                  _concepteurProfileData['pays'] ??
                  '')
              .toString(),
    );
    final statusController = TextEditingController(
      text:
          (_concepteurProfileData['status'] ??
                  _concepteurProfileData['statut'] ??
                  '')
              .toString(),
    );
    final websiteUrlController = TextEditingController(
      text:
          (_concepteurProfileData['websiteUrl'] ??
                  _concepteurProfileData['siteWeb'] ??
                  _concepteurProfileData['website'] ??
                  _concepteurProfileData['url'] ??
                  '')
              .toString(),
    );
    final profileUrlController = TextEditingController(
      text:
          (_concepteurProfileData['profileUrl'] ??
                  _concepteurProfileData['linkedinUrl'] ??
                  _concepteurProfileData['portfolioUrl'] ??
                  '')
              .toString(),
    );
    await showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: sidebarColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.white.withOpacity(0.08)),
            ),
            title: Text(
              'Modifier le profil',
              style: GoogleFonts.spaceGrotesk(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            content: SizedBox(
              width: 430,
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: nameController,
                          style: GoogleFonts.inter(color: Colors.white),
                          validator:
                              (v) => FormValidators.nom(
                                v,
                                required: true,
                                label: 'Nom affiché',
                              ),
                          decoration: InputDecoration(
                            labelText: 'Nom affiché *',
                            labelStyle: GoogleFonts.inter(
                              color: mutedTextColor,
                            ),
                            errorStyle: GoogleFonts.inter(
                              color: alertColor,
                              fontSize: 11,
                            ),
                            filled: true,
                            fillColor: cardColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: emailController,
                          style: GoogleFonts.inter(color: Colors.white),
                          validator: (v) => FormValidators.email(v),
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: 'Email',
                            hintText: 'nom@domaine.com',
                            labelStyle: GoogleFonts.inter(
                              color: mutedTextColor,
                            ),
                            hintStyle: GoogleFonts.inter(color: mutedTextColor),
                            errorStyle: GoogleFonts.inter(
                              color: alertColor,
                              fontSize: 11,
                            ),
                            filled: true,
                            fillColor: cardColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: phoneController,
                          style: GoogleFonts.inter(color: Colors.white),
                          validator: (v) => FormValidators.phone(v),
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            labelText: 'Téléphone',
                            hintText: '+216 20 000 000',
                            labelStyle: GoogleFonts.inter(
                              color: mutedTextColor,
                            ),
                            hintStyle: GoogleFonts.inter(color: mutedTextColor),
                            errorStyle: GoogleFonts.inter(
                              color: alertColor,
                              fontSize: 11,
                            ),
                            filled: true,
                            fillColor: cardColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: companyController,
                          style: GoogleFonts.inter(color: Colors.white),
                          validator:
                              (v) => FormValidators.text(
                                v,
                                max: 150,
                                label: 'Société',
                              ),
                          decoration: InputDecoration(
                            labelText: 'Société',
                            labelStyle: GoogleFonts.inter(
                              color: mutedTextColor,
                            ),
                            errorStyle: GoogleFonts.inter(
                              color: alertColor,
                              fontSize: 11,
                            ),
                            filled: true,
                            fillColor: cardColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: specialityController,
                          style: GoogleFonts.inter(color: Colors.white),
                          validator:
                              (v) => FormValidators.text(
                                v,
                                max: 150,
                                label: 'Spécialité',
                              ),
                          decoration: InputDecoration(
                            labelText: 'Spécialité',
                            labelStyle: GoogleFonts.inter(
                              color: mutedTextColor,
                            ),
                            errorStyle: GoogleFonts.inter(
                              color: alertColor,
                              fontSize: 11,
                            ),
                            filled: true,
                            fillColor: cardColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: urlController,
                          style: GoogleFonts.inter(color: Colors.white),
                          validator: (v) => FormValidators.photoUrl(v),
                          decoration: InputDecoration(
                            labelText: 'URL photo',
                            hintText: 'https://...',
                            labelStyle: GoogleFonts.inter(
                              color: mutedTextColor,
                            ),
                            hintStyle: GoogleFonts.inter(color: mutedTextColor),
                            errorStyle: GoogleFonts.inter(
                              color: alertColor,
                              fontSize: 11,
                            ),
                            filled: true,
                            fillColor: cardColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: websiteUrlController,
                          style: GoogleFonts.inter(color: Colors.white),
                          validator:
                              (v) =>
                                  FormValidators.url(v, label: 'URL site web'),
                          keyboardType: TextInputType.url,
                          decoration: InputDecoration(
                            labelText: 'URL site web',
                            hintText: 'https://monsite.com',
                            labelStyle: GoogleFonts.inter(
                              color: mutedTextColor,
                            ),
                            hintStyle: GoogleFonts.inter(color: mutedTextColor),
                            errorStyle: GoogleFonts.inter(
                              color: alertColor,
                              fontSize: 11,
                            ),
                            filled: true,
                            fillColor: cardColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: profileUrlController,
                          style: GoogleFonts.inter(color: Colors.white),
                          validator:
                              (v) => FormValidators.url(v, label: 'URL profil'),
                          keyboardType: TextInputType.url,
                          decoration: InputDecoration(
                            labelText: 'URL profil (LinkedIn/Portfolio)',
                            hintText: 'https://...',
                            labelStyle: GoogleFonts.inter(
                              color: mutedTextColor,
                            ),
                            hintStyle: GoogleFonts.inter(color: mutedTextColor),
                            errorStyle: GoogleFonts.inter(
                              color: alertColor,
                              fontSize: 11,
                            ),
                            filled: true,
                            fillColor: cardColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: addressController,
                          style: GoogleFonts.inter(color: Colors.white),
                          validator:
                              (v) => FormValidators.text(
                                v,
                                max: 255,
                                label: 'Adresse',
                              ),
                          decoration: InputDecoration(
                            labelText: 'Adresse',
                            labelStyle: GoogleFonts.inter(
                              color: mutedTextColor,
                            ),
                            errorStyle: GoogleFonts.inter(
                              color: alertColor,
                              fontSize: 11,
                            ),
                            filled: true,
                            fillColor: cardColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: cityController,
                          style: GoogleFonts.inter(color: Colors.white),
                          validator:
                              (v) => FormValidators.text(
                                v,
                                max: 100,
                                label: 'Ville',
                              ),
                          decoration: InputDecoration(
                            labelText: 'Ville',
                            labelStyle: GoogleFonts.inter(
                              color: mutedTextColor,
                            ),
                            errorStyle: GoogleFonts.inter(
                              color: alertColor,
                              fontSize: 11,
                            ),
                            filled: true,
                            fillColor: cardColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: countryController,
                          style: GoogleFonts.inter(color: Colors.white),
                          validator:
                              (v) => FormValidators.text(
                                v,
                                max: 100,
                                label: 'Pays',
                              ),
                          decoration: InputDecoration(
                            labelText: 'Pays',
                            labelStyle: GoogleFonts.inter(
                              color: mutedTextColor,
                            ),
                            errorStyle: GoogleFonts.inter(
                              color: alertColor,
                              fontSize: 11,
                            ),
                            filled: true,
                            fillColor: cardColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: statusController,
                          style: GoogleFonts.inter(color: Colors.white),
                          validator:
                              (v) => FormValidators.text(
                                v,
                                max: 50,
                                label: 'Statut',
                              ),
                          decoration: InputDecoration(
                            labelText: 'Statut',
                            labelStyle: GoogleFonts.inter(
                              color: mutedTextColor,
                            ),
                            errorStyle: GoogleFonts.inter(
                              color: alertColor,
                              fontSize: 11,
                            ),
                            filled: true,
                            fillColor: cardColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: () async {
                                final dataUrl = await _pickImageAsDataUrl();
                                if (dataUrl == null || dataUrl.isEmpty) return;
                                urlController.text = dataUrl;
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Image locale selectionnee.'),
                                    backgroundColor: successColor,
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.photo_library_outlined,
                                size: 18,
                              ),
                              label: const Text('Choisir image locale'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                  color: Colors.white.withOpacity(0.25),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Conseil: si une URL externe ne s affiche pas, utilisez une image locale.',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: mutedTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(
                  'Annuler',
                  style: GoogleFonts.inter(color: mutedTextColor),
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  final nextName = nameController.text.trim();
                  final nextEmail = emailController.text.trim();
                  final nextPhone = phoneController.text.trim();
                  final nextCompany = companyController.text.trim();
                  final nextSpeciality = specialityController.text.trim();
                  final nextAddress = addressController.text.trim();
                  final nextCity = cityController.text.trim();
                  final nextCountry = countryController.text.trim();
                  final nextStatus = statusController.text.trim();
                  final nextWebsiteUrl = websiteUrlController.text.trim();
                  final nextProfileUrl = profileUrlController.text.trim();
                  final nextUrl = _normalizeProfilePhotoUrl(urlController.text);
                  // --- Validation via Form ---
                  if (!(formKey.currentState?.validate() ?? false)) return;
                  final previousName = _profileDisplayName;
                  final previousPhoto = _profilePhotoUrl;
                  final previousProfileData = Map<String, dynamic>.from(
                    _concepteurProfileData,
                  );
                  setState(() {
                    _profileDisplayName = nextName;
                    _profilePhotoUrl = nextUrl;
                    _concepteurProfileData = {
                      ..._concepteurProfileData,
                      'name': nextName,
                      'email': nextEmail,
                      'mail': nextEmail,
                      'phone': nextPhone,
                      'telephone': nextPhone,
                      'mobile': nextPhone,
                      'companyName': nextCompany,
                      'company': nextCompany,
                      'organization': nextCompany,
                      'speciality': nextSpeciality,
                      'specialty': nextSpeciality,
                      'poste': nextSpeciality,
                      'title': nextSpeciality,
                      'address': nextAddress,
                      'adresse': nextAddress,
                      'street': nextAddress,
                      'city': nextCity,
                      'ville': nextCity,
                      'country': nextCountry,
                      'pays': nextCountry,
                      'status': nextStatus,
                      'statut': nextStatus,
                      'websiteUrl': nextWebsiteUrl,
                      'siteWeb': nextWebsiteUrl,
                      'website': nextWebsiteUrl,
                      'url': nextWebsiteUrl,
                      'profileUrl': nextProfileUrl,
                      'linkedinUrl': nextProfileUrl,
                      'portfolioUrl': nextProfileUrl,
                      'photoUrl': nextUrl,
                      'avatarUrl': nextUrl,
                      'profilePhotoUrl': nextUrl,
                      'image': nextUrl,
                    };
                  });
                  var savedInDb = false;
                  String? errorMessage;
                  try {
                    String finalImageUrl = nextUrl;
                    if (nextUrl.toLowerCase().startsWith('data:image/')) {
                      String ext = 'png';
                      final match = RegExp(
                        r'^data:image/([a-zA-Z0-9+]+);base64,',
                      ).firstMatch(nextUrl);
                      if (match != null) {
                        ext = match.group(1) ?? 'png';
                        if (ext == 'jpeg') ext = 'jpg';
                      }
                      final uploadedUrl = await ApiService.uploadFile(
                        base64Data: nextUrl,
                        filename:
                            'profile_${DateTime.now().millisecondsSinceEpoch}.$ext',
                      );
                      if (uploadedUrl == null || uploadedUrl.isEmpty) {
                        throw Exception("L'upload de l'image locale a echoue.");
                      }
                      finalImageUrl = uploadedUrl;
                    }

                    final updated = await ApiService.updateMyConcepteurProfile({
                      if (nextName.isNotEmpty) 'username': nextName,
                      if (nextEmail.isNotEmpty) 'email': nextEmail,
                      if (nextAddress.isNotEmpty) 'address': nextAddress,
                      if (nextPhone.isNotEmpty) 'phone': nextPhone,
                      if (nextCompany.isNotEmpty) 'companyName': nextCompany,
                      if (nextSpeciality.isNotEmpty)
                        'speciality': nextSpeciality,
                      if (nextCity.isNotEmpty) 'city': nextCity,
                      if (nextCountry.isNotEmpty) 'country': nextCountry,
                      if (nextStatus.isNotEmpty) 'status': nextStatus,
                      if (nextWebsiteUrl.isNotEmpty)
                        'websiteUrl': nextWebsiteUrl,
                      if (nextProfileUrl.isNotEmpty)
                        'profileUrl': nextProfileUrl,
                      'imageUrl': finalImageUrl,
                    });
                    // Refresh displayed name from server response
                    final serverName =
                        (updated['name'] ??
                                updated['fullName'] ??
                                updated['nom'] ??
                                nextName)
                            .toString();
                    if (mounted) {
                      setState(() {
                        _profileDisplayName =
                            serverName.isNotEmpty ? serverName : nextName;
                        _profileEmail =
                            (updated['email'] ?? nextEmail).toString();
                        final nextPhotoUrl =
                            (updated['imageUrl'] ??
                                    updated['photoUrl'] ??
                                    updated['avatarUrl'] ??
                                    updated['profilePhotoUrl'] ??
                                    finalImageUrl)
                                .toString();
                        if (nextPhotoUrl.isNotEmpty) {
                          _profilePhotoUrl = _normalizeProfilePhotoUrl(
                            nextPhotoUrl,
                          );
                        }
                        _concepteurProfileData = {
                          ..._concepteurProfileData,
                          ...updated,
                        };
                        final projectTeam = updated['projectTeam'];
                        if (projectTeam is Map) {
                          _concepteurProjectTeam = Map<String, dynamic>.from(
                            projectTeam,
                          );
                        }
                      });
                    }
                    savedInDb = true;
                  } catch (e) {
                    errorMessage = e.toString().replaceAll('Exception: ', '');
                    if (mounted) {
                      setState(() {
                        _profileDisplayName = previousName;
                        _profilePhotoUrl = previousPhoto;
                        _concepteurProfileData = previousProfileData;
                      });
                    }
                  }
                  if (!mounted) return;
                  if (savedInDb) {
                    Navigator.of(ctx).pop();
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        savedInDb
                            ? 'Profil enregistre dans la base de donnees.'
                            : (errorMessage != null && errorMessage.isNotEmpty
                                ? 'Sauvegarde echouee: $errorMessage'
                                : 'Profil local modifie, mais sauvegarde base impossible.'),
                      ),
                      backgroundColor: savedInDb ? successColor : alertColor,
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.black,
                ),
                child: Text(
                  'Enregistrer',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
    );
  }

  Widget _buildTopBar() {
    final width = MediaQuery.of(context).size.width;
    final isCompact = width < 980;
    return Container(
      height: isCompact ? 132 : 80,
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 12 : 24,
        vertical: isCompact ? 8 : 0,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
      ),
      child:
          isCompact
              ? Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.search,
                                color: mutedTextColor,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _searchController,
                                  onChanged: (v) => setState(() {}),
                                  decoration: InputDecoration(
                                    hintText: 'Rechercher une machine...',
                                    hintStyle: GoogleFonts.inter(
                                      color: mutedTextColor,
                                      fontSize: 13,
                                    ),
                                    border: InputBorder.none,
                                  ),
                                  style: GoogleFonts.inter(
                                    color: textColor,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _loading ? null : _fetchMachines,
                        icon:
                            _loading
                                ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                : const Icon(
                                  Icons.refresh_rounded,
                                  color: Colors.white,
                                ),
                      ),
                      const SizedBox.shrink(),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const SizedBox.shrink(),
                ],
              )
              : Row(
                children: [
                  // Search in TopBar (Optional, we have one in filter bar too)
                  const SizedBox.shrink(),
                  const SizedBox(width: 32),
                  const SizedBox.shrink(),
                  const Spacer(),
                  const SizedBox.shrink(),
                  const SizedBox(width: 24),
                  const SizedBox.shrink(),
                ],
              ),
    );
  }

  Widget _buildStatsGrid() {
    return const SizedBox.shrink();
  }

  // ignore: unused_element
  Widget _buildStatsGridOld() {
    final tiles = <Widget>[
      _statCardContent(
        'TOTAL MACHINES',
        _allMachines.length.toString(),
        null,
        primaryColor,
      ),
      _statCardContent(
        'PUBLIÉES',
        _publishedCount.toString(),
        null,
        accentColor,
      ),
      _statCardContent(
        'NON PUBLIÉES',
        _notPublishedCount.toString(),
        _notPublishedCount > 0 ? 'Attention' : null,
        alertColor,
      ),
      _statCardContent(
        'FILTRÉES',
        _filteredMachines.length.toString(),
        null,
        Colors.cyan,
      ),
      _statCardContent(
        'MODÈLES 3D',
        _allMachines
            .where((m) => m['has3D'] == true || m['threeDModel'] != null)
            .length
            .toString(),
        null,
        successColor,
      ),
      _statCardContent('MAINTENANCE', '12', 'Actifs', Colors.amber),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;

        Widget threeCol(Widget a, Widget b, Widget c) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: a),
              const SizedBox(width: 16),
              Expanded(child: b),
              const SizedBox(width: 16),
              Expanded(child: c),
            ],
          );
        }

        if (w >= 1100) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(width: 16),
                Expanded(child: tiles[i]),
              ],
            ],
          );
        }
        if (w >= 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              threeCol(tiles[0], tiles[1], tiles[2]),
              const SizedBox(height: 16),
              threeCol(tiles[3], tiles[4], tiles[5]),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: tiles[0]),
                const SizedBox(width: 12),
                Expanded(child: tiles[1]),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: tiles[2]),
                const SizedBox(width: 12),
                Expanded(child: tiles[3]),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: tiles[4]),
                const SizedBox(width: 12),
                Expanded(child: tiles[5]),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _statCardContent(
    String title,
    String value,
    String? badge,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sidebarColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: mutedTextColor,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badge,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMainSectionHeader() {
    final narrow = isMobileLayout(context);
    final titleStyle = GoogleFonts.spaceGrotesk(
      fontSize: narrow ? 22 : 32,
      fontWeight: FontWeight.w900,
      color: Colors.white,
      letterSpacing: -0.5,
    );
    final subtitle = GoogleFonts.inter(
      fontSize: narrow ? 10 : 12,
      fontWeight: FontWeight.bold,
      color: mutedTextColor,
      letterSpacing: 1,
    );
    final addBtn = ElevatedButton.icon(
      onPressed: _showAddMachineDialog,
      icon: const Icon(Icons.add, size: 20),
      label: const Text('NOUVELLE MACHINE'),
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 14),
      ),
    );

    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('LISTE DE TOUTES LES MACHINES', style: titleStyle),
        const SizedBox(height: 4),
        Row(
          children: [
            Container(width: 40, height: 2, color: primaryColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'TOUTES LES MACHINES EN BASE // ${_allMachines.length} UNITÉS',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: subtitle,
              ),
            ),
          ],
        ),
      ],
    );

    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [heading, const SizedBox(height: 16), addBtn],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Expanded(child: heading), const SizedBox(width: 16), addBtn],
    );
  }

  Widget _buildFilterBar() {
    final categories = [
      'Toutes les catégories',
      ..._allMachines
          .map((e) => (e['type'] ?? e['category'] ?? 'Inconnu').toString())
          .toSet(),
    ];

    final narrow = isMobileLayout(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sidebarColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child:
          narrow
              ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.filter_list,
                        color: primaryColor,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _filterInput(
                          'Rechercher par nom ou référence...',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _filterDropdown(
                          'CATÉGORIE',
                          _selectedCategory,
                          categories.toList(),
                          (v) => setState(() => _selectedCategory = v!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _filterDropdown(
                          'STATUS PUBLICATION',
                          _selectedStatus,
                          ['Tous', 'Publié', 'Non publié'],
                          (v) => setState(() => _selectedStatus = v!),
                        ),
                      ),
                    ],
                  ),
                ],
              )
              : Row(
                children: [
                  const Icon(Icons.filter_list, color: primaryColor, size: 20),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _filterInput('Rechercher par nom ou référence...'),
                  ),
                  const SizedBox(width: 24),
                  _filterDropdown(
                    'CATÉGORIE',
                    _selectedCategory,
                    categories.toList(),
                    (v) => setState(() => _selectedCategory = v!),
                  ),
                  const SizedBox(width: 24),
                  _filterDropdown(
                    'STATUS PUBLICATION',
                    _selectedStatus,
                    ['Tous', 'Publié', 'Non publié'],
                    (v) => setState(() => _selectedStatus = v!),
                  ),
                ],
              ),
    );
  }

  Widget _filterInput(String hint) {
    return TextField(
      controller: _searchController,
      onChanged: (v) => setState(() {}),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(
          color: mutedTextColor.withOpacity(0.5),
          fontSize: 13,
        ),
        border: InputBorder.none,
      ),
      style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
    );
  }

  Widget _filterDropdown(
    String label,
    String value,
    List<String> items,
    ValueChanged<String?> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: mutedTextColor,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: items.contains(value) ? value : items.first,
            dropdownColor: sidebarColor,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
            icon: const Icon(
              Icons.keyboard_arrow_down,
              color: mutedTextColor,
              size: 16,
            ),
            items:
                items
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildMachineGrid() {
    final machines = _filteredMachines;
    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = 3;
        if (constraints.maxWidth < 600)
          crossAxisCount = 1;
        else if (constraints.maxWidth < 1000)
          crossAxisCount = 2;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 0.58,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: machines.length,
          itemBuilder:
              (context, index) => _buildMachineGalleryCard(machines[index]),
        );
      },
    );
  }

  Widget _buildMachineGalleryCard(Map<String, dynamic> m) {
    final id = (m['id'] ?? m['_id'] ?? m['machineId'] ?? '').toString();
    final name = (m['name'] ?? 'Machine sans nom').toString();
    final ref =
        (m['machineId'] ?? m['reference'] ?? 'REF-000')
            .toString()
            .toUpperCase();
    final type = (m['type'] ?? m['category'] ?? 'Non categorisee').toString();
    final location = (m['location'] ?? 'Localisation inconnue').toString();
    final isPublished = m['isPublic'] == true;
    final has3D =
        m['has3D'] == true ||
        m['threeDModel'] != null ||
        (m['model3dUrl'] ?? '').toString().trim().isNotEmpty;
    final dateRaw = (m['createdAt'] ?? m['dateAjout'] ?? '').toString();
    final dateLabel =
        dateRaw.contains('T')
            ? dateRaw.split('T').first
            : (dateRaw.isEmpty ? 'Date non definie' : dateRaw);
    final imageUrl = (m['imageUrl'] ?? '').toString();
    final enMarche = (m['status'] ?? '').toString().toUpperCase() == 'RUNNING';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF171733),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              _buildMachineImageWidget(
                imageUrl,
                height: 154,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.15),
                        Colors.black.withOpacity(0.55),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 10,
                left: 10,
                child: Row(
                  children: [
                    _statusBadge(
                      isPublished ? 'PUBLIC' : 'NON PUBLIC',
                      isPublished
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFFE53935),
                    ),
                    const SizedBox(width: 6),
                    _statusBadge(
                      has3D ? '3D DISPONIBLE' : 'NO 3D',
                      has3D ? const Color(0xFF26C6DA) : const Color(0xFF8A8AA1),
                    ),
                    const SizedBox(width: 6),
                    _statusBadge(
                      'STOCK: ${m['stock'] ?? 0}',
                      const Color(0xFFFF9800),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'REF: $ref',
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: primaryColor,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Categorie\n$type',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: mutedTextColor,
                            height: 1.25,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Localisation\n$location',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: mutedTextColor,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Date d\'ajout\n$dateLabel',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: mutedTextColor,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // ── Live telemetry state display ─────────────────────
                  ValueListenableBuilder<int>(
                    valueListenable: _telemetryTick,
                    builder: (context, _, __) {
                      final tel = _liveTelemetryByMachineId[id];
                      if (tel == null) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.sensors_off, color: Color(0xFF8A8AA1), size: 12),
                              const SizedBox(width: 6),
                              Text(
                                'Capteurs en attente…',
                                style: GoogleFonts.inter(color: const Color(0xFF8A8AA1), fontSize: 9),
                              ),
                            ],
                          ),
                        );
                      }
                      double? parseVal(dynamic v) {
                        if (v == null) return null;
                        if (v is num) return v.toDouble();
                        return double.tryParse(v.toString());
                      }
                      final tempVal = parseVal(tel['temperature'] ?? tel['temp']);
                      final vibVal = parseVal(tel['vibration']);
                      final risk = _computeRiskFromTelemetry(tel);
                      final Color stateColor = risk == 'DANGER'
                          ? const Color(0xFFF44336)
                          : risk == 'RISQUE'
                              ? const Color(0xFFFF9800)
                              : const Color(0xFF4CAF50);
                      final IconData stateIcon = risk == 'DANGER'
                          ? Icons.error_outline
                          : risk == 'RISQUE'
                              ? Icons.warning_amber_rounded
                              : Icons.check_circle_outline;
                      return Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: stateColor.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: stateColor.withOpacity(0.25)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(stateIcon, color: stateColor, size: 12),
                                const SizedBox(width: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: stateColor.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    risk,
                                    style: GoogleFonts.spaceGrotesk(
                                      color: stateColor,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  width: 5, height: 5,
                                  decoration: BoxDecoration(color: stateColor, shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 4),
                                Text('LIVE', style: GoogleFonts.inter(color: stateColor, fontSize: 7, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(Icons.thermostat_outlined, color: stateColor.withOpacity(0.7), size: 11),
                                const SizedBox(width: 3),
                                Text(
                                  tempVal != null ? '${tempVal.toStringAsFixed(1)}°C' : '--',
                                  style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 12),
                                Icon(Icons.vibration, color: stateColor.withOpacity(0.7), size: 11),
                                const SizedBox(width: 3),
                                Text(
                                  vibVal != null ? '${vibVal.toStringAsFixed(1)} mm/s' : '--',
                                  style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: _cardButton(
                          Icons.visibility_outlined,
                          'DETAILS',
                          const Color(0xFF212142),
                          () => _openDetails(id),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _cardButton(
                          Icons.view_in_ar_outlined,
                          'VOIR 3D',
                          const Color(0xFF212142),
                          () => _open3DForMachine(m),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _cardButton(
                          enMarche
                              ? Icons.stop_circle_outlined
                              : Icons.play_circle_outline,
                          enMarche ? 'ARRÊTER' : 'DÉMARRER',
                          enMarche
                              ? const Color(0xFF3A1D2A)
                              : const Color(0xFF214221),
                          () => _toggleMachineStatus(m),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMachineCard(Map<String, dynamic> m) {
    final id = (m['id'] ?? m['_id'] ?? '').toString();
    final name = (m['name'] ?? 'Machine sans nom').toString();
    final ref = (m['machineId'] ?? m['reference'] ?? 'REF-000').toString();
    final type = (m['type'] ?? m['category'] ?? 'Non catégorisé').toString();
    final location = (m['location'] ?? 'Localisation inconnue').toString();

    // --- STEP 5: DATA EXTRACTION ---
    final tempsMarcheData = m['tempsMarche'] ?? {};
    final totalHeures = (tempsMarcheData['totalHeures'] ?? 0).toDouble();
    final h = totalHeures.toInt();
    final min = ((totalHeures - h) * 60).round();
    final enMarche = tempsMarcheData['enMarche'] == true;
    // -------------------------------

    String dateStr = 'Date non définie';
    final rawDate = m['createdAt'] ?? m['dateAjout'];
    if (rawDate != null && rawDate.toString().isNotEmpty) {
      dateStr = rawDate.toString().split('T')[0];
    }

    final isPublished = m['isPublic'] == true;
    final statusLabel = isPublished ? 'Publié' : 'Non public';
    final has3D = m['has3D'] == true || m['threeDModel'] != null;
    final imageUrl = (m['imageUrl'] ?? '').toString();

    return Container(
      decoration: BoxDecoration(
        color: sidebarColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image Section
          Stack(
            children: [
              _buildMachineImageWidget(
                imageUrl,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                fallback: Container(
                  color: cardColor,
                  height: 180,
                  child: const Icon(
                    Icons.precision_manufacturing,
                    color: mutedTextColor,
                    size: 48,
                  ),
                ),
              ),
              Positioned(
                top: 12,
                left: 12,
                child: Row(
                  children: [
                    _statusBadge(
                      statusLabel.toUpperCase(),
                      isPublished ? successColor : alertColor,
                    ),
                    const SizedBox(width: 8),
                    _statusBadge(
                      has3D ? '3D' : 'NO 3D',
                      has3D ? accentColor : mutedTextColor,
                    ),
                    const SizedBox(width: 8),
                    _statusBadge(
                      'STOCK: ${m['stock'] ?? 0}',
                      const Color(0xFFFF9800),
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.6),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      ref.toUpperCase(),
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                    _buildMachineActions(m),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _infoItem('CATÉGORIE', type),
                    const SizedBox(width: 16),
                    _infoItem('LOCALISATION', location),
                  ],
                ),
                const SizedBox(height: 12),
                _infoItem('DATE D\'AJOUT', dateStr),
                const SizedBox(height: 16),

                // --- STEP 5: TEMPS DE MARCHE ---
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: bgColor.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.timer_outlined,
                                color: primaryColor,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Temps de marche',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: mutedTextColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: enMarche ? successColor : alertColor,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: (enMarche
                                              ? successColor
                                              : alertColor)
                                          .withOpacity(0.5),
                                      blurRadius: 4,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                enMarche ? 'EN MARCHE' : 'ARRÊTÉE',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: enMarche ? successColor : alertColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${h}h ${min}min',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value:
                              (totalHeures % 100) /
                              100, // Visual progress relative to 100h cycles
                          backgroundColor: Colors.white.withOpacity(0.05),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            enMarche
                                ? primaryColor
                                : mutedTextColor.withOpacity(0.3),
                          ),
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ),
                ),

                // -------------------------------
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _cardButton(
                        Icons.visibility_outlined,
                        'DÉTAILS',
                        cardColor,
                        () => _openDetails(id),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _cardButton(
                        Icons.view_in_ar_outlined,
                        'VOIR 3D',
                        cardColor,
                        has3D ? () {} : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _miniButton(
                      Icons.edit_outlined,
                      () => _showMachineManagementDialog(
                        m,
                        initialEditMode: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _miniButton(
                      Icons.delete_outline,
                      () => _confirmDelete(id, name),
                      color: alertColor,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        height: 36,
                        decoration: BoxDecoration(
                          color:
                              enMarche
                                  ? alertColor.withOpacity(0.1)
                                  : successColor,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color:
                                enMarche
                                    ? alertColor.withOpacity(0.3)
                                    : Colors.transparent,
                          ),
                        ),
                        child: InkWell(
                          onTap: () => _toggleMachineStatus(m),
                          child: Center(
                            child: Text(
                              enMarche ? 'MARQUER ARRÊT' : 'DÉMARRER',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: enMarche ? alertColor : Colors.black,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMachineActions(Map<String, dynamic> m) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: mutedTextColor, size: 18),
      color: sidebarColor,
      itemBuilder:
          (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: Text(
                'Modifier',
                style: TextStyle(color: textColor, fontSize: 13),
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Text(
                'Supprimer',
                style: TextStyle(color: alertColor, fontSize: 13),
              ),
            ),
            const PopupMenuItem(
              value: 'publish',
              child: Text(
                'Publier/Dépublier',
                style: TextStyle(color: primaryColor, fontSize: 13),
              ),
            ),
          ],
      onSelected: (val) {
        if (val == 'edit') _showEditMachineDialog(m);
        if (val == 'delete') _confirmDelete(m['id'] ?? m['_id'], m['name']);
        if (val == 'publish') {
          final id = (m['id'] ?? m['_id'] ?? '').toString();
          if (id.isNotEmpty) {
            _togglePublish(id, m['isPublic'] == true);
          }
        }
      },
    );
  }

  Widget _statusBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.20),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.65)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 8,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _infoItem(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 8,
              fontWeight: FontWeight.bold,
              color: mutedTextColor,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardButton(
    IconData icon,
    String label,
    Color color,
    VoidCallback? onTap,
  ) {
    bool disabled = onTap == null;
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: color.withOpacity(disabled ? 0.3 : 1.0),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: accentColor.withOpacity(0.1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 14,
              color: Colors.white.withOpacity(disabled ? 0.3 : 1.0),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.white.withOpacity(disabled ? 0.3 : 1.0),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniButton(IconData icon, VoidCallback onTap, {Color? color}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, size: 16, color: color ?? mutedTextColor),
      ),
    );
  }

  Widget _buildPagination() {
    final count = _allMachines.length;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Affichage de $count sur ${_allMachines.length} machines au total',
          style: GoogleFonts.inter(fontSize: 12, color: mutedTextColor),
        ),
        Row(
          children: [
            _pageArrow(Icons.keyboard_arrow_left),
            const SizedBox(width: 8),
            _pageNumber('1', true),
            const SizedBox(width: 8),
            _pageArrow(Icons.keyboard_arrow_right),
          ],
        ),
      ],
    );
  }

  Widget _pageArrow(IconData icon) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(icon, size: 16, color: mutedTextColor),
    );
  }

  Widget _pageNumber(String num, bool isActive) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isActive ? primaryColor : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.center,
      child: Text(
        num,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: isActive ? Colors.black : mutedTextColor,
        ),
      ),
    );
  }

  // --- ACTIONS ---

  void _openDetails(String id) {
    // Find machine by ID in _machines
    final machine = _allMachines.firstWhere(
      (m) => (m['id'] ?? m['_id'] ?? '').toString() == id,
      orElse: () => <String, dynamic>{},
    );
    if (machine.isNotEmpty) {
      _showMachineManagementDialog(machine, initialEditMode: false);
    }
  }

  void _open3DForMachine(Map<String, dynamic> m) {
    _showMachine3DPreview(m);
  }

  Future<void> _confirmDelete(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: sidebarColor,
            title: Text(
              'Supprimer $name ?',
              style: GoogleFonts.spaceGrotesk(color: textColor),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cette action est irréversible.',
                  style: GoogleFonts.inter(color: mutedTextColor),
                ),
                const SizedBox(height: 10),
                Text(
                  'Machine ciblée :',
                  style: GoogleFonts.inter(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Nom: $name',
                  style: GoogleFonts.inter(color: mutedTextColor),
                ),
                Text(
                  'ID: $id',
                  style: GoogleFonts.inter(
                    color: primaryColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('ANNULER'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'SUPPRIMER',
                  style: TextStyle(color: alertColor),
                ),
              ),
            ],
          ),
    );
    if (ok == true) {
      try {
        await ApiService.deleteMachine(id);
        _fetchMachines();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Machine supprimée')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur: $e'), backgroundColor: alertColor),
          );
        }
      }
    }
  }

  Future<void> _togglePublish(String id, bool currentIsPublic) async {
    try {
      await ApiService.updateMachine(id, {'isPublic': !currentIsPublic});
      _fetchMachines();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur publication: $e'),
            backgroundColor: alertColor,
          ),
        );
      }
    }
  }

  void _showAddMachineDialog() {
    _showMachineManagementDialog(<String, dynamic>{}, initialEditMode: true);
  }

  Future<void> _toggleMachineStatus(Map<String, dynamic> m) async {
    final id = (m['id'] ?? m['_id'] ?? '').toString();
    final currentStatus = (m['status'] ?? 'STOPPED').toString().toUpperCase();
    final isStopped = currentStatus == 'STOPPED';

    try {
      if (isStopped) {
        await ApiService.startMachine(id);
      } else {
        await ApiService.stopMachine(
          id,
          reason: 'Arrêt manuel par concepteur',
          stoppedBy: 'Concepteur',
        );
      }
      _fetchMachines();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: alertColor),
        );
      }
    }
  }

  void _showMachine3DPreview(Map<String, dynamic> m) {
    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              width: 600,
              height: 500,
              decoration: BoxDecoration(
                color: sidebarColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: primaryColor.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.view_in_ar, color: primaryColor),
                        const SizedBox(width: 12),
                        Text(
                          'Visualisation 3D : ${m['name']}',
                          style: GoogleFonts.spaceGrotesk(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, color: mutedTextColor),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Stack(
                        children: [
                          Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.precision_manufacturing,
                                  size: 80,
                                  color: primaryColor.withOpacity(0.1),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Chargement du modèle 3D...',
                                  style: GoogleFonts.inter(
                                    color: mutedTextColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Mock visualizer
                          Positioned.fill(
                            child: CustomPaint(
                              painter: GridPainter(
                                color: primaryColor.withOpacity(0.05),
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
          ),
    );
  }

  void _showMachineManagementDialog(
    Map<String, dynamic> m, {
    bool initialEditMode = false,
  }) {
    showDialog(
      context: context,
      builder:
          (context) => _MachineManagementDialog(
            machine: m,
            initialEditMode: initialEditMode,
            concepterId: _concepteurProfileId, // Pass the current designer's ID
            onUpdate: () => _fetchMachines(),
          ),
    );
  }

  void _showEditMachineDialog(Map<String, dynamic> m) {
    _showMachineManagementDialog(m, initialEditMode: true);
  }
}

class _MachineManagementDialog extends StatefulWidget {
  final Map<String, dynamic> machine;
  final bool initialEditMode;
  final VoidCallback onUpdate;
  final String? concepterId;

  const _MachineManagementDialog({
    required this.machine,
    required this.initialEditMode,
    required this.onUpdate,
    this.concepterId,
  });

  @override
  State<_MachineManagementDialog> createState() =>
      _MachineManagementDialogState();
}

class _MachineManagementDialogState extends State<_MachineManagementDialog> {
  late bool _editMode;
  late TextEditingController _nameCtrl;
  late TextEditingController _typeCtrl;
  late TextEditingController _locationCtrl;
  late TextEditingController _urlCtrl;
  late TextEditingController _model3dCtrl;
  late TextEditingController _priceCtrl;
  late TextEditingController _stockCtrl;
  String _aiType = 'M';
  bool _saving = false;
  bool _isPublic = true;
  String _companyId = '';
  List<Map<String, dynamic>> _clients = [];
  bool _loadingClients = true;

  @override
  void initState() {
    super.initState();
    _editMode = widget.initialEditMode;
    _nameCtrl = TextEditingController(
      text: (widget.machine['name'] ?? '').toString(),
    );
    _typeCtrl = TextEditingController(
      text: (widget.machine['type'] ?? '').toString(),
    );
    _locationCtrl = TextEditingController(
      text: (widget.machine['location'] ?? '').toString(),
    );
    _urlCtrl = TextEditingController(
      text: (widget.machine['imageUrl'] ?? '').toString(),
    );
    _model3dCtrl = TextEditingController(
      text: (widget.machine['model3dUrl'] ?? '').toString(),
    );
    _priceCtrl = TextEditingController(
      text: (widget.machine['price'] ?? widget.machine['prix'] ?? '').toString(),
    );
    _stockCtrl = TextEditingController(
      text: (widget.machine['stock'] ?? 0).toString(),
    );
    _aiType = (widget.machine['aiType'] ?? 'M').toString();
    _isPublic = widget.machine['isPublic'] == true;
    _companyId = (widget.machine['companyId'] ?? widget.machine['clientId'] ?? '').toString();
    _fetchClients();
  }

  Future<void> _fetchClients() async {
    try {
      final clients = await ApiService.getClients();
      if (mounted) {
        setState(() {
          _clients = clients;
          _loadingClients = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingClients = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF00D1FF);
    const sidebarColor = Color(0xFF0F111A);
    const cardColor = Color(0xFF1A1D2E);
    const textColor = Colors.white;
    const mutedTextColor = Color(0xFFA0A5BA);

    final id = (widget.machine['id'] ?? widget.machine['_id'] ?? '').toString();

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 700,
        constraints: const BoxConstraints(maxHeight: 800),
        decoration: BoxDecoration(
          color: sidebarColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: primaryColor.withOpacity(0.2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // HEADER
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.precision_manufacturing,
                      color: primaryColor,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _editMode
                              ? 'MODIFIER LA MACHINE'
                              : 'DÉTAILS DE LA MACHINE',
                          style: GoogleFonts.spaceGrotesk(
                            color: primaryColor,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                        Text(
                          _nameCtrl.text.isEmpty
                              ? 'Nouvelle Machine'
                              : _nameCtrl.text,
                          style: GoogleFonts.spaceGrotesk(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (id.isNotEmpty)
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                      ),
                      tooltip: 'Supprimer cette machine',
                      onPressed: _onDelete,
                    ),
                  IconButton(
                    icon: const Icon(Icons.close, color: mutedTextColor),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            const Divider(color: Colors.white10),

            // CONTENT
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Preview Image
                    Center(
                      child: Container(
                        height: 160,
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _buildMachineImageWidget(
                          _urlCtrl.text,
                          height: 160,
                          fallback: Container(
                            color: cardColor,
                            child: const Icon(
                              Icons.precision_manufacturing,
                              size: 48,
                              color: mutedTextColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (!_editMode) ...[
                      _buildInfoSection('IDENTifiant UNIQUE', id, primaryColor),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: _buildInfoSection(
                              'CATÉGORIE',
                              _typeCtrl.text,
                              textColor,
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            child: _buildInfoSection(
                              'LOCALISATION',
                              _locationCtrl.text,
                              textColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: _buildInfoSection(
                              'PRIX',
                              _priceCtrl.text.isEmpty ? 'Non renseigné' : '${_priceCtrl.text} €',
                              textColor,
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            child: _buildInfoSection(
                              'STOCK',
                              _stockCtrl.text,
                              textColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildInfoSection(
                        'URL DE L\'IMAGE',
                        _urlCtrl.text.isEmpty ? 'Aucune image configurée' : _urlCtrl.text,
                        mutedTextColor,
                      ),
                      const SizedBox(height: 24),
                      _buildInfoSection(
                        'MODÈLE 3D (GLB/OBJ)',
                        _model3dCtrl.text.isEmpty
                            ? 'Aucun modèle configuré'
                            : _model3dCtrl.text,
                        Colors.orangeAccent,
                      ),
                      const SizedBox(height: 24),
                      _buildInfoSection(
                        'STATUT DE PUBLICATION',
                        _isPublic
                            ? 'Publiée (catalogue public)'
                            : 'Non publiée (dashboard uniquement)',
                        _isPublic
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFFE53935),
                      ),
                    ] else ...[
                      _buildTextField(
                        'Nom de la machine',
                        _nameCtrl,
                        Icons.title_outlined,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              'Catégorie',
                              _typeCtrl,
                              Icons.category_outlined,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildTextField(
                              'Localisation',
                              _locationCtrl,
                              Icons.location_on_outlined,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DropdownButtonFormField<String>(
                            value: ['L', 'M', 'H'].contains(_aiType) ? _aiType : 'M',
                            dropdownColor: const Color(0xFF1A1D2E),
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Taille de la machine (Type IA)',
                              labelStyle: const TextStyle(color: Color(0xFFA0A5BA)),
                              prefixIcon: const Icon(Icons.psychology_outlined, color: Color(0xFF00D1FF), size: 20),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Colors.white10),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFF00D1FF)),
                              ),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.05),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'L', child: Text('Type L (Petite < 15kW)')),
                              DropdownMenuItem(value: 'M', child: Text('Type M (Moyenne 15-75kW)')),
                              DropdownMenuItem(value: 'H', child: Text('Type H (Grosse > 75kW)')),
                            ],
                            onChanged: (v) {
                              if (v != null) setState(() => _aiType = v);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              'Prix',
                              _priceCtrl,
                              Icons.monetization_on_outlined,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildTextField(
                              'Stock',
                              _stockCtrl,
                              Icons.pin_outlined,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        'URL de l\'image (Optionnel)',
                        _urlCtrl,
                        Icons.image_outlined,
                        onUpload:
                            () => _pickAndUploadFile(_urlCtrl, isImage: true),
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        'Modèle 3D (URL)',
                        _model3dCtrl,
                        Icons.view_in_ar_outlined,
                        onUpload: () => _pickAndUploadFile(_model3dCtrl),
                      ),
                      const SizedBox(height: 16),
                      if (_loadingClients)
                        const Center(child: CircularProgressIndicator())
                      else ...[
                        Text(
                          'Assigner à un client',
                          style: GoogleFonts.inter(
                            color: mutedTextColor,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              dropdownColor: const Color(0xFF1A1D2E),
                              icon: const Icon(Icons.arrow_drop_down, color: primaryColor),
                              value: _companyId.isEmpty ? null : _companyId,
                              hint: const Text('Aucun client assigné', style: TextStyle(color: Colors.white54)),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: null,
                                  child: Text('Aucun client (Désassigner)', style: TextStyle(color: Colors.white)),
                                ),
                                ..._clients.map((c) {
                                  final id = (c['id'] ?? c['_id'] ?? c['clientId'] ?? '').toString();
                                  final name = (c['name'] ?? c['clientName'] ?? 'Client sans nom').toString();
                                  return DropdownMenuItem<String>(
                                    value: id,
                                    child: Text(name, style: const TextStyle(color: Colors.white)),
                                  );
                                }),
                              ],
                              onChanged: (val) => setState(() => _companyId = val ?? ''),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      SwitchListTile(
                        title: Text(
                          _isPublic ? 'Publiée' : 'Non publiée',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          _isPublic
                              ? 'Activé : visible dans le catalogue public'
                              : 'Désactivé : visible uniquement dans votre dashboard',
                          style: GoogleFonts.inter(
                            color: mutedTextColor,
                            fontSize: 12,
                          ),
                        ),
                        value: _isPublic,
                        activeColor: primaryColor,
                        onChanged: (v) => setState(() => _isPublic = v),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const Divider(color: Colors.white10),

            // FOOTER
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  if (!_editMode)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.view_in_ar),
                      label: const Text('VOIR EN 3D'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orangeAccent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        // Trigger 3D View from parent
                      },
                    ),
                  const Spacer(),
                  if (!_editMode)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('MODIFIER'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primaryColor,
                        side: const BorderSide(color: primaryColor),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      onPressed: () => setState(() => _editMode = true),
                    )
                  else ...[
                    TextButton(
                      onPressed:
                          () => setState(() {
                            _editMode = false;
                            if (id.isEmpty) Navigator.pop(context);
                          }),
                      child: const Text(
                        'ANNULER',
                        style: TextStyle(color: mutedTextColor),
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 12,
                        ),
                      ),
                      onPressed: _saving ? null : _save,
                      child:
                          _saving
                              ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                              : const Text(
                                'ENREGISTRER',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
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

  Widget _buildInfoSection(String title, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.inter(
            color: const Color(0xFFA0A5BA),
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value.isEmpty ? '—' : value,
          style: GoogleFonts.spaceGrotesk(
            color: valueColor,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController ctrl,
    IconData icon, {
    VoidCallback? onUpload,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: ctrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: label,
                  labelStyle: const TextStyle(color: Color(0xFFA0A5BA)),
                  prefixIcon: Icon(
                    icon,
                    color: const Color(0xFF00D1FF),
                    size: 20,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF00D1FF)),
                  ),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                ),
              ),
            ),
            if (onUpload != null) ...[
              const SizedBox(width: 8),
              Container(
                height: 56,
                child: Center(
                  child: IconButton(
                    onPressed: onUpload,
                    icon: const Icon(
                      Icons.file_upload_outlined,
                      color: Color(0xFF00D1FF),
                    ),
                    tooltip: 'Téléverser depuis le PC',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.05),
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Future<void> _pickAndUploadFile(
    TextEditingController ctrl, {
    bool isImage = false,
  }) async {
    try {
      final result = await FilePicker.pickFiles(
        type: isImage ? FileType.image : FileType.any,
        allowedExtensions: isImage ? null : ['glb', 'obj'],
        withData: true,
      );

      if (result != null && result.files.single.bytes != null) {
        final file = result.files.single;
        setState(() => _saving = true);

        final base64String = base64Encode(file.bytes!);
        final url = await ApiService.uploadFile(
          base64Data: base64String,
          filename: file.name,
        );

        if (url != null) {
          ctrl.text = url;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Fichier téléversé avec succès !'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur upload: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final payload = {
        'name': _nameCtrl.text.trim(),
        'type': _typeCtrl.text.trim(),
        'aiType': _aiType,
        'location': _locationCtrl.text.trim(),
        'imageUrl': _urlCtrl.text.trim(),
        'model3dUrl': _model3dCtrl.text.trim(),
        'price': _priceCtrl.text.trim(),
        'stock': int.tryParse(_stockCtrl.text.trim()) ?? 0,
        'isPublic': _isPublic,
        'companyId': _companyId,
      };

      final id =
          (widget.machine['id'] ?? widget.machine['_id'] ?? '').toString();
      if (id.isEmpty) {
        await ApiService.createStandaloneMachine(
          payload,
          actorRole: 'concepteur',
          concepterId: widget.concepterId, // Pass the owner ID here
        );
      } else {
        await ApiService.updateMachine(id, payload);
      }

      widget.onUpdate();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: const Color(0xFFD32F2F),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _onDelete() async {
    final id = (widget.machine['id'] ?? widget.machine['_id'] ?? '').toString();
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A1D2E),
            title: const Text(
              'Supprimer la machine ?',
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              'Cette action est irréversible. Toutes les données liées seront perdues.',
              style: TextStyle(color: Color(0xFFA0A5BA)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  'ANNULER',
                  style: TextStyle(color: Color(0xFFA0A5BA)),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'SUPPRIMER',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
    );

    if (confirm == true) {
      setState(() => _saving = true);
      try {
        await ApiService.deleteMachine(id);
        widget.onUpdate();
        if (mounted) Navigator.pop(context);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erreur suppression: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }
  }

  bool _looksLikeNetworkImage(String value) {
    final v = value.trim().toLowerCase();
    return v.startsWith('http://') || v.startsWith('https://');
  }

  bool _looksLikeDataImage(String value) {
    final v = value.trim().toLowerCase();
    return v.startsWith('data:image/');
  }

  Widget _buildMachineImageWidget(
    String rawImageValue, {
    required double height,
    double width = double.infinity,
    BoxFit fit = BoxFit.cover,
    Widget? fallback,
  }) {
    final normalized = ApiService.fullUrl(rawImageValue);
    final fallbackWidget =
        fallback ??
        Container(
          height: height,
          width: width,
          color: const Color(0xFF1A1A2E),
          alignment: Alignment.center,
          child: const Icon(
            Icons.precision_manufacturing,
            color: Color(0xFF9E9EAE),
            size: 36,
          ),
        );

    if (normalized.isEmpty) return fallbackWidget;

    if (_looksLikeDataImage(normalized)) {
      try {
        final bytes = base64Decode(normalized.split(',').last);
        return Image.memory(
          bytes,
          height: height,
          width: width,
          fit: fit,
          errorBuilder: (_, __, ___) => fallbackWidget,
        );
      } catch (_) {
        return fallbackWidget;
      }
    }

    if (_looksLikeNetworkImage(normalized)) {
      return Image.network(
        normalized,
        height: height,
        width: width,
        fit: fit,
        errorBuilder: (_, __, ___) => fallbackWidget,
      );
    }

    return fallbackWidget;
  }
}

class GridPainter extends CustomPainter {
  final Color color;
  GridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = 1.0;

    const spacing = 30.0;
    for (double i = 0; i < size.width; i += spacing) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += spacing) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
