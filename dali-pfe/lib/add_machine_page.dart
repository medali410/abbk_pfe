import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'services/api_service.dart';

class AddMachinePage extends StatefulWidget {
  final String clientId;
  final String clientName;

  const AddMachinePage({
    super.key,
    this.clientId = '',
    this.clientName = '',
  });

  @override
  State<AddMachinePage> createState() => _AddMachinePageState();
}

class _AddMachinePageState extends State<AddMachinePage> {
  final _formKey = GlobalKey<FormState>();
  
  final _nameController = TextEditingController();
  final _powerController = TextEditingController();
  final _voltageController = TextEditingController();
  final _speedController = TextEditingController();
  final _locationController = TextEditingController();
  final _companyIdController = TextEditingController();
  final _serialNumberController = TextEditingController();
  final _firmwareVersionController = TextEditingController(text: 'v1.0.0');

  String _type = 'pompe_centrifuge';
  String _motorType = 'air_cooled';
  DateTime _installDate = DateTime.now();
  String _status = 'RUNNING';

  List<Map<String, dynamic>> _technicians = [];
  bool _loadingTechs = false;
  final Set<String> _techniciensAssignes = {};

  List<Map<String, dynamic>> _seuilsControle = [];
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
    if (widget.clientId.isNotEmpty) {
      _companyIdController.text = widget.clientId;
    }
    if (widget.clientName.isNotEmpty) {
      _locationController.text = 'Site ${widget.clientName}';
    }
    _initializeSeuilsControle();
    _loadTechnicians();
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

  Future<void> _loadTechnicians() async {
    setState(() => _loadingTechs = true);
    try {
      final list = await ApiService.getTechnicians();
      if (!mounted) return;
      setState(() {
        _technicians = list;
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
    _powerController.dispose();
    _voltageController.dispose();
    _speedController.dispose();
    _locationController.dispose();
    _companyIdController.dispose();
    _serialNumberController.dispose();
    _firmwareVersionController.dispose();
    super.dispose();
  }

  Future<void> _saveMachine() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isSaving = true);

    final machineData = {
      "name": _nameController.text.trim(),
      "type": _type,
      "power": _powerController.text.trim(),
      "voltage": _voltageController.text.trim(),
      "speed": _speedController.text.trim(),
      "motorType": _motorType,
      "installDate": _installDate.toIso8601String(),
      "location": _locationController.text.trim(),
      "companyId": _companyIdController.text.trim(),
      "serialNumber": _serialNumberController.text.trim(),
      "firmwareVersion": _firmwareVersionController.text.trim(),
      "status": _status,
      "seuilsControle": _seuilsControle,
      "techniciensAssignes": _techniciensAssignes.toList(),
      "tempsMarche": {"totalHeures": 0, "enMarche": false},
    };

    try {
      // Use direct HTTP post to match the exact requirement /api/machines
      final uri = Uri.parse('${ApiService.baseUrl}/machines');
      final headers = await ApiService.jsonHeadersAuthorized();
      final response = await http.post(uri, headers: headers, body: json.encode(machineData));

      if (response.statusCode == 201 || response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Machine ajoutée avec succès !'), backgroundColor: Colors.green),
          );
          Navigator.pop(context, true);
        }
      } else {
        throw Exception('Erreur serveur: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  label: 'PUISSANCE (kW) *',
                  hint: 'ex: 15',
                  controller: _powerController,
                  icon: Icons.flash_on_outlined,
                  keyboardType: TextInputType.number,
                  validator: (v) => (double.tryParse(v ?? '') ?? 0) > 0 ? null : 'Invalide',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildTextField(
                  label: 'TENSION (V) *',
                  hint: 'ex: 400',
                  controller: _voltageController,
                  icon: Icons.bolt_outlined,
                  validator: (v) => v == null || v.isEmpty ? 'Requis' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  label: 'VITESSE (tr/min) *',
                  hint: 'ex: 1500',
                  controller: _speedController,
                  icon: Icons.speed_outlined,
                  keyboardType: TextInputType.number,
                  validator: (v) => (int.tryParse(v ?? '') ?? 0) > 0 ? null : 'Invalide',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildDateField(
                  label: 'DATE INSTALLATION *',
                  value: _installDate,
                  onChanged: (date) => setState(() => _installDate = date),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildTextField(
            label: 'LOCALISATION *',
            hint: 'ex: Zone B',
            controller: _locationController,
            icon: Icons.location_on_outlined,
            validator: (v) => v == null || v.isEmpty ? 'Requis' : null,
          ),
          const SizedBox(height: 24),
          _buildTextField(
            label: 'ID ENTREPRISE *',
            hint: 'ex: CLI-2026',
            controller: _companyIdController,
            icon: Icons.business_outlined,
            validator: (v) => v == null || v.isEmpty ? 'Requis' : null,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  label: 'NUMÉRO SÉRIE',
                  hint: 'Optionnel',
                  controller: _serialNumberController,
                  icon: Icons.tag,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildTextField(
                  label: 'FIRMWARE',
                  hint: 'ex: v1.0.0',
                  controller: _firmwareVersionController,
                  icon: Icons.memory,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildDropdownField(
            label: 'STATUT INITIAL',
            value: _status,
            items: ['RUNNING', 'STOPPED', 'MAINTENANCE', 'ERROR'],
            icon: Icons.online_prediction,
            onChanged: (v) {
              if (v != null) setState(() => _status = v);
            },
          ),
          const SizedBox(height: 32),
          _buildSectionTitle('TECHNICIENS ASSIGNÉS'),
          const SizedBox(height: 16),
          _buildTechniciansSelect(),
          const SizedBox(height: 32),
          _buildSectionTitle('SEUILS DE MAINTENANCE'),
          const SizedBox(height: 16),
          _buildSeuilsList(),
        ],
      ),
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

  Widget _buildDateField({
    required String label,
    required DateTime value,
    required void Function(DateTime) onChanged,
  }) {
    final dateStr = "${value.toLocal()}".split(' ')[0];
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
        InkWell(
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: value,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
              builder: (context, child) {
                return Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: const ColorScheme.dark(
                      primary: _primary,
                      onPrimary: Colors.white,
                      surface: _surface,
                      onSurface: _onSurface,
                    ),
                  ),
                  child: child!,
                );
              },
            );
            if (date != null) onChanged(date);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: _bg.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today_outlined, color: _primary.withOpacity(0.6), size: 20),
                const SizedBox(width: 12),
                Text(dateStr, style: GoogleFonts.spaceGrotesk(color: _onSurface, fontSize: 16)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTechniciansSelect() {
    if (_loadingTechs) {
      return const Center(child: CircularProgressIndicator(color: _primary));
    }
    if (_technicians.isEmpty) {
      return Text('Aucun technicien disponible.', style: GoogleFonts.inter(color: _onSurfaceVariant));
    }
    return Column(
      children: _technicians.map((tech) {
        final id = (tech['_id'] ?? tech['id'] ?? tech['technicianId'] ?? '').toString();
        final name = (tech['name'] ?? id).toString();
        if (id.isEmpty) return const SizedBox.shrink();
        final isSelected = _techniciensAssignes.contains(id);
        
        return CheckboxListTile(
          value: isSelected,
          onChanged: (v) {
            setState(() {
              if (v == true) {
                _techniciensAssignes.add(id);
              } else {
                _techniciensAssignes.remove(id);
              }
            });
          },
          title: Text(name, style: GoogleFonts.inter(color: _onSurface)),
          activeColor: _primary,
          checkColor: Colors.white,
          contentPadding: EdgeInsets.zero,
        );
      }).toList(),
    );
  }

  Widget _buildSeuilsList() {
    if (_seuilsControle.isEmpty) {
      return Text('Aucun seuil défini pour ce type de moteur.', style: GoogleFonts.inter(color: _onSurfaceVariant));
    }
    return Column(
      children: _seuilsControle.map((seuil) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: _bg.withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: ListTile(
            leading: const Icon(Icons.build_circle_outlined, color: _primary),
            title: Text(seuil['typeControle'], style: GoogleFonts.inter(color: _onSurface, fontWeight: FontWeight.w600)),
            subtitle: Text('Toutes les ${seuil['intervalleHeures']} heures', style: GoogleFonts.spaceGrotesk(color: _onSurfaceVariant, fontSize: 12)),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
              onPressed: () {
                setState(() {
                  _seuilsControle.remove(seuil);
                });
              },
            ),
          ),
        );
      }).toList(),
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
