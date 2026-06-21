import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/api_service.dart';

/// Page dédiée à l'envoi d'une mission depuis l'agent maintenance vers un technicien.
class SendMissionPage extends StatefulWidget {
  const SendMissionPage({
    super.key,
    required this.machineId,
    required this.machineName,
    this.agentName = 'Agent Maintenance',
    this.existingInterventionId,
  });

  final String machineId;
  final String machineName;
  final String agentName;
  final String? existingInterventionId;

  @override
  State<SendMissionPage> createState() => _SendMissionPageState();
}

class _SendMissionPageState extends State<SendMissionPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _descController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  bool _isSending = false;
  bool _sent = false;
  String? _sentMissionId;
  String? _interventionId;

  // Technicians
  List<Map<String, dynamic>> _technicians = [];
  Map<String, dynamic>? _selectedTechnician;
  bool _isLoadingTechnicians = true;
  String? _techLoadError;

  static const _bg = Color(0xFF0B0B1E);
  static const _surface = Color(0xFF131330);
  static const _surfaceHigh = Color(0xFF1D1D40);
  static const _accent = Color(0xFFFF6E00);
  static const _textPrimary = Color(0xFFE2DFFF);
  static const _textMuted = Color(0xFF8884A8);

  @override
  void initState() {
    super.initState();
    _interventionId = widget.existingInterventionId;
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
    _loadTechnicians();
  }

  Future<void> _loadTechnicians() async {
    try {
      final techs = await ApiService.getTechnicians(machineId: widget.machineId);
      if (mounted) {
        setState(() {
          _technicians = techs;
          _isLoadingTechnicians = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _techLoadError = 'Impossible de charger les techniciens.';
          _isLoadingTechnicians = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _sendMission() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedTechnician == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez sélectionner un technicien.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }
    setState(() => _isSending = true);

    try {
      final techId = (_selectedTechnician!['_id'] ?? _selectedTechnician!['id'] ?? '').toString();
      final techName = (_selectedTechnician!['fullName'] ?? _selectedTechnician!['name'] ?? 'Technicien').toString();

      String interventionId = _interventionId ?? '';
      if (interventionId.isEmpty) {
        try {
          final list = await ApiService.getDiagnosticInterventions();
          final active = list.lastWhere(
            (i) => (i['machineId'] ?? '').toString() == widget.machineId &&
                   (i['technicianId'] ?? '').toString() == techId &&
                   i['status'] != 'DONE' &&
                   i['status'] != 'CANCELLED',
            orElse: () => <String, dynamic>{},
          );
          if (active.isNotEmpty) {
            interventionId = (active['id'] ?? active['_id'] ?? '').toString();
            if (mounted) setState(() => _interventionId = interventionId);
          }
        } catch (_) {}
      }

      if (interventionId.isEmpty) {
        final resp = await ApiService.createDiagnosticIntervention({
          'machineId': widget.machineId,
          'machineName': widget.machineName,
          'technicianId': techId,
          'authorName': widget.agentName,
          'type': 'INSPECTION',
          'priority': 'NORMAL',
        });
        interventionId = (resp['id'] ?? resp['_id'] ?? '').toString();
        if (mounted) setState(() => _interventionId = interventionId);
      }

      if (interventionId.isEmpty) throw Exception('Impossible de créer l\'intervention.');

      final missionContent = '[MISSION → $techName]\n\n${_descController.text.trim()}';

      final result = await ApiService.addCoordinationNote(
        interventionId,
        missionContent,
        authorName: widget.agentName,
        isMission: true,
      );

      final noteId = (result['noteId'] ?? result['id'] ?? '').toString();
      if (mounted) {
        setState(() {
          _sent = true;
          _sentMissionId = noteId;
          _isSending = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur : $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: _sent ? _buildSuccessView() : _buildMainView(),
      ),
    );
  }

  Widget _buildMainView() {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: _buildForm(),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 48, 16, 16),
      decoration: BoxDecoration(
        color: _surface,
        border: Border(
          bottom: BorderSide(color: _accent.withValues(alpha: 0.25), width: 1),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white70),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _accent.withValues(alpha: 0.4)),
            ),
            child: const Icon(Icons.assignment_turned_in_outlined, color: _accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ENVOYER UNE MISSION',
                  style: GoogleFonts.orbitron(
                    color: _accent,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.machineName,
                  style: GoogleFonts.spaceGrotesk(
                    color: _textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Machine info banner
            _buildMachineBanner(),
            const SizedBox(height: 24),

            // Technician selector
            _buildSectionLabel('👷 SÉLECTIONNER UN TECHNICIEN'),
            const SizedBox(height: 12),
            _buildTechnicianSelector(),
            const SizedBox(height: 24),

            // Description
            _buildSectionLabel('📝 DESCRIPTION DE LA MISSION'),
            const SizedBox(height: 10),
            _buildTextField(
              controller: _descController,
              hint: 'Décrivez les étapes, les observations attendues…',
              icon: Icons.description_outlined,
              maxLines: 5,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'La description est obligatoire'
                  : null,
            ),
            const SizedBox(height: 32),

            // Send button
            _buildSendButton(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildMachineBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1620),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          const Icon(Icons.precision_manufacturing, color: Colors.cyanAccent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.machineName,
                  style: GoogleFonts.orbitron(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'ID: ${widget.machineId}',
                  style: GoogleFonts.spaceGrotesk(
                    color: Colors.blueGrey,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTechnicianSelector() {
    if (_isLoadingTechnicians) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(color: _accent),
        ),
      );
    }

    if (_techLoadError != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _techLoadError!,
                style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _isLoadingTechnicians = true;
                  _techLoadError = null;
                });
                _loadTechnicians();
              },
              child: const Text('Réessayer', style: TextStyle(color: _accent)),
            ),
          ],
        ),
      );
    }

    if (_technicians.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _surfaceHigh,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          'Aucun technicien disponible.',
          style: GoogleFonts.inter(color: _textMuted, fontSize: 13),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _technicians.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final tech = _technicians[i];
        final name = (tech['fullName'] ?? tech['name'] ?? 'Technicien').toString();
        final techId = (tech['technicianId'] ?? tech['displayId'] ?? '').toString();
        final email = (tech['email'] ?? '').toString();
        final isSelected = _selectedTechnician == tech;

        return GestureDetector(
          onTap: () => setState(() => _selectedTechnician = tech),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isSelected ? _accent.withValues(alpha: 0.12) : _surfaceHigh,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? _accent.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.06),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: isSelected ? _accent.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.06),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'T',
                    style: GoogleFonts.orbitron(
                      color: isSelected ? _accent : _textMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.spaceGrotesk(
                          color: isSelected ? _textPrimary : Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (techId.isNotEmpty || email.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          techId.isNotEmpty ? 'ID: $techId' : email,
                          style: GoogleFonts.inter(
                            color: _textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (isSelected)
                  const Icon(Icons.check_circle_rounded, color: _accent, size: 20)
                else
                  Icon(Icons.radio_button_unchecked_rounded, color: _textMuted.withValues(alpha: 0.5), size: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.orbitron(
        color: _accent,
        fontSize: 10,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      style: GoogleFonts.inter(color: _textPrimary, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(color: _textMuted, fontSize: 13),
        prefixIcon: Icon(icon, color: _textMuted, size: 18),
        filled: true,
        fillColor: _surfaceHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _buildSendButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _isSending ? null : _sendMission,
        icon: _isSending
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : const Icon(Icons.send_rounded, size: 18),
        label: Text(
          _isSending ? 'Envoi en cours…' : 'ENVOYER LA MISSION',
          style: GoogleFonts.orbitron(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          disabledBackgroundColor: _accent.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _buildSuccessView() {
    final techName = _selectedTechnician != null
        ? (_selectedTechnician!['fullName'] ?? _selectedTechnician!['name'] ?? 'le technicien').toString()
        : 'le technicien';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 56),
            ),
            const SizedBox(height: 24),
            Text(
              'Mission envoyée !',
              style: GoogleFonts.orbitron(
                color: Colors.greenAccent,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'La mission pour ${widget.machineName} a été envoyée à $techName.',
              style: GoogleFonts.inter(color: _textMuted, fontSize: 14, height: 1.5),
              textAlign: TextAlign.center,
            ),
            if (_sentMissionId != null && _sentMissionId!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Référence: $_sentMissionId',
                style: GoogleFonts.spaceGrotesk(color: _textMuted, fontSize: 11),
              ),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _surfaceHigh,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Retour', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
