import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'services/api_service.dart';

class MachineDetailProPage extends StatefulWidget {
  const MachineDetailProPage({super.key, required this.machine});

  final Map<String, dynamic> machine;

  @override
  State<MachineDetailProPage> createState() => _MachineDetailProPageState();
}

class _MachineDetailProPageState extends State<MachineDetailProPage> {
  late Map<String, dynamic> _machine;
  late List<Map<String, dynamic>> _history;
  bool _savingHistory = false;

  bool _looksLikeNetworkImage(String value) {
    final v = value.trim().toLowerCase();
    return v.startsWith('http://') || v.startsWith('https://');
  }

  bool _looksLikeDataImage(String value) {
    final v = value.trim().toLowerCase();
    return v.startsWith('data:image/');
  }

  String _normalizeMachineImageValue(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    if (_looksLikeNetworkImage(trimmed) || _looksLikeDataImage(trimmed)) {
      return trimmed;
    }
    final hasExtension = RegExp(r'\.[a-z0-9]{2,5}$', caseSensitive: false)
        .hasMatch(trimmed);
    return hasExtension ? trimmed : '$trimmed.png';
  }

  String _toEditImageValue(String value) {
    final trimmed = value.trim();
    if (trimmed.toLowerCase().endsWith('.png') &&
        !_looksLikeNetworkImage(trimmed) &&
        !_looksLikeDataImage(trimmed)) {
      return trimmed.substring(0, trimmed.length - 4);
    }
    return trimmed;
  }

  @override
  void initState() {
    super.initState();
    _machine = Map<String, dynamic>.from(widget.machine);
    _history = _extractHistory(_machine);
  }

  String _read(List<String> keys, {String fallback = '-'}) {
    for (final k in keys) {
      final v = _machine[k];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString();
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 1200;
    final heroHeight = isCompact ? 140.0 : 180.0;
    final machineId = _read(['machineId', '_id', 'id'], fallback: '');
    final name = _read(['name', 'model'], fallback: 'Machine industrielle');
    final brand = _read(['brand', 'marque']);
    final type = _read(['type', 'category']);
    final status = _read(['status', 'etat', 'state'], fallback: 'disponible');
    final price = _read(['price', 'prix']);
    final description = _read(['description'], fallback: 'Aucune description.');
    final imageUrl = _normalizeMachineImageValue(
      _read(['imageUrl', 'image', 'photo'], fallback: ''),
    );

    final capteurs = <MapEntry<String, String>>[
      MapEntry('Température', _read(['temperature', 'temp'])),
      MapEntry('Pression', _read(['pressure'])),
      MapEntry('Vibration', _read(['vibration'])),
      MapEntry('Puissance', _read(['power', 'powerConsumption'])),
      MapEntry('RPM', _read(['rpm'])),
      MapEntry('Couple', _read(['torque'])),
      MapEntry('Usure outil', _read(['toolWear'])),
    ];

    final maintenance = <MapEntry<String, String>>[
      MapEntry('Dernier contrôle', _read(['lastMaintenanceDate', 'lastControlDate'])),
      MapEntry('Prochain contrôle', _read(['nextMaintenanceDate', 'nextControlDate'])),
      MapEntry('Technicien', _read(['technicianName', 'assignedTechnician'])),
      MapEntry('État maintenance', _read(['maintenanceStatus', 'maintenanceState'])),
    ];
    final motorType = _read(['motorType', 'typeMoteur'], fallback: '');
    final machineType = _read(['machineType', 'typeMachine'], fallback: '');
    final fabricationData = _read(['fabricationData', 'fabricationDate', 'dateFabrication'], fallback: '');
    final components = _readStringList(['components', 'composants']);
    final options = _readStringList(['options', 'machineOptions']);
    final canDesign = ApiService.canAddMachineAsConcepteur || ApiService.canManageFleet;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1020),
        appBar: AppBar(
          backgroundColor: const Color(0xFF131B31),
          toolbarHeight: 52,
          title: Text(
            'Détail machine pro',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
          actions: [
            TextButton.icon(
              onPressed:
                  machineId.isEmpty ? null : () => _editMachine(context, machineId),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Modifier'),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed:
                  machineId.isEmpty
                      ? null
                      : () => _confirmDelete(context, machineId, name),
              icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFFF9A9A)),
              label: const Text('Supprimer', style: TextStyle(color: Color(0xFFFF9A9A))),
            ),
            const SizedBox(width: 8),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(40),
            child: TabBar(
              labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
              unselectedLabelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500),
              tabs: const [
                Tab(height: 36, text: 'Vue générale'),
                Tab(height: 36, text: 'Capteurs'),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: [
            SingleChildScrollView(
              padding: EdgeInsets.all(isCompact ? 14 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: double.infinity,
                      height: heroHeight,
                      child:
                          imageUrl.isEmpty
                              ? _fallbackBanner()
                              : (_looksLikeDataImage(imageUrl)
                                  ? Image.memory(
                                      base64Decode(imageUrl.split(',').last),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          _fallbackBanner(),
                                    )
                                  : Image.network(
                                      ApiService.fullUrl(imageUrl),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          _fallbackBanner(),
                                    )),
                    ),
                  ),
                  SizedBox(height: isCompact ? 12 : 16),
                  Text(
                    name,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: isCompact ? 21 : 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: isCompact ? 8 : 10),
                  Wrap(
                    spacing: isCompact ? 6 : 8,
                    runSpacing: isCompact ? 6 : 8,
                    children: [
                      _chip('ID', machineId, compact: isCompact),
                      _chip('Marque', brand, compact: isCompact),
                      _chip('Type', type, compact: isCompact),
                      _chip('Statut', status, compact: isCompact),
                      _chip('Prix', price, compact: isCompact),
                    ],
                  ),
                  SizedBox(height: isCompact ? 10 : 14),
                  _panel(
                    Text(
                      description,
                      style: GoogleFonts.inter(
                        color: const Color(0xFFD7E2F6),
                        fontSize: isCompact ? 12.5 : 14,
                        height: 1.45,
                      ),
                    ),
                    compact: isCompact,
                  ),
                  SizedBox(height: isCompact ? 10 : 14),
                  _panel(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Fiche technique concepteur',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: isCompact ? 13 : 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            if (canDesign)
                              OutlinedButton.icon(
                                onPressed:
                                    machineId.isEmpty
                                        ? null
                                        : () => _editDesignSpecs(context, machineId),
                                icon: const Icon(Icons.construction_outlined, size: 16),
                                label: const Text('Configurer'),
                              ),
                          ],
                        ),
                        SizedBox(height: isCompact ? 8 : 10),
                        _buildMotor3dViewer(compact: isCompact),
                        SizedBox(height: isCompact ? 8 : 10),
                        Wrap(
                          spacing: isCompact ? 6 : 8,
                          runSpacing: isCompact ? 6 : 8,
                          children: [
                            _chip('Type moteur', motorType.isEmpty ? 'Non défini' : motorType, compact: isCompact),
                            _chip('Type machine', machineType.isEmpty ? 'Non défini' : machineType, compact: isCompact),
                            _chip('Data fabrication', fabricationData.isEmpty ? 'Non définie' : fabricationData, compact: isCompact),
                          ],
                        ),
                        SizedBox(height: isCompact ? 8 : 10),
                        Text(
                          'Composants',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: isCompact ? 13 : 14,
                          ),
                        ),
                        SizedBox(height: isCompact ? 5 : 6),
                        if (components.isEmpty)
                          Text(
                            'Aucun composant ajouté pour le moment.',
                            style: GoogleFonts.inter(
                              color: const Color(0xFF9FB1D3),
                              fontSize: isCompact ? 12 : 13,
                            ),
                          )
                        else
                          Wrap(
                            spacing: isCompact ? 6 : 8,
                            runSpacing: isCompact ? 6 : 8,
                            children: components
                                .map((c) => _chip('Composant', c, compact: isCompact))
                                .toList(),
                          ),
                        SizedBox(height: isCompact ? 8 : 10),
                        Text(
                          'Options machine',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: isCompact ? 13 : 14,
                          ),
                        ),
                        SizedBox(height: isCompact ? 5 : 6),
                        if (options.isEmpty)
                          Text(
                            'Aucune option ajoutée pour le moment.',
                            style: GoogleFonts.inter(
                              color: const Color(0xFF9FB1D3),
                              fontSize: isCompact ? 12 : 13,
                            ),
                          )
                        else
                          Wrap(
                            spacing: isCompact ? 6 : 8,
                            runSpacing: isCompact ? 6 : 8,
                            children: options
                                .map((o) => _chip('Option', o, compact: isCompact))
                                .toList(),
                          ),
                      ],
                    ),
                    compact: isCompact,
                  ),
                ],
              ),
            ),
            _kvList(capteurs, compact: isCompact),
          ],
        ),
      ),
    );
  }

  Widget _kvList(List<MapEntry<String, String>> entries, {bool compact = false}) {
    return ListView.builder(
      padding: EdgeInsets.all(compact ? 14 : 18),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[i];
        return Container(
          margin: EdgeInsets.only(bottom: compact ? 8 : 10),
          padding: EdgeInsets.all(compact ? 10 : 12),
          decoration: BoxDecoration(
            color: const Color(0x33182236),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x33FFFFFF)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  e.key,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: compact ? 12 : 14,
                  ),
                ),
              ),
              Text(
                e.value,
                style: GoogleFonts.inter(
                  color: const Color(0xFFD7E2F6),
                  fontSize: compact ? 12 : 14,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _panel(Widget child, {bool compact = false}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 11 : 14),
      decoration: BoxDecoration(
        color: const Color(0x33182236),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: child,
    );
  }

  Widget _buildMotor3dViewer({bool compact = false}) {
    final modelSrc = _read(['model3dUrl', 'model3d', 'modelUrl'], fallback: '');
    final viewerHeight = compact ? 120.0 : 150.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0x33FFFFFF)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: double.infinity,
              height: viewerHeight,
              child: Container(
                color: const Color(0xFF121A2E),
                child:
                    modelSrc.isNotEmpty
                        ? ModelViewer(
                          src: modelSrc,
                          alt: 'Modele 3D machine',
                          ar: false,
                          autoRotate: true,
                          cameraControls: true,
                          backgroundColor: const Color(0xFF121A2E),
                        )
                        : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset(
                                'assets/images/motor_3d_default.png',
                                fit: BoxFit.contain,
                                height: compact ? 95 : 120,
                              ),
                              SizedBox(height: compact ? 8 : 10),
                              Text(
                                'Aucun modele 3D configure',
                                style: GoogleFonts.inter(
                                  color: const Color(0xFFD7E2F6),
                                  fontWeight: FontWeight.w600,
                                  fontSize: compact ? 12 : 14,
                                ),
                              ),
                            ],
                          ),
                        ),
              ),
            ),
          ),
        ),
        SizedBox(height: compact ? 6 : 8),
        Text(
          modelSrc.isNotEmpty
              ? 'Visualiseur 3D natif (rotation/zoom avec souris ou tactile)'
              : 'Ajoutez une URL .glb/.gltf dans "Configurer" pour activer la 3D native',
          style: GoogleFonts.inter(
            color: const Color(0xFFD7E2F6),
            fontSize: compact ? 11 : 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryTab(BuildContext context, String machineId, {bool compact = false}) {
    final canAdd = ApiService.canAddMachineAsConcepteur || ApiService.canManageFleet;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Historique professionnel',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: compact ? 14 : 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed:
                  (!canAdd || machineId.isEmpty || _savingHistory)
                      ? null
                      : () => _addHistoryEntry(context, machineId),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Ajouter'),
            ),
          ],
        ),
        SizedBox(height: compact ? 8 : 10),
        if (!canAdd)
          Text(
            'Seuls les concepteurs/admins peuvent ajouter des entrées.',
            style: GoogleFonts.inter(color: const Color(0xFF9FB1D3), fontSize: 12),
          ),
        SizedBox(height: compact ? 8 : 10),
        if (_history.isEmpty)
          _panel(
            Text(
              'Aucune entrée pour le moment.',
              style: GoogleFonts.inter(color: const Color(0xFFD7E2F6)),
            ),
            compact: compact,
          )
        else
          Column(
            children:
                _history.map((entry) {
                  final title =
                      (entry['title'] ?? entry['event'] ?? 'Événement').toString();
                  final details =
                      (entry['details'] ?? entry['note'] ?? entry['description'] ?? '-')
                          .toString();
                  final author = (entry['author'] ?? entry['by'] ?? '-').toString();
                  final date = (entry['date'] ?? entry['createdAt'] ?? '').toString();
                  final type = (entry['type'] ?? 'INFO').toString();
                  return Container(
                    width: double.infinity,
                    margin: EdgeInsets.only(bottom: compact ? 8 : 10),
                    padding: EdgeInsets.all(compact ? 10 : 12),
                    decoration: BoxDecoration(
                      color: const Color(0x33182236),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0x33FFFFFF)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0x221D88E5),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                type,
                                style: GoogleFonts.inter(
                                  color: const Color(0xFFD2E6FF),
                                  fontSize: compact ? 10 : 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              date,
                              style: GoogleFonts.inter(
                                color: const Color(0xFF9FB1D3),
                                fontSize: compact ? 11 : 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          title,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: compact ? 13 : 14,
                          ),
                        ),
                        SizedBox(height: compact ? 4 : 5),
                        Text(
                          details,
                          style: GoogleFonts.inter(
                            color: const Color(0xFFD7E2F6),
                            height: 1.4,
                            fontSize: compact ? 12 : 13,
                          ),
                        ),
                        SizedBox(height: compact ? 5 : 6),
                        Text(
                          'Ajouté par: $author',
                          style: GoogleFonts.inter(
                            color: const Color(0xFF9FB1D3),
                            fontSize: compact ? 11 : 12,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
          ),
        SizedBox(height: compact ? 6 : 8),
        _panel(
          SelectableText(
            const JsonEncoder.withIndent('  ').convert(_machine),
            style: GoogleFonts.spaceMono(
              color: const Color(0xFFCFD9F0),
              fontSize: compact ? 10 : 11,
            ),
          ),
          compact: compact,
        ),
      ],
    );
  }

  Future<void> _addHistoryEntry(BuildContext context, String machineId) async {
    final titleCtrl = TextEditingController();
    final detailsCtrl = TextEditingController();
    String selectedType = 'INFO';

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setDialog) => AlertDialog(
                  title: const Text('Ajouter une entrée historique'),
                  content: SizedBox(
                    width: 520,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _field(titleCtrl, 'Titre'),
                        _field(detailsCtrl, 'Détails', maxLines: 4),
                        DropdownButtonFormField<String>(
                          value: selectedType,
                          items: const [
                            DropdownMenuItem(value: 'INFO', child: Text('INFO')),
                            DropdownMenuItem(value: 'MAINTENANCE', child: Text('MAINTENANCE')),
                            DropdownMenuItem(value: 'ALERTE', child: Text('ALERTE')),
                            DropdownMenuItem(value: 'ACTION', child: Text('ACTION')),
                          ],
                          onChanged: (v) => setDialog(() => selectedType = v ?? 'INFO'),
                          decoration: const InputDecoration(
                            labelText: 'Type',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
                    ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ajouter')),
                  ],
                ),
          ),
    );

    if (ok != true || !context.mounted) return;
    if (titleCtrl.text.trim().isEmpty || detailsCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Titre et détails sont obligatoires.')),
      );
      return;
    }

    final entry = <String, dynamic>{
      'type': selectedType,
      'title': titleCtrl.text.trim(),
      'details': detailsCtrl.text.trim(),
      'author': ApiService.savedUserRole ?? 'concepteur',
      'createdAt': DateTime.now().toIso8601String(),
      'date': DateTime.now().toIso8601String().substring(0, 16).replaceFirst('T', ' '),
    };

    setState(() => _savingHistory = true);
    try {
      final updatedHistory = [entry, ..._history];
      await ApiService.updateMachine(machineId, {'history': updatedHistory});
      if (!context.mounted) return;
      setState(() {
        _history = updatedHistory;
        _machine['history'] = updatedHistory;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entrée historique ajoutée.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ajout impossible: ${e.toString().replaceAll('Exception: ', '')}')),
      );
    } finally {
      if (mounted) setState(() => _savingHistory = false);
    }
  }

  Future<void> _confirmDelete(BuildContext context, String machineId, String name) async {
    if (!ApiService.canManageFleet) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Accès refusé: seul un admin peut supprimer une machine.')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmer suppression'),
        content: Text('Supprimer la machine $name ($machineId) ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      try {
        await ApiService.deleteMachine(machineId);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Machine supprimée avec succès.')),
        );
        Navigator.pop(context, true);
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Suppression impossible: ${e.toString().replaceAll('Exception: ', '')}')),
        );
      }
    }
  }

  Future<void> _editMachine(BuildContext context, String machineId) async {
    final canEdit = ApiService.canManageFleet || ApiService.canAddMachineAsConcepteur;
    if (!canEdit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Accès refusé: vous ne pouvez pas modifier cette machine.')),
      );
      return;
    }

    final nameCtrl = TextEditingController(text: _read(['name', 'model'], fallback: ''));
    final brandCtrl = TextEditingController(text: _read(['brand', 'marque'], fallback: ''));
    final typeCtrl = TextEditingController(text: _read(['type', 'category'], fallback: ''));
    final statusCtrl = TextEditingController(text: _read(['status', 'etat', 'state'], fallback: ''));
    final priceCtrl = TextEditingController(text: _read(['price', 'prix'], fallback: ''));
    final descCtrl = TextEditingController(text: _read(['description'], fallback: ''));
    final imageCtrl = TextEditingController(
      text: _toEditImageValue(_read(['imageUrl', 'image', 'photo'], fallback: '')),
    );

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Modifier la machine'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _field(nameCtrl, 'Nom'),
                    _field(brandCtrl, 'Marque'),
                    _field(typeCtrl, 'Type'),
                    _field(statusCtrl, 'Statut'),
                    _field(priceCtrl, 'Prix'),
                    _field(imageCtrl, 'Image URL'),
                    _field(descCtrl, 'Description', maxLines: 3),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
            ],
          ),
    );

    if (ok != true || !context.mounted) return;

    final payload = <String, dynamic>{
      'name': nameCtrl.text.trim(),
      'brand': brandCtrl.text.trim(),
      'type': typeCtrl.text.trim(),
      'status': statusCtrl.text.trim(),
      'price': priceCtrl.text.trim(),
      'description': descCtrl.text.trim(),
      'imageUrl': _normalizeMachineImageValue(imageCtrl.text),
    };

    try {
      await ApiService.updateMachine(machineId, payload);
      if (!context.mounted) return;
      setState(() {
        _machine.addAll(payload);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Machine mise à jour avec succès.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mise à jour impossible: ${e.toString().replaceAll('Exception: ', '')}')),
      );
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  List<String> _readStringList(List<String> keys) {
    for (final k in keys) {
      final v = _machine[k];
      if (v is List) {
        return v.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
      }
      if (v is String && v.trim().isNotEmpty) {
        return v
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
    }
    return <String>[];
  }

  Future<void> _editDesignSpecs(BuildContext context, String machineId) async {
    if (!(ApiService.canAddMachineAsConcepteur || ApiService.canManageFleet)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Accès refusé: réservé au concepteur/admin.')),
      );
      return;
    }

    final motorCtrl = TextEditingController(text: _read(['motorType', 'typeMoteur'], fallback: ''));
    final machineTypeCtrl = TextEditingController(text: _read(['machineType', 'typeMachine'], fallback: ''));
    final fabricationCtrl = TextEditingController(text: _read(['fabricationData', 'fabricationDate', 'dateFabrication'], fallback: ''));
    final componentsCtrl = TextEditingController(text: _readStringList(['components', 'composants']).join(', '));
    final optionsCtrl = TextEditingController(text: _readStringList(['options', 'machineOptions']).join(', '));
    final model3dCtrl = TextEditingController(text: _read(['model3dUrl', 'model3d', 'modelUrl'], fallback: ''));

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Configurer fiche technique'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _field(motorCtrl, 'Type de moteur'),
                    _field(machineTypeCtrl, 'Type de machine'),
                    _field(fabricationCtrl, 'Data fabrication'),
                    _field(model3dCtrl, 'URL modele 3D (.glb/.gltf)'),
                    _field(componentsCtrl, 'Composants (séparés par virgule)', maxLines: 3),
                    _field(optionsCtrl, 'Options (séparées par virgule)', maxLines: 3),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
            ],
          ),
    );

    if (ok != true || !context.mounted) return;

    final payload = <String, dynamic>{
      'motorType': motorCtrl.text.trim(),
      'machineType': machineTypeCtrl.text.trim(),
      'fabricationData': fabricationCtrl.text.trim(),
      'model3dUrl': model3dCtrl.text.trim(),
      'components': componentsCtrl.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      'options': optionsCtrl.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
    };

    try {
      await ApiService.updateMachine(machineId, payload);
      if (!context.mounted) return;
      setState(() {
        _machine.addAll(payload);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fiche technique mise à jour.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Enregistrement impossible: ${e.toString().replaceAll('Exception: ', '')}')),
      );
    }
  }

  Widget _chip(String label, String value, {bool compact = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 6 : 7,
      ),
      decoration: BoxDecoration(
        color: const Color(0x221D88E5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x3D7CB8FF)),
      ),
      child: Text(
        '$label: $value',
        style: GoogleFonts.inter(
          color: const Color(0xFFD2E6FF),
          fontWeight: FontWeight.w600,
          fontSize: compact ? 11 : 12,
        ),
      ),
    );
  }

  Widget _fallbackBanner() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2B365A), Color(0xFF222B49)],
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.precision_manufacturing_rounded,
          color: Color(0xFFC7D4F0),
          size: 44,
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _extractHistory(Map<String, dynamic> machine) {
    final raw = machine['history'] ?? machine['historique'] ?? machine['events'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return <Map<String, dynamic>>[];
  }
}
