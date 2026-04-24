import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/api_service.dart';

class AddMachinePage extends StatefulWidget {
  final String clientId;
  final String clientName;

  const AddMachinePage({
    super.key,
    required this.clientId,
    required this.clientName,
  });

  @override
  State<AddMachinePage> createState() => _AddMachinePageState();
}

class _AddMachinePageState extends State<AddMachinePage> {
  final _nameController = TextEditingController();
  final _typeController = TextEditingController();
  final _powerController = TextEditingController();
  final _voltageController = TextEditingController();
  final _speedController = TextEditingController();
  final _rulHoursScaleController = TextEditingController();

  /// EL_S / EL_M / EL_L — aligné modèle IA (AI4I Type L/M/H).
  String _iaMotorType = 'EL_M';

  List<Map<String, dynamic>> _technicians = [];
  bool _loadingTechs = false;
  final Set<String> _selectedTechnicianIds = {};

  bool _isSaving = false;

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
    _loadTechnicians();
  }

  Future<void> _loadTechnicians() async {
    setState(() => _loadingTechs = true);
    try {
      final list = await ApiService.getTechniciansForClient(widget.clientId);
      if (!mounted) return;
      setState(() {
        _technicians = list;
        if (list.length == 1) {
          final tid = (list.first['technicianId'] ?? '').toString();
          if (tid.isNotEmpty) _selectedTechnicianIds.add(tid);
        }
      });
    } catch (_) {
      if (mounted) setState(() => _technicians = []);
    } finally {
      if (mounted) setState(() => _loadingTechs = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _typeController.dispose();
    _powerController.dispose();
    _voltageController.dispose();
    _speedController.dispose();
    _rulHoursScaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          'NOUVELLE UNITÉ MACHINE',
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
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Enregistrement de \nl\'équipement industriel',
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
        children: [
          _buildField(
            label: 'NOM DE LA MACHINE',
            hint: 'ex: MAC-A01-CENTRIFUGE',
            controller: _nameController,
            icon: Icons.precision_manufacturing_outlined,
          ),
          const SizedBox(height: 24),
          _buildField(
            label: 'TYPE / MODÈLE',
            hint: 'ex: Pompe de Refroidissement',
            controller: _typeController,
            icon: Icons.category_outlined,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _buildField(
                  label: 'PUISSANCE',
                  hint: 'ex: 15 kW',
                  controller: _powerController,
                  icon: Icons.flash_on_outlined,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildField(
                  label: 'TENSION',
                  hint: 'ex: 400V',
                  controller: _voltageController,
                  icon: Icons.bolt_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildField(
            label: 'VITESSE NOMINALE',
            hint: 'ex: 1500 tr/min',
            controller: _speedController,
            icon: Icons.speed_outlined,
          ),
          const SizedBox(height: 24),
          _buildIaMotorSection(),
          const SizedBox(height: 28),
          Text(
            'TECHNICIENS RESPONSABLES',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: _secondary,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _technicians.isEmpty
                ? 'Première machine : enregistrement possible sans technicien. Ensuite, créez un technicien en cochant cette machine parmi celles qu\'il contrôle.'
                : 'Obligatoire : cochez au moins un technicien pour cette machine (le client a déjà une équipe).',
            style: GoogleFonts.inter(fontSize: 12, color: _onSurfaceVariant, height: 1.35),
          ),
          const SizedBox(height: 16),
          if (_loadingTechs)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(color: _primary)),
            )
          else if (_technicians.isEmpty)
            Text(
              'Aucun technicien enregistré pour ce client — vous pouvez quand même créer cette machine.',
              style: GoogleFonts.inter(fontSize: 13, color: _secondary),
            )
          else
            ..._technicians.map((t) {
              final tid = (t['technicianId'] ?? '').toString();
              if (tid.isEmpty) return const SizedBox.shrink();
              final name = (t['name'] ?? tid).toString();
              return CheckboxListTile(
                value: _selectedTechnicianIds.contains(tid),
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _selectedTechnicianIds.add(tid);
                    } else {
                      _selectedTechnicianIds.remove(tid);
                    }
                  });
                },
                title: Text(name, style: GoogleFonts.inter(color: _onSurface)),
                subtitle: Text(tid, style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant)),
                activeColor: _primary,
                checkColor: Colors.white,
                contentPadding: EdgeInsets.zero,
              );
            }),
        ],
      ),
    );
  }

  Widget _buildIaMotorSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TYPE MOTEUR POUR L\'IA',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: _onSurfaceVariant,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Le modèle distingue trois familles (comme le jeu AI4I). Choisis celle qui correspond au couple / charge nominale.',
          style: GoogleFonts.inter(fontSize: 11, color: _onSurfaceVariant, height: 1.35),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _bg.withOpacity(0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _iaMotorType,
              isExpanded: true,
              dropdownColor: _surface,
              icon: Icon(Icons.expand_more, color: _primary.withOpacity(0.8)),
              style: GoogleFonts.spaceGrotesk(color: _onSurface, fontSize: 15),
              items: const [
                DropdownMenuItem(value: 'EL_S', child: Text('EL_S — faible (type L)')),
                DropdownMenuItem(value: 'EL_M', child: Text('EL_M — moyen (type M)')),
                DropdownMenuItem(value: 'EL_L', child: Text('EL_L — fort (type H)')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _iaMotorType = v);
              },
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'OPTIONNEL — HEURES PAR UNITÉ RUL MODÈLE',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: _onSurfaceVariant,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Si renseigné : affichage « heures indicatives » = RUL modèle × ce nombre (calibration métier, pas une mesure physique).',
          style: GoogleFonts.inter(fontSize: 11, color: _onSurfaceVariant, height: 1.35),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _rulHoursScaleController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: GoogleFonts.spaceGrotesk(color: _onSurface, fontSize: 16),
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.schedule, color: _primary.withOpacity(0.6), size: 20),
            hintText: 'ex: 0.05 (laisser vide si inconnu)',
            hintStyle: GoogleFonts.spaceGrotesk(color: _onSurfaceVariant.withOpacity(0.35), fontSize: 14),
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

  Widget _buildField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required IconData icon,
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
        TextField(
          controller: controller,
          style: GoogleFonts.spaceGrotesk(color: _onSurface, fontSize: 16),
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

  Future<void> _saveMachine() async {
    if (_nameController.text.isEmpty) {
      _showSnack('Le nom est requis', Colors.orange);
      return;
    }
    if (_technicians.isNotEmpty && _selectedTechnicianIds.isEmpty) {
      _showSnack(
        'Ce client a déjà des techniciens : sélectionnez au moins un responsable pour cette machine.',
        Colors.orange,
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final payload = <String, dynamic>{
        'name': _nameController.text,
        'type': _typeController.text,
        'power': _powerController.text,
        'voltage': _voltageController.text,
        'speed': _speedController.text,
        'motorType': _iaMotorType,
        'location': 'Site ${widget.clientName}',
      };
      final scale = double.tryParse(_rulHoursScaleController.text.trim());
      if (scale != null && scale > 0) {
        payload['rulHoursPerModelUnit'] = scale;
      }
      if (_selectedTechnicianIds.isNotEmpty) {
        payload['assignedTechnicianIds'] = _selectedTechnicianIds.toList();
      }

      await ApiService.addMachine(widget.clientId, payload);

      if (mounted) {
        _showSnack('Machine ajoutée avec succès !', Colors.green);
        Navigator.pop(context, true); // Return true to indicate refresh needed
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Erreur: $e', Colors.red);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }
}
