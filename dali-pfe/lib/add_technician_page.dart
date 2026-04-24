import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/api_service.dart';

class AddTechnicianPage extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  final VoidCallback? onBack;
  const AddTechnicianPage({super.key, this.initialData, this.onBack});

  @override
  State<AddTechnicianPage> createState() => _AddTechnicianPageState();
}

String _techClientRowId(Map<String, dynamic> c) {
  final cid = (c['clientId'] ?? '').toString().trim();
  if (cid.isNotEmpty) return cid;
  return (c['id'] ?? c['_id'] ?? '').toString();
}

String _techClientLabel(Map<String, dynamic> c) {
  final name = (c['name'] ?? '').toString().trim();
  final id = _techClientRowId(c);
  if (name.isEmpty) return id.isEmpty ? '—' : id;
  return '$name ($id)';
}

String _techMachineRowId(Map<String, dynamic> m) {
  return (m['id'] ?? m['machineId'] ?? m['_id'] ?? '').toString();
}

class _AddTechnicianPageState extends State<AddTechnicianPage> {
  static const _bg = Color(0xFF0F0F1E);
  static const _nav = Color(0xFF191934);
  static const _card = Color(0xFF1A1A35);
  static const _surface = Color(0xFF32324E);
  static const _outline = Color(0xFF594136);
  static const _on = Color(0xFFE2DFFF);
  static const _onVariant = Color(0xFFE2BFB0);
  static const _primary = Color(0xFFFFB692);
  static const _primaryContainer = Color(0xFFFF6E00);
  static const _secondary = Color(0xFF75D1FF);
  static const _tertiary = Color(0xFFEFB1F9);

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _techDescCtrl = TextEditingController();

  bool _obscurePass = true;
  bool _isLoading = false;
  bool _mobileAccess = true;
  bool _forceChangeAtFirstLogin = false;

  String _selectedSpecialization = 'Vibration';
  String? _selectedClientId;
  List<Map<String, dynamic>> _clients = [];
  bool _isLoadingClients = false;
  List<Map<String, dynamic>> _machines = [];
  bool _loadingMachines = false;
  final Set<String> _selectedMachineIds = {};
  Map<String, String> _fieldErrors = {};

  bool get _isEditMode {
    final tid = widget.initialData?['id'] ?? widget.initialData?['technicianId'];
    final s = tid?.toString().trim() ?? '';
    return s.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    final data = widget.initialData;
    if (data != null) {
      _nameCtrl.text = data['name'] ?? '';
      _emailCtrl.text = data['email'] ?? '';
      _phoneCtrl.text = data['phone'] ?? '';
      _techDescCtrl.text = data['technicalDescription'] ?? '';
      _selectedSpecialization = (data['specialization'] ?? 'Vibration').toString();
      _passCtrl.clear();
      final mids = data['machineIds'];
      if (mids is List) {
        for (final e in mids) {
          _selectedMachineIds.add(e.toString());
        }
      }
      _selectedClientId = data['companyId']?.toString();
    }
    _loadClients();
  }

  Future<void> _loadClients() async {
    setState(() => _isLoadingClients = true);
    try {
      var clients = await ApiService.getClients();
      clients = List<Map<String, dynamic>>.from(clients);
      clients.sort((a, b) => _techClientLabel(a).toLowerCase().compareTo(_techClientLabel(b).toLowerCase()));
      if (!mounted) return;
      setState(() {
        _clients = clients;
        final pre = _selectedClientId?.trim();
        if (pre != null && pre.isNotEmpty) {
          String? match;
          for (final c in clients) {
            if (_techClientRowId(c) == pre) {
              match = _techClientRowId(c);
              break;
            }
            final mongoId = (c['id'] ?? c['_id'] ?? '').toString();
            if (mongoId == pre) {
              match = _techClientRowId(c);
              break;
            }
          }
          _selectedClientId = match;
        }
      });
      if (_selectedClientId != null && _selectedClientId!.isNotEmpty) {
        await _loadMachinesForClient();
      }
    } finally {
      if (mounted) setState(() => _isLoadingClients = false);
    }
  }

  Future<void> _loadMachinesForClient() async {
    final cid = _selectedClientId;
    if (cid == null || cid.isEmpty) {
      if (mounted) {
        setState(() {
          _machines = [];
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
        final valid = list.map(_techMachineRowId).where((s) => s.isNotEmpty).toSet();
        _selectedMachineIds.removeWhere((id) => !valid.contains(id));
      });
    } catch (_) {
      if (mounted) setState(() => _machines = []);
    } finally {
      if (mounted) setState(() => _loadingMachines = false);
    }
  }

  Map<String, String> _validate() {
    final errors = <String, String>{};
    if (_nameCtrl.text.trim().isEmpty || !_nameCtrl.text.trim().contains(' ')) {
      errors['name'] = 'Nom et prénom obligatoires';
    }
    if (_emailCtrl.text.trim().isEmpty || !_emailCtrl.text.contains('@')) {
      errors['email'] = 'Email invalide (@ obligatoire)';
    }
    if (!_isEditMode) {
      if (_passCtrl.text.trim().length < 6) {
        errors['password'] = 'Mot de passe de connexion min. 6 caractères';
      }
    } else if (_passCtrl.text.trim().isNotEmpty && _passCtrl.text.trim().length < 6) {
      errors['password'] = 'Mot de passe min. 6 caractères';
    }
    if (_techDescCtrl.text.trim().isEmpty) {
      errors['technicalDescription'] = 'Description technique obligatoire';
    }
    if (_selectedClientId == null) {
      errors['companyId'] = 'Assignation client obligatoire';
    }
    if (!_isEditMode) {
      if (_machines.isEmpty) {
        errors['machines'] =
            'Aucune machine : ajoutez d\'abord au moins une machine pour ce client (sans technicien si c\'est la première), puis revenez créer le technicien et cochez les machines qu\'il contrôle.';
      } else if (_selectedMachineIds.isEmpty) {
        errors['machines'] = 'Obligatoire : cochez au moins une machine que ce technicien contrôlera.';
      }
    } else if (_machines.isNotEmpty && _selectedMachineIds.isEmpty) {
      errors['machines'] = 'Cochez au moins une machine (obligatoire pour ce client).';
    }
    return errors;
  }

  Future<void> _submit() async {
    setState(() {
      _fieldErrors = _validate();
      _isLoading = true;
    });
    if (_fieldErrors.isNotEmpty) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez corriger les champs en rouge'), backgroundColor: Colors.red),
      );
      return;
    }

    try {
      final payload = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim().toLowerCase(),
        'phone': _phoneCtrl.text.trim(),
        'specialization': _selectedSpecialization,
        'technicalDescription': _techDescCtrl.text.trim(),
        'companyId': _selectedClientId,
        'status': _forceChangeAtFirstLogin ? 'En attente' : 'Disponible',
        'machineIds': _selectedMachineIds.toList(),
        'imageUrl':
            'https://lh3.googleusercontent.com/aida-public/AB6AXuCNdhFyhbxJvHxiR2UcLJjq61disbRYdUBbwvF2JJ1QQ1hozTX8TlXL6KGBkZ2pCDXqLitGXQcipEDylFMdZv6Ek9dhszqAnxhvYgFhKmliM04pd9sgvAXeaRyBvAFWGUI6YXO0t3Y7HAnbObX_sEF-8bD2T0Ft6QsnGEs9NIZGITiv5FuE7-tVKn2u3u40TwGk8cHMmg4F_jSPwdq-M2-cLZKFlWQKL1INoECy1najkM_tlk0Q8-wbekTs9zf60MINWSJCei4ku18',
      };
      if (!_isEditMode || _passCtrl.text.trim().isNotEmpty) {
        payload['password'] = _passCtrl.text.trim();
      }

      if (_isEditMode) {
        final tid = (widget.initialData!['id'] ?? widget.initialData!['technicianId']).toString();
        await ApiService.updateTechnician(tid, payload);
      } else {
        await ApiService.addTechnician(payload);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEditMode ? 'Technicien modifié avec succès' : 'Technicien créé avec succès'),
          backgroundColor: Colors.green,
        ),
      );
      if (widget.onBack != null) {
        widget.onBack!();
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    _techDescCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 1100;
    return Scaffold(
      backgroundColor: _bg,
      body: Row(
        children: [
          if (isDesktop) _buildSidebar(),
          Expanded(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1300),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildPageHeader(),
                          const SizedBox(height: 24),
                          if (isDesktop)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 8, child: _buildLeftColumn()),
                                const SizedBox(width: 24),
                                Expanded(flex: 4, child: _buildRightColumn()),
                              ],
                            )
                          else
                            Column(
                              children: [
                                _buildLeftColumn(),
                                const SizedBox(height: 24),
                                _buildRightColumn(),
                              ],
                            ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Icon(Icons.info_outline, color: _onVariant.withOpacity(.5), size: 14),
                              const SizedBox(width: 8),
                              Text(
                                'Toutes les données sont encryptées selon le protocole AES-256',
                                style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onVariant.withOpacity(.5)),
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: _bg, border: Border(bottom: BorderSide(color: _outline.withOpacity(.15)))),
      child: Row(
        children: [
          Text('PREDICTIVE CLOUD', style: GoogleFonts.inter(color: _primaryContainer, fontWeight: FontWeight.w900, letterSpacing: 2)),
          const SizedBox(width: 24),
          Expanded(
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  Icon(Icons.search, color: _onVariant.withOpacity(.6), size: 18),
                  const SizedBox(width: 10),
                  Text('Rechercher un actif...', style: GoogleFonts.inter(color: _onVariant.withOpacity(.5), fontSize: 13)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Icon(Icons.notifications, color: _onVariant),
          const SizedBox(width: 16),
          Icon(Icons.settings, color: _onVariant),
          const SizedBox(width: 16),
          const CircleAvatar(radius: 14),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 250,
      color: _nav,
      padding: const EdgeInsets.fromLTRB(14, 88, 14, 14),
      child: Column(
        children: [
          _sideItem(Icons.dashboard, 'Dashboard'),
          _sideItem(Icons.account_tree, 'Asset Tree'),
          _sideItem(Icons.engineering, 'Techniciens', active: true),
          _sideItem(Icons.precision_manufacturing, 'Fleet Health'),
          _sideItem(Icons.timeline, 'Predictive Logs'),
          const Spacer(),
          Row(
            children: [
              const Icon(Icons.circle, size: 8, color: Colors.green),
              const SizedBox(width: 8),
              Text('SYSTEM STATUS: OPTIMAL', style: GoogleFonts.spaceGrotesk(color: Colors.green, fontSize: 10)),
            ],
          )
        ],
      ),
    );
  }

  Widget _sideItem(IconData icon, String label, {bool active = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        gradient: active ? const LinearGradient(colors: [_primaryContainer, _primary]) : null,
        color: active ? null : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: active ? _bg : _onVariant),
        title: Text(label, style: GoogleFonts.inter(color: active ? _bg : _onVariant, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
        onTap: () {
          if (!active && widget.onBack != null) widget.onBack!();
        },
      ),
    );
  }

  Widget _buildPageHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.circle, size: 8, color: _tertiary),
                const SizedBox(width: 8),
                Text('GESTION DU PERSONNEL', style: GoogleFonts.spaceGrotesk(color: _tertiary, letterSpacing: 2, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 8),
            Text(_isEditMode ? 'Modifier Technicien' : 'Nouveau Technicien', style: GoogleFonts.inter(fontSize: 44, fontWeight: FontWeight.w900, color: _on)),
            if (!_isEditMode) ...[
              const SizedBox(height: 6),
              Text(
                'Rôle : technicien (terrain & machines)',
                style: GoogleFonts.spaceGrotesk(color: _primaryContainer, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2),
              ),
            ],
            Text('Enregistrez un nouvel expert dans le réseau Predictive Cloud.', style: GoogleFonts.inter(color: _onVariant)),
          ],
        ),
        ElevatedButton.icon(
          onPressed: _isLoading ? null : _submit,
          icon: const Icon(Icons.person_add),
          label: Text(_isLoading ? (_isEditMode ? 'Modification...' : 'Création...') : (_isEditMode ? 'Enregistrer modifications' : 'Créer le profil')),
          style: ElevatedButton.styleFrom(
            foregroundColor: const Color(0xFF552000),
            backgroundColor: _primaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        )
      ],
    );
  }

  Widget _buildLeftColumn() {
    return Column(
      children: [
        _cardWrap(
          title: 'INFORMATIONS PERSONNELLES',
          accent: _tertiary,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _outline.withOpacity(.5), style: BorderStyle.solid),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add_a_photo, color: _onVariant),
                    const SizedBox(height: 8),
                    Text('Télécharger\nphoto', textAlign: TextAlign.center, style: GoogleFonts.spaceGrotesk(color: _onVariant, fontSize: 10)),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: _input('Nom complet', _nameCtrl, fieldKey: 'name', hint: 'ex: Marc Dubois')),
                        const SizedBox(width: 16),
                        Expanded(child: _input('Téléphone', _phoneCtrl, hint: '+33 6 00 00 00 00')),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _input('Email professionnel', _emailCtrl, fieldKey: 'email', hint: 'm.dubois@predictivecloud.io'),
                  ],
                ),
              )
            ],
          ),
        ),
        const SizedBox(height: 20),
        _cardWrap(
          title: 'COMPÉTENCES & ACCÈS',
          accent: _tertiary,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _dropdown(
                      label: 'Spécialisation',
                      value: _selectedSpecialization,
                      items: const ['Vibration', 'Mécanique', 'Électricité', 'Automatisme', 'Analyse d\'huile'],
                      onChanged: (v) => setState(() => _selectedSpecialization = v ?? _selectedSpecialization),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _clientDropdown(),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _input(
                'Description technique',
                _techDescCtrl,
                fieldKey: 'technicalDescription',
                hint: 'Compétences techniques détaillées...',
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _buildMachineAssignmentSection(),
      ],
    );
  }

  Widget _buildMachineAssignmentSection() {
    if (_selectedClientId == null) return const SizedBox.shrink();
    return _cardWrap(
      title: 'MACHINES À CONTRÔLER (OBLIGATOIRE)',
      accent: _secondary,
      titleActions: IconButton(
        tooltip: 'Actualiser la liste des machines',
        icon: Icon(Icons.refresh, color: _secondary, size: 22),
        onPressed: _loadingMachines ? null : () => _loadMachinesForClient(),
      ),
      child: _loadingMachines
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : _machines.isEmpty
              ? Text(
                  'Étape 1 : pour ce client, enregistrez d\'abord au moins une machine (la première peut être créée sans technicien). Étape 2 : revenez sur cet écran et cochez les machines que ce technicien supervisera.',
                  style: GoogleFonts.inter(color: _onVariant, fontSize: 12, height: 1.45),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Toutes les machines de ce client sont listées ci-dessous. Cochez uniquement celles que ce technicien doit contrôler (une ou plusieurs).',
                      style: GoogleFonts.inter(color: _onVariant.withOpacity(0.95), fontSize: 12, height: 1.35),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_machines.length} machine(s) au total pour ce client',
                      style: GoogleFonts.spaceGrotesk(color: _secondary, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        TextButton(
                          onPressed: () {
                            setState(() {
                              for (final m in _machines) {
                                final mid = _techMachineRowId(m);
                                if (mid.isNotEmpty) _selectedMachineIds.add(mid);
                              }
                              _fieldErrors.remove('machines');
                            });
                          },
                          child: Text('Tout sélectionner', style: GoogleFonts.inter(color: _secondary, fontSize: 12)),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _selectedMachineIds.clear();
                              _fieldErrors.remove('machines');
                            });
                          },
                          child: Text('Tout désélectionner', style: GoogleFonts.inter(color: _onVariant, fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ..._machines.map((m) {
                      final mid = _techMachineRowId(m);
                      if (mid.isEmpty) return const SizedBox.shrink();
                      final checked = _selectedMachineIds.contains(mid);
                      final mName = (m['name'] ?? '').toString().trim();
                      return CheckboxListTile(
                        value: checked,
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
                        title: Text(mName.isEmpty ? mid : mName, style: GoogleFonts.inter(color: _on, fontWeight: FontWeight.w600)),
                        subtitle: Text(mid, style: GoogleFonts.spaceGrotesk(color: _onVariant, fontSize: 10)),
                        activeColor: _secondary,
                        checkColor: _bg,
                      );
                    }),
                    if (_fieldErrors['machines'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(_fieldErrors['machines']!, style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 12)),
                      ),
                  ],
                ),
    );
  }

  Widget _buildRightColumn() {
    return Column(
      children: [
        _cardWrap(
          title: 'CONNEXION TECHNICIEN',
          accent: const Color(0xFFFFB4AB),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isEditMode
                    ? 'Email ci-dessus. Nouveau mot de passe : laisser vide pour ne pas changer.'
                    : 'Email (identifiant) et mot de passe permettent au technicien de se connecter à son espace.',
                style: GoogleFonts.inter(color: _onVariant.withOpacity(0.85), fontSize: 11, height: 1.35),
              ),
              const SizedBox(height: 14),
              _input(
                _isEditMode ? 'Nouveau mot de passe (optionnel)' : 'Mot de passe de connexion',
                _passCtrl,
                fieldKey: 'password',
                isPassword: true,
                hint: _isEditMode ? 'Laisser vide pour conserver' : 'Minimum 6 caractères',
              ),
              const SizedBox(height: 18),
              _switchTile('Accès mobile', 'AUTORISER L\'APP MOBILE', _mobileAccess, (v) => setState(() => _mobileAccess = v)),
              const SizedBox(height: 12),
              _switchTile('Forcer changement', 'À LA PREMIÈRE CONNEXION', _forceChangeAtFirstLogin, (v) => setState(() => _forceChangeAtFirstLogin = v)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _cardWrap(
          title: 'APERÇU DE LA CARTE ID',
          accent: _secondary,
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.engineering, color: _onVariant),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_nameCtrl.text.isEmpty ? 'Nom du Technicien' : _nameCtrl.text, style: GoogleFonts.inter(color: _on, fontWeight: FontWeight.bold)),
                      Text('ID: TECH-XXXX-XXXX', style: GoogleFonts.spaceGrotesk(color: _onVariant, fontSize: 10)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('STATUS', style: GoogleFonts.spaceGrotesk(color: _onVariant, fontSize: 10)),
                  Row(
                    children: [
                      Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text('EN ATTENTE', style: GoogleFonts.spaceGrotesk(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 10)),
                    ],
                  )
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cardWrap({required String title, required Color accent, required Widget child, Widget? titleActions}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 3, height: 14, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: GoogleFonts.spaceGrotesk(color: _onVariant, letterSpacing: 3, fontWeight: FontWeight.bold, fontSize: 11)),
              ),
              if (titleActions != null) titleActions,
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  Widget _input(String label, TextEditingController controller, {String? fieldKey, bool isPassword = false, String hint = ''}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: GoogleFonts.spaceGrotesk(color: _onVariant.withOpacity(.6), fontSize: 10, fontWeight: FontWeight.bold)),
        TextField(
          controller: controller,
          obscureText: isPassword && _obscurePass,
          onChanged: (_) {
            if (fieldKey != null && _fieldErrors.containsKey(fieldKey)) {
              setState(() => _fieldErrors.remove(fieldKey));
            }
            setState(() {});
          },
          style: GoogleFonts.inter(color: _on),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: _onVariant.withOpacity(.4)),
            border: const UnderlineInputBorder(borderSide: BorderSide(color: _outline)),
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: _outline)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: _secondary)),
            suffixIcon: isPassword
                ? IconButton(
                    onPressed: () => setState(() => _obscurePass = !_obscurePass),
                    icon: Icon(_obscurePass ? Icons.visibility : Icons.visibility_off, color: _onVariant),
                  )
                : null,
          ),
        ),
        if (fieldKey != null && _fieldErrors[fieldKey] != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_fieldErrors[fieldKey]!, style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 12)),
          ),
      ],
    );
  }

  Widget _dropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: GoogleFonts.spaceGrotesk(color: _onVariant.withOpacity(.6), fontSize: 10, fontWeight: FontWeight.bold)),
        DropdownButtonFormField<String>(
          value: value,
          onChanged: onChanged,
          dropdownColor: _surface,
          style: GoogleFonts.inter(color: _on),
          decoration: const InputDecoration(
            border: UnderlineInputBorder(borderSide: BorderSide(color: _outline)),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: _outline)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: _secondary)),
          ),
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        ),
      ],
    );
  }

  Widget _clientDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ASSIGNATION CLIENT', style: GoogleFonts.spaceGrotesk(color: _onVariant.withOpacity(.6), fontSize: 10, fontWeight: FontWeight.bold)),
        if (_isLoadingClients)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else
          DropdownButtonFormField<String>(
            value: _selectedClientId != null && _clients.any((c) => _techClientRowId(c) == _selectedClientId)
                ? _selectedClientId
                : null,
            hint: Text('Choisir un client dans la base…', style: GoogleFonts.inter(color: _onVariant, fontSize: 13)),
            onChanged: (v) {
              setState(() {
                _selectedClientId = v;
                _fieldErrors.remove('companyId');
                _fieldErrors.remove('machines');
              });
              _loadMachinesForClient();
            },
            isExpanded: true,
            dropdownColor: _surface,
            style: GoogleFonts.inter(color: _on),
            decoration: const InputDecoration(
              border: UnderlineInputBorder(borderSide: BorderSide(color: _outline)),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: _outline)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: _secondary)),
            ),
            items: _clients.map((c) {
              final id = _techClientRowId(c);
              if (id.isEmpty) return null;
              return DropdownMenuItem<String>(
                value: id,
                child: Text(_techClientLabel(c), overflow: TextOverflow.ellipsis, maxLines: 1),
              );
            }).whereType<DropdownMenuItem<String>>().toList(),
          ),
        if (_fieldErrors['companyId'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_fieldErrors['companyId']!, style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 12)),
          )
      ],
    );
  }

  Widget _switchTile(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: GoogleFonts.inter(color: _on, fontWeight: FontWeight.bold)),
            Text(subtitle, style: GoogleFonts.spaceGrotesk(color: _onVariant.withOpacity(.6), fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: _secondary,
        ),
      ],
    );
  }
}
