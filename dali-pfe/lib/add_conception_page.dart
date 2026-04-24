import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'maintenance_module_page.dart';
import 'services/api_service.dart';

class AddConceptionPage extends StatefulWidget {
  /// Si non null : intégré au dashboard (pas de barre latérale dupliquée, retour vers la liste).
  final VoidCallback? onEmbeddedBack;

  const AddConceptionPage({super.key, this.onEmbeddedBack});

  @override
  State<AddConceptionPage> createState() => _AddConceptionPageState();
}

class _AddConceptionPageState extends State<AddConceptionPage> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  int _selectedDocType = 1;

  static const List<String> _docTypes = [
    'Plan mécanique',
    'Schéma électrique',
    'Rapport technique',
    'Manuel maintenance',
  ];

  final _docNameCtrl = TextEditingController(text: 'Plan Turbo-Alternateur XJ4');
  final _versionCtrl = TextEditingController(text: 'v1.0');
  final _secEmailCtrl = TextEditingController();
  final _secPassCtrl = TextEditingController();

  List<Map<String, dynamic>> _clients = [];
  bool _clientsLoading = true;
  String? _selectedClientKey;
  bool _saving = false;

  String get _selectedDocTypeLabel =>
      _docTypes[_selectedDocType.clamp(0, _docTypes.length - 1)];

  void _notifySummary() {
    if (mounted) setState(() {});
  }

  String _clientApiKey(Map<String, dynamic> c) {
    final v = c['clientId'] ?? c['id'] ?? c['_id'];
    return v == null ? '' : v.toString();
  }

  String _clientDisplayName(Map<String, dynamic> c) {
    final name = c['name'] ?? c['companyName'];
    if (name != null && name.toString().isNotEmpty) return name.toString();
    return _clientApiKey(c);
  }

  String _selectedClientDisplayName() {
    final key = _selectedClientKey;
    if (key == null || key.isEmpty) return '—';
    for (final c in _clients) {
      if (_clientApiKey(c) == key) return _clientDisplayName(c);
    }
    return key;
  }

  Future<void> _loadClients() async {
    setState(() => _clientsLoading = true);
    try {
      final list = await ApiService.getClients();
      if (!mounted) return;
      setState(() {
        _clients = list;
        _clientsLoading = false;
        final keys = list.map(_clientApiKey).where((k) => k.isNotEmpty).toList();
        if (_selectedClientKey == null || !keys.contains(_selectedClientKey)) {
          _selectedClientKey = keys.isNotEmpty ? keys.first : null;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _clientsLoading = false);
    }
  }

  Future<void> _saveDocument() async {
    final name = _docNameCtrl.text.trim();
    final version = _versionCtrl.text.trim();
    final clientKey = _selectedClientKey?.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nom du document obligatoire'), backgroundColor: Colors.red),
      );
      return;
    }
    if (clientKey == null || clientKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sélectionnez le client qui pilote les machines concernées'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ApiService.addConception({
        'name': name,
        'version': version.isEmpty ? 'v1.0' : version,
        'documentType': _selectedDocTypeLabel,
        'clientId': clientKey,
        if (_secEmailCtrl.text.trim().isNotEmpty) 'securityEmail': _secEmailCtrl.text.trim(),
        if (_secPassCtrl.text.isNotEmpty) 'password': _secPassCtrl.text,
      });
      if (!mounted) return;
      if (widget.onEmbeddedBack != null) {
        widget.onEmbeddedBack!();
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _cancel() {
    if (widget.onEmbeddedBack != null) {
      widget.onEmbeddedBack!();
    } else {
      Navigator.pop(context);
    }
  }

  // Colors
  static const Color _bg = Color(0xFF10102b);
  static const Color _surfaceContainerLowest = Color(0xFF0b0b26);
  static const Color _surfaceContainerLow = Color(0xFF191934);
  static const Color _surfaceContainer = Color(0xFF1d1d38);
  static const Color _surfaceContainerHigh = Color(0xFF272743);
  static const Color _surfaceContainerHighest = Color(0xFF32324e);
  
  static const Color _primary = Color(0xFFffb692);
  static const Color _primaryContainer = Color(0xFFff6e00);
  static const Color _secondary = Color(0xFF4DD0E1); // Using cyan from screenshot
  static const Color _secondaryBlue = Color(0xFF75d1ff);
  static const Color _error = Color(0xFFffb4ab);
  
  static const Color _onSurface = Color(0xFFe2dfff);
  static const Color _onSurfaceVariant = Color(0xFFe2bfb0);
  static const Color _outlineVariant = Color(0xFF594136);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _docNameCtrl.addListener(_notifySummary);
    _versionCtrl.addListener(_notifySummary);
    _loadClients();
  }

  @override
  void dispose() {
    _docNameCtrl.removeListener(_notifySummary);
    _versionCtrl.removeListener(_notifySummary);
    _docNameCtrl.dispose();
    _versionCtrl.dispose();
    _secEmailCtrl.dispose();
    _secPassCtrl.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final embedded = widget.onEmbeddedBack != null;
    return Scaffold(
      backgroundColor: _bg,
      body: Row(
        children: [
          if (!embedded) _buildSidebar(),
          Expanded(
            child: Column(
              children: [
                _buildTopNavBar(),
                Expanded(
                  child: _buildMainContent(),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  // --- Sidebar ---
  Widget _buildSidebar() {
    return Container(
      width: 256,
      decoration: BoxDecoration(
        color: _surfaceContainerLow,
        border: Border(right: BorderSide(color: _outlineVariant.withOpacity(0.15))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Predictive Cloud', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: _primaryContainer, letterSpacing: -0.5)),
                const SizedBox(height: 4),
                Text('SuperAdmin Dashboard', style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.bold, color: _onSurfaceVariant, letterSpacing: 2)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _sidebarItem(Icons.business_center_outlined, 'Clients', false),
                _sidebarItem(Icons.factory_outlined, 'Actifs', false),
                _sidebarItem(Icons.engineering_outlined, 'Techniciens', false),
                _sidebarItem(
                  Icons.build_circle_outlined,
                  'Maintenance',
                  false,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const MaintenanceModulePage(standalone: true),
                      ),
                    );
                  },
                ),
                _sidebarItem(Icons.precision_manufacturing, 'Conception', true),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                _sidebarItem(Icons.settings_outlined, 'Paramètres', false),
                const SizedBox(height: 8),
                _sidebarItem(Icons.logout, 'Déconnexion', false, colorOverride: _error),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebarItem(IconData icon, String title, bool isActive, {Color? colorOverride, VoidCallback? onTap}) {
    final color = colorOverride ?? (isActive ? _primaryContainer : _onSurfaceVariant);
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: isActive ? _surfaceContainerHighest.withOpacity(0.6) : Colors.transparent,
        border: isActive ? Border(right: BorderSide(color: _primaryContainer, width: 3)) : null,
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 16),
          Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: isActive ? FontWeight.bold : FontWeight.w500, color: colorOverride ?? (isActive ? _primaryContainer : _onSurfaceVariant.withOpacity(0.9)))),
        ],
      ),
    );
    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(onTap: onTap, child: child),
      );
    }
    return child;
  }

  // --- Top Navigation Bar ---
  Widget _buildTopNavBar() {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        color: _bg.withOpacity(0.8),
        border: Border(bottom: BorderSide(color: _outlineVariant.withOpacity(0.15))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 300,
                height: 40,
                decoration: BoxDecoration(color: _surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(Icons.search, color: _onSurfaceVariant.withOpacity(0.7), size: 18),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        style: GoogleFonts.spaceGrotesk(fontSize: 12, color: _onSurface),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          hintText: 'RECHERCHER UN ÉLÉMENT...',
                          hintStyle: GoogleFonts.spaceGrotesk(fontSize: 12, color: _onSurfaceVariant.withOpacity(0.5), letterSpacing: 2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 32),
              Text('STATUT SYSTÈME', style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.bold, color: _onSurfaceVariant, letterSpacing: 2)),
              const SizedBox(width: 24),
              Text('ALERTES', style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.bold, color: _onSurfaceVariant, letterSpacing: 2)),
            ],
          ),
          Row(
            children: [
              const Icon(Icons.notifications_outlined, color: _onSurfaceVariant),
              const SizedBox(width: 24),
              Container(width: 1, height: 32, color: _outlineVariant.withOpacity(0.2)),
              const SizedBox(width: 24),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('CONNECTÉ EN TANT QUE', style: GoogleFonts.spaceGrotesk(fontSize: 8, color: _onSurfaceVariant, letterSpacing: 2)),
                  Text('SuperAdmin', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: _onSurface)),
                ],
              ),
              const SizedBox(width: 16),
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(shape: BoxShape.circle, color: _surfaceContainerHighest, border: Border.all(color: _outlineVariant.withOpacity(0.3))),
                child: const Icon(Icons.person, color: _onSurface, size: 20),
              )
            ],
          )
        ],
      ),
    );
  }

  // --- Main Content ---
  Widget _buildMainContent() {
    return ListView(
      padding: const EdgeInsets.all(40),
      children: [
        _buildHeader(),
        const SizedBox(height: 32),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 8, child: _buildLeftForm()),
            const SizedBox(width: 32),
            Expanded(flex: 4, child: _buildRightSidebar()),
          ],
        )
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(color: _surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                if (widget.onEmbeddedBack != null) {
                  widget.onEmbeddedBack!();
                } else {
                  Navigator.pop(context);
                }
              },
              child: const Icon(Icons.arrow_back, color: _onSurface),
            ),
          ),
        ),
        const SizedBox(width: 24),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ajouter un Élément de Conception', style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w900, color: _onSurface, letterSpacing: -0.5)),
            const SizedBox(height: 8),
            Row(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (_,__) => Container(
                        width: 12, height: 12,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF66BB6A).withOpacity(_pulseController.value * 0.3)),
                        transform: Matrix4.identity()..scale(1.0 + (_pulseController.value * 0.5)),
                      ),
                    ),
                    Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF66BB6A), shape: BoxShape.circle)),
                  ],
                ),
                const SizedBox(width: 8),
                Text('ÉDITION EN COURS • FLUX DE DONNÉES SÉCURISÉ', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
              ],
            )
          ],
        )
      ],
    );
  }

  // -- LEFT FORM --
  Widget _buildLeftForm() {
    return Column(
      children: [
        _buildSectionCard(
          icon: Icons.info_outline,
          title: 'INFORMATIONS GÉNÉRALES',
          iconColor: _primary,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  children: [
                    _buildControlledField('NOM DU DOCUMENT', 'Ex: Plan Turbo-Alternateur XJ4', _docNameCtrl),
                    const SizedBox(height: 32),
                    _buildControlledField('VERSION', 'v1.0', _versionCtrl),
                  ],
                ),
              ),
              const SizedBox(width: 32),
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CLIENT ASSOCIÉ', style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.w600, color: _onSurfaceVariant, letterSpacing: 1.5)),
                    const SizedBox(height: 8),
                    if (_clientsLoading)
                      const LinearProgressIndicator(minHeight: 2)
                    else if (_clients.isEmpty)
                      Text(
                        'Aucun client en base — créez un client pour lier ce document.',
                        style: GoogleFonts.spaceGrotesk(fontSize: 12, color: _onSurfaceVariant, height: 1.4),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _outlineVariant.withOpacity(0.3)))),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: _selectedClientKey != null &&
                                    _clients.any((c) => _clientApiKey(c) == _selectedClientKey)
                                ? _selectedClientKey
                                : null,
                            hint: Text(
                              'Sélectionner un client…',
                              style: GoogleFonts.inter(fontSize: 14, color: _onSurfaceVariant.withOpacity(0.6)),
                            ),
                            dropdownColor: _surfaceContainer,
                            style: GoogleFonts.inter(fontSize: 14, color: _onSurface),
                            items: _clients
                                .map((c) {
                                  final k = _clientApiKey(c);
                                  if (k.isEmpty) return null;
                                  return DropdownMenuItem<String>(
                                    value: k,
                                    child: Text(_clientDisplayName(c)),
                                  );
                                })
                                .whereType<DropdownMenuItem<String>>()
                                .toList(),
                            onChanged: (val) => setState(() {
                              _selectedClientKey = val;
                            }),
                          ),
                        ),
                      ),
                  ],
                ),
              )
            ],
          )
        ),
        const SizedBox(height: 32),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('TYPE DE DOCUMENT', style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.w600, color: _onSurfaceVariant, letterSpacing: 1.5)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildDocTypeCard(0, Icons.straighten, 'Plan\nmécanique')),
                const SizedBox(width: 16),
                Expanded(child: _buildDocTypeCard(1, Icons.bolt, 'Schéma\nélectrique', isBlue: true)),
                const SizedBox(width: 16),
                Expanded(child: _buildDocTypeCard(2, Icons.bar_chart, 'Rapport\ntechnique')),
                const SizedBox(width: 16),
                Expanded(child: _buildDocTypeCard(3, Icons.menu_book, 'Manuel\nmaintenance')),
              ],
            )
          ],
        ),
        const SizedBox(height: 32),
        _buildSectionCard(
          icon: Icons.security_outlined,
          title: 'SÉCURITÉ & ACCÈS',
          iconColor: _secondaryBlue,
          child: Row(
            children: [
              Expanded(
                child: _buildIconInputField(
                  'EMAIL DE CONSULTATION',
                  Icons.alternate_email,
                  _secEmailCtrl,
                  hintText: 'destinataire@client.com',
                ),
              ),
              const SizedBox(width: 32),
              Expanded(
                child: _buildIconInputField(
                  'MOT DE PASSE SÉCURISÉ (optionnel)',
                  Icons.lock_outline,
                  _secPassCtrl,
                  hintText: '••••••••',
                  obscureText: true,
                  suffixIcon: Icons.visibility_outlined,
                ),
              ),
            ],
          )
        ),
        const SizedBox(height: 32),
        // Upload Area
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 48),
          decoration: BoxDecoration(
            color: _surfaceContainerLowest.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _outlineVariant.withOpacity(0.3), width: 2, style: BorderStyle.none), // We use custom dashed border typically, but solid is fine for simple Flutter
          ),
          child: Column(
            children: [
              Container(
                width: 64, height: 64,
                decoration: const BoxDecoration(color: _surfaceContainerHighest, shape: BoxShape.circle),
                child: const Icon(Icons.upload_file, color: _onSurfaceVariant, size: 32),
              ),
              const SizedBox(height: 24),
              Text('Glisser-déposer le fichier ici', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: _onSurface)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('ou ', style: GoogleFonts.spaceGrotesk(fontSize: 14, color: _onSurfaceVariant)),
                  Text('parcourir vos fichiers localement', style: GoogleFonts.spaceGrotesk(fontSize: 14, color: _secondaryBlue, decoration: TextDecoration.underline)),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: _surfaceContainerLow, borderRadius: BorderRadius.circular(32), border: Border.all(color: _outlineVariant.withOpacity(0.1))),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('PDF, DWG, STEP', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 12),
                    Container(width: 4, height: 4, decoration: const BoxDecoration(shape: BoxShape.circle, color: _outlineVariant)),
                    const SizedBox(width: 12),
                    Text('50MB MAX', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
                  ],
                ),
              )
            ],
          ),
        )
      ],
    );
  }

  Widget _buildSectionCard({required IconData icon, required String title, required Color iconColor, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: _surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _outlineVariant.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 12),
              Text(title, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: _onSurface, letterSpacing: 1.5)),
            ],
          ),
          const SizedBox(height: 32),
          child,
        ],
      ),
    );
  }

  Widget _buildControlledField(String label, String hint, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.w600, color: _onSurfaceVariant, letterSpacing: 1.5)),
        TextFormField(
          controller: controller,
          style: GoogleFonts.inter(fontSize: 14, color: _onSurface),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(fontSize: 14, color: _onSurfaceVariant.withOpacity(0.5)),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: _outlineVariant.withOpacity(0.3))),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: _secondaryBlue)),
          ),
        )
      ],
    );
  }

  Widget _buildIconInputField(
    String label,
    IconData prefix,
    TextEditingController controller, {
    String? hintText,
    bool obscureText = false,
    IconData? suffixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.w600, color: _onSurfaceVariant, letterSpacing: 1.5)),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          style: GoogleFonts.inter(fontSize: 14, color: _onSurface),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: GoogleFonts.inter(fontSize: 14, color: _onSurfaceVariant.withOpacity(0.5)),
            prefixIconConstraints: const BoxConstraints(minWidth: 40),
            prefixIcon: Icon(prefix, color: _onSurfaceVariant, size: 18),
            suffixIcon: suffixIcon != null ? Icon(suffixIcon, color: _onSurfaceVariant, size: 18) : null,
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: _outlineVariant.withOpacity(0.3))),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: _secondaryBlue)),
          ),
        )
      ],
    );
  }

  Widget _buildDocTypeCard(int index, IconData icon, String title, {bool isBlue = false}) {
    final bool isSelected = _selectedDocType == index;
    final activeColor = isBlue ? _secondary : _primary;

    return GestureDetector(
      onTap: () { setState(() { _selectedDocType = index; }); },
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isSelected ? _surfaceContainerHighest.withOpacity(0.3) : _surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? activeColor : _outlineVariant.withOpacity(0.1), width: isSelected ? 2 : 1),
          boxShadow: isSelected ? [BoxShadow(color: activeColor.withOpacity(0.1), blurRadius: 15)] : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: isSelected ? activeColor : activeColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: isSelected ? _bg : activeColor, size: 24),
            ),
            const SizedBox(height: 24),
            Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: isSelected ? activeColor : _onSurface)),
          ],
        ),
      ),
    );
  }

  // -- RIGHT SIDEBAR --
  Widget _buildRightSidebar() {
    return Column(
      children: [
        // Summary Card
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(color: _surfaceContainerLow, borderRadius: BorderRadius.circular(12), border: Border.all(color: _outlineVariant.withOpacity(0.15))),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Résumé de\nl\'Élément', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: _onSurface)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: _secondaryBlue.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                    child: Text('BROUILLON', style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.bold, color: _secondaryBlue, letterSpacing: 1)),
                  )
                ],
              ),
              const SizedBox(height: 32),
              _buildSummaryRow('DOCUMENT', _docNameCtrl.text.isEmpty ? '—' : _docNameCtrl.text, showEdit: true),
              const SizedBox(height: 24),
              _buildSummaryRow('TYPE', _selectedDocTypeLabel),
              const SizedBox(height: 24),
              _buildSummaryRow('CLIENT PILOTE', _selectedClientDisplayName(), valueColor: _primary),
              const SizedBox(height: 32),
              Container(height: 1, color: _outlineVariant.withOpacity(0.15)),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Icon(Icons.schedule, color: _onSurfaceVariant, size: 14),
                  const SizedBox(width: 8),
                  Text('Dernière modification : Aujourd\'hui, 14:32', style: GoogleFonts.inter(fontSize: 10, color: _onSurfaceVariant)),
                ],
              )
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Security Status
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: _surfaceContainerLowest, 
            borderRadius: BorderRadius.circular(12), 
            border: const Border(left: BorderSide(color: _primaryContainer, width: 4))
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.verified_user, color: _primaryContainer, size: 20),
                  const SizedBox(width: 12),
                  Text('Niveau de Protection', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: _onSurface)),
                ],
              ),
              const SizedBox(height: 24),
              _buildSecurityStatusRow('CHIFFREMENT AES-256', 'ACTIF', const Color(0xFF66BB6A)),
              const SizedBox(height: 12),
              _buildSecurityStatusRow('INDEXATION IA', 'EN ATTENTE', _onSurfaceVariant, bgColor: _surfaceContainerHighest),
              const SizedBox(height: 24),
              Container(
                height: 4, width: double.infinity,
                decoration: BoxDecoration(color: _surfaceContainerHighest, borderRadius: BorderRadius.circular(2)),
                child: Row(
                  children: [
                    Expanded(flex: 75, child: Container(decoration: BoxDecoration(color: _primaryContainer, borderRadius: BorderRadius.circular(2)))),
                    const Expanded(flex: 25, child: SizedBox()),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text('SCORE DE COMPLÉTION : 75%', style: GoogleFonts.spaceGrotesk(fontSize: 8, fontWeight: FontWeight.bold, color: _onSurfaceVariant, letterSpacing: 1.5)),
              )
            ],
          ),
        ),
        const SizedBox(height: 32),
        // Buttons
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _saving ? null : _saveDocument,
            borderRadius: BorderRadius.circular(8),
            child: Ink(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_primaryContainer, _primary], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [BoxShadow(color: _primaryContainer.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 5))],
              ),
              child: Center(
                child: _saving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF552000)),
                      )
                    : Text(
                        'ENREGISTRER LE DOCUMENT',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF552000), letterSpacing: 1.5),
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _saving ? null : _cancel,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                border: Border.all(color: _outlineVariant.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text('ANNULER', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: _onSurfaceVariant, letterSpacing: 1.5)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool showEdit = false, Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.bold, color: _onSurfaceVariant, letterSpacing: 1.5)),
            const SizedBox(height: 4),
            Text(value, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: valueColor ?? _onSurface)),
          ],
        ),
        if (showEdit)
          const Icon(Icons.edit, color: _onSurfaceVariant, size: 16),
      ],
    );
  }

  Widget _buildSecurityStatusRow(String label, String badgeText, Color badgeColor, {Color? bgColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: _surfaceContainerLow, borderRadius: BorderRadius.circular(4), border: Border.all(color: _outlineVariant.withOpacity(0.15))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.bold, color: _onSurfaceVariant, letterSpacing: 1)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: bgColor ?? badgeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
            child: Text(badgeText, style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.bold, color: badgeColor)),
          )
        ],
      ),
    );
  }
}
