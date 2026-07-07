import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'services/api_service.dart';
import 'services/theme_service.dart';

/// Formulaire super-admin : fiche personnel maintenance (Mongo `MaintenanceAgent`).
class AddMaintenanceAgentPage extends StatefulWidget {
  /// Intégré au dashboard (sans pile) : retour vers l’écran appelant.
  final VoidCallback? onEmbeddedBack;

  /// Édition : données issues de `team-directory` ou GET agents (clés `maintenanceAgentId`, `clientId`, `machineIds`, etc.).
  final Map<String, dynamic>? initialData;

  const AddMaintenanceAgentPage({super.key, this.onEmbeddedBack, this.initialData});

  @override
  State<AddMaintenanceAgentPage> createState() => _AddMaintenanceAgentPageState();
}

class _AddMaintenanceAgentPageState extends State<AddMaintenanceAgentPage> {
  bool get _isDark => ThemeService().isDarkMode;
  Color get _bg => _isDark ? const Color(0xFF10102B) : const Color(0xFFF4F6F8);
  Color get _surface => _isDark ? const Color(0xFF1D1D38) : Colors.white;
  Color get _onSurface => _isDark ? const Color(0xFFE2DFFF) : const Color(0xFF1E1E2D);
  Color get _onVariant => _isDark ? const Color(0xFFE2BFB0) : const Color(0xFF7A7A8C);
  static const _primary = Color(0xFFFF6E00);

  final _name = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _address = TextEditingController();
  final _location = TextEditingController();

  List<Map<String, dynamic>> _clients = [];
  List<Map<String, dynamic>> _machines = [];
  String? _clientKey;
  final Set<String> _selectedMachineIds = {};
  bool _loadingClients = true;
  bool _loadingMachines = false;
  bool _saving = false;
  bool _obscure = true;
  bool _sendCredentialsEmail = true;

  bool get _isEdit {
    final i = widget.initialData;
    if (i == null) return false;
    final mid = (i['maintenanceAgentId'] ?? '').toString().trim();
    if (mid.isNotEmpty) return true;
    final oid = (i['id'] ?? '').toString().trim();
    return oid.isNotEmpty;
  }

  String get _apiUpdateId {
    final i = widget.initialData;
    if (i == null) return '';
    final mid = (i['maintenanceAgentId'] ?? '').toString().trim();
    if (mid.isNotEmpty) return mid;
    return (i['id'] ?? '').toString().trim();
  }

  String _clientRowKey(Map<String, dynamic> c) {
    final v = c['clientId'] ?? c['id'] ?? c['_id'];
    return v == null ? '' : v.toString();
  }

  String _clientLabel(Map<String, dynamic> c) {
    final k = _clientRowKey(c);
    final n = c['name']?.toString().trim() ?? '';
    if (n.isNotEmpty) return '$n ($k)';
    return k;
  }

  String _machineId(Map<String, dynamic> m) {
    return (m['machineId'] ?? m['id'] ?? m['_id'] ?? '').toString();
  }

  String _machineName(Map<String, dynamic> m) {
    return (m['name'] ?? _machineId(m)).toString();
  }

  @override
  void initState() {
    super.initState();
    final init = widget.initialData;
    if (init != null) {
      final first = (init['firstName'] ?? '').toString().trim();
      final last = (init['lastName'] ?? '').toString().trim();
      _name.text = ([first, last].where((e) => e.isNotEmpty).join(' ')).trim();
      _firstName.text = (init['firstName'] ?? '').toString();
      _lastName.text = (init['lastName'] ?? '').toString();
      _email.text = (init['email'] ?? '').toString();
      _address.text = (init['address'] ?? '').toString();
      _location.text = (init['location'] ?? '').toString();
      final ck = init['clientId']?.toString();
      if (ck != null && ck.isNotEmpty) {
        _clientKey = ck;
      }
      final mids = init['machineIds'];
      if (mids is List) {
        for (final e in mids) {
          final s = e.toString();
          if (s.isNotEmpty) _selectedMachineIds.add(s);
        }
      }
    }
    _loadClients();
  }

  @override
  void dispose() {
    _name.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _password.dispose();
    _address.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _loadClients() async {
    setState(() => _loadingClients = true);
    try {
      var list = await ApiService.getClients();
      list = List<Map<String, dynamic>>.from(list);
      list.sort((a, b) => _clientLabel(a).toLowerCase().compareTo(_clientLabel(b).toLowerCase()));
      if (!mounted) return;
      setState(() {
        _clients = list;
        _loadingClients = false;
        final pre = _clientKey?.trim();
        if (pre != null && pre.isNotEmpty) {
          String? match;
          for (final c in list) {
            if (_clientRowKey(c) == pre) {
              match = _clientRowKey(c);
              break;
            }
            final mongoId = (c['id'] ?? c['_id'] ?? '').toString();
            if (mongoId == pre) {
              match = _clientRowKey(c);
              break;
            }
          }
          _clientKey = match;
        }
      });
      if (_clientKey != null && _clientKey!.isNotEmpty) {
        await _loadMachinesForClient(
          _clientKey!,
          preserveSelection: _selectedMachineIds.isNotEmpty,
        );
      }
    } catch (_) {
      if (mounted) setState(() => _loadingClients = false);
    }
  }

  Future<void> _loadMachinesForClient(String key, {bool preserveSelection = false}) async {
    setState(() {
      _loadingMachines = true;
      if (!preserveSelection) {
        _selectedMachineIds.clear();
      }
      _machines = [];
    });
    try {
      final list = await ApiService.getMachinesForClient(key);
      if (!mounted) return;
      setState(() {
        _machines = list;
        _loadingMachines = false;
        if (preserveSelection) {
          final valid = list.map(_machineId).where((s) => s.isNotEmpty).toSet();
          _selectedMachineIds.removeWhere((id) => !valid.contains(id));
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMachines = false);
    }
  }

  Future<void> _submit() async {
    final identifier = _name.text.trim();
    final em = _email.text.trim().toLowerCase();
    final pw = _password.text;
    if (identifier.isEmpty) {
      _snack('Nom obligatoire', err: true);
      return;
    }
    if (RegExp(r'\bagent\b', caseSensitive: false).hasMatch(identifier)) {
      _snack('Le nom ne doit pas contenir "agent". Saisissez un vrai nom.', err: true);
      return;
    }
    if (em.isEmpty || !em.contains('@')) {
      _snack('Email (Gmail) valide obligatoire', err: true);
      return;
    }
    final parts = identifier.split(RegExp(r'\s+')).where((e) => e.trim().isNotEmpty).toList();
    final typedFirst = _firstName.text.trim();
    final typedLast = _lastName.text.trim();
    final fn = typedFirst.isNotEmpty ? typedFirst : (parts.isNotEmpty ? parts.first : identifier);
    final ln = typedLast.isNotEmpty ? typedLast : (parts.length > 1 ? parts.sublist(1).join(' ') : '');
    if (!_isEdit && pw.length < 6) {
      _snack('Mot de passe : 6 caractères minimum', err: true);
      return;
    }
    if (_isEdit && pw.isNotEmpty && pw.length < 6) {
      _snack('Nouveau mot de passe : 6 caractères minimum', err: true);
      return;
    }
    final ck = _clientKey?.trim();
    if (ck == null || ck.isEmpty) {
      _snack('Choisissez un client', err: true);
      return;
    }

    setState(() => _saving = true);
    try {
      if (_isEdit) {
        final body = <String, dynamic>{
          'name': identifier,
          'firstName': fn,
          'lastName': ln,
          'email': em,
          'address': _address.text.trim(),
          'location': _location.text.trim(),
          'clientId': ck,
          'machineIds': _selectedMachineIds.toList(),
        };
        if (pw.isNotEmpty) body['password'] = pw;
        await ApiService.updateMaintenanceAgent(_apiUpdateId, body);
      } else {
        final result = await ApiService.addMaintenanceAgent({
          'name': identifier,
          'firstName': fn,
          'lastName': ln,
          'email': em,
          'password': pw,
          'address': _address.text.trim(),
          'location': _location.text.trim(),
          'clientId': ck,
          'machineIds': _selectedMachineIds.toList(),
          'sendEmail': _sendCredentialsEmail,
        });
        final mailInfo = result['credentialsEmail'];
        final mailMap = mailInfo is Map ? Map<String, dynamic>.from(mailInfo) : null;
        final mailMsg = _credentialsEmailSnackMessage(mailMap);
        if (mailMsg.isNotEmpty) {
          _snack(mailMsg, err: mailMap?['sent'] != true);
        }
      }
      if (!mounted) return;
      if (widget.onEmbeddedBack != null) {
        widget.onEmbeddedBack!();
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      _snack('$e', err: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg, {bool err = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: err ? Colors.red : null),
    );
  }

  String _credentialsEmailSnackMessage(Map<String, dynamic>? mail) {
    if (mail == null) return '';
    if (mail['sent'] == true) {
      return 'Un e-mail avec le mot de passe a été envoyé à ${mail['to'] ?? 'l\'adresse indiquée'}.';
    }
    final reason = (mail['reason'] ?? '').toString();
    final detail = (mail['detail'] ?? '').toString().trim();
    switch (reason) {
      case 'smtp_credentials_missing':
        return 'Compte créé. SMTP_USER / SMTP_PASS manquants dans .env.';
      case 'send_failed':
        if (detail.isNotEmpty) {
          return 'Compte créé. E-mail non envoyé : $detail';
        }
        return 'Compte créé. E-mail non envoyé (vérifiez SMTP dans .env).';
      case 'skipped_by_user':
        return 'Compte créé sans envoi d\'e-mail.';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: _onSurface,
        leading: widget.onEmbeddedBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onEmbeddedBack,
              )
            : null,
        title: Text(
          _isEdit ? 'Edit Maintenance' : 'Add Maintenance',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Fiche enregistrée en base MongoDB. Réservé au super-admin.',
                  style: GoogleFonts.spaceGrotesk(fontSize: 12, color: _onVariant, height: 1.4),
                ),
                const SizedBox(height: 8),
                Text(
                  'Rôle : Add Maintenance',
                  style: GoogleFonts.spaceGrotesk(
                    color: _primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 20),
                _field(
                  'Nom complet maintenance',
                  _name,
                  hintText: 'ex: Omar Bensalem',
                ),
                _field('Gmail', _email, keyboard: TextInputType.emailAddress, hintText: 'ex: om1@gmail.com'),
                const SizedBox(height: 12),
                _field('Mot de passe', _password, obscure: _obscure, suffix: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: _onVariant),
                  onPressed: () => setState(() => _obscure = !_obscure),
                )),
                _field('Localisation (ville/site)', _location),
                const SizedBox(height: 8),
                Text('CLIENT / CONTRÔLEUR', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onVariant, letterSpacing: 1.2)),
                const SizedBox(height: 8),
                if (_loadingClients)
                  LinearProgressIndicator(minHeight: 2, color: _primary)
                else if (_clients.isEmpty)
                  Text('Aucun client.', style: GoogleFonts.inter(color: _onVariant))
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _onVariant.withOpacity(0.2)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _clientKey != null && _clients.any((c) => _clientRowKey(c) == _clientKey)
                            ? _clientKey
                            : null,
                        hint: Text('Choisir un client…', style: GoogleFonts.inter(color: _onVariant)),
                        dropdownColor: _surface,
                        style: GoogleFonts.inter(color: _onSurface),
                        items: _clients
                            .map((c) {
                              final k = _clientRowKey(c);
                              if (k.isEmpty) return null;
                              return DropdownMenuItem(value: k, child: Text(_clientLabel(c)));
                            })
                            .whereType<DropdownMenuItem<String>>()
                            .toList(),
                        onChanged: (v) {
                          setState(() {
                            _clientKey = v;
                          });
                          if (v != null) _loadMachinesForClient(v, preserveSelection: false);
                        },
                      ),
                    ),
                  ),
                const SizedBox(height: 18),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  collapsedIconColor: _onVariant,
                  iconColor: _primary,
                  title: Text(
                    'Optionnel (avancé)',
                    style: GoogleFonts.inter(
                      color: _onVariant,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  children: [
                    _field('Prénom (optionnel)', _firstName),
                    _field('Nom de famille (optionnel)', _lastName),
                    _field('Adresse', _address, maxLines: 2),
                    Text('Machines (optionnel)', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onVariant, letterSpacing: 1.2)),
                    const SizedBox(height: 8),
                    if (_loadingMachines)
                      Center(child: Padding(padding: const EdgeInsets.all(16), child: CircularProgressIndicator(color: _primary)))
                    else if (_clientKey == null)
                      Text('Choisissez d’abord un client.', style: GoogleFonts.inter(fontSize: 13, color: _onVariant))
                    else if (_machines.isEmpty)
                      Text('Aucune machine pour ce client.', style: GoogleFonts.inter(fontSize: 13, color: _onVariant))
                    else
                      Container(
                        constraints: const BoxConstraints(maxHeight: 220),
                        decoration: BoxDecoration(
                          color: _surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _onVariant.withOpacity(0.2)),
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _machines.length,
                          itemBuilder: (context, i) {
                            final m = _machines[i];
                            final id = _machineId(m);
                            if (id.isEmpty) return const SizedBox.shrink();
                            final sel = _selectedMachineIds.contains(id);
                            return CheckboxListTile(
                              value: sel,
                              onChanged: (v) {
                                setState(() {
                                  if (v == true) {
                                    _selectedMachineIds.add(id);
                                  } else {
                                    _selectedMachineIds.remove(id);
                                  }
                                });
                              },
                              activeColor: _primary,
                              title: Text(
                                _machineName(m),
                                style: GoogleFonts.inter(color: _onSurface, fontSize: 14),
                              ),
                              subtitle: Text(
                                id,
                                style: GoogleFonts.spaceGrotesk(fontSize: 11, color: _onVariant),
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
                const SizedBox(height: 20),
                if (!_isEdit)
                  CheckboxListTile(
                    value: _sendCredentialsEmail,
                    onChanged: (v) => setState(() => _sendCredentialsEmail = v ?? true),
                    activeColor: _primary,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Envoyer les identifiants par e-mail',
                      style: GoogleFonts.inter(color: _onSurface, fontSize: 14),
                    ),
                    subtitle: Text(
                      'Un e-mail contenant l\'adresse et le mot de passe sera envoyé à l\'agent maintenance.',
                      style: GoogleFonts.inter(color: _onVariant, fontSize: 12),
                    ),
                  ),
                if (!_isEdit) const SizedBox(height: 8),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          _isEdit ? 'ENREGISTRER LES MODIFICATIONS' : 'ENREGISTRER',
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

  // ignore: unused_element
  Widget _twoFields() {
    return Row(
      children: [
        Expanded(child: _field('Prénom', _firstName)),
        const SizedBox(width: 12),
        Expanded(child: _field('Nom', _lastName)),
      ],
    );
  }

  Widget _field(
    String label,
    TextEditingController c, {
    TextInputType? keyboard,
    bool obscure = false,
    Widget? suffix,
    int maxLines = 1,
    String? hintText,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label.trim().isNotEmpty)
            Text(label, style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onVariant, letterSpacing: 1)),
          const SizedBox(height: 6),
          TextField(
            controller: c,
            keyboardType: keyboard,
            obscureText: obscure,
            maxLines: obscure ? 1 : maxLines,
            style: GoogleFonts.inter(color: _onSurface),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: GoogleFonts.inter(color: _onVariant.withOpacity(0.65), fontSize: 13),
              filled: true,
              fillColor: _surface,
              suffixIcon: suffix,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _onVariant.withOpacity(0.2))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _onVariant.withOpacity(0.2))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _primary)),
            ),
          ),
        ],
      ),
    );
  }
}
