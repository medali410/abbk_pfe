import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'services/api_service.dart';

class AddConcepteurPage extends StatefulWidget {
  /// Si renseigné : édition (PUT `/api/concepteurs/:id`). Sinon création.
  final Map<String, dynamic>? initialData;

  /// Intégré au dashboard (sans pile de navigation) : retour vers la liste conception.
  final VoidCallback? onEmbeddedBack;

  const AddConcepteurPage({super.key, this.initialData, this.onEmbeddedBack});

  @override
  State<AddConcepteurPage> createState() => _AddConcepteurPageState();
}

String _clientRowId(Map<String, dynamic> c) {
  final cid = (c['clientId'] ?? '').toString().trim();
  if (cid.isNotEmpty) return cid;
  return (c['id'] ?? c['_id'] ?? '').toString();
}

String _clientLabel(Map<String, dynamic> c) {
  final name = (c['name'] ?? '').toString().trim();
  final id = _clientRowId(c);
  if (name.isEmpty) return id.isEmpty ? '—' : id;
  return '$name ($id)';
}

String _machineRowId(Map<String, dynamic> m) {
  return (m['machineId'] ?? m['id'] ?? m['_id'] ?? '').toString();
}

String _machineLabel(Map<String, dynamic> m) {
  final name = (m['name'] ?? '').toString().trim();
  final id = _machineRowId(m);
  if (name.isEmpty) return id.isEmpty ? '—' : id;
  return '$name — $id';
}

class _AddConcepteurPageState extends State<AddConcepteurPage> {
  static const _bg = Color(0xFF10102B);
  static const _surface = Color(0xFF1D1D38);
  static const _onSurface = Color(0xFFE2DFFF);
  static const _onVariant = Color(0xFFE2BFB0);
  static const _primary = Color(0xFFFF6E00);

  final _email = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _location = TextEditingController();
  final _specialite = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  List<Map<String, dynamic>> _clients = [];
  bool _clientsLoading = true;
  String? _clientsError;

  String? _selectedClientApiId;
  List<Map<String, dynamic>> _machines = [];
  bool _machinesLoading = false;
  String? _machinesError;
  final Set<String> _selectedMachineIds = {};

  bool get _isEdit {
    final id = widget.initialData?['id']?.toString();
    return id != null && id.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    final init = widget.initialData;
    if (init != null) {
      _email.text = (init['email'] ?? '').toString();
      _username.text = (init['username'] ?? '').toString();
      _location.text = (init['location'] ?? '').toString();
      _specialite.text = (init['specialite'] ?? '').toString();
    }
    _bootstrapClientsAndMachines();
  }

  Future<void> _bootstrapClientsAndMachines() async {
    setState(() {
      _clientsLoading = true;
      _clientsError = null;
    });
    try {
      var list = await ApiService.getClients();
      list = List<Map<String, dynamic>>.from(list);
      list.sort((a, b) => _clientLabel(a).toLowerCase().compareTo(_clientLabel(b).toLowerCase()));
      if (!mounted) return;
      setState(() {
        _clients = list;
        _clientsLoading = false;
      });

      final init = widget.initialData;
      final pre = (init?['companyId'] ?? '').toString().trim();
      if (pre.isEmpty) return;

      String? match;
      for (final c in list) {
        if (_clientRowId(c) == pre) {
          match = _clientRowId(c);
          break;
        }
        final mongoId = (c['id'] ?? c['_id'] ?? '').toString();
        if (mongoId == pre) {
          match = _clientRowId(c);
          break;
        }
      }

      if (match == null) {
        if (mounted) {
          setState(() {
            _clientsError = 'Réf. client enregistrée ($pre) introuvable dans la liste — sélectionnez à nouveau.';
          });
        }
        return;
      }

      setState(() => _selectedClientApiId = match);
      await _loadMachinesForClient(match, preserveSelection: false);
      final mids = init?['machineIds'];
      if (mids is List && mounted) {
        setState(() {
          _selectedMachineIds
            ..clear()
            ..addAll(mids.map((e) => e.toString()).where((s) => s.isNotEmpty));
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _clientsLoading = false;
          _clientsError = '$e';
        });
      }
    }
  }

  Future<void> _loadMachinesForClient(String clientApiId, {bool preserveSelection = true}) async {
    setState(() {
      _machinesLoading = true;
      _machinesError = null;
      if (!preserveSelection) _selectedMachineIds.clear();
    });
    try {
      final m = await ApiService.getMachinesForClient(clientApiId);
      if (!mounted) return;
      final ids = m.map(_machineRowId).where((s) => s.isNotEmpty).toSet();
      setState(() {
        _machines = m;
        _machinesLoading = false;
        if (preserveSelection) {
          _selectedMachineIds.removeWhere((id) => !ids.contains(id));
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _machinesLoading = false;
          _machinesError = '$e';
          _machines = [];
        });
      }
    }
  }

  void _onClientChanged(String? newId) {
    setState(() {
      _selectedClientApiId = newId;
      _selectedMachineIds.clear();
      _machines = [];
      _machinesError = null;
    });
    if (newId != null && newId.isNotEmpty) {
      _loadMachinesForClient(newId, preserveSelection: false);
    }
  }

  void _toggleMachine(String machineId) {
    setState(() {
      if (_selectedMachineIds.contains(machineId)) {
        _selectedMachineIds.remove(machineId);
      } else {
        _selectedMachineIds.add(machineId);
      }
    });
  }

  List<String> _machineIdsForSubmit() {
    return _selectedMachineIds.where((s) => s.isNotEmpty).toList();
  }

  @override
  void dispose() {
    _email.dispose();
    _username.dispose();
    _password.dispose();
    _location.dispose();
    _specialite.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final username = _username.text.trim();
    final password = _password.text.trim();
    if (!email.contains('@') || username.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email valide et nom d’utilisateur (2+) requis'), backgroundColor: Colors.red),
      );
      return;
    }
    if ((_selectedClientApiId ?? '').isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sélectionnez un client / entreprise (obligatoire pour piloter les machines)'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (!_isEdit && password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mot de passe obligatoire à la création (6+ caractères)'), backgroundColor: Colors.red),
      );
      return;
    }
    if (_isEdit && password.isNotEmpty && password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nouveau mot de passe : minimum 6 caractères'), backgroundColor: Colors.red),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final companyId = _selectedClientApiId!.trim();
      final mids = _machineIdsForSubmit();
      if (_isEdit) {
        final id = widget.initialData!['id']!.toString();
        final body = <String, dynamic>{
          'email': email,
          'username': username,
          if (_location.text.trim().isNotEmpty) 'location': _location.text.trim(),
          'companyId': companyId,
          if (_specialite.text.trim().isNotEmpty) 'specialite': _specialite.text.trim(),
          'machineIds': mids,
        };
        if (password.isNotEmpty) body['password'] = password;
        await ApiService.updateConcepteur(id, body);
      } else {
        await ApiService.addConcepteur({
          'email': email,
          'username': username,
          'password': password,
          if (_location.text.trim().isNotEmpty) 'location': _location.text.trim(),
          'companyId': companyId,
          if (_specialite.text.trim().isNotEmpty) 'specialite': _specialite.text.trim(),
          if (mids.isNotEmpty) 'machineIds': mids,
        });
      }
      if (!context.mounted) return;
      if (widget.onEmbeddedBack != null) {
        widget.onEmbeddedBack!();
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: _onSurface,
        automaticallyImplyLeading: widget.onEmbeddedBack == null,
        leading: widget.onEmbeddedBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onEmbeddedBack,
              )
            : null,
        title: Text(
          _isEdit ? 'Modifier le concepteur' : 'Nouveau concepteur',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _isEdit
                      ? 'Modification réservée au super-admin. Laissez le mot de passe vide pour ne pas le changer.'
                      : 'Création réservée au super-admin. Compte proche du technicien : arrêt d’urgence des moteurs assignés, ordres de maintenance et liaison client via la messagerie.',
                  style: GoogleFonts.spaceGrotesk(fontSize: 12, color: _onVariant, height: 1.4),
                ),
                if (!_isEdit) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Rôle : concepteur',
                    style: GoogleFonts.spaceGrotesk(
                      color: _primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                _field('Email', _email, keyboard: TextInputType.emailAddress),
                _field('Nom d\'utilisateur', _username),
                _field(
                  _isEdit ? 'Nouveau mot de passe (optionnel)' : 'Mot de passe',
                  _password,
                  obscure: _obscure,
                  suffix: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: _onVariant),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                _field('Spécialité (optionnel)', _specialite),
                _field('Lieu / bureau (optionnel)', _location),
                _clientSelector(),
                _machineSelector(),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _loading
                      ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(
                          _isEdit ? 'ENREGISTRER' : 'CRÉER LE COMPTE',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, letterSpacing: 1),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _clientSelector() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Client / entreprise (obligatoire pour piloter les machines)',
            style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onVariant, letterSpacing: 1),
          ),
          const SizedBox(height: 6),
          if (_clientsLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: _primary))),
            )
          else if (_clientsError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_clientsError!, style: GoogleFonts.inter(fontSize: 12, color: Colors.orangeAccent)),
            ),
          if (!_clientsLoading)
            DropdownButtonFormField<String>(
              value: _selectedClientApiId != null &&
                      _clients.any((c) => _clientRowId(c) == _selectedClientApiId)
                  ? _selectedClientApiId
                  : null,
              isExpanded: true,
              dropdownColor: _surface,
              style: GoogleFonts.inter(color: _onSurface),
              decoration: InputDecoration(
                filled: true,
                fillColor: _surface,
                hintText: 'Choisir un client dans la base',
                hintStyle: GoogleFonts.inter(color: _onVariant.withOpacity(0.7)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _onVariant.withOpacity(0.2))),
                enabledBorder:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _onVariant.withOpacity(0.2))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _primary, width: 1.5)),
              ),
              iconEnabledColor: _onVariant,
              items: _clients
                  .map(
                    (c) => DropdownMenuItem<String>(
                      value: _clientRowId(c),
                      child: Text(_clientLabel(c), overflow: TextOverflow.ellipsis, maxLines: 1),
                    ),
                  )
                  .toList(),
              onChanged: _clients.isEmpty ? null : (v) => _onClientChanged(v),
            ),
        ],
      ),
    );
  }

  Widget _machineSelector() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Machines du client (optionnel — aucune case = tout le parc de ce client)',
            style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onVariant, letterSpacing: 1),
          ),
          const SizedBox(height: 6),
          if ((_selectedClientApiId ?? '').isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _onVariant.withOpacity(0.2)),
              ),
              child: Text(
                'Sélectionnez d’abord un client pour afficher ses machines.',
                style: GoogleFonts.inter(fontSize: 13, color: _onVariant.withOpacity(0.85)),
              ),
            )
          else if (_machinesLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: _primary))),
            )
          else if (_machinesError != null)
            Text(_machinesError!, style: GoogleFonts.inter(fontSize: 12, color: Colors.orangeAccent))
          else if (_machines.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _onVariant.withOpacity(0.2)),
              ),
              child: Text(
                'Aucune machine enregistrée pour ce client.',
                style: GoogleFonts.inter(fontSize: 13, color: _onVariant.withOpacity(0.85)),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _machines.map((m) {
                final id = _machineRowId(m);
                if (id.isEmpty) return const SizedBox.shrink();
                final selected = _selectedMachineIds.contains(id);
                return FilterChip(
                  label: Text(
                    _machineLabel(m),
                    style: GoogleFonts.inter(fontSize: 12, color: selected ? Colors.white : _onSurface),
                  ),
                  selected: selected,
                  onSelected: (_) => _toggleMachine(id),
                  selectedColor: _primary.withOpacity(0.85),
                  backgroundColor: _surface,
                  side: BorderSide(color: selected ? _primary : _onVariant.withOpacity(0.25)),
                  checkmarkColor: Colors.white,
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c, {TextInputType? keyboard, bool obscure = false, Widget? suffix}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onVariant, letterSpacing: 1)),
          const SizedBox(height: 6),
          TextField(
            controller: c,
            keyboardType: keyboard,
            obscureText: obscure,
            style: GoogleFonts.inter(color: _onSurface),
            decoration: InputDecoration(
              filled: true,
              fillColor: _surface,
              suffixIcon: suffix,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _onVariant.withOpacity(0.2))),
              enabledBorder:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _onVariant.withOpacity(0.2))),
            ),
          ),
        ],
      ),
    );
  }
}
