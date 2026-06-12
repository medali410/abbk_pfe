import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/api_service.dart';

class AddMachinePage extends StatefulWidget {
  final String clientId;
  final String clientName;
  final String actorRole;

  const AddMachinePage({
    super.key,
    this.clientId = '',
    this.clientName = '',
    this.actorRole = '',
  });

  @override
  State<AddMachinePage> createState() => _AddMachinePageState();
}

class _AddMachinePageState extends State<AddMachinePage> {
  final _formKey = GlobalKey<FormState>();
  
  final _nameController = TextEditingController();
  final _model3dController = TextEditingController();
  final _imageUrlController = TextEditingController();
  final _priceController = TextEditingController();
  final _stockController = TextEditingController(text: '0');

  String _type = 'pompe_centrifuge';
  String _motorType = 'air_cooled';
  String _selectedImage = '';

  List<Map<String, dynamic>> _seuilsControle = [];
  bool _isSaving = false;
  bool _isAuthorized = false;
  bool _isCheckingAuth = true;
  bool _isPublic = false;

  // Design Tokens
  static const _bg = Color(0xFF0A0A1F);
  static const _surface = Color(0xFF12122D);
  static const _primary = Color(0xFFFF6E00);
  static const _secondary = Color(0xFF75D1FF);
  static const _onSurface = Color(0xFFE2DFFF);
  static const _onSurfaceVariant = Color(0xFFA0A0B0);

  @override
  void initState() {
    super.initState();
    _resolveAuthorization();
    _initializeSeuilsControle();
  }

  Future<void> _resolveAuthorization() async {
    final routeRole = widget.actorRole.toLowerCase().trim();
    if (routeRole == 'concepteur' || routeRole == 'conception') {
      if (!mounted) return;
      setState(() {
        _isAuthorized = true;
        _isCheckingAuth = false;
      });
      return;
    }

    await ApiService.loadSavedAuth();
    if (!mounted) return;
    final role = (ApiService.savedUserRole ?? '').toLowerCase();
    setState(() {
      _isAuthorized = role == 'concepteur' || role == 'conception';
      _isCheckingAuth = false;
    });
  }

  void _initializeSeuilsControle() {
    if (_motorType == 'air_cooled') {
      _seuilsControle = [
        {"typeControle": "Contrôle huile", "intervalleHeures": 100},
        {"typeControle": "Contrôle filtre air", "intervalleHeures": 50},
        {"typeControle": "Contrôle courroie", "intervalleHeures": 250},
        {"typeControle": "Nettoyage radiateur", "intervalleHeures": 300},
        {"typeControle": "Révision générale", "intervalleHeures": 500},
      ];
    } else if (_motorType == 'water_cooled') {
      _seuilsControle = [
        {"typeControle": "Contrôle niveau eau", "intervalleHeures": 50},
        {"typeControle": "Contrôle pompe eau", "intervalleHeures": 100},
        {"typeControle": "Vérification circuit eau", "intervalleHeures": 200},
        {"typeControle": "Changement liquide", "intervalleHeures": 500},
        {"typeControle": "Révision générale", "intervalleHeures": 1000},
      ];
    } else {
      _seuilsControle = [];
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _model3dController.dispose();
    _imageUrlController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  bool _looksLikeNetworkImage(String value) {
    final v = value.trim().toLowerCase();
    return v.startsWith('http://') || v.startsWith('https://');
  }

  bool _looksLikeDataImage(String value) {
    final v = value.trim().toLowerCase();
    return v.startsWith('data:image/');
  }

  bool _looksLikeLocalFilePath(String value) {
    final v = value.trim();
    if (v.isEmpty) return false;
    return RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(v) ||
        v.startsWith(r'\\') ||
        v.startsWith('/');
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

    final ext = (file.extension ?? '').toLowerCase();
    var mime = 'image/jpeg';
    if (ext == 'png') mime = 'image/png';
    if (ext == 'gif') mime = 'image/gif';
    if (ext == 'webp') mime = 'image/webp';
    final b64 = base64Encode(bytes);
    return 'data:$mime;base64,$b64';
  }

  String _toFriendlyError(Object error) {
    final msg = error.toString().replaceFirst('Exception: ', '').trim();
    if (msg.contains('403')) {
      return 'Acces refuse : seul le role Concepteur peut ajouter une machine.';
    }
    if (msg.contains('401')) {
      return 'Session invalide. Reconnectez-vous puis reessayez.';
    }
    if (msg.contains('400')) {
      final details = msg.replaceAll(RegExp(r'^.*400[:\s-]*', caseSensitive: false), '').trim();
      if (details.isNotEmpty) {
        return 'Donnees invalides : $details';
      }
      return 'Donnees invalides. Verifiez les champs puis reessayez.';
    }
    return msg;
  }

  Future<void> _saveMachine() async {
    if (!_isAuthorized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Accès refusé : seul le rôle Concepteur peut ajouter une machine.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final rawImageInput = _imageUrlController.text.trim();
    if (_looksLikeLocalFilePath(rawImageInput)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Chemin local detecte. Utilisez "Choisir photo" pour televerser une image.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    setState(() => _isSaving = true);
    final normalizedImage = _normalizeMachineImageValue(rawImageInput);

    final machineData = {
      "name": _nameController.text.trim(),
      "type": _type,
      "motorType": _motorType,
      "model3dUrl": _model3dController.text.trim(),
      "imageUrl": normalizedImage,
      "price": _priceController.text.trim(),
      "stock": int.tryParse(_stockController.text.trim()) ?? 0,
      "isPublic": _isPublic,
      "seuilsControle": _seuilsControle,
    };

    try {
      final created = await ApiService.createStandaloneMachine(
        machineData,
        actorRole: widget.actorRole,
      );
      final createdId = (created['id'] ?? created['_id'] ?? '').toString().trim();
      final createdName = (created['name'] ?? machineData['name'] ?? '').toString().trim().toLowerCase();

      // Controle fort: on confirme que la machine est bien persistee en base
      // avant d'annoncer le succes a l'utilisateur.
      final allMachines = await ApiService.getMachines();
      final stored = allMachines.any((m) {
        final mid = (m['id'] ?? m['_id'] ?? '').toString().trim();
        final mname = (m['name'] ?? '').toString().trim().toLowerCase();
        if (createdId.isNotEmpty && mid == createdId) return true;
        return createdName.isNotEmpty && mname == createdName;
      });
      if (!stored) {
        throw FormatException('Machine non confirmee en base de donnees. Reessayez.');
      }

      if (widget.clientId.isNotEmpty) {
        final machineId = (created['id'] ?? created['_id'] ?? '').toString().trim();
        if (machineId.isNotEmpty) {
          await ApiService.assignMachineToClient(machineId, widget.clientId);
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Machine ajoutée avec succès !'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, created);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_toFriendlyError(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingAuth) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(
          child: CircularProgressIndicator(color: _primary),
        ),
      );
    }

    if (!_isAuthorized) {
      return Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: _onSurface, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            'AJOUTER UNE MACHINE',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
              color: _onSurface,
            ),
          ),
          centerTitle: true,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withOpacity(0.35)),
              ),
              child: Text(
                'Accès refusé : cette fonctionnalité est réservée au rôle Concepteur.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: _onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: _onSurface, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '➕ AJOUTER UNE MACHINE',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
            color: _onSurface,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 40),
              _buildForm(),
              const SizedBox(height: 40),
              _buildSubmitButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.clientName.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: _primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: _primary.withOpacity(0.3)),
            ),
            child: Text(
              'CLIENT: ${widget.clientName.toUpperCase()}',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: _primary,
                letterSpacing: 1,
              ),
            ),
          ),
        Text(
          'Enregistrement de\nl\'équipement industriel',
          style: GoogleFonts.inter(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: _onSurface,
            height: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTextField(
            label: 'NOM DE LA MACHINE *',
            hint: 'ex: MAC-A01',
            controller: _nameController,
            icon: Icons.precision_manufacturing_outlined,
            validator: (v) => v == null || v.isEmpty ? 'Champ obligatoire' : null,
          ),
          const SizedBox(height: 24),
          _buildDropdownField(
            label: 'TYPE DE MACHINE *',
            value: _type,
            items: ['pompe_centrifuge', 'moteur_electrique', 'ventilateur', 'compresseur', 'machine_standard'],
            icon: Icons.category_outlined,
            onChanged: (v) {
              if (v != null) setState(() { _type = v; _initializeSeuilsControle(); });
            },
          ),
          const SizedBox(height: 24),
          _buildDropdownField(
            label: 'TYPE DE MOTEUR *',
            value: _motorType,
            items: ['air_cooled', 'water_cooled', 'electric', 'diesel'],
            icon: Icons.settings_input_component_outlined,
            onChanged: (v) {
              if (v != null) setState(() { _motorType = v; _initializeSeuilsControle(); });
            },
          ),
          const SizedBox(height: 24),
          _buildTextField(
            label: 'MODÈLE 3D *',
            hint: 'ex: machine.glb',
            controller: _model3dController,
            icon: Icons.view_in_ar_outlined,
            validator: (v) => v == null || v.trim().isEmpty ? 'Champ obligatoire' : null,
          ),
          const SizedBox(height: 24),
          _buildTextField(
            label: 'PRIX DE LA MACHINE',
            hint: 'ex: 1500',
            controller: _priceController,
            icon: Icons.monetization_on_outlined,
          ),
          const SizedBox(height: 24),
          _buildTextField(
            label: 'STOCK INITIAL',
            hint: 'ex: 5',
            controller: _stockController,
            icon: Icons.pin_outlined,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 24),
          _buildMachinePhotoField(),
          const SizedBox(height: 24),
          SwitchListTile(
            title: Text(
              _isPublic ? 'MACHINE PUBLIÉE' : 'MACHINE NON PUBLIÉE',
              style: GoogleFonts.spaceGrotesk(color: _onSurface, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
            subtitle: Text(
              _isPublic
                  ? 'Activé : visible dans le catalogue public'
                  : 'Désactivé : visible uniquement dans votre dashboard',
              style: GoogleFonts.inter(color: _onSurfaceVariant, fontSize: 11),
            ),
            value: _isPublic,
            activeColor: _primary,
            contentPadding: EdgeInsets.zero,
            onChanged: (v) => setState(() => _isPublic = v),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildMachinePhotoField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PHOTO DE LA MACHINE',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: _onSurfaceVariant,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _imageUrlController,
          style: GoogleFonts.spaceGrotesk(color: _onSurface, fontSize: 16),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixIcon: Icon(
              Icons.image_outlined,
              color: _primary.withOpacity(0.6),
              size: 20,
            ),
            hintText: 'URL image ou image upload',
            hintStyle: GoogleFonts.spaceGrotesk(
              color: _onSurfaceVariant.withOpacity(0.3),
              fontSize: 14,
            ),
            filled: true,
            fillColor: _bg.withOpacity(0.5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _primary),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                final dataUrl = await _pickImageAsDataUrl();
                if (dataUrl != null && dataUrl.isNotEmpty && mounted) {
                  setState(() {
                    _selectedImage = dataUrl;
                    _imageUrlController.text = dataUrl;
                  });
                }
              },
              icon: const Icon(Icons.upload_file_outlined, size: 16),
              label: const Text('Choisir photo'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _selectedImage = '';
                  _imageUrlController.clear();
                });
              },
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Supprimer'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildImagePreview(),
      ],
    );
  }

  Widget _buildImagePreview() {
    final raw = _selectedImage.isNotEmpty
        ? _selectedImage
        : _normalizeMachineImageValue(_imageUrlController.text);
    return Container(
      height: 120,
      width: double.infinity,
      decoration: BoxDecoration(
        color: _bg.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: raw.isEmpty
          ? const Center(
              child: Icon(Icons.image_outlined, color: _onSurfaceVariant),
            )
          : (_looksLikeNetworkImage(raw)
              ? Image.network(
                  ApiService.fullUrl(raw),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image_outlined, color: _onSurfaceVariant),
                  ),
                )
              : (_looksLikeDataImage(raw)
                  ? Image.memory(
                      base64Decode(raw.split(',').last),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image_outlined, color: _onSurfaceVariant),
                      ),
                    )
                  : const Center(
                      child: Text(
                        'Apercu indisponible (URL invalide)',
                        style: TextStyle(color: _onSurfaceVariant, fontSize: 12),
                      ),
                    ))),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.spaceGrotesk(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: _secondary,
        letterSpacing: 2,
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: _onSurfaceVariant,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          style: GoogleFonts.spaceGrotesk(color: _onSurface, fontSize: 16),
          keyboardType: keyboardType,
          validator: validator,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: _primary.withOpacity(0.6), size: 20),
            hintText: hint,
            hintStyle: GoogleFonts.spaceGrotesk(color: _onSurfaceVariant.withOpacity(0.3), fontSize: 14),
            filled: true,
            fillColor: _bg.withOpacity(0.5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _primary),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String value,
    required List<String> items,
    required IconData icon,
    required void Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: _onSurfaceVariant,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: value,
          dropdownColor: _surface,
          icon: Icon(Icons.expand_more, color: _primary.withOpacity(0.8)),
          style: GoogleFonts.spaceGrotesk(color: _onSurface, fontSize: 15),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: _primary.withOpacity(0.6), size: 20),
            filled: true,
            fillColor: _bg.withOpacity(0.5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _primary),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return InkWell(
      onTap: _isSaving ? null : _saveMachine,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_primary, Color(0xFFFF8F3F)],
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: _primary.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: _isSaving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : Text(
                  'ENREGISTRER LA MACHINE',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
        ),
      ),
    );
  }
}
