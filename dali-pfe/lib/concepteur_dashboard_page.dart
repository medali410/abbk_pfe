import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'services/api_service.dart';
import 'machine_detail_ai_page.dart';
import 'add_machine_page.dart';

class ConcepteurDashboardPage extends StatefulWidget {
  const ConcepteurDashboardPage({super.key});

  @override
  State<ConcepteurDashboardPage> createState() => _ConcepteurDashboardPageState();
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
  List<Map<String, dynamic>> _archives = [];
  bool _loading = true;
  bool _loadingRequests = false;
  bool _loadingArchives = false;
  String? _error;
  
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'Toutes les catégories';
  String _selectedStatus = 'Tous';

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

    final hasExtension = RegExp(r'\.[a-z0-9]{2,5}$', caseSensitive: false)
        .hasMatch(trimmed);
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

  Widget _buildMachineImageWidget(
    String rawImageValue, {
    required double height,
    double width = double.infinity,
    BoxFit fit = BoxFit.cover,
    Widget? fallback,
  }) {
    final normalized = _normalizeMachineImageValue(rawImageValue);
    final fallbackWidget = fallback ??
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
    if (working.width > _maxImageDimension || working.height > _maxImageDimension) {
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
            content: Text(
              'Image source trop volumineuse (max 12 Mo).',
            ),
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
    _fetchMachines();
    _fetchPurchaseRequests();
    _fetchArchives();
  }

  Future<void> _fetchPurchaseRequests() async {
    setState(() => _loadingRequests = true);
    try {
      final rows = await ApiService.getPurchaseRequests();
      if (!mounted) return;
      setState(() => _purchaseRequests = rows);
    } catch (_) {
      if (!mounted) return;
      setState(() => _purchaseRequests = []);
    } finally {
      if (mounted) setState(() => _loadingRequests = false);
    }
  }

  Future<void> _fetchArchives() async {
    setState(() => _loadingArchives = true);
    try {
      final rows = await ApiService.getInterventionArchives();
      if (!mounted) return;
      setState(() => _archives = rows);
    } catch (_) {
      if (!mounted) return;
      setState(() => _archives = []);
    } finally {
      if (mounted) setState(() => _loadingArchives = false);
    }
  }

  Future<void> _validateAndProvisionTeam(Map<String, dynamic> req) async {
    final reqId = (req['id'] ?? req['_id'] ?? '').toString();
    if (reqId.isEmpty) return;

    final clientNameCtrl = TextEditingController(
      text: (req['requesterName'] ?? '').toString(),
    );
    final clientPwdCtrl = TextEditingController();
    final clientLocCtrl = TextEditingController(
      text: (req['googleMapsUrl'] ?? req['location'] ?? '').toString(),
    );

    final techNameCtrl = TextEditingController();
    final techPwdCtrl = TextEditingController();
    final techLocCtrl = TextEditingController();

    final maintNameCtrl = TextEditingController();
    final maintPwdCtrl = TextEditingController();
    final maintLocCtrl = TextEditingController();

    final submit = await showDialog<bool>(
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
                    TextField(
                      controller: clientNameCtrl,
                      decoration: const InputDecoration(labelText: 'Client - Nom'),
                    ),
                    TextField(
                      controller: clientPwdCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Client - Mot de passe',
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
                child: const Text('Creer'),
              ),
            ],
          ),
    );
    if (submit != true) return;

    final fullMaint = maintNameCtrl.text.trim();
    final parts = fullMaint.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    final first = parts.isNotEmpty ? parts.first : '';
    final last = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    if (first.isEmpty || last.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nom maintenance complet requis.')),
      );
      return;
    }

    try {
      await ApiService.provisionPurchaseRequestTeam(reqId, {
        'reviewedByName': 'Concepteur',
        'clientName': clientNameCtrl.text.trim(),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Provision terminee: client, technicien et maintenance crees.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Provision impossible: $e')));
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

  Future<void> _showArchiveExport(Map<String, dynamic> a) async {
    final interventionId = (a['interventionId'] ?? '').toString();
    if (interventionId.isEmpty) return;
    try {
      final archive = await ApiService.exportInterventionArchive(interventionId);
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              backgroundColor: sidebarColor,
              title: Text(
                'Archive $interventionId',
                style: GoogleFonts.inter(color: textColor),
              ),
              content: SizedBox(
                width: 600,
                child: SingleChildScrollView(
                  child: SelectableText(
                    const JsonEncoder.withIndent('  ').convert(archive),
                    style: GoogleFonts.spaceGrotesk(
                      color: textColor,
                      fontSize: 12,
                    ),
                  ),
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export impossible: $e')));
    }
  }

  Future<void> _fetchMachines() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _loadMachinesFromBackend();
      if (mounted) {
        setState(() {
          _allMachines = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
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
      final fromMachinesApi = await ApiService.getAllMachinesFromMongo();
      for (final m in fromMachinesApi) {
        final mm = Map<String, dynamic>.from(m);
        final id = (mm['id'] ?? mm['_id'] ?? mm['machineId'] ?? '')
            .toString()
            .trim();
        if (id.isNotEmpty) {
          mm['id'] = id;
        }
        if (id.isNotEmpty) {
          mergedById[id] = mm;
        } else {
          final fallbackKey = 'name:${(mm['name'] ?? '').toString().trim().toLowerCase()}';
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
          final id = (mm['id'] ?? mm['_id'] ?? mm['machineId'] ?? '')
              .toString()
              .trim();
          if (id.isNotEmpty) {
            mm['id'] = id;
          }
          if (id.isNotEmpty) {
            // Évite qu'une version workspace obsolète écrase les données
            // fraîches Mongo (ex: image mise à jour juste après édition).
            if (mergedById.containsKey(id)) {
              mergedById[id] = {
                ...mm,
                ...mergedById[id]!,
              };
            } else {
              mergedById[id] = mm;
            }
          } else {
            final fallbackKey = 'name:${(mm['name'] ?? '').toString().trim().toLowerCase()}';
            if (mergedById.containsKey(fallbackKey)) {
              mergedById[fallbackKey] = {
                ...mm,
                ...mergedById[fallbackKey]!,
              };
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
      final status = (m['status'] ?? '').toString();
      
      bool matchesSearch = name.contains(query) || ref.contains(query);
      bool matchesCategory = _selectedCategory == 'Toutes les catégories' || cat == _selectedCategory;
      bool matchesStatus = _selectedStatus == 'Tous' || 
          (_selectedStatus == 'Publié' && (m['isPublished'] == true || status == 'active')) ||
          (_selectedStatus == 'Non publié' && (m['isPublished'] != true && status != 'active'));
          
      return matchesSearch && matchesCategory && matchesStatus;
    }).toList();
  }

  int get _publishedCount => _allMachines.where((m) => m['isPublished'] == true || m['status'] == 'active').length;
  int get _notPublishedCount => _allMachines.length - _publishedCount;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: Row(
        children: [
          // Sidebar
          _buildSidebar(),
          // Main Content
          Expanded(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: _loading 
                    ? const Center(child: CircularProgressIndicator(color: primaryColor))
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
          Text(_error!, style: GoogleFonts.inter(color: textColor, fontSize: 16)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _fetchMachines,
            style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
            child: Text('Réessayer', style: GoogleFonts.inter(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return RefreshIndicator(
      onRefresh: _fetchMachines,
      color: primaryColor,
      backgroundColor: cardColor,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPurchaseRequestsPanel(),
            const SizedBox(height: 20),
            _buildArchivesPanel(),
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
        ),
      ),
    );
  }

  Widget _buildPurchaseRequestsPanel() {
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
              const Icon(Icons.shopping_cart_checkout, color: primaryColor),
              const SizedBox(width: 8),
              Text(
                'Demandes d\'achat (Home)',
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
          else if (_purchaseRequests.isEmpty)
            Text(
              'Aucune demande d\'achat en attente.',
              style: GoogleFonts.inter(color: mutedTextColor),
            )
          else
            ..._purchaseRequests.take(8).map((r) {
              final status = (r['status'] ?? 'PENDING').toString();
              final pending = status == 'PENDING';
              return Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
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
                          : (status == 'REJECTED' ? alertColor : primaryColor),
                    ),
                    const SizedBox(width: 8),
                    if (pending)
                      TextButton(
                        onPressed: () => _rejectRequest(r),
                        child: const Text('Rejeter'),
                      ),
                    if (pending)
                      ElevatedButton(
                        onPressed: () => _validateAndProvisionTeam(r),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.black,
                        ),
                        child: const Text('Valider'),
                      ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildArchivesPanel() {
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
              const Icon(Icons.inventory_2_outlined, color: accentColor),
              const SizedBox(width: 8),
              Text(
                'Archives pannes (rapport final)',
                style: GoogleFonts.spaceGrotesk(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _loadingArchives ? null : _fetchArchives,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Actualiser'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_loadingArchives)
            const Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (_archives.isEmpty)
            Text(
              'Aucune archive disponible.',
              style: GoogleFonts.inter(color: mutedTextColor),
            )
          else
            ..._archives.take(8).map((a) {
              final iid = (a['interventionId'] ?? '').toString();
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${a['scenarioLabel'] ?? 'Intervention'}',
                  style: GoogleFonts.inter(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  'Intervention: $iid • Machine: ${(a['machineId'] ?? '').toString()}',
                  style: GoogleFonts.inter(color: mutedTextColor, fontSize: 12),
                ),
                trailing: OutlinedButton.icon(
                  onPressed: () => _showArchiveExport(a),
                  icon: const Icon(Icons.download_for_offline_outlined, size: 16),
                  label: const Text('Exporter'),
                ),
              );
            }),
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
          Icon(Icons.search_off, color: mutedTextColor.withOpacity(0.3), size: 64),
          const SizedBox(height: 16),
          Text(
            'Aucune machine trouvée',
            style: GoogleFonts.spaceGrotesk(fontSize: 20, color: mutedTextColor, fontWeight: FontWeight.bold),
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

  Widget _buildSidebar() {
    return Container(
      width: 260,
      color: sidebarColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'KINETIC',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 2,
                  ),
                ),
                Text(
                  'PREDICTIVE INTELLIGENCE',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          _sidebarItem(Icons.grid_view_rounded, 'DASHBOARD'),
          _sidebarItem(Icons.precision_manufacturing_outlined, 'MY MACHINES'),
          _sidebarItem(Icons.add_circle_outline, 'ADD MACHINE'),
          _sidebarItem(Icons.settings_input_component_outlined, 'COMPONENTS'),
          _sidebarItem(Icons.people_outline_rounded, 'TECHNICIANS'),
          _sidebarItem(Icons.support_agent_rounded, 'AGENTS'),
          _sidebarItem(Icons.menu_book_rounded, 'CLIENT CATALOG'),
          _sidebarItem(Icons.settings_outlined, 'SETTINGS'),
          const Spacer(),
          _buildUserCard(),
        ],
      ),
    );
  }

  Widget _sidebarItem(IconData icon, String title) {
    bool isSelected = selectedMenu == title;
    return InkWell(
      onTap: () => setState(() => selectedMenu = title),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          border: isSelected
              ? const Border(right: BorderSide(color: primaryColor, width: 3))
              : null,
          color: isSelected ? primaryColor.withOpacity(0.05) : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? primaryColor : mutedTextColor,
              size: 20,
            ),
            const SizedBox(width: 16),
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? primaryColor : mutedTextColor,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCard() {
    final role = (ApiService.savedUserRole ?? 'Concepteur').toUpperCase();
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 20,
            backgroundImage: NetworkImage('https://i.pravatar.cc/150?u=concepteur'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Equipe Design',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  role,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: mutedTextColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Row(
        children: [
          // Search in TopBar (Optional, we have one in filter bar too)
          Container(
            width: 300,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.search, color: mutedTextColor, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Rechercher une machine...',
                      hintStyle: GoogleFonts.inter(color: mutedTextColor, fontSize: 13),
                      border: InputBorder.none,
                    ),
                    style: GoogleFonts.inter(color: textColor, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 32),
          Text(
            'INDUSTRIAL INTELLIGENCE',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: mutedTextColor,
              letterSpacing: 2,
            ),
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () => _showAddMachineDialog(),
            icon: const Icon(Icons.add_circle, size: 18),
            label: const Text('Ajouter une machine'),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              textStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: _loading ? null : _fetchMachines,
            icon: _loading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Rafraîchir'),
            style: OutlinedButton.styleFrom(
              foregroundColor: textColor,
              side: BorderSide(color: Colors.white.withOpacity(0.2)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
          const SizedBox(width: 24),
          Stack(
            children: [
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.notifications_outlined, color: Colors.white),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: primaryColor,
                    shape: BoxShape.circle,
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
      ),
    );
  }

  Widget _buildStatsGrid() {
    return Row(
      children: [
        _statCard('TOTAL MACHINES', _allMachines.length.toString(), null, primaryColor),
        const SizedBox(width: 16),
        _statCard('PUBLIÉES', _publishedCount.toString(), null, accentColor),
        const SizedBox(width: 16),
        _statCard('NON PUBLIÉES', _notPublishedCount.toString(), _notPublishedCount > 0 ? 'Attention' : null, alertColor),
        const SizedBox(width: 16),
        _statCard('FILTRÉES', _filteredMachines.length.toString(), null, Colors.cyan),
        const SizedBox(width: 16),
        _statCard('MODÈLES 3D', _allMachines.where((m) => m['has3D'] == true || m['threeDModel'] != null).length.toString(), null, successColor),
        const SizedBox(width: 16),
        _statCard('MAINTENANCE', '12', 'Actifs', Colors.amber),
      ],
    );
  }

  Widget _statCard(String title, String value, String? badge, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
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
                Text(
                  value,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
      ),
    );
  }

  Widget _buildMainSectionHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'LISTE DE TOUTES LES MACHINES',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(width: 40, height: 2, color: primaryColor),
                const SizedBox(width: 12),
                Text(
                  'TOUTES LES MACHINES EN BASE // ${_allMachines.length} UNITÉS',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: mutedTextColor,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ],
        ),
        ElevatedButton.icon(
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
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    final categories = ['Toutes les catégories', ..._allMachines.map((e) => (e['type'] ?? e['category'] ?? 'Inconnu').toString()).toSet()];
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sidebarColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          const Icon(Icons.filter_list, color: primaryColor, size: 20),
          const SizedBox(width: 16),
          Expanded(
            child: _filterInput('Rechercher par nom ou référence...'),
          ),
          const SizedBox(width: 24),
          _filterDropdown('CATÉGORIE', _selectedCategory, categories.toList(), (v) => setState(() => _selectedCategory = v!)),
          const SizedBox(width: 24),
          _filterDropdown('STATUS PUBLICATION', _selectedStatus, ['Tous', 'Publié', 'Non publié'], (v) => setState(() => _selectedStatus = v!)),
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
        hintStyle: GoogleFonts.inter(color: mutedTextColor.withOpacity(0.5), fontSize: 13),
        border: InputBorder.none,
      ),
      style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
    );
  }

  Widget _filterDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: mutedTextColor, letterSpacing: 0.5),
        ),
        const SizedBox(height: 4),
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: items.contains(value) ? value : items.first,
            dropdownColor: sidebarColor,
            style: GoogleFonts.inter(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500),
            icon: const Icon(Icons.keyboard_arrow_down, color: mutedTextColor, size: 16),
            items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
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
        if (constraints.maxWidth < 600) crossAxisCount = 1;
        else if (constraints.maxWidth < 1000) crossAxisCount = 2;
        
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 0.80,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: machines.length,
          itemBuilder: (context, index) => _buildMachineGalleryCard(machines[index]),
        );
      },
    );
  }

  Widget _buildMachineGalleryCard(Map<String, dynamic> m) {
    final id = (m['id'] ?? m['_id'] ?? m['machineId'] ?? '').toString();
    final name = (m['name'] ?? 'Machine sans nom').toString();
    final ref = (m['machineId'] ?? m['reference'] ?? 'REF-000').toString().toUpperCase();
    final type = (m['type'] ?? m['category'] ?? 'Non categorisee').toString();
    final location = (m['location'] ?? 'Localisation inconnue').toString();
    final isPublished = m['isPublished'] == true || m['status'] == 'active' || m['status'] == 'Publié';
    final has3D = m['has3D'] == true ||
        m['threeDModel'] != null ||
        (m['model3dUrl'] ?? '').toString().trim().isNotEmpty;
    final dateRaw = (m['createdAt'] ?? m['dateAjout'] ?? '').toString();
    final dateLabel = dateRaw.contains('T') ? dateRaw.split('T').first : (dateRaw.isEmpty ? 'Date non definie' : dateRaw);
    final imageUrl = (m['imageUrl'] ?? '').toString();

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
                      isPublished ? const Color(0xFF4CAF50) : const Color(0xFFE53935),
                    ),
                    const SizedBox(width: 6),
                    _statusBadge(
                      has3D ? '3D DISPONIBLE' : 'NO 3D',
                      has3D ? const Color(0xFF26C6DA) : const Color(0xFF8A8AA1),
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
                          style: GoogleFonts.inter(fontSize: 10, color: mutedTextColor, height: 1.25),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Localisation\n$location',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 10, color: mutedTextColor, height: 1.25),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Date d\'ajout\n$dateLabel',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 10, color: mutedTextColor, height: 1.25),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: _cardButton(Icons.visibility_outlined, 'DETAILS', const Color(0xFF212142), () => _openDetails(id)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _cardButton(Icons.view_in_ar_outlined, 'VOIR 3D', const Color(0xFF212142), () => _open3DForMachine(m)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _cardButton(
                          Icons.edit_outlined,
                          'MODIFIER',
                          const Color(0xFF212142),
                          () => _showEditMachineDialog(m),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _cardButton(
                          Icons.delete_outline,
                          'EFFACER',
                          const Color(0xFF3A1D2A),
                          () => _confirmDelete(id, name),
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
    
    final isPublished = m['isPublished'] == true || m['status'] == 'active' || m['status'] == 'Publié';
    final statusLabel = isPublished ? 'Publié' : 'Non publié';
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
                    _statusBadge(statusLabel.toUpperCase(), isPublished ? successColor : alertColor),
                    const SizedBox(width: 8),
                    _statusBadge(has3D ? '3D' : 'NO 3D', has3D ? accentColor : mutedTextColor),
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
                      colors: [Colors.transparent, Colors.black.withOpacity(0.6)],
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
                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: primaryColor, letterSpacing: 0.5),
                    ),
                    _buildMachineActions(m),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
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
                              const Icon(Icons.timer_outlined, color: primaryColor, size: 14),
                              const SizedBox(width: 6),
                              Text(
                                'Temps de marche',
                                style: GoogleFonts.inter(fontSize: 11, color: mutedTextColor, fontWeight: FontWeight.w500),
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
                                      color: (enMarche ? successColor : alertColor).withOpacity(0.5),
                                      blurRadius: 4,
                                      spreadRadius: 1,
                                    )
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
                          value: (totalHeures % 100) / 100, // Visual progress relative to 100h cycles
                          backgroundColor: Colors.white.withOpacity(0.05),
                          valueColor: AlwaysStoppedAnimation<Color>(enMarche ? primaryColor : mutedTextColor.withOpacity(0.3)),
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
                      child: _cardButton(Icons.visibility_outlined, 'DÉTAILS', cardColor, () => _openDetails(id)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _cardButton(Icons.view_in_ar_outlined, 'VOIR 3D', cardColor, has3D ? () {} : null),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _miniButton(Icons.edit_outlined, () => _showEditMachineDialog(m)),
                    const SizedBox(width: 8),
                    _miniButton(Icons.delete_outline, () => _confirmDelete(id, name), color: alertColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        height: 36,
                        decoration: BoxDecoration(
                          color: isPublished ? cardColor : primaryColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: InkWell(
                          onTap: () => _togglePublish(id, isPublished),
                          child: Center(
                            child: Text(
                              isPublished ? 'DÉPUBLIER' : 'PUBLIER',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isPublished ? mutedTextColor : Colors.black,
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
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'edit', child: Text('Modifier', style: TextStyle(color: textColor, fontSize: 13))),
        const PopupMenuItem(value: 'delete', child: Text('Supprimer', style: TextStyle(color: alertColor, fontSize: 13))),
        const PopupMenuItem(value: 'publish', child: Text('Publier/Dépublier', style: TextStyle(color: primaryColor, fontSize: 13))),
      ],
      onSelected: (val) {
        if (val == 'edit') _showEditMachineDialog(m);
        if (val == 'delete') _confirmDelete(m['id'] ?? m['_id'], m['name']);
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
            style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.bold, color: mutedTextColor, letterSpacing: 0.5),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _cardButton(IconData icon, String label, Color color, VoidCallback? onTap) {
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
            Icon(icon, size: 14, color: Colors.white.withOpacity(disabled ? 0.3 : 1.0)),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white.withOpacity(disabled ? 0.3 : 1.0)),
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
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => MachineDetailAiPage(machineId: id))
    );
  }

  void _open3DForMachine(Map<String, dynamic> m) {
    final id = (m['id'] ?? m['_id'] ?? '').toString().trim();
    if (id.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Machine invalide: identifiant introuvable.'),
            backgroundColor: alertColor,
          ),
        );
      }
      return;
    }
    _openDetails(id);
  }

  Future<void> _confirmDelete(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: sidebarColor,
        title: Text('Supprimer $name ?', style: GoogleFonts.spaceGrotesk(color: textColor)),
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
              style: GoogleFonts.inter(color: primaryColor, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ANNULER')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('SUPPRIMER', style: TextStyle(color: alertColor))),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ApiService.deleteMachine(id);
        _fetchMachines();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Machine supprimée')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e'), backgroundColor: alertColor));
        }
      }
    }
  }

  Future<void> _togglePublish(String id, bool currentStatus) async {
    try {
      await ApiService.updateMachine(id, {'isPublished': !currentStatus, 'status': !currentStatus ? 'active' : 'inactive'});
      _fetchMachines();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur publication: $e'), backgroundColor: alertColor));
      }
    }
  }

  void _showAddMachineDialog() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AddMachinePage(actorRole: 'conception'),
      ),
    ).then((result) {
      if (result != null) {
        if (result is Map<String, dynamic>) {
          setState(() {
            final created = Map<String, dynamic>.from(result);
            _allMachines.insert(0, created);
          });
          _fetchMachines();
        } else {
          _fetchMachines();
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Machine ajoutee et synchronisee dans le dashboard Concepteur.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    });
  }

  void _showEditMachineDialog(Map<String, dynamic> m) {
    final id = (m['id'] ?? m['_id'] ?? '').toString();
    final nameController = TextEditingController(text: m['name'] ?? '');
    final imageUrlController = TextEditingController(
      text: _toEditImageValue((m['imageUrl'] ?? '').toString()),
    );
    final model3dController = TextEditingController(text: (m['model3dUrl'] ?? m['threeDModel'] ?? '').toString());
    final locationController = TextEditingController(text: (m['location'] ?? '').toString());
    final typeController = TextEditingController(text: (m['type'] ?? m['category'] ?? '').toString());
    
    showDialog(
      context: context,
      builder: (context) {
        String selectedImage = _normalizeMachineImageValue(imageUrlController.text);
        return StatefulBuilder(
          builder: (context, setLocalState) => AlertDialog(
            backgroundColor: sidebarColor,
            title: Text('Éditer machine', style: GoogleFonts.spaceGrotesk(color: textColor)),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Nom de la machine'),
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: imageUrlController,
                            decoration: const InputDecoration(labelText: 'Photo (URL image)'),
                            style: const TextStyle(color: Colors.white),
                            onChanged: (v) => setLocalState(() {
                              selectedImage = _normalizeMachineImageValue(v);
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final dataUrl = await _pickImageAsDataUrl();
                            if (dataUrl != null && dataUrl.isNotEmpty) {
                              setLocalState(() {
                                selectedImage = dataUrl;
                                imageUrlController.text = dataUrl;
                              });
                            }
                          },
                          icon: const Icon(Icons.upload_file, size: 16),
                          label: const Text('Choisir photo'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            setLocalState(() {
                              selectedImage = '';
                              imageUrlController.clear();
                            });
                          },
                          icon: const Icon(Icons.delete_outline, size: 16),
                          label: const Text('Supprimer photo'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 120,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: bgColor.withOpacity(0.45),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: selectedImage.isEmpty
                          ? const Center(child: Icon(Icons.image_outlined, color: mutedTextColor))
                          : (_looksLikeNetworkImage(selectedImage)
                              ? Image.network(
                                  selectedImage,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Center(
                                    child: Icon(Icons.broken_image_outlined, color: mutedTextColor),
                                  ),
                                )
                              : (_looksLikeDataImage(selectedImage)
                                  ? Image.memory(
                                      base64Decode(selectedImage.split(',').last),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Center(
                                        child: Icon(Icons.broken_image_outlined, color: mutedTextColor),
                                      ),
                                    )
                                  : const Center(
                                      child: Text(
                                        'Aperçu indisponible (URL invalide)',
                                        style: TextStyle(color: mutedTextColor, fontSize: 12),
                                      ),
                                    ))),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: model3dController,
                      decoration: const InputDecoration(labelText: 'Modèle 3D (URL/fichier)'),
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: typeController,
                      decoration: const InputDecoration(labelText: 'Catégorie'),
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: locationController,
                      decoration: const InputDecoration(labelText: 'Localisation'),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('ANNULER')),
              TextButton(
                onPressed: () async {
                  try {
                    final rawImageInput = imageUrlController.text.trim();
                    if (_looksLikeLocalFilePath(rawImageInput)) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Chemin local detecte. Utilisez "Choisir photo" pour televerser une image.',
                            ),
                            backgroundColor: alertColor,
                          ),
                        );
                      }
                      return;
                    }
                    final normalizedImage =
                        _normalizeMachineImageValue(rawImageInput);
                    final payload = <String, dynamic>{
                      'name': nameController.text.trim(),
                      'imageUrl': normalizedImage,
                      'model3dUrl': model3dController.text.trim(),
                      'type': typeController.text.trim(),
                      'location': locationController.text.trim(),
                    };
                    await ApiService.updateMachine(id, payload);
                    if (mounted) {
                      setState(() {
                        final idx = _allMachines.indexWhere((x) {
                          final xid = (x['id'] ?? x['_id'] ?? x['machineId'] ?? '')
                              .toString();
                          return xid == id;
                        });
                        if (idx != -1) {
                          _allMachines[idx] = {
                            ..._allMachines[idx],
                            ...payload,
                          };
                        }
                      });
                    }
                    Navigator.pop(context);
                    _fetchMachines();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Machine mise à jour avec succès.'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erreur: $e'), backgroundColor: alertColor),
                    );
                  }
                },
                child: const Text('ENREGISTRER', style: TextStyle(color: primaryColor)),
              ),
            ],
          ),
        );
      },
    );
  }
}
