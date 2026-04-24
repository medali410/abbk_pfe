import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/api_service.dart';
import 'client_dashboard_page.dart';

class AddClientPage extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  final VoidCallback? onBack;
  
  const AddClientPage({super.key, this.initialData, this.onBack});

  @override
  State<AddClientPage> createState() => _AddClientPageState();
}

class _AddClientPageState extends State<AddClientPage> {
  String? _selectedMotorType;
  bool _obscurePassword = true;
  final _companyController = TextEditingController();
  final _locationController = TextEditingController();
  final _addressController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

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
    final isDesktop = screenWidth > 992;

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // Sidebar (Desktop only)
          if (isDesktop)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 256,
              child: _buildSidebar(),
            ),

          // Main content
          Positioned.fill(
            left: isDesktop ? 256 : 0,
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: _buildMainContent(isDesktop),
                ),
              ],
            ),
          ),
        ],
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'KINETIC OBSERVATORY',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: _onSurface,
            ),
          ),
          Row(
            children: [
              _iconBtn(Icons.notifications_active_outlined),
              const SizedBox(width: 8),
              _iconBtn(Icons.settings_outlined),
              const SizedBox(width: 8),
              _iconBtn(Icons.account_circle_outlined),
            ],
          ),
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

  // ─── SIDEBAR ───────────────────────────────────────────────
  Widget _buildSidebar() {
    return Container(
      color: _surface,
      padding: const EdgeInsets.only(top: 80, bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SUPERADMIN',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _onSurface,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  'System Core',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: _onSurfaceVariant.withOpacity(0.6),
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          _sidebarItem(Icons.hub_outlined, 'Fleet Overview', false),
          _sidebarItem(Icons.analytics_outlined, 'Asset Health', false),
          _sidebarItem(Icons.precision_manufacturing_outlined, 'Predictive Maintenance', false),
          _sidebarItem(Icons.domain, 'Client Management', true), // ACTIVE
          const Spacer(),
          _sidebarItem(Icons.description_outlined, 'Documentation', false, isSmall: true),
          _sidebarItem(Icons.contact_support_outlined, 'Support', false, isSmall: true),
        ],
      ),
    );
  }

  Widget _sidebarItem(IconData icon, String label, bool active, {bool isSmall = false}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: active ? _surfaceHighest.withOpacity(0.5) : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: active
            ? const Border(right: BorderSide(color: _primaryContainer, width: 4))
            : null,
      ),
      child: ListTile(
        dense: true,
        leading: Icon(
          icon,
          size: isSmall ? 18 : 20,
          color: active ? _primaryContainer : _onSurfaceVariant.withOpacity(0.6),
        ),
        title: Text(
          label.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
            color: active ? _primaryContainer : _onSurfaceVariant.withOpacity(0.6),
            letterSpacing: 1.5,
          ),
        ),
        onTap: () {},
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
                  const SizedBox(height: 32),
                  _buildStatusBento(),
                  const SizedBox(height: 32),
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
          _buildMotorTypeSection(),
          const SizedBox(height: 32),
          _buildLocationSection(),
          const SizedBox(height: 32),
          _buildAddressField(),
          const SizedBox(height: 32),
          _buildCredentialsSection(),
          const SizedBox(height: 32),
          _buildActions(),
        ],
      ),
    );
  }

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
        Text(
          widget.initialData == null ? 'INITIALISATION DU PROTOCOLE D\'ENREGISTREMENT' : 'MISE À JOUR DE LA BASE DE DONNÉES CLOUD',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 11,
            color: _onSurfaceVariant,
            letterSpacing: 2.5,
            fontWeight: FontWeight.w500,
          ),
        ),
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

  // ─── MOTOR TYPE ────────────────────────────────────────────
  Widget _buildMotorTypeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Type de Moteur Industriel'),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 500;
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: isWide ? 4 : 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.9,
              children: [
                _motorCard(
                  id: 'ac-induction',
                  icon: Icons.electrical_services,
                  label: 'Moteur à Induction AC',
                ),
                _motorCard(
                  id: 'permanent-magnet',
                  icon: Icons.filter_tilt_shift,
                  label: 'Moteur Synchrone à Aimants Permanents',
                ),
                _motorCard(
                  id: 'dc-motor',
                  icon: Icons.bolt,
                  label: 'Moteur à Courant Continu (DC)',
                ),
                _motorCard(
                  id: 'servo',
                  icon: Icons.settings_input_component,
                  label: 'Servomoteur Haute Précision',
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _motorCard({required String id, required IconData icon, required String label}) {
    final isSelected = _selectedMotorType == id;
    return GestureDetector(
      onTap: () => setState(() => _selectedMotorType = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? _primaryContainer.withOpacity(0.05) : _inputBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? _primaryContainer : _outline.withOpacity(0.2),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: _primaryContainer.withOpacity(0.1), blurRadius: 15)]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? _primary : _onSurfaceVariant.withOpacity(0.6),
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 10,
                color: isSelected ? _onSurface : _onSurfaceVariant.withOpacity(0.7),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── LOCATION ──────────────────────────────────────────────
  Widget _buildLocationSection() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 500;
        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildLocationField()),
              const SizedBox(width: 24),
              Expanded(child: _buildMapPlaceholder()),
            ],
          );
        } else {
          return Column(
            children: [
              _buildLocationField(),
              const SizedBox(height: 16),
              _buildMapPlaceholder(),
            ],
          );
        }
      },
    );
  }

  Widget _buildLocationField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Localisation'),
        const SizedBox(height: 8),
        _buildInputField(
          controller: _locationController,
          hint: 'City, Country',
          keyboardType: TextInputType.text,
        ),
      ],
    );
  }

  Widget _buildMapPlaceholder() {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: _surfaceHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _outline.withOpacity(0.1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: ColorFiltered(
              colorFilter: const ColorFilter.matrix([
                0.2126, 0.7152, 0.0722, 0, 0,
                0.2126, 0.7152, 0.0722, 0, 0,
                0.2126, 0.7152, 0.0722, 0, 0,
                0,      0,      0,      1, 0,
              ]),
              child: Opacity(
                opacity: 0.4,
                child: Image.network(
                  'https://lh3.googleusercontent.com/aida-public/AB6AXuB_K306U8EHtrj0hmDqTj3723mOsnMK94yBdBsXLfWOr9KLsLsWeEX9Zbsxd5EdOKkfc3UWUNcYipJm3XBNQdXINj0dVWL5ngp3_3OAh-CxgQNz49UZD0e-zsjLpKDhxwP81OQRXh2K5Hd1_biI1b-s0ElLjfNv7DFCECwGZ8eeRJTYmX2Fe95qv2n1hQpXEF_HlzkckqmDyYslrzTmQ2RRNPxRCfLFE6EMRPDJh0C6YZ8UU5lcC-ZLlfLKP-PibTwJV2MMhxZAFqY',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: _surfaceHigh),
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, _surface.withOpacity(0.7)],
              ),
            ),
          ),
          Center(
            child: Icon(
              Icons.location_on_outlined,
              color: _secondary.withOpacity(0.4),
              size: 36,
            ),
          ),
        ],
      ),
    );
  }

  // ─── ADDRESS ───────────────────────────────────────────────
  Widget _buildAddressField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Adresse Complète'),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: _outline.withOpacity(0.3)),
            ),
          ),
          child: TextField(
            controller: _addressController,
            maxLines: 2,
            style: GoogleFonts.spaceGrotesk(color: _onSurface, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Saisir l\'adresse de siège social...',
              hintStyle: GoogleFonts.spaceGrotesk(
                color: _onSurfaceVariant.withOpacity(0.3),
                fontSize: 14,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
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
          Text(
            'Identifiants tableau de bord client',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: _secondary,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Le super admin définit l’email et le mot de passe : le client se connecte avec ces identifiants pour voir uniquement ses machines.',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: _onSurfaceVariant.withOpacity(0.85),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 24),

          // Email
          _fieldLabel('Email de connexion (unique)'),
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
              : 'Nouveau mot de passe (optionnel)'),
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
          // Cancel button
          TextButton(
            onPressed: () {
              if (widget.onBack != null) widget.onBack!();
              else Navigator.pop(context);
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
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

          // Submit button
          InkWell(
            onTap: _onSubmit,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_primaryContainer, _primary],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: _primaryContainer.withOpacity(0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                widget.initialData == null ? 'Créer le Client' : 'Sauvegarder',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── STATUS BENTO ──────────────────────────────────────────
  Widget _buildStatusBento() {
    return Row(
      children: [
        Expanded(
          child: _bentoCard(
            label: 'SYS_AUTH',
            value: 'Encryption Active',
            valueColor: _secondary,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _bentoCard(
            label: 'INSTANCE_LOC',
            value: 'Global Node',
            valueColor: _onSurface,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _bentoCard(
            label: 'PROTO_VER',
            value: 'v4.2.0-STABLE',
            valueColor: _onSurface,
          ),
        ),
      ],
    );
  }

  Widget _bentoCard({required String label, required String value, required Color valueColor}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceContainer,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _outline.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 10,
              color: _onSurfaceVariant.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.toUpperCase(),
            style: GoogleFonts.spaceGrotesk(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: valueColor,
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez renseigner le nom de l\'entreprise')),
      );
      return;
    }

    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email de connexion client obligatoire (format valide)')),
      );
      return;
    }

    final isNew = widget.initialData == null;
    if (isNew && _passwordController.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mot de passe obligatoire pour un nouveau client (minimum 6 caractères)')),
      );
      return;
    }

    final payload = <String, dynamic>{
      'name': _companyController.text.trim(),
      'location': _locationController.text.trim(),
      'address': _addressController.text.trim(),
      'email': email.toLowerCase(),
      'motorType': _selectedMotorType ?? 'ac-induction',
    };
    if (_passwordController.text.isNotEmpty) {
      payload['password'] = _passwordController.text;
    }

    try {
      if (isNew) {
        await ApiService.addClient(payload);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Client ajouté avec succès !', style: TextStyle(color: Colors.white)),
              backgroundColor: Colors.green,
              action: SnackBarAction(
                label: 'OUVRIR',
                textColor: Colors.white,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ClientDashboardPage(
                        clientName: _companyController.text,
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        }
      } else {
        final id = widget.initialData!['clientId'] ?? widget.initialData!['id'] ?? widget.initialData!['_id'] ?? '';
        await ApiService.updateClient(id, payload);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Client mis à jour !', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green),
          );
        }
      }
      
      if (mounted) {
        if (widget.onBack != null) widget.onBack!();
        else Navigator.pop(context); // Go back to the client list or profile
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur API: $e', style: const TextStyle(color: Colors.white)), backgroundColor: Colors.red),
        );
      }
    }
  }
}
