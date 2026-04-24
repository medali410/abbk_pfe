import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'constants/deployed_sensors.dart';
import 'client_position_page.dart';
import 'machine_detail_ai_page.dart';
import 'services/api_service.dart';
import 'utils/panne_display.dart';
import 'widgets/motor_analytics_panel.dart';

/// Tableau de bord conception « The Observatory » — détail machine + sidebar (PWA / web / mobile).
class ConceptionObservatoryPage extends StatefulWidget {
  const ConceptionObservatoryPage({super.key});

  @override
  State<ConceptionObservatoryPage> createState() => _ConceptionObservatoryPageState();
}

class _ConceptionObservatoryPageState extends State<ConceptionObservatoryPage> with SingleTickerProviderStateMixin {
  static const _bg = Color(0xFF10102B);
  static const _surface = Color(0xFF1D1D38);
  static const _surfaceLow = Color(0xFF191934);
  static const _surfaceHigh = Color(0xFF272743);
  static const _surfaceHighest = Color(0xFF32324E);
  static const _surfaceLowest = Color(0xFF0B0B26);
  static const _onSurface = Color(0xFFE2DFFF);
  static const _onVariant = Color(0xFFE2BFB0);
  static const _primary = Color(0xFFFFB692);
  static const _primaryContainer = Color(0xFFFF6E00);
  static const _secondary = Color(0xFF75D1FF);
  static const _tertiary = Color(0xFFEFB1F9);
  static const _outlineVariant = Color(0xFF594136);
  static const _green = Color(0xFF66BB6A);
  static const _error = Color(0xFFFFB4AB);
  static const _errorContainer = Color(0xFF93000A);

  static const _turbineImg =
      'https://lh3.googleusercontent.com/aida-public/AB6AXuDl1msCjQDtGAZTvSAiL-NUSawW7_HVF6IyjQ9vK4pBQGdvVvKPgpB88Q6EoP_zf0hXs74O6aiao0u5CY1MjOo7QexAwSqR_5FIgfXLH_ztljKqzTmqxAjzz5zydcCOPLuvsktyqeuh5RDMLB6pKm-Fm4VcWRNpHDFi98gN_470tdJn9yixKsekBRiB_m7CuPjAAGiRt16jGIeqVP_4a1Dh7PW0Xp-Q9O9JDCCHk6VCiCVzVe_FaKzwxRhf68qYK0jwe3Q5rpdCoz8';

  static const _mapLiveImg =
      'https://lh3.googleusercontent.com/aida-public/AB6AXuDd_AxDBejX3t6ArzX1LoBHRupPXx1OB1pTQqo_wTB3mWb8l84wloMILfIj_4dJ5NLTpNKPI4zI_rOGrl_Kh4L61nAYcPmBn3AR1GcIUaF4YsNH7YJvLizYZSl4uoP8LxVIu28jFuvUTiGn1jyYjv0WxO1kN7hYk2aXI2s88CYT-aqyNTNjcRFF4AL-X8Fn__9fE6aRHceVf0ivweAZjVYaXtbcHCE3zaeNegQW6PT_UmCd2K6DMlj7zcF8oRfg6mCQCfWZUf-gLdM';

  Map<String, dynamic>? _args;
  /// 0 = Operational Status. 1–4 = vues détaillées. 5 = analyse moteur (courbes).
  int _navIndex = 0;
  Future<Map<String, dynamic>>? _workspaceFuture;
  List<Map<String, dynamic>> _machines = [];
  Map<String, dynamic>? _clientInfo;
  String _displayName = 'Concepteur';
  String? _selectedMachineId;
  Map<String, dynamic>? _machineRow;
  Map<String, dynamic>? _latest;
  List<Map<String, dynamic>> _history = [];
  int _healthPct = 94;
  int _probPanne = 12;
  String _iaHint =
      'L\'IA analyse les capteurs en temps réel. Connectez des données MQTT pour enrichir les prédictions.';
  bool _pressureAlert = false;
  Timer? _pollTimer;
  bool _loadingTelemetry = false;
  bool _redirectedOnUserMissing = false;
  late AnimationController _pulseCtrl;

  /// Photos personnalisées capteurs (clé API : thermal, pressure, vibration, ultrasonic) — par machine.
  Map<String, String?> _sensorPhotoOverrides = {};

  static const Map<String, String> _defaultSensorPhotoUrls = {
    'thermal': 'https://picsum.photos/seed/dali-cap-thermal/104/104',
    'pressure': 'https://picsum.photos/seed/dali-cap-pressure/104/104',
    'vibration': 'https://picsum.photos/seed/dali-cap-vibration/104/104',
    'ultrasonic': 'https://picsum.photos/seed/dali-cap-flow/104/104',
  };

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final a = ModalRoute.of(context)?.settings.arguments;
    if (a is Map<String, dynamic>) {
      _args = Map<String, dynamic>.from(a);
      _displayName = (_args!['username'] ?? _args!['name'] ?? _args!['email'] ?? 'Concepteur').toString();
    }
    _workspaceFuture ??= _loadWorkspace();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  /// Panneau type maquette HTML (blur + calque).
  Widget _glassPanel({required Widget child, EdgeInsetsGeometry padding = const EdgeInsets.all(0)}) {
    return ClipRRect(
      borderRadius: BorderRadius.zero,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF32324E).withValues(alpha: 0.58),
            border: Border.all(color: _outlineVariant.withValues(alpha: 0.12)),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> _loadWorkspace() async {
    final data = await ApiService.getConceptionWorkspace();
    if (!mounted) return data;
    setState(() {
      _machines = (data['machines'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final c = data['client'];
      _clientInfo = c is Map ? Map<String, dynamic>.from(c) : null;
      final u = data['user'];
      if (u is Map) {
        final um = Map<String, dynamic>.from(u);
        final dn = (um['username'] ?? um['email'] ?? '').toString().trim();
        if (dn.isNotEmpty) _displayName = dn;
        // Session « remember me » : pas d'arguments de route — complète le profil header.
        _args = {...?_args, ...um, 'specialization': um['specialization'] ?? _args?['specialization']};
      }
      if (_selectedMachineId == null && _machines.isNotEmpty) {
        _selectedMachineId = _machineIdOf(_machines.first);
        _machineRow = _machines.first;
      }
    });
    await _reloadSensorPhotoPrefs();
    if (_selectedMachineId != null) {
      await _refreshTelemetry(_selectedMachineId!);
      _startPoll();
    }
    return data;
  }

  String _sensorPrefsMid() {
    final m = (_selectedMachineId ?? '').trim();
    return m.isEmpty ? 'none' : m;
  }

  Future<void> _reloadSensorPhotoPrefs() async {
    final mid = _sensorPrefsMid();
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    final next = <String, String?>{};
    for (final k in _defaultSensorPhotoUrls.keys) {
      next[k] = p.getString('obs_cap_${mid}_$k');
    }
    setState(() {
      _sensorPhotoOverrides = next;
    });
  }

  Future<void> _showChangeSensorPhotoDialog(String sensorKey, String label, String defaultUrl) async {
    final initial = _sensorPhotoOverrides[sensorKey] ?? '';
    final ctrl = TextEditingController(text: initial);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: _surface,
          surfaceTintColor: Colors.transparent,
          title: Text('Photo — $label', style: GoogleFonts.inter(color: _onSurface, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Collez une URL d’image (https…). Laissez vide puis « Réinitialiser » pour l’image par défaut.',
                  style: GoogleFonts.inter(fontSize: 12, color: _onVariant, height: 1.35),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  style: GoogleFonts.inter(color: _onSurface, fontSize: 13),
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: defaultUrl,
                    hintStyle: GoogleFonts.inter(color: _onVariant.withValues(alpha: 0.45), fontSize: 11),
                    filled: true,
                    fillColor: _surfaceLowest,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _primaryContainer, width: 1.2)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: Text('Réinitialiser', style: GoogleFonts.inter(color: _secondary, fontWeight: FontWeight.w600)),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx, '__cancel__'), child: Text('Annuler', style: GoogleFonts.inter(color: _onVariant))),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              style: FilledButton.styleFrom(backgroundColor: _primaryContainer, foregroundColor: const Color(0xFF582100)),
              child: Text('Enregistrer', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
            ),
          ],
        );
      },
    );
    ctrl.dispose();
    if (!mounted || saved == null || saved == '__cancel__') return;
    final p = await SharedPreferences.getInstance();
    final mid = _sensorPrefsMid();
    final key = 'obs_cap_${mid}_$sensorKey';
    if (saved.isEmpty) {
      await p.remove(key);
    } else {
      await p.setString(key, saved);
    }
    await _reloadSensorPhotoPrefs();
  }

  Widget _sensorCardWithPhoto({
    required String sensorKey,
    required String label,
    required String value,
    required IconData icon,
    required Color c,
  }) {
    final def = _defaultSensorPhotoUrls[sensorKey] ?? _defaultSensorPhotoUrls['thermal']!;
    final custom = _sensorPhotoOverrides[sensorKey];
    final imageUrl = (custom != null && custom.trim().isNotEmpty) ? custom.trim() : def;
    const thumb = 52.0;

    Widget thumbImage() {
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        width: thumb,
        height: thumb,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            width: thumb,
            height: thumb,
            color: _surfaceHighest,
            alignment: Alignment.center,
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _primaryContainer,
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded / (loadingProgress.expectedTotalBytes ?? 1)
                    : null,
              ),
            ),
          );
        },
        errorBuilder: (_, __, ___) => Container(
          width: thumb,
          height: thumb,
          color: _surfaceHighest,
          alignment: Alignment.center,
          child: Icon(icon, size: 26, color: c.withValues(alpha: 0.5)),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _surfaceLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _outlineVariant.withValues(alpha: 0.14)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
        child: Row(
          children: [
            Tooltip(
              message: 'Changer la photo',
              child: InkWell(
                onTap: () => _showChangeSensorPhotoDialog(sensorKey, label, def),
                borderRadius: BorderRadius.circular(8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: thumbImage(),
                ),
              ),
            ),
                const SizedBox(width: 12),
                Icon(icon, color: c, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: _onSurface),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: _onSurface),
                ),
            Tooltip(
              message: 'Changer la photo',
              child: IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
                icon: Icon(Icons.photo_camera_outlined, size: 18, color: _primaryContainer.withValues(alpha: 0.9)),
                onPressed: () => _showChangeSensorPhotoDialog(sensorKey, label, def),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _machineIdOf(Map<String, dynamic> m) {
    return (m['id'] ?? m['machineId'] ?? m['_id'] ?? '').toString();
  }

  void _startPoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final id = _selectedMachineId;
      if (id != null && mounted) _refreshTelemetry(id);
    });
  }

  Future<void> _refreshTelemetry(String machineId) async {
    setState(() => _loadingTelemetry = true);
    try {
      final latest = await ApiService.getLatestTelemetry(machineId);
      final hist = await ApiService.getTelemetryHistory(machineId, limit: 200);
      Map<String, dynamic>? pred;
      try {
        if (latest != null) {
          final m = latest['metrics'] as Map<String, dynamic>?;
          pred = await ApiService.predictMachine(
            {
              'temperature': latest['temperature'] ?? m?['thermal'] ?? 0,
              'pressure': latest['pressure'] ?? m?['pressure'] ?? 0,
              'vibration': latest['vibration'] ?? m?['vibration'] ?? 0,
              'power': latest['power'] ?? m?['power'] ?? 0,
            },
            machineId: machineId,
          );
        }
      } catch (_) {}
      if (!mounted) return;
      final mlProb = _toInt(pred?['prob_panne'] ?? pred?['failureProbability'], -1);
      final fallbackProb = _fallbackRiskFromLatest(latest);
      final prob = mlProb < 0
          ? fallbackProb
          : (mlProb == 0 && fallbackProb > 0 ? fallbackProb : mlProb);
      final health = (100 - prob).clamp(60, 100);
      final p = _toDouble(latest?['pressure'] ?? (latest?['metrics'] as Map?)?['pressure'], 4.2);
      setState(() {
        _latest = latest;
        _history = hist;
        _probPanne = prob;
        _healthPct = health;
        _pressureAlert = p > 4.5;
        if (pred != null) {
          final expl = (pred['message'] ?? pred['explanation'] ?? '').toString();
          if (expl.isNotEmpty) _iaHint = expl;
        }
        _loadingTelemetry = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingTelemetry = false);
    }
  }

  double _toDouble(dynamic v, double fb) {
    if (v == null) return fb;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fb;
  }

  int _toInt(dynamic v, int fb) {
    if (v == null) return fb;
    if (v is num) return v.round().clamp(0, 100);
    return int.tryParse(v.toString()) ?? fb;
  }

  int _fallbackRiskFromLatest(Map<String, dynamic>? latest) {
    if (latest == null) return 0;
    final raw = latest['metrics'];
    Map<String, dynamic>? m;
    if (raw is Map<String, dynamic>) {
      m = raw;
    } else if (raw is Map) {
      m = Map<String, dynamic>.from(raw);
    }

    final t = _toDouble(latest['temperature'] ?? m?['thermal'], 0);
    final p = _toDouble(latest['pressure'] ?? m?['pressure'], 0);
    final v = _toDouble(latest['vibration'] ?? m?['vibration'], 0);
    final pow = _toDouble(latest['power'] ?? m?['power'], 0);

    var risk = 0.0;
    if (t >= 85) {
      risk += 40;
    } else if (t >= 70) {
      risk += 25;
    } else if (t >= 55) {
      risk += 10;
    }

    if (p >= 6.0 || (p > 0 && p <= 0.8)) {
      risk += 25;
    } else if (p >= 4.8 || (p > 0 && p <= 1.2)) {
      risk += 12;
    }

    if (v >= 8.0) {
      risk += 25;
    } else if (v >= 4.0) {
      risk += 12;
    }

    if (pow >= 6500) {
      risk += 15;
    } else if (pow >= 4500) {
      risk += 8;
    }

    return risk.round().clamp(0, 100);
  }

  double _metric(String key, double fb) {
    final L = _latest;
    if (L == null) return fb;
    final m = L['metrics'];
    if (m is Map && m[key] != null) return _toDouble(m[key], fb);
    return _toDouble(L[key], fb);
  }

  double? _tryDoubleNullable(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return double.tryParse(s.replaceAll(',', '.'));
  }

  /// GPS issu du dernier point MQTT / télémétrie (`lat`/`lng` ou `latitude`/`longitude` dans le corps ou dans `metrics`).
  ({double? lat, double? lng, bool hasFix}) _readGpsFromLatest() {
    final L = _latest;
    if (L == null) return (lat: null, lng: null, hasFix: false);
    Map<String, dynamic>? m;
    final raw = L['metrics'];
    if (raw is Map<String, dynamic>) {
      m = raw;
    } else if (raw is Map) {
      m = Map<String, dynamic>.from(raw);
    }
    final la = _tryDoubleNullable(m?['lat'] ?? m?['latitude'] ?? L['lat'] ?? L['latitude']);
    final ln = _tryDoubleNullable(m?['lng'] ?? m?['longitude'] ?? L['lng'] ?? L['longitude']);
    final fix = la != null && ln != null && la.isFinite && ln.isFinite;
    return (lat: la, lng: ln, hasFix: fix);
  }

  String? _latestTelemetryLabel() {
    final L = _latest;
    if (L == null) return null;
    final t = L['createdAt'] ?? L['updatedAt'];
    if (t == null) return null;
    return t.toString();
  }

  Future<void> _openGpsInMaps(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible d’ouvrir la carte : $uri', style: GoogleFonts.inter())),
      );
    }
  }

  Future<void> _logout() async {
    await ApiService.clearAuth();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
  }

  void _openFullMachineIa() {
    final id = _selectedMachineId;
    if (id == null || id.isEmpty) return;
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => MachineDetailPage(
          machineId: id,
          machineName: (_machineRow?['name'] ?? '').toString(),
          viewerRole: 'conception',
          viewerName: _displayName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final isWide = w > 960;
    final sidebar = _buildSidebar(isWide);

    return Scaffold(
      backgroundColor: _bg,
      drawer: isWide ? null : Drawer(child: sidebar),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _workspaceFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && _machines.isEmpty) {
            return const Center(child: CircularProgressIndicator(color: _primaryContainer));
          }
          if (snap.hasError) {
            final err = snap.error.toString().toLowerCase();
            if (err.contains('utilisateur introuvable') && !_redirectedOnUserMissing) {
              _redirectedOnUserMissing = true;
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                await ApiService.clearAuth();
                if (!context.mounted) return;
                Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
              });
            }
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${snap.error}', textAlign: TextAlign.center, style: GoogleFonts.spaceGrotesk(color: _onVariant)),
                    if (err.contains('utilisateur introuvable')) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Session ou base obsolète : retour à la connexion…',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 12, color: _secondary),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isWide) SizedBox(width: 288, child: sidebar),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTopBar(isWide),
                    Expanded(
                      child: Container(
                        color: _surface,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                          child: _buildMainBody(isWide),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSidebar(bool isWide) {
    Widget nav(int idx, IconData icon, String label) {
      final active = _navIndex == idx;
      return Material(
        color: active ? _primaryContainer.withValues(alpha: 0.1) : Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() => _navIndex = idx);
            if (idx == 2 || idx == 5) {
              final id = _selectedMachineId;
              if (id != null && id.isNotEmpty) _refreshTelemetry(id);
            }
            if (!isWide) Navigator.pop(context);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: active ? _primaryContainer : Colors.transparent, width: 2)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 22, color: active ? _primaryContainer : _onVariant.withValues(alpha: 0.6)),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                      letterSpacing: 0.6,
                      color: active ? _primaryContainer : _onVariant.withValues(alpha: 0.65),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      color: _surfaceLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isWide)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 48, 16, 8),
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: _onSurface),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(28, isWide ? 32 : 8, 28, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('OBSERVATORY', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w900, color: _onSurface, letterSpacing: 2)),
                const SizedBox(height: 4),
                Text(
                  'PRECISION INTELLIGENCE',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: _primaryContainer,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          nav(0, Icons.business_outlined, 'Client'),
          nav(1, Icons.precision_manufacturing_outlined, 'Machine'),
          nav(2, Icons.location_on_outlined, 'Localisation'),
          nav(3, Icons.settings_input_component, 'Détail Capteur'),
          nav(4, Icons.analytics_outlined, 'Détail Machine'),
          nav(5, Icons.insights, 'Analyse moteur'),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: const LinearGradient(colors: [_primaryContainer, _primary]),
                boxShadow: [BoxShadow(color: _primaryContainer.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() => _navIndex = 4),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.bolt, size: 18, color: Color(0xFF582100)),
                        const SizedBox(width: 8),
                        Text(
                          'SYSTEM HEALTH',
                          style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.6, color: const Color(0xFF582100)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            dense: true,
            leading: Icon(Icons.engineering_outlined, color: _onVariant.withValues(alpha: 0.75), size: 20),
            title: Text('TECHNICAL SUPPORT', style: GoogleFonts.spaceGrotesk(fontSize: 10, letterSpacing: 1, color: _onVariant.withValues(alpha: 0.85))),
            onTap: () {},
          ),
          ListTile(
            dense: true,
            leading: Icon(Icons.settings_outlined, color: _onVariant.withValues(alpha: 0.75), size: 20),
            title: Text('SETTINGS', style: GoogleFonts.spaceGrotesk(fontSize: 10, letterSpacing: 1, color: _onVariant.withValues(alpha: 0.85))),
            onTap: () {},
          ),
          const Divider(height: 1, color: Colors.white10),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: _surfaceHighest,
                  child: Text(_displayName.isNotEmpty ? _displayName[0].toUpperCase() : '?', style: GoogleFonts.inter(color: _primary, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_displayName, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: _onSurface)),
                      Text('CONNECTÉ', style: GoogleFonts.spaceGrotesk(fontSize: 9, letterSpacing: 2, color: _onVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: TextButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout, size: 18, color: _onVariant),
              label: Text('Déconnexion', style: GoogleFonts.inter(color: _onVariant, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(bool isWide) {
    final unit = (_machineRow?['name'] ?? _selectedMachineId ?? '—').toString();
    final initial = _displayName.isNotEmpty ? _displayName[0].toUpperCase() : '?';
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 64,
          alignment: Alignment.center,
          padding: EdgeInsets.fromLTRB(isWide ? 24 : 8, 0, 16, 0),
          decoration: BoxDecoration(
            color: _bg.withValues(alpha: 0.6),
            border: Border(bottom: BorderSide(color: _outlineVariant.withValues(alpha: 0.15))),
          ),
          child: Row(
            children: [
              if (!isWide)
                IconButton(
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  icon: const Icon(Icons.menu, color: _onSurface),
                ),
              Container(width: 2, height: 28, color: _primaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: _onSurface, letterSpacing: -0.2),
                    children: [
                      const TextSpan(text: 'Predictive Intel '),
                      TextSpan(text: '//', style: TextStyle(color: _primaryContainer.withValues(alpha: 0.55))),
                      const TextSpan(text: ' Dashboard'),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_navIndex == 4 || _navIndex == 5) ...[
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 1,
                  height: 18,
                  color: _outlineVariant.withValues(alpha: 0.3),
                ),
                Expanded(
                  child: Text(
                    _navIndex == 5 ? 'ANALYSE // ${unit.toUpperCase()}' : 'UNIT // ${unit.toUpperCase()}',
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                      color: _onSurface.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ],
              if (isWide)
                SizedBox(
                  width: 256,
                  child: TextField(
                    style: GoogleFonts.spaceGrotesk(fontSize: 10, letterSpacing: 1.8, color: _onSurface),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: _surfaceLowest,
                      hintText: 'RECHERCHE SYSTÈME...',
                      hintStyle: GoogleFonts.spaceGrotesk(fontSize: 9, color: _onVariant.withValues(alpha: 0.35)),
                      prefixIcon: Icon(Icons.search, size: 18, color: _onVariant.withValues(alpha: 0.5)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                  ),
                ),
              IconButton(
                onPressed: () {},
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.notifications_active_outlined, color: _primaryContainer),
                    Positioned(
                      right: 2,
                      top: 2,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(color: _error, shape: BoxShape.circle),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(onPressed: () {}, icon: Icon(Icons.chat_bubble_outline, color: _onVariant.withValues(alpha: 0.85))),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Row(
                  children: [
                    if (isWide) ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_displayName, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: _onSurface)),
                          Text(
                            ((_args?['specialization'] ?? _args?['specialite'] ?? 'Ingénieur conception') as Object).toString().toUpperCase(),
                            style: GoogleFonts.inter(fontSize: 8, color: _onVariant, letterSpacing: 0.2),
                          ),
                        ],
                      ),
                      const SizedBox(width: 10),
                    ],
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: _surfaceHighest,
                      backgroundImage: (_args?['imageUrl'] ?? '').toString().trim().isNotEmpty
                          ? NetworkImage((_args!['imageUrl'] ?? '').toString())
                          : null,
                      child: (_args?['imageUrl'] ?? '').toString().trim().isEmpty
                          ? Text(initial, style: GoogleFonts.inter(color: _primary, fontWeight: FontWeight.w800, fontSize: 14))
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainBody(bool isWide) {
    switch (_navIndex) {
      case 0:
        return _buildOperationalDashboard(isWide);
      case 1:
        return _panelMachines();
      case 2:
        return _panelLocalisation();
      case 3:
        return _panelCapteurs();
      case 5:
        return _panelMotorAnalytics(isWide);
      case 4:
      default:
        return _panelMachineDetail(isWide);
    }
  }

  Widget _panelMotorAnalytics(bool isWide) {
    final name = (_machineRow?['name'] ?? _selectedMachineId ?? 'Machine').toString();
    return _card(
      child: MotorAnalyticsPanel(
        machineId: _selectedMachineId,
        machineLabel: name,
        history: _history,
        latest: _latest,
        loading: _loadingTelemetry,
        onRefresh: () {
          final id = _selectedMachineId;
          if (id != null && id.isNotEmpty) _refreshTelemetry(id);
        },
        healthPct: _healthPct,
        probPanne: _probPanne,
        panneType: (_latest?['panne_type'] ?? _latest?['ml_scenario'] ?? '').toString(),
        scenarioLabel: (_latest?['scenarioLabel'] ?? _latest?['scenario_label'] ?? '').toString(),
        scenarioExplanation: failureScenarioExplanation(_latest) ?? (_latest?['scenarioExplanation']?.toString() ?? ''),
      ),
    );
  }

  /// Maquette « Operational Status » (web + mobile) — données réelles quand disponibles.
  Widget _buildOperationalDashboard(bool isWide) {
    final clientName = (_clientInfo?['name'] ?? 'Flotte industrielle').toString();
    final n = _machines.length;
    final nominal = _probPanne < 35;
    final activeLabel = n > 0 ? (n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k UNITS' : '$n UNITS') : '0 UNITS';

    final header = isWide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                flex: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Operational ',
                            style: GoogleFonts.inter(fontSize: 40, fontWeight: FontWeight.w900, color: _onSurface, height: 1.0),
                          ),
                          TextSpan(
                            text: 'Status',
                            style: GoogleFonts.inter(fontSize: 40, fontWeight: FontWeight.w900, color: _primary, height: 1.0),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Analyse en temps réel de la flotte industrielle. Surveillance des vecteurs de vibration, température et flux cinétique.',
                      style: GoogleFonts.spaceGrotesk(fontSize: 13, color: _onVariant, height: 1.45),
                    ),
                    const SizedBox(height: 10),
                    Text('Client : $clientName', style: GoogleFonts.inter(fontSize: 12, color: _secondary, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Expanded(
                flex: 4,
                child: Row(
                  children: [
                    Expanded(child: _operStatusPill(nominal: nominal)),
                    const SizedBox(width: 12),
                    Expanded(child: _operActivePill(label: activeLabel)),
                  ],
                ),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: 'Operational ', style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w900, color: _onSurface)),
                    TextSpan(text: 'Status', style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w900, color: _primary)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Analyse en temps réel de la flotte industrielle.',
                style: GoogleFonts.spaceGrotesk(fontSize: 12, color: _onVariant),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _operStatusPill(nominal: nominal)),
                  const SizedBox(width: 10),
                  Expanded(child: _operActivePill(label: activeLabel)),
                ],
              ),
            ],
          );

    final gridTop = isWide
        ? SizedBox(
            height: 420,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      Expanded(child: _operMachineCard(slot: 0)),
                      const SizedBox(height: 14),
                      Expanded(child: _operMachineCard(slot: 1)),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(child: _operMapCard()),
              ],
            ),
          )
        : Column(
            children: [
              _operMachineCard(slot: 0),
              const SizedBox(height: 14),
              _operMachineCard(slot: 1),
              const SizedBox(height: 14),
              SizedBox(height: 260, child: _operMapCard()),
            ],
          );

    final bottomRow = isWide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _operAlertsCard()),
              const SizedBox(width: 16),
              Expanded(child: _operEfficiencyCard()),
            ],
          )
        : Column(
            children: [
              _operAlertsCard(),
              const SizedBox(height: 14),
              _operEfficiencyCard(),
            ],
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 28),
        gridTop,
        const SizedBox(height: 16),
        bottomRow,
        const SizedBox(height: 24),
        _operDataStreamSection(),
      ],
    );
  }

  Widget _operStatusPill({required bool nominal}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _outlineVariant.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: _green, shape: BoxShape.circle)),
              AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (_, __) {
                  final t = Curves.easeInOut.transform(_pulseCtrl.value);
                  return Container(
                    width: 8 + t * 8,
                    height: 8 + t * 8,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: _green.withValues(alpha: 0.15 - t * 0.1)),
                  );
                },
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SYSTÈME', style: GoogleFonts.spaceGrotesk(fontSize: 9, letterSpacing: 2, color: _onVariant)),
                Text(nominal ? 'NOMINAL' : 'SURVEILLANCE', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: _onSurface)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _operActivePill({required String label}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _outlineVariant.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(Icons.sensors, color: _secondary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ACTIFS', style: GoogleFonts.spaceGrotesk(fontSize: 9, letterSpacing: 2, color: _onVariant)),
                Text(label, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: _onSurface)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic>? _machineAtSlot(int slot) {
    if (_machines.isEmpty) return null;
    if (slot == 0) return _machines.first;
    if (_machines.length > 1) return _machines[1];
    return null;
  }

  Widget _operMachineCard({required int slot}) {
    final m = _machineAtSlot(slot);
    final isSynth = m == null;
    final id = m != null ? _machineIdOf(m) : 'ARM-X8';
    final name = (m?['name'] ?? (slot == 0 ? 'Générateur Principal' : 'Bras Robotique 02')).toString();
    final sub = (m?['motorType'] ?? m?['type'] ?? (slot == 0 ? 'Turbine-A42' : 'ARM-X8')).toString();
    final mid = m != null ? id : '';
    final warn = !isSynth && _probPanne > 40 && _selectedMachineId == mid;

    double t;
    double v;
    if (!isSynth && _latest != null && _selectedMachineId == mid) {
      t = _metric('thermal', 42.5);
      v = _metric('vibration', 0.02);
    } else if (!isSynth) {
      t = 42.5;
      v = 0.02;
    } else {
      t = 42.5;
      v = 0.02;
    }

    const torque = 88.2;
    const cycles = '1,2k';
    final showTorqueRow = slot == 1 && isSynth;

    return Material(
      color: _surfaceLow,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () {
          if (m != null) {
            final mid = _machineIdOf(m);
            setState(() {
              _selectedMachineId = mid;
              _machineRow = m;
              _navIndex = 4;
            });
            _refreshTelemetry(mid);
            _startPoll();
            _reloadSensorPhotoPrefs();
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _outlineVariant.withValues(alpha: 0.12)),
          ),
          clipBehavior: Clip.hardEdge,
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sub.toUpperCase(),
                            style: GoogleFonts.spaceGrotesk(fontSize: 8, fontWeight: FontWeight.w800, color: _secondary, letterSpacing: 1.6),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: _onSurface, height: 1.15),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: _surfaceHighest,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: (warn ? _primary : _green).withValues(alpha: 0.25)),
                      ),
                      child: Text(
                        warn ? 'WARNING' : 'OPTIMAL',
                        style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.bold, color: warn ? _primary : _green),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (showTorqueRow)
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('COUPLE', style: GoogleFonts.spaceGrotesk(fontSize: 8, color: _onVariant)),
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: '$torque', style: GoogleFonts.spaceGrotesk(fontSize: 18, color: warn ? _primary : _onSurface)),
                                  TextSpan(text: ' Nm', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onVariant)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('CYCLE', style: GoogleFonts.spaceGrotesk(fontSize: 8, color: _onVariant)),
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: cycles, style: GoogleFonts.spaceGrotesk(fontSize: 18, color: _onSurface)),
                                  TextSpan(text: ' /h', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onVariant)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('TEMPÉRATURE', style: GoogleFonts.spaceGrotesk(fontSize: 8, color: _onVariant)),
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: t.toStringAsFixed(1), style: GoogleFonts.spaceGrotesk(fontSize: 18, color: _onSurface)),
                                  TextSpan(text: ' °C', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onVariant)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('VIBRATION', style: GoogleFonts.spaceGrotesk(fontSize: 8, color: _onVariant)),
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: v.toStringAsFixed(2), style: GoogleFonts.spaceGrotesk(fontSize: 18, color: _onSurface)),
                                  TextSpan(text: ' mm/s', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onVariant)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          gradient: const LinearGradient(colors: [_primaryContainer, _primary]),
                          boxShadow: [BoxShadow(color: _primaryContainer.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              if (m != null) {
                                final mid = _machineIdOf(m);
                                setState(() {
                                  _selectedMachineId = mid;
                                  _machineRow = m;
                                  _navIndex = 4;
                                });
                                _refreshTelemetry(mid);
                                _startPoll();
                                _reloadSensorPhotoPrefs();
                              }
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Center(
                                child: Text(
                                  slot == 1 || warn ? 'DIAGNOSTIQUE' : 'CONTRÔLER',
                                  style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.6, color: const Color(0xFF582100)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                      padding: EdgeInsets.zero,
                      style: IconButton.styleFrom(backgroundColor: _surfaceHighest, foregroundColor: _onVariant),
                      onPressed: () {},
                      icon: const Icon(Icons.forum_outlined, size: 20),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _operMapCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surfaceLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _outlineVariant.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MAP_LIVE', style: GoogleFonts.spaceGrotesk(fontSize: 9, fontWeight: FontWeight.w800, color: _secondary, letterSpacing: 2)),
          const SizedBox(height: 6),
          Text('Répartition géographique', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: _onSurface)),
          const SizedBox(height: 14),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColorFiltered(
                    colorFilter: const ColorFilter.matrix(<double>[
                      0.2126, 0.7152, 0.0722, 0, 0,
                      0.2126, 0.7152, 0.0722, 0, 0,
                      0.2126, 0.7152, 0.0722, 0, 0,
                      0, 0, 0, 1, 0,
                    ]),
                    child: Image.network(_mapLiveImg, fit: BoxFit.cover, opacity: const AlwaysStoppedAnimation(0.55)),
                  ),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xFF0B0B26)]),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          color: _surface.withValues(alpha: 0.82),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('SITE ALPHA-6', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 2)),
                                  Text('Active', style: GoogleFonts.inter(fontSize: 9, color: _secondary, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(99),
                                child: LinearProgressIndicator(value: 0.66, minHeight: 4, backgroundColor: _surfaceHighest, color: _secondary),
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
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Charge réseau', style: GoogleFonts.inter(fontSize: 11, color: _onVariant)),
              Text('84%', style: GoogleFonts.spaceGrotesk(fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Latence moyenne', style: GoogleFonts.inter(fontSize: 11, color: _onVariant)),
              Text('12 ms', style: GoogleFonts.spaceGrotesk(fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _operAlertsCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _surfaceLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _outlineVariant.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SYSTÈME D\'ALERTES', style: GoogleFonts.spaceGrotesk(fontSize: 9, fontWeight: FontWeight.w800, color: _secondary, letterSpacing: 2)),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(width: 6, height: 6, margin: const EdgeInsets.only(top: 5), decoration: const BoxDecoration(color: _error, shape: BoxShape.circle)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Alerte vibration ${_machines.isNotEmpty ? _machineIdOf(_machines.first) : 'Turbine-A42'}',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    Text('Il y a 5 minutes', style: GoogleFonts.inter(fontSize: 10, color: _onVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(width: 6, height: 6, margin: const EdgeInsets.only(top: 5), decoration: const BoxDecoration(color: _secondary, shape: BoxShape.circle)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Maintenance préventive ligne B', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                    Text('Prévu demain à 08:00', style: GoogleFonts.inter(fontSize: 10, color: _onVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.arrow_forward, size: 16, color: Color(0xFF75D1FF)),
            label: Text('VOIR TOUT L\'HISTORIQUE', style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.bold, color: _secondary, letterSpacing: 1.2)),
          ),
        ],
      ),
    );
  }

  Widget _operEfficiencyCard() {
    final pct = _healthPct.clamp(0, 100) / 100.0;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _surfaceLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _outlineVariant.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('EFFICIENCY_CORE', style: GoogleFonts.spaceGrotesk(fontSize: 9, fontWeight: FontWeight.w800, color: _secondary, letterSpacing: 2)),
          const SizedBox(height: 6),
          Text('Efficacité globale', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: _onSurface)),
          const SizedBox(height: 12),
          Center(
            child: SizedBox(
              width: 120,
              height: 120,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: pct,
                      strokeWidth: 8,
                      backgroundColor: _surfaceHighest,
                      color: _secondary,
                    ),
                  ),
                  Text(
                    '${_healthPct}%',
                    style: GoogleFonts.spaceGrotesk(fontSize: 28, fontWeight: FontWeight.w900, color: _onSurface),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '+4.2% depuis dernier log',
              style: GoogleFonts.spaceGrotesk(fontSize: 9, color: _onVariant, letterSpacing: 1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _operDataStreamSection() {
    return _glassPanel(
      padding: const EdgeInsets.all(28),
      child: Stack(
        children: [
          Positioned(
            right: 0,
            top: 0,
            child: Icon(Icons.analytics_outlined, size: 100, color: _primaryContainer.withValues(alpha: 0.12)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'FLUX DE DONNÉES TEMPS RÉEL',
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w900, color: _primaryContainer, letterSpacing: 3),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 40,
                runSpacing: 24,
                children: [
                  SizedBox(
                    width: 200,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('THROUGHPUT', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onVariant)),
                        const SizedBox(height: 6),
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: '14.8 ', style: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.w900, color: _onSurface)),
                              TextSpan(text: 'GB/s', style: GoogleFonts.inter(fontSize: 16, color: _primaryContainer, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(value: 0.75, minHeight: 4, backgroundColor: _surfaceHighest, color: _primaryContainer),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ACTIVE QUERIES', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onVariant)),
                        const SizedBox(height: 6),
                        Text('1,042', style: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.w900, color: _onSurface)),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(value: 0.5, minHeight: 4, backgroundColor: _surfaceHighest, color: _secondary),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 280,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('HEALTH DISTRIBUTION', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onVariant)),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 48,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [0.9, 0.7, 0.85, 0.95, 1.0, 0.8, 0.6, 0.4].map((h) {
                              final isP = h == 1.0;
                              return Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 2),
                                  child: Align(
                                    alignment: Alignment.bottomCenter,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: (isP ? _primaryContainer : _secondary).withValues(alpha: isP ? 1 : (0.15 + h * 0.45).clamp(0.2, 0.85)),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                      child: SizedBox(height: (48 * h).clamp(8.0, 48.0), width: double.infinity),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _panelClient() {
    final name = (_clientInfo?['name'] ?? '—').toString();
    final cid = (_clientInfo?['clientId'] ?? _args?['companyId'] ?? '').toString();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CLIENT RATTACHÉ', style: GoogleFonts.spaceGrotesk(fontSize: 10, letterSpacing: 2, color: _onVariant)),
          const SizedBox(height: 16),
          Text(name, style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800, color: _onSurface)),
          const SizedBox(height: 8),
          Text('Réf. client : $cid', style: GoogleFonts.spaceGrotesk(color: _secondary)),
        ],
      ),
    );
  }

  Widget _panelMachines() {
    if (_machines.isEmpty) {
      return _card(child: Text('Aucune machine assignée à ce compte.', style: GoogleFonts.inter(color: _onVariant)));
    }
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: _machines.map((m) {
        final id = _machineIdOf(m);
        final sel = id == _selectedMachineId;
        final latestTemp = sel ? _metric('thermal', _toDouble(_latest?['temperature'], 0)) : null;
        return InkWell(
          onTap: () {
            setState(() {
              _selectedMachineId = id;
              _machineRow = m;
              _navIndex = 4;
            });
            _refreshTelemetry(id);
            _startPoll();
            _reloadSensorPhotoPrefs();
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 220,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _surfaceLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: sel ? _primaryContainer : _outlineVariant.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.precision_manufacturing, color: sel ? _primaryContainer : _secondary),
                const SizedBox(height: 12),
                Text((m['name'] ?? id).toString(), style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: _onSurface)),
                Text(id, style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onVariant)),
                if (sel && latestTemp != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: _surfaceHighest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _primaryContainer.withValues(alpha: 0.32)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.thermostat, size: 16, color: _primary),
                        const SizedBox(width: 6),
                        Text(
                          'MQTT temp: ${latestTemp.toStringAsFixed(1)} °C',
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: _onSurface),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _panelLocalisation() {
    final cid = (_clientInfo?['clientId'] ?? _args?['companyId'] ?? '').toString();
    final name = (_clientInfo?['name'] ?? 'Client').toString();
    if (cid.isEmpty) {
      return _card(child: Text('Aucun client associé (companyId).', style: GoogleFonts.inter(color: _onVariant)));
    }
    final mid = (_selectedMachineId ?? '').trim();
    final gps = _readGpsFromLatest();
    final topic = mid.isEmpty ? 'machines/<machineId>/telemetry' : 'machines/$mid/telemetry';
    const espHint =
        'Sur l’ESP32 + module GPS : lire NMEA / TinyGPS++, puis publier en JSON sur MQTT (même broker que la télémétrie). '
        'Le backend enregistre automatiquement lat/lng dans la dernière télémétrie.';

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.satellite_alt, color: _secondary, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('LOCALISATION DU PARC', style: GoogleFonts.spaceGrotesk(fontSize: 10, letterSpacing: 2, color: _onVariant)),
                    const SizedBox(height: 4),
                    Text(name, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: _onSurface)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _surfaceLowest,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _outlineVariant.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('GPS — liaison ESP32 → MQTT → API', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: _onSurface)),
                const SizedBox(height: 8),
                Text(espHint, style: GoogleFonts.inter(fontSize: 12, color: _onVariant, height: 1.4)),
                const SizedBox(height: 12),
                Text('Topic MQTT', style: GoogleFonts.spaceGrotesk(fontSize: 9, letterSpacing: 1.2, color: _secondary)),
                const SizedBox(height: 4),
                SelectableText(topic, style: GoogleFonts.spaceGrotesk(fontSize: 11, color: _onSurface, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Text('Exemple de payload JSON', style: GoogleFonts.spaceGrotesk(fontSize: 9, letterSpacing: 1.2, color: _secondary)),
                const SizedBox(height: 6),
                SelectableText(
                  mid.isEmpty
                      ? '{"machineId":"VOTRE_ID_MACHINE","lat":36.7538,"lng":3.0588,"temperature":42}'
                      : '{"machineId":"$mid","lat":36.7538,"lng":3.0588,"temperature":42}',
                  style: GoogleFonts.jetBrainsMono(fontSize: 10.5, color: _onSurface.withValues(alpha: 0.92), height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (mid.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _primaryContainer.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _primaryContainer.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Icon(Icons.precision_manufacturing_outlined, color: _primaryContainer, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Sélectionnez une machine dans l’onglet « Machine » pour afficher le flux GPS et le topic exact.',
                      style: GoogleFonts.inter(fontSize: 12, color: _onSurface, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
            if (mid.isEmpty) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ClientPositionPage(clientName: name, clientData: {'clientId': cid}),
                    ),
                  );
                },
                icon: const Icon(Icons.map_outlined),
                label: const Text('Ouvrir la vue localisation (flotte)'),
                style: FilledButton.styleFrom(backgroundColor: _primaryContainer, foregroundColor: const Color(0xFF582100)),
              ),
            ],
          if (mid.isNotEmpty) ...[
            Text('Machine suivie', style: GoogleFonts.spaceGrotesk(fontSize: 9, letterSpacing: 1.2, color: _onVariant)),
            const SizedBox(height: 4),
            Text(mid, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: _secondary)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _gpsCoordTile('Latitude', gps.lat != null ? '${gps.lat!.toStringAsFixed(6)}°' : '—', gps.hasFix ? _green : _onVariant),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _gpsCoordTile('Longitude', gps.lng != null ? '${gps.lng!.toStringAsFixed(6)}°' : '—', gps.hasFix ? _green : _onVariant),
                ),
              ],
            ),
            if (_latestTelemetryLabel() != null) ...[
              const SizedBox(height: 8),
              Text(
                'Dernière télémétrie : ${_latestTelemetryLabel()}',
                style: GoogleFonts.inter(fontSize: 11, color: _onVariant.withValues(alpha: 0.85)),
              ),
            ],
            if (_loadingTelemetry) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(minHeight: 3, color: _primaryContainer, backgroundColor: _surfaceHighest),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(gps.hasFix ? Icons.gps_fixed : Icons.gps_not_fixed, size: 18, color: gps.hasFix ? _green : _onVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    gps.hasFix ? 'Signal GPS présent dans les données reçues.' : 'En attente de lat/lng depuis l’ESP32 (MQTT).',
                    style: GoogleFonts.inter(fontSize: 12, color: _onVariant, height: 1.3),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: gps.hasFix ? () => _openGpsInMaps(gps.lat!, gps.lng!) : null,
                  icon: const Icon(Icons.map_outlined, size: 20),
                  label: const Text('Ouvrir dans Maps'),
                  style: FilledButton.styleFrom(backgroundColor: _primaryContainer, foregroundColor: const Color(0xFF582100)),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push<void>(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => ClientPositionPage(clientName: name, clientData: {'clientId': cid}),
                      ),
                    );
                  },
                  icon: Icon(Icons.dashboard_customize_outlined, size: 20, color: _secondary),
                  label: Text('Vue flotte / carte', style: GoogleFonts.inter(color: _onSurface, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(side: BorderSide(color: _outlineVariant.withValues(alpha: 0.45))),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _gpsCoordTile(String title, String value, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: _surfaceLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: accent == _green ? 0.35 : 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: GoogleFonts.spaceGrotesk(fontSize: 8, letterSpacing: 1.2, color: _onVariant)),
          const SizedBox(height: 4),
          Text(value, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: _onSurface)),
        ],
      ),
    );
  }

  Widget _panelCapteurs() {
    final t = _metric('thermal', 142.8);
    final p = _metric('pressure', 4.12);
    final v = _metric('vibration', 0.02);
    final deb = _metric('ultrasonic', 850);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('CAPTEURS (DERNIÈRE TÉLÉMÉTRIE)', style: GoogleFonts.spaceGrotesk(fontSize: 10, letterSpacing: 2, color: _onVariant)),
              ),
              Text(
                'Machine : ${_selectedMachineId ?? '—'}',
                style: GoogleFonts.inter(fontSize: 10, color: _secondary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _sensorCardWithPhoto(
            sensorKey: 'thermal',
            label: 'Thermique',
            value: '${t.toStringAsFixed(1)} °C',
            icon: Icons.thermostat,
            c: _primary,
          ),
          _sensorCardWithPhoto(
            sensorKey: 'pressure',
            label: 'Pression',
            value: '${p.toStringAsFixed(2)} bar',
            icon: Icons.compress,
            c: _secondary,
          ),
          _sensorCardWithPhoto(
            sensorKey: 'vibration',
            label: 'Vibration',
            value: '${v.toStringAsFixed(2)} mm/s',
            icon: Icons.vibration,
            c: _tertiary,
          ),
          _sensorCardWithPhoto(
            sensorKey: 'ultrasonic',
            label: 'Débit / prox.',
            value: deb.toStringAsFixed(0),
            icon: Icons.waves,
            c: _onVariant,
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: _surfaceHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _secondary.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RÉF. CAPTEURS (PARC)',
                  style: GoogleFonts.spaceGrotesk(fontSize: 8, letterSpacing: 1.2, color: _secondary),
                ),
                const SizedBox(height: 6),
                ...DeployedSensors.summaryLines.map(
                  (line) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      '· $line',
                      style: GoogleFonts.inter(fontSize: 10, height: 1.35, color: _onSurface.withValues(alpha: 0.88)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _panelMachineDetail(bool isWide) {
    if (_selectedMachineId == null || _selectedMachineId!.isEmpty) {
      return _card(child: Text('Sélectionnez une machine dans l’onglet « Machine ».', style: GoogleFonts.inter(color: _onVariant)));
    }
    final title = (_machineRow?['name'] ?? _selectedMachineId).toString();
    final sub = (_machineRow?['type'] ?? 'Générateur thermique haute pression').toString();
    final t = _metric('thermal', 142.8);
    final p = _metric('pressure', 4.12);
    final v = _metric('vibration', 0.02);
    final deb = _metric('ultrasonic', 850);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AnimatedBuilder(
                        animation: _pulseCtrl,
                        builder: (_, __) {
                          final p = Curves.easeOutCubic.transform(_pulseCtrl.value);
                          return Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _green,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: _green.withValues(alpha: 0.45),
                                  blurRadius: 6 + p * 14,
                                  spreadRadius: p * 3,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          title.toUpperCase(),
                          style: GoogleFonts.inter(fontSize: 26, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, color: _onSurface),
                        ),
                      ),
                      if (_loadingTelemetry) ...[const SizedBox(width: 12), const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _primaryContainer))],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('$sub // $_selectedMachineId', style: GoogleFonts.spaceGrotesk(fontSize: 12, letterSpacing: 1.2, color: _onVariant)),
                ],
              ),
            ),
            Wrap(
              spacing: 10,
              children: [
                OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(foregroundColor: _onSurface, side: BorderSide(color: _outlineVariant.withValues(alpha: 0.35))),
                  child: Text('LOGS SYSTÈME', style: GoogleFonts.spaceGrotesk(fontSize: 10, letterSpacing: 1.5)),
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _openFullMachineIa,
                    borderRadius: BorderRadius.circular(8),
                    child: Ink(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [_primaryContainer, _primary],
                        ),
                        boxShadow: [
                          BoxShadow(color: _primaryContainer.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        child: Text(
                          'INTERVENTION IA',
                          style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: Color(0xFF582100)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (isWide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 8, child: _hero3d(t, p, isWide: true)),
              const SizedBox(width: 20),
              Expanded(flex: 4, child: Column(children: [_predictiveCard(), const SizedBox(height: 16), _alertCard()])),
            ],
          )
        else ...[
          _hero3d(t, p, isWide: false),
          const SizedBox(height: 16),
          _predictiveCard(),
          const SizedBox(height: 16),
          _alertCard(),
        ],
        const SizedBox(height: 20),
        _telemetryStrip(t, p, v, deb),
        const SizedBox(height: 20),
        _historyChart(),
      ],
    );
  }

  Widget _hero3d(double t, double p, {required bool isWide}) {
    return Container(
      height: isWide ? 500 : 360,
      decoration: BoxDecoration(
        color: _surfaceLow,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: _outlineVariant.withValues(alpha: 0.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [_bg, Colors.transparent]))),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Image.network(_turbineImg, fit: BoxFit.contain, opacity: const AlwaysStoppedAnimation(0.85)),
          ),
          Positioned(
            top: 100,
            left: 72,
            child: Row(
              children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: _primary, shape: BoxShape.circle, boxShadow: [BoxShadow(color: _primary.withValues(alpha: 0.4), blurRadius: 8)])),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: _surfaceHighest.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(4)),
                  child: Text('TEMP_CORE: ${t.toStringAsFixed(0)}°C', style: GoogleFonts.spaceGrotesk(fontSize: 9, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 120,
            right: 48,
            child: Row(
              children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: _secondary, shape: BoxShape.circle, boxShadow: [BoxShadow(color: _secondary.withValues(alpha: 0.4), blurRadius: 8)])),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: _surfaceHighest.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(4)),
                  child: Text('PRESS_VALVE: ${p.toStringAsFixed(1)} BAR', style: GoogleFonts.spaceGrotesk(fontSize: 9, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          Positioned(
            left: 16,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _legendLine(_primary, 'ZONE DE CHALEUR CRITIQUE'),
                const SizedBox(height: 6),
                _legendLine(_secondary, 'FLUX DE LIQUIDE'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendLine(Color c, String s) {
    return Row(
      children: [
        Container(width: 36, height: 1, color: c),
        const SizedBox(width: 8),
        Text(s, style: GoogleFonts.spaceGrotesk(fontSize: 9, letterSpacing: 1.2, color: _onVariant)),
      ],
    );
  }

  String _revisionLabel() {
    final raw = _machineRow?['updatedAt'] ?? _machineRow?['installDate'];
    if (raw == null) return '—';
    try {
      final d = DateTime.parse(raw.toString()).toLocal();
      const mois = ['janv', 'févr', 'mars', 'avr', 'mai', 'juin', 'juil', 'août', 'sept', 'oct', 'nov', 'déc'];
      return '${d.day} ${mois[d.month - 1]} ${d.year}';
    } catch (_) {
      return '—';
    }
  }

  Widget _predictiveCard() {
    return _glassPanel(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('SANTÉ PRÉDICTIVE', style: GoogleFonts.spaceGrotesk(fontSize: 10, letterSpacing: 2.2, color: _onVariant)),
              Icon(Icons.psychology_rounded, color: _secondary, size: 22),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$_healthPct', style: GoogleFonts.inter(fontSize: 56, fontWeight: FontWeight.w900, color: _onSurface, height: 1)),
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text('%', style: GoogleFonts.inter(fontSize: 20, color: _onVariant)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: _healthPct / 100,
              minHeight: 4,
              backgroundColor: _surfaceHighest,
              color: _secondary,
            ),
          ),
          const SizedBox(height: 16),
          Text.rich(
            TextSpan(
              style: GoogleFonts.inter(fontSize: 13, height: 1.45, color: _onVariant),
              children: [
                const TextSpan(
                  text:
                      "L'IA détecte une anomalie mineure de vibration dans le palier B. Probabilité de maintenance requise sous 14 jours : ",
                ),
                TextSpan(
                  text: '$_probPanne%',
                  style: GoogleFonts.inter(color: _primary, fontWeight: FontWeight.w800),
                ),
                const TextSpan(text: '.\n'),
                TextSpan(text: _iaHint),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('PROCHAINE RÉVISION', style: GoogleFonts.spaceGrotesk(fontSize: 9, letterSpacing: 1.6, color: _onVariant)),
              Text(_revisionLabel(), style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.w600, color: _onSurface)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _alertCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _errorContainer.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: _error),
              const SizedBox(width: 8),
              Text('ALERTE SYSTÈME', style: GoogleFonts.spaceGrotesk(fontSize: 10, letterSpacing: 2, color: _error, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _pressureAlert ? 'Pic de pression détecté sur la vanne de décharge V-12.' : 'Aucune alerte critique sur les seuils courants.',
            style: GoogleFonts.inter(fontSize: 12, color: _error.withValues(alpha: 0.85)),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {},
              style: FilledButton.styleFrom(backgroundColor: _error, foregroundColor: const Color(0xFF690005)),
              child: Text('RÉSOUDRE L\'INCIDENT', style: GoogleFonts.spaceGrotesk(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _telemetryStrip(double t, double p, double v, double deb) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth > 900 ? 4 : 2;
        final w = (c.maxWidth - (cols - 1) * 16) / cols;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _telTile('Thermique', t, '°C', Icons.thermostat, _primary, w, const [0.4, 0.6, 0.55, 0.7, 0.85]),
            _telTile('Pression', p, 'BAR', Icons.compress, _secondary, w, const [0.8, 0.75, 0.82, 0.78, 0.8]),
            _telTile('Vibration', v, 'MM/S', Icons.vibration, _tertiary, w, const [0.2, 0.15, 0.25, 0.3, 0.15]),
            _telTile('Débit', deb, 'L/MIN', Icons.waves, _onVariant, w, const [0.6, 0.62, 0.58, 0.6, 0.61]),
          ],
        );
      },
    );
  }

  Widget _telTile(String label, double val, String unit, IconData icon, Color accent, double width, List<double> bars) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: _surfaceLow, borderRadius: BorderRadius.circular(4)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label.toUpperCase(), style: GoogleFonts.spaceGrotesk(fontSize: 9, letterSpacing: 1.5, color: _onVariant)),
                Icon(icon, size: 18, color: accent),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  val >= 100 ? val.toStringAsFixed(0) : val.toStringAsFixed(val < 1 ? 2 : 1),
                  style: GoogleFonts.spaceGrotesk(fontSize: 28, fontWeight: FontWeight.bold, color: _onSurface),
                ),
                const SizedBox(width: 6),
                Text(unit, style: GoogleFonts.spaceGrotesk(fontSize: 11, color: _onVariant)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 32,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(5, (i) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Container(
                        height: 32 * bars[i].clamp(0.05, 1.0),
                        decoration: BoxDecoration(
                          color: i == 4 ? accent : accent.withValues(alpha: 0.22),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyChart() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: _surfaceLow, borderRadius: BorderRadius.circular(4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('ANALYSE DE PERFORMANCE HISTORIQUE', style: GoogleFonts.spaceGrotesk(fontSize: 10, letterSpacing: 2, color: _onSurface)),
              Row(
                children: [
                  _dotLegend('Température', _primary),
                  const SizedBox(width: 16),
                  _dotLegend('Pression', _secondary),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: CustomPaint(
              painter: _HistoryPainter(_history),
              size: const Size(double.infinity, 200),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: ['08:00', '10:00', '12:00', '14:00', '16:00', '18:00', '20:00']
                .map((e) => Text(e, style: GoogleFonts.spaceGrotesk(fontSize: 9, color: _onVariant.withValues(alpha: 0.5))))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _dotLegend(String s, Color c) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(s.toUpperCase(), style: GoogleFonts.spaceGrotesk(fontSize: 9, color: _onVariant)),
      ],
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: _surfaceLow, borderRadius: BorderRadius.circular(12), border: Border.all(color: _outlineVariant.withValues(alpha: 0.1))),
      child: child,
    );
  }
}

class _HistoryPainter extends CustomPainter {
  final List<Map<String, dynamic>> history;
  _HistoryPainter(this.history);

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = const Color(0xFF594136).withValues(alpha: 0.12)..strokeWidth = 1;
    for (var y = 0.0; y <= size.height; y += 50) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (history.length < 2) {
      final p1 = Paint()..color = const Color(0xFFFFB692).withValues(alpha: 0.85)..strokeWidth = 2..style = PaintingStyle.stroke;
      final p2 = Paint()..color = const Color(0xFF75D1FF).withValues(alpha: 0.85)..strokeWidth = 2..style = PaintingStyle.stroke;
      canvas.drawPath(_demoPath(size, 0.55, 0.35), p1);
      canvas.drawPath(_demoPath(size, 0.4, 0.5), p2);
      return;
    }
    final n = history.length;
    final temps = <double>[];
    final press = <double>[];
    for (final h in history) {
      final m = h['metrics'];
      double t = 0, p = 0;
      if (m is Map) {
        t = (m['thermal'] as num?)?.toDouble() ?? 0;
        p = (m['pressure'] as num?)?.toDouble() ?? 0;
      }
      t = t > 0 ? t : (h['temperature'] as num?)?.toDouble() ?? 0;
      p = p > 0 ? p : (h['pressure'] as num?)?.toDouble() ?? 0;
      temps.add(t);
      press.add(p);
    }
    void drawSeries(List<double> vals, Color color) {
      if (vals.isEmpty) return;
      final minV = vals.reduce(math.min);
      final maxV = vals.reduce(math.max);
      final span = (maxV - minV).abs() < 1e-6 ? 1.0 : (maxV - minV);
      final path = Path();
      for (var i = 0; i < vals.length; i++) {
        final x = size.width * (i / (n - 1));
        final ny = (vals[i] - minV) / span;
        final y = size.height * (0.85 - ny * 0.7);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.9)..strokeWidth = 2..style = PaintingStyle.stroke);
    }

    drawSeries(temps, const Color(0xFFFFB692));
    drawSeries(press, const Color(0xFF75D1FF));
  }

  Path _demoPath(Size size, double phase, double amp) {
    final path = Path();
    for (var i = 0; i <= 40; i++) {
      final x = size.width * (i / 40);
      final y = size.height * (0.5 + amp * math.sin(i / 5 + phase * 10));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant _HistoryPainter oldDelegate) => oldDelegate.history != history;
}
