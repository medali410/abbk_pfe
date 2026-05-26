import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/api_service.dart';
import 'client_dashboard_page.dart';

class AddClientPage extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  final VoidCallback? onBack;
  final bool isDialog;
  
  const AddClientPage({super.key, this.initialData, this.onBack, this.isDialog = false});

  @override
  State<AddClientPage> createState() => _AddClientPageState();
}

class _AddClientPageState extends State<AddClientPage> {
  String? _selectedMotorType;
  bool _obscurePassword = true;
  bool _isSubmitting = false;
  bool _isLoadingLinks = false;
  final _companyController = TextEditingController();
  final _locationController = TextEditingController();
  final _addressController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  List<Map<String, dynamic>> _machines = [];
  List<Map<String, dynamic>> _technicians = [];
  List<Map<String, dynamic>> _maintenanceAgents = [];
  final Set<String> _selectedMachineIds = {};
  final Set<String> _selectedTechnicianIds = {};
  final Set<String> _selectedMaintenanceAgentIds = {};

  // Color constants
  static const _bg = Color(0xFF10102B);
  static const _surface = Color(0xFF191934);
  static const _surfaceContainer = Color(0xFF1D1D38);
  static const _surfaceHigh = Color(0xFF272743);
  static const _surfaceHighest = Color(0xFF32324E);
  static const _inputBg = Color(0xFF1A1A35);
  static const _onSurface = Color(0xFFE2DFFF);
  static const _onSurfaceVariant = Color(0xFFE2BFB0);
  static const _outline = Color(0xFF594136);
  static const _primary = Color(0xFFFFB692);
  static const _primaryContainer = Color(0xFFFF6E00);
  static const _secondary = Color(0xFF75D1FF);

  @override
  void initState() {
    super.initState();
    _loadLinkData();
    if (widget.initialData != null) {
      _companyController.text = widget.initialData!['name'] ?? '';
      _locationController.text = widget.initialData!['location'] ?? '';
      _addressController.text = widget.initialData!['address'] ?? '';
      _emailController.text = widget.initialData!['email'] ?? '';
      // Le mot de passe n'est jamais renvoyé par l'API (haché) : saisir un nouveau MDP pour le remplacer
      _passwordController.clear();
      _selectedMotorType = widget.initialData!['motorType'] ?? 'ac-induction';
    }
  }

  Future<void> _loadLinkData() async {
    setState(() => _isLoadingLinks = true);
    try {
      final results = await Future.wait([
        ApiService.getUnassignedMachines(),
        ApiService.getTechnicians(),
        ApiService.getMaintenanceAgents(),
      ]);
      if (!mounted) return;
      setState(() {
        _machines = (results[0] as List).cast<Map<String, dynamic>>();
        _technicians = (results[1] as List).cast<Map<String, dynamic>>();
        _maintenanceAgents = (results[2] as List).cast<Map<String, dynamic>>();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _machines = [];
        _technicians = [];
        _maintenanceAgents = [];
      });
    } finally {
      if (mounted) setState(() => _isLoadingLinks = false);
    }
  }

  @override
  void dispose() {
    _companyController.dispose();
    _locationController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 992 && !widget.isDialog;

    final content = Column(
      children: [
        _buildTopBar(),
        Expanded(
          child: _buildMainContent(false),
        ),
      ],
    );

    if (widget.isDialog) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: Container(
          width: 900,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _primaryContainer.withOpacity(0.2)),
          ),
          child: content,
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      body: content,
    );
  }

  // ─── TOP BAR ───────────────────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: _bg.withOpacity(0.95),
        border: Border(
          bottom: BorderSide(color: _primaryContainer.withOpacity(0.1), width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (widget.isDialog)
                IconButton(
                  icon: const Icon(Icons.close, color: _onSurfaceVariant),
                  onPressed: () => Navigator.pop(context),
                )
              else
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: _onSurfaceVariant),
                  onPressed: widget.onBack ?? () => Navigator.pop(context),
                ),
              const SizedBox(width: 8),
            ],
          ),
          const SizedBox(),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon) {
    return InkWell(
      onTap: () {},
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, color: _onSurfaceVariant, size: 24),
      ),
    );
  }


  // ─── MAIN CONTENT ──────────────────────────────────────────
  Widget _buildMainContent(bool isDesktop) {
    return Stack(
      children: [
        // Ambient glows
        Positioned(
          top: 100,
          left: 100,
          child: Container(
            width: 384,
            height: 384,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [_primaryContainer.withOpacity(0.05), Colors.transparent],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 100,
          right: 100,
          child: Container(
            width: 384,
            height: 384,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [_secondary.withOpacity(0.05), Colors.transparent],
              ),
            ),
          ),
        ),

        // Scrollable form
        SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 768),
              child: Column(
                children: [
                  _buildFormCard(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── FORM CARD ─────────────────────────────────────────────
  Widget _buildFormCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _outline.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 40,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          _buildFormHeader(),
          const SizedBox(height: 40),

          // Form fields
          _buildCompanyNameField(),
          const SizedBox(height: 32),
          _buildLocationField(),
          const SizedBox(height: 32),
          _buildCredentialsSection(),
          const SizedBox(height: 32),
          _buildActions(),
        ],
      ),
    );
  }

  // ─── FORM HEADER ───────────────────────────────────────────
  Widget _buildFormHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.initialData == null ? 'Ajouter un Nouveau Client' : 'Modifier le Client',
          style: GoogleFonts.inter(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: _onSurface,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  // ─── COMPANY NAME ──────────────────────────────────────────
  Widget _buildCompanyNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Nom de l\'entreprise'),
        const SizedBox(height: 8),
        _buildInputField(
          controller: _companyController,
          hint: 'EX: KINETIC CORP',
          keyboardType: TextInputType.text,
        ),
      ],
    );
  }

  // ─── LOCATION ─────────────────────────────────────────────
  Widget _buildLocationField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Localisation'),
        const SizedBox(height: 8),
        _buildInputField(
          controller: _locationController,
          hint: 'EX: ALGER, ORAN, CONSTANTINE',
          keyboardType: TextInputType.text,
        ),
      ],
    );
  }

  // ─── CREDENTIALS SECTION ───────────────────────────────────
  Widget _buildCredentialsSection() {
    return Container(
      padding: const EdgeInsets.only(top: 24),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x1A594136))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // Email
          _fieldLabel('Email de connexion'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: _outline.withOpacity(0.3))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: GoogleFonts.spaceGrotesk(color: _onSurface, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'name@company.com',
                      hintStyle: GoogleFonts.spaceGrotesk(
                        color: _onSurfaceVariant.withOpacity(0.3),
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                Icon(Icons.alternate_email, color: _onSurfaceVariant.withOpacity(0.4), size: 20),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Password
          _fieldLabel(widget.initialData == null
              ? 'Mot de passe initial (min. 6 caractères)'
              : 'Nouveau mot de passe'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: _outline.withOpacity(0.3))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    style: GoogleFonts.spaceGrotesk(
                      color: _onSurface,
                      fontSize: 14,
                      letterSpacing: _obscurePassword ? 4 : 0,
                    ),
                    decoration: InputDecoration(
                      hintText: widget.initialData == null
                          ? 'Définir le mot de passe client'
                          : 'Laisser vide pour ne pas modifier',
                      hintStyle: GoogleFonts.spaceGrotesk(
                        color: _onSurfaceVariant.withOpacity(0.3),
                        fontSize: 14,
                        letterSpacing: 4,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => setState(() => _obscurePassword = !_obscurePassword),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      color: _onSurfaceVariant.withOpacity(0.6),
                      size: 20,
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

  // ─── ACTIONS ───────────────────────────────────────────────
  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () {
              if (widget.onBack != null) widget.onBack!();
              else Navigator.pop(context);
            },
            child: Text(
              'Annuler',
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: _onSurfaceVariant,
                letterSpacing: 2,
              ),
            ),
          ),
          const SizedBox(width: 24),
          InkWell(
            onTap: _isSubmitting ? null : _onSubmit,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_primaryContainer, _primary],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _isSubmitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(
                      widget.initialData == null ? 'Créer le Client' : 'Sauvegarder',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 2),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── HELPERS ───────────────────────────────────────────────
  Widget _fieldLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: GoogleFonts.inter(
        fontSize: 10,
        fontWeight: FontWeight.bold,
        color: _onSurfaceVariant,
        letterSpacing: 2,
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _outline.withOpacity(0.3))),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: GoogleFonts.spaceGrotesk(color: _onSurface, fontSize: 16),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.spaceGrotesk(
            color: _onSurfaceVariant.withOpacity(0.3),
            fontSize: 16,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Future<void> _onSubmit() async {
    if (_companyController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Veuillez renseigner le nom de l\'entreprise')));
      return;
    }
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email de connexion client obligatoire')));
      return;
    }
    final isNew = widget.initialData == null;
    if (isNew && _passwordController.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mot de passe obligatoire (minimum 6 caractères)')));
      return;
    }

    final payload = <String, dynamic>{
      'name': _companyController.text.trim(),
      'email': email.toLowerCase(),
      // Reste des champs par défaut ou supprimés
      'location': _locationController.text.trim(),
      'address': '',
      'motorType': 'ac-induction',
    };
    if (_passwordController.text.isNotEmpty) {
      payload['password'] = _passwordController.text;
    }

    setState(() => _isSubmitting = true);
    try {
      if (isNew) {
        await ApiService.addClient(payload);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Client ajouté avec succès !'), backgroundColor: Colors.green));
      } else {
        final id = widget.initialData!['clientId'] ?? widget.initialData!['id'] ?? widget.initialData!['_id'] ?? '';
        await ApiService.updateClient(id, payload);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Client mis à jour !'), backgroundColor: Colors.green));
      }
      
      if (mounted) {
        if (widget.onBack != null) widget.onBack!();
        else Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur API: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
