import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/api_service.dart';

class MachineTeamPage extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  final VoidCallback? onBack;
  const MachineTeamPage({super.key, this.initialData, this.onBack});

  @override
  State<MachineTeamPage> createState() => _MachineTeamPageState();
}

class _MachineTeamPageState extends State<MachineTeamPage> {
  // Theme colors based on HTML schema
  static const _surface = Color(0xFF10102b);
  static const _onSurface = Color(0xFFe2dfff);
  static const _surfaceContainerLowest = Color(0xFF0b0b26);
  static const _surfaceContainerLow = Color(0xFF191934);
  static const _surfaceContainer = Color(0xFF1d1d38);
  static const _surfaceContainerHigh = Color(0xFF272743);
  static const _surfaceContainerHighest = Color(0xFF32324e);
  static const _surfaceVariant = Color(0xFF32324e);
  static const _onSurfaceVariant = Color(0xFFe2bfb0);
  
  static const _primary = Color(0xFFFFB692);
  static const _primaryContainer = Color(0xFFFF6E00);
  static const _onPrimary = Color(0xFF552000);
  
  static const _secondary = Color(0xFF75D1FF);
  static const _tertiary = Color(0xFFEFB1F9);
  static const _outlineVariant = Color(0xFF594136);

  String _selectedRole = 'Technicien Terrain';
  String? _selectedClientId;
  List<Map<String, dynamic>> _clients = [];
  List<Map<String, dynamic>> _machines = [];
  bool _loadingMachines = false;
  final Set<String> _selectedMachineIds = {};

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _techDescCtrl = TextEditingController();

  final Map<String, bool> _specializations = {
    'Automatisme PLC': false,
    'Cyber-Sécurité IoT': true,
    'Maintenance Prédictive': false,
    'Électrotechnique': false,
    'Réseaux Industriels': true,
  };

  bool _obscurePass = true;
  bool _isLoading = false;
  bool _isLoadingClients = false;
  Map<String, String> _fieldErrors = {};

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _nameCtrl.text = widget.initialData!['name'] ?? '';
      _emailCtrl.text = widget.initialData!['email'] ?? '';
      _phoneCtrl.text = widget.initialData!['phone'] ?? '';
      _techDescCtrl.text = widget.initialData!['technicalDescription'] ?? '';
    }
    _loadClients();
  }

  Map<String, String> _validateTechnicianForm() {
    final errors = <String, String>{};
    final fullName = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text;
    if (fullName.isEmpty || !fullName.contains(' ')) {
      errors['name'] = 'Nom et prénom obligatoires (ex: Jean Dupont)';
    }
    if (email.isEmpty || !email.contains('@')) {
      errors['email'] = 'Email invalide: le symbole @ est obligatoire';
    }
    if (password.isEmpty || password.length < 6) {
      errors['password'] = 'Mot de passe obligatoire (minimum 6 caractères)';
    }
    if (_techDescCtrl.text.trim().isEmpty) {
      errors['technicalDescription'] = 'Description technique obligatoire';
    }
    if (_selectedClientId == null) {
      errors['companyId'] = 'Sélection client obligatoire';
    }
    if (_machines.isEmpty) {
      errors['machines'] =
          'Aucune machine pour ce client : créez d\'abord au moins une machine, puis ajoutez le technicien en cochant les machines qu\'il contrôle.';
    } else if (_selectedMachineIds.isEmpty) {
      errors['machines'] = 'Obligatoire : cochez au moins une machine que ce technicien contrôlera.';
    }
    return errors;
  }

  Future<void> _loadMachinesForClient() async {
    final cid = _selectedClientId;
    if (cid == null || cid.isEmpty) {
      if (mounted) {
        setState(() {
          _machines = [];
          _selectedMachineIds.clear();
        });
      }
      return;
    }
    setState(() => _loadingMachines = true);
    try {
      final list = await ApiService.getMachinesForClient(cid);
      if (!mounted) return;
      setState(() {
        _machines = list;
        final valid = list
            .map((m) => (m['_id'] ?? m['id'] ?? '').toString())
            .where((s) => s.isNotEmpty)
            .toSet();
        _selectedMachineIds.removeWhere((id) => !valid.contains(id));
      });
    } catch (_) {
      if (mounted) setState(() => _machines = []);
    } finally {
      if (mounted) setState(() => _loadingMachines = false);
    }
  }

  Future<void> _loadClients() async {
    setState(() => _isLoadingClients = true);
    try {
      final clients = await ApiService.getClients();
      if (mounted) {
        setState(() {
          _clients = clients;
          if (_selectedClientId == null && _clients.isNotEmpty) {
            _selectedClientId =
                (_clients.first['clientId'] ?? _clients.first['id'] ?? _clients.first['_id'])?.toString();
          }
        });
        await _loadMachinesForClient();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _clients = [];
        });
      }
    } finally {
      if (mounted) setState(() => _isLoadingClients = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final isDesktop = sw > 900;

    return Scaffold(
      backgroundColor: _surface,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop) _buildSidebar(),
          Expanded(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildTitleSection(),
                            const SizedBox(height: 32),
                            if (isDesktop)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 8, child: _buildMainForm()),
                                  const SizedBox(width: 32),
                                  Expanded(flex: 4, child: _buildRightPanel()),
                                ],
                              )
                            else
                              Column(
                                children: [
                                  _buildMainForm(),
                                  const SizedBox(height: 32),
                                  _buildRightPanel(),
                                ],
                              ),
                            const SizedBox(height: 48),
                            _buildFooter(),
                          ],
                        ),
                      ),
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

  // ─── Top Header ──────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        color: const Color(0xFF10102b),
        border: Border(bottom: BorderSide(color: _outlineVariant.withOpacity(0.15))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('DEPLOYMENT PORTAL', style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: _onSurface, letterSpacing: -1)),
              Text('PERSONNEL ONBOARDING / v4.2', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant, letterSpacing: 2, fontWeight: FontWeight.bold)),
            ],
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _outlineVariant.withOpacity(0.15)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, color: _onSurfaceVariant, size: 16),
                    const SizedBox(width: 8),
                    Text('RECHERCHE GLOBALE...', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_outlined, color: _onSurfaceVariant)),
              const SizedBox(width: 16),
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _primaryContainer, width: 2),
                  image: const DecorationImage(
                    image: NetworkImage('https://lh3.googleusercontent.com/aida-public/AB6AXuCzdLrRAAinEgrLTHdSRAy_TlTO5GiW3wZaoPJLs6yKMjMg2RP4Am34RM5IOAWmp1wSyHPW5TAhGzNWN79KD6qhoQcWonrwRsqaXcJ9yYKkPB5WUnbnGk02F6rIWLlQaLDv58_a7cUQO_sKHwb81WRXcznlCI6odYF0uTYJTr69qmdp5uAX5beMid4Wm1pL3-BXHRMoojDwxSYqXLPVd5e1GtysjDRpoV2rU2SSsfxsaA28iVVWjAc1gIRzxn0NZ2rSbgepgqSbRf8'),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Title Section ───────────────────────────────────────────
  Widget _buildTitleSection() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 32, height: 1, color: _primaryContainer),
                const SizedBox(width: 8),
                Text('SYSTÈME D\'INSCRIPTION', style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.bold, color: _primaryContainer, letterSpacing: 2)),
              ],
            ),
            const SizedBox(height: 8),
            Text('NOUVEAU TECHNICIEN', style: GoogleFonts.inter(fontSize: 36, fontWeight: FontWeight.w900, color: _onSurface, letterSpacing: -1)),
            const SizedBox(height: 16),
            SizedBox(
              width: 500,
              child: Text(
                'Assignez un expert qualifié aux infrastructures critiques de nos clients industriels avec une précision chirurgicale.',
                style: GoogleFonts.inter(fontSize: 14, color: _onSurfaceVariant, height: 1.6),
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _surfaceVariant.withOpacity(0.6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _outlineVariant.withOpacity(0.15)),
          ),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Status Serveur', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant, letterSpacing: 2)),
                  Text('OPÉRATIONNEL', style: GoogleFonts.spaceGrotesk(fontSize: 14, fontWeight: FontWeight.bold, color: _secondary)),
                ],
              ),
              const SizedBox(width: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _bar(12, 0.4), const SizedBox(width: 4),
                  _bar(24, 1.0), const SizedBox(width: 4),
                  _bar(16, 0.6), const SizedBox(width: 4),
                  _bar(32, 1.0), const SizedBox(width: 4),
                  _bar(8, 0.3),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bar(double h, double op) => Container(width: 4, height: h, color: _secondary.withOpacity(op));

  // ─── Main Form ───────────────────────────────────────────────
  Widget _buildMainForm() {
    return Column(
      children: [
        // Identité & Accès
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: _surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(width: 4, height: 16, color: _primaryContainer),
                  const SizedBox(width: 16),
                  Text('IDENTITÉ & ACCÈS', style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.bold, color: _primaryContainer, letterSpacing: 3)),
                ],
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(child: _buildInput('Nom complet', 'JEAN DUPONT', _nameCtrl, fieldKey: 'name')),
                  const SizedBox(width: 32),
                  Expanded(child: _buildInput('Email professionnel', 'j.dupont@kinetic-ops.io', _emailCtrl, fieldKey: 'email')),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: _buildInput('Mot de passe', '••••••••••••', _passCtrl, isPassword: true, fieldKey: 'password')),
                  const SizedBox(width: 32),
                  Expanded(child: _buildInput('Numéro de téléphone', '+33 6 00 00 00 00', _phoneCtrl)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Expertise Technique
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: _surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                   Container(width: 4, height: 16, color: _secondary),
                   const SizedBox(width: 16),
                   Text('EXPERTISE TECHNIQUE', style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.bold, color: _secondary, letterSpacing: 3)),
                ],
              ),
              const SizedBox(height: 32),
              Text('SPÉCIALITÉS & CERTIFICATIONS', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant, letterSpacing: 2)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12, runSpacing: 12,
                children: _specializations.keys.map((k) {
                  final active = _specializations[k]!;
                  return InkWell(
                    onTap: () => setState(() => _specializations[k] = !active),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: active ? _secondary.withOpacity(0.2) : Colors.transparent,
                        border: Border.all(color: active ? _secondary : _outlineVariant),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(k.toUpperCase(), style: GoogleFonts.spaceGrotesk(fontSize: 10, color: active ? _secondary : _onSurfaceVariant)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 32),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('RÔLE AU SEIN DE L\'ÉQUIPE', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant, letterSpacing: 2)),
                        const SizedBox(height: 16),
                        _buildRadioItem('Technicien Terrain', _primaryContainer),
                        const SizedBox(height: 12),
                        _buildRadioItem('Ingénieur Conception', _tertiary),
                      ],
                    ),
                  ),
                  const SizedBox(width: 32),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text('MACHINES CONTRÔLÉES', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant, letterSpacing: 2)),
                            ),
                            IconButton(
                              tooltip: 'Actualiser la liste des machines',
                              icon: Icon(Icons.refresh, color: _secondary, size: 22),
                              onPressed: _loadingMachines ? null : () => _loadMachinesForClient(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Toutes les machines du client sélectionné apparaissent ici. Cochez celles que ce technicien contrôlera.',
                          style: GoogleFonts.inter(fontSize: 11, color: _onSurfaceVariant.withOpacity(0.9), height: 1.35),
                        ),
                        const SizedBox(height: 6),
                        if (!_loadingMachines && _machines.isNotEmpty)
                          Text(
                            '${_machines.length} machine(s) — obligatoire : au moins une case cochée',
                            style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _secondary, fontWeight: FontWeight.w600),
                          ),
                        const SizedBox(height: 8),
                        if (!_loadingMachines && _machines.isNotEmpty)
                          Wrap(
                            spacing: 6,
                            children: [
                              TextButton(
                                onPressed: () => setState(() {
                                  for (final m in _machines) {
                                    final mid = (m['_id'] ?? m['id'] ?? '').toString();
                                    if (mid.isNotEmpty) _selectedMachineIds.add(mid);
                                  }
                                  _fieldErrors.remove('machines');
                                }),
                                child: Text('Tout sélectionner', style: GoogleFonts.inter(color: _secondary, fontSize: 11)),
                              ),
                              TextButton(
                                onPressed: () => setState(() {
                                  _selectedMachineIds.clear();
                                  _fieldErrors.remove('machines');
                                }),
                                child: Text('Tout désélectionner', style: GoogleFonts.inter(color: _onSurfaceVariant, fontSize: 11)),
                              ),
                            ],
                          ),
                        const SizedBox(height: 8),
                        if (_loadingMachines)
                          const Padding(
                            padding: EdgeInsets.all(12),
                            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        else if (_machines.isEmpty)
                          Text(
                            'Créez d\'abord une machine pour ce client (sans technicien si besoin), puis revenez ici : le technicien doit obligatoirement choisir les machines qu\'il contrôle.',
                            style: GoogleFonts.inter(fontSize: 11, color: _onSurfaceVariant, height: 1.4),
                          )
                        else
                          ..._machines.map((m) {
                            final mid = (m['_id'] ?? m['id'] ?? '').toString();
                            if (mid.isEmpty) return const SizedBox.shrink();
                            return CheckboxListTile(
                              value: _selectedMachineIds.contains(mid),
                              contentPadding: EdgeInsets.zero,
                              onChanged: (v) {
                                setState(() {
                                  if (v == true) {
                                    _selectedMachineIds.add(mid);
                                  } else {
                                    _selectedMachineIds.remove(mid);
                                  }
                                  _fieldErrors.remove('machines');
                                });
                              },
                              title: Text(m['name'] ?? mid, style: GoogleFonts.inter(color: _onSurface, fontSize: 13)),
                              subtitle: Text(mid, style: GoogleFonts.spaceGrotesk(fontSize: 9, color: _onSurfaceVariant)),
                              activeColor: _secondary,
                            );
                          }),
                        if (_fieldErrors['machines'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(_fieldErrors['machines']!, style: GoogleFonts.inter(fontSize: 12, color: Colors.redAccent)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildInput(
                'Description technique',
                'Ex: Expert maintenance predictive des moteurs industriels',
                _techDescCtrl,
                fieldKey: 'technicalDescription',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRadioItem(String title, Color activeColor) {
    bool isSelected = _selectedRole == title;
    return InkWell(
      onTap: () => setState(() => _selectedRole = title),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _surfaceContainer,
          border: Border.all(color: _outlineVariant.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              width: 16, height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: isSelected ? activeColor : _outlineVariant, width: 2),
              ),
              child: isSelected ? Center(child: Container(width: 8, height: 8, decoration: BoxDecoration(color: activeColor, shape: BoxShape.circle))) : null,
            ),
            const SizedBox(width: 12),
            Text(title.toUpperCase(), style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurface, letterSpacing: 2)),
          ],
        ),
      ),
    );
  }

  Widget _buildInput(
    String label,
    String hint,
    TextEditingController ctrl, {
    bool isPassword = false,
    String? fieldKey,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant, letterSpacing: 2)),
        const SizedBox(height: 8),
        TextField(
          controller: ctrl,
          onChanged: (_) {
            if (fieldKey != null && _fieldErrors.containsKey(fieldKey)) {
              setState(() => _fieldErrors.remove(fieldKey));
            }
          },
          obscureText: isPassword && _obscurePass,
          style: GoogleFonts.inter(fontSize: 16, color: _onSurface, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: _onSurfaceVariant.withOpacity(0.3)),
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            border: const UnderlineInputBorder(borderSide: BorderSide(color: _outlineVariant)),
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: _outlineVariant)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: _secondary, width: 2)),
            suffixIcon: isPassword
                ? IconButton(
                    icon: Icon(_obscurePass ? Icons.visibility : Icons.visibility_off, color: _onSurfaceVariant, size: 20),
                    onPressed: () => setState(() => _obscurePass = !_obscurePass),
                  )
                : null,
          ),
        ),
        if (fieldKey != null && _fieldErrors[fieldKey] != null) ...[
          const SizedBox(height: 6),
          Text(
            _fieldErrors[fieldKey]!,
            style: GoogleFonts.inter(fontSize: 12, color: Colors.redAccent),
          ),
        ],
      ],
    );
  }

  // ─── Right Panel ─────────────────────────────────────────────
  Widget _buildRightPanel() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: _surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: const Border(top: BorderSide(color: _primaryContainer, width: 4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('AFFECTATION CLIENT', style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.bold, color: _onSurface, letterSpacing: 3)),
              const SizedBox(height: 16),
              Text('Sélectionnez le partenaire industriel pour lequel ce membre d\'équipe opérera en priorité.', style: GoogleFonts.inter(fontSize: 12, color: _onSurfaceVariant, height: 1.5)),
              const SizedBox(height: 24),
              if (_isLoadingClients)
                const Center(child: CircularProgressIndicator())
              else if (_clients.isEmpty)
                Text(
                  'Aucun client disponible. Ajoutez un client avant de créer un technicien.',
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.redAccent),
                )
              else
                ..._clients.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final c = entry.value;
                  final color = idx % 3 == 0
                      ? _primaryContainer
                      : (idx % 3 == 1 ? _secondary : _tertiary);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildClientSelector(c, color),
                  );
                }),
              if (_fieldErrors['companyId'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _fieldErrors['companyId']!,
                    style: GoogleFonts.inter(fontSize: 12, color: Colors.redAccent),
                  ),
                ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _surfaceVariant.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(8),
                  border: const Border(left: BorderSide(color: _secondary, width: 2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, color: _secondary, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text('CE MEMBRE AURA ACCÈS AUX TÉLÉMÉTRIES EN TEMPS RÉEL DU SITE SÉLECTIONNÉ UNIQUEMENT.', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurface, height: 1.5, letterSpacing: 1))),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              InkWell(
                onTap: _isLoading ? null : () async {
                  setState(() => _isLoading = true);
                  try {
                    final errors = _validateTechnicianForm();
                    setState(() => _fieldErrors = errors);
                    if (errors.isNotEmpty) {
                      throw Exception('Veuillez corriger les champs en rouge');
                    }

                    final newTech = {
                      'name': _nameCtrl.text.trim(),
                      'email': _emailCtrl.text.trim().toLowerCase(),
                      'password': _passCtrl.text.trim(),
                      'phone': _phoneCtrl.text.trim().isEmpty ? 'N/A' : _phoneCtrl.text.trim(),
                      'specialization': _selectedRole,
                      'technicalDescription': _techDescCtrl.text.trim(),
                      'companyId': _selectedClientId,
                      'machineIds': _selectedMachineIds.toList(),
                      'status': 'Disponible',
                      'imageUrl': 'https://lh3.googleusercontent.com/aida-public/AB6AXuCNdhFyhbxJvHxiR2UcLJjq61disbRYdUBbwvF2JJ1QQ1hozTX8TlXL6KGBkZ2pCDXqLitGXQcipEDylFMdZv6Ek9dhszqAnxhvYgFhKmliM04pd9sgvAXeaRyBvAFWGUI6YXO0t3Y7HAnbObX_sEF-8bD2T0Ft6QsnGEs9NIZGITiv5FuE7-tVKn2u3u40TwGk8cHMmg4F_jSPwdq-M2-cLZKFlWQKL1INoECy1najkM_tlk0Q8-wbekTs9zf60MINWSJCei4ku18',
                    };

                    await ApiService.addTechnician(newTech);
                    setState(() => _fieldErrors = {});
                    
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Technicien déployé avec succès !'), backgroundColor: Colors.green),
                      );
                      if (widget.onBack != null) {
                        widget.onBack!();
                      } else {
                        Navigator.pop(context, true);
                      }
                    }
                  } catch (e) {
                    final raw = e.toString();
                    final message = raw.startsWith('Exception: ')
                        ? raw.substring('Exception: '.length)
                        : raw;
                    final msgLower = message.toLowerCase();

                    if (mounted) {
                      if (msgLower.contains('email') && (msgLower.contains('déjà') || msgLower.contains('existe'))) {
                        setState(() {
                          _fieldErrors['email'] = message;
                        });
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(message), backgroundColor: Colors.red),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _isLoading = false);
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_primaryContainer, _primary]),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [BoxShadow(color: _primaryContainer.withOpacity(0.2), blurRadius: 16)],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_isLoading ? 'DÉPLOIEMENT...' : 'DÉPLOYER LE MEMBRE', style: const TextStyle(fontFamily: 'Space Grotesk', fontSize: 12, fontWeight: FontWeight.bold, color: _onPrimary, letterSpacing: 2)),
                      const SizedBox(width: 8),
                      _isLoading 
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _onPrimary))
                        : const Icon(Icons.rocket_launch, color: _onPrimary, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: () {
                  if (widget.onBack != null) widget.onBack!();
                  else Navigator.pop(context);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    border: Border.all(color: _outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text('ANNULER L\'OPÉRATION', style: GoogleFonts.spaceGrotesk(fontSize: 12, color: _onSurfaceVariant, letterSpacing: 2)),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: _primary.withOpacity(0.05), blurRadius: 40, spreadRadius: -10),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _primaryContainer.withOpacity(0.3)),
                      image: const DecorationImage(
                        image: NetworkImage('https://lh3.googleusercontent.com/aida-public/AB6AXuCNdhFyhbxJvHxiR2UcLJjq61disbRYdUBbwvF2JJ1QQ1hozTX8TlXL6KGBkZ2pCDXqLitGXQcipEDylFMdZv6Ek9dhszqAnxhvYgFhKmliM04pd9sgvAXeaRyBvAFWGUI6YXO0t3Y7HAnbObX_sEF-8bD2T0Ft6QsnGEs9NIZGITiv5FuE7-tVKn2u3u40TwGk8cHMmg4F_jSPwdq-M2-cLZKFlWQKL1INoECy1najkM_tlk0Q8-wbekTs9zf60MINWSJCei4ku18'),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('APERÇU DU PROFIL', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: _onSurface)),
                      Text('GÉNÉRÉ EN TEMPS RÉEL', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant, letterSpacing: 2)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(height: 8, decoration: BoxDecoration(color: _surfaceVariant.withOpacity(0.3), borderRadius: BorderRadius.circular(4))),
              const SizedBox(height: 8),
              Container(height: 8, width: 220, alignment: Alignment.centerLeft, decoration: BoxDecoration(color: _surfaceVariant.withOpacity(0.3), borderRadius: BorderRadius.circular(4))),
              const SizedBox(height: 8),
              Container(height: 8, width: 150, alignment: Alignment.centerLeft, decoration: BoxDecoration(color: _surfaceVariant.withOpacity(0.3), borderRadius: BorderRadius.circular(4))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildClientSelector(Map<String, dynamic> client, Color badgeColor) {
    final title = (client['name'] ?? 'Client').toString();
    final location = (client['location'] ?? 'SITE INDUSTRIEL').toString();
    final clientId = (client['clientId'] ?? client['id'] ?? client['_id'])?.toString();
    bool isSelected = _selectedClientId != null && _selectedClientId == clientId;
    return InkWell(
      onTap: () {
        setState(() => _selectedClientId = clientId);
        _loadMachinesForClient();
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surfaceContainer,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? badgeColor : _outlineVariant.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: _surfaceContainerLowest,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _outlineVariant.withOpacity(0.3)),
              ),
              child: Icon(Icons.factory_outlined, color: badgeColor, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title.toUpperCase(), style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: _onSurface)),
                  Text(location.toUpperCase(), style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant, letterSpacing: 1)),
                ],
              ),
            ),
            Container(
              width: 20, height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: isSelected ? badgeColor : _outlineVariant, width: 2),
              ),
              child: isSelected ? Center(child: Container(width: 10, height: 10, decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle))) : null,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Footer ──────────────────────────────────────────────────
  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.only(top: 24),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: _outlineVariant.withOpacity(0.2)))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text('© 2024 KINETIC OPS SYSTEMS', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant, letterSpacing: 2)),
              const SizedBox(width: 24),
              Container(width: 4, height: 4, decoration: const BoxDecoration(color: _primaryContainer, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text('AUDIT DE SÉCURITÉ: PASS', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant, letterSpacing: 2)),
            ],
          ),
          Row(
            children: [
              Text('POLITIQUE DE CONFIDENTIALITÉ', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant, letterSpacing: 2)),
              const SizedBox(width: 24),
              Text('JOURNAL DES MODIFICATIONS', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant, letterSpacing: 2)),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Sidebar ──────────────────────────────────────────────────
  Widget _buildSidebar() {
    return Container(
      width: 256,
      height: MediaQuery.of(context).size.height,
      color: _surfaceContainerLow,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_primaryContainer, _primary]),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.engineering, color: _onPrimary, size: 24),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('INDUSTRIAL INTEL', style: GoogleFonts.spaceGrotesk(fontSize: 14, fontWeight: FontWeight.w900, color: _primaryContainer, letterSpacing: -0.5)),
                    Text('PREDICTIVE ENGINE', style: GoogleFonts.spaceGrotesk(fontSize: 8, color: _onSurfaceVariant, letterSpacing: 2)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 48),
          _sidebarItem(Icons.dashboard, 'DASHBOARD', false),
          _sidebarItem(Icons.engineering, 'TECHNICIANS', true),
          _sidebarItem(Icons.groups, 'WORK ORDERS', false),
          _sidebarItem(Icons.inventory_2, 'INVENTORY', false),
          _sidebarItem(Icons.assessment, 'REPORTS', false),
          const Spacer(),
          _sidebarItem(Icons.help, 'SUPPORT', false),
          _sidebarItem(Icons.terminal, 'LOGS', false),
        ],
      ),
    );
  }

  Widget _sidebarItem(IconData icon, String label, bool active) {
    return InkWell(
      onTap: () {
        if (!active && widget.onBack != null) widget.onBack!();
        else if (!active) Navigator.pop(context);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: active ? _surfaceVariant : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: active ? const Border(right: BorderSide(color: _primaryContainer, width: 4)) : null,
        ),
        child: Row(
          children: [
            Icon(icon, color: active ? _primaryContainer : _onSurfaceVariant.withOpacity(0.8), size: 20),
            const SizedBox(width: 16),
            Text(label, style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: active ? FontWeight.bold : FontWeight.normal, color: active ? _primaryContainer : _onSurfaceVariant.withOpacity(0.8), letterSpacing: 2)),
          ],
        ),
      ),
    );
  }
}
