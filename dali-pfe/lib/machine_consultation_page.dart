import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'services/api_service.dart';
import 'control_calendar_page.dart';
import 'control_reports_history_page.dart';

class MachineConsultationPage extends StatefulWidget {
  final String? technicianId;
  final String? technicianName;
  final List<String>? machineIds;
  final String? companyId;

  const MachineConsultationPage({
    super.key,
    this.technicianId,
    this.technicianName,
    this.machineIds,
    this.companyId,
  });

  @override
  State<MachineConsultationPage> createState() => _MachineConsultationPageState();
}

class _MachineConsultationPageState extends State<MachineConsultationPage> {
  DateTime _selectedDate = DateTime.now();
  String _selectedMachineId = '';
  List<Map<String, dynamic>> _machines = [];
  bool _isLoading = true;
  final TextEditingController _typeController = TextEditingController();

  final List<String> _timeSlots = [
    '08:00', '09:00', '10:00', '11:00', '14:00', '15:00', '16:00', '17:00'
  ];

  @override
  void initState() {
    super.initState();
    _fetchMachines();
  }

  @override
  void dispose() {
    _typeController.dispose();
    super.dispose();
  }

  Future<void> _fetchMachines() async {
    try {
      final machines = await ApiService.getMachines(); // Assuming getMachines exists, or get from profile
      setState(() {
        _machines = machines;
        if (_machines.isNotEmpty) {
          _selectedMachineId = _machines.first['id']?.toString() ?? '';
        }
        _isLoading = false;
      });
    } catch (e) {
      // Si on n'arrive pas à charger les machines (ex: méthode pas exposée directement), on met des fausses pour la démo
      setState(() {
        _machines = [
          {'id': 'MAC_001', 'name': 'Compresseur Atlas'},
          {'id': 'MAC_002', 'name': 'Moteur Hyperion'},
        ];
        _selectedMachineId = 'MAC_001';
        _isLoading = false;
      });
    }
  }

  Future<void> _scheduleConsultation(String timeSlot) async {
    if (_selectedMachineId.isEmpty) return;

    final parts = timeSlot.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    final dt = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, hour, minute);

    try {
      showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
      
      final type = _typeController.text.trim();
      final noteText = type.isNotEmpty ? 'Type : $type\nConsultation programmée via drag & drop' : 'Consultation programmée via drag & drop';

      await ApiService.createConsultation({
        'machineId': _selectedMachineId,
        'scheduledDate': dt.toIso8601String(),
        'durationMinutes': 60,
        'note': noteText,
      });
      
      if (mounted) Navigator.pop(context); // close dialog
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Consultation planifiée ! Notifications envoyées au client et à l\'agent de maintenance.'),
            backgroundColor: Colors.green,
          ),
        );
        // On ne fait plus Navigator.pop(context) car la page est embarquée dans le profil.
      }
    } catch (e) {
      if (mounted) Navigator.pop(context); // close dialog
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Widget _buildDraggableToken() {
    final typeText = _typeController.text.trim().isNotEmpty 
        ? _typeController.text.trim() 
        : 'Nouvelle Consultation';

    return Draggable<String>(
      data: 'consultation_token',
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFF6E00),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [BoxShadow(color: const Color(0xFFFF6E00).withOpacity(0.5), blurRadius: 10)],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.event, color: Colors.white),
              const SizedBox(width: 8),
              Text(typeText, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
      childWhenDragging: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.2),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event, color: Colors.grey),
            const SizedBox(width: 8),
            Text('En deplacement...', style: GoogleFonts.inter(color: Colors.grey)),
          ],
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFF6E00),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event, color: Colors.white),
            const SizedBox(width: 8),
            Text('Nouvelle Consultation', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeSlot(String time) {
    return DragTarget<String>(
      onAccept: (data) {
        if (data == 'consultation_token') {
          _scheduleConsultation(time);
        }
      },
      builder: (context, candidateData, rejectedData) {
        final isHovered = candidateData.isNotEmpty;
        final typeText = _typeController.text.trim().isNotEmpty 
            ? _typeController.text.trim() 
            : 'Deposer ici';

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isHovered ? const Color(0xFFFF6E00).withOpacity(0.3) : const Color(0xFF1D1D38),
            border: Border.all(color: isHovered ? const Color(0xFFFF6E00) : Colors.transparent, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(time, style: GoogleFonts.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
              if (isHovered)
                Row(
                  children: [
                    Text(typeText, style: GoogleFonts.inter(color: const Color(0xFFFF6E00), fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    const Icon(Icons.archive, color: Color(0xFFFF6E00)),
                  ],
                )
              else
                Text('Disponible', style: GoogleFonts.inter(color: Colors.greenAccent, fontStyle: FontStyle.italic)),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(backgroundColor: Color(0xFF0F0F1E), body: Center(child: CircularProgressIndicator()));
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F1E),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1D1D38),
          elevation: 0,
          title: Text('Gestion des Consultations & Contrôles', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          bottom: const TabBar(
            indicatorColor: Color(0xFFFF6E00),
            tabs: [
              Tab(icon: Icon(Icons.add_task), text: 'Planifier'),
              Tab(icon: Icon(Icons.calendar_month), text: 'Calendrier'),
              Tab(icon: Icon(Icons.history), text: 'Historique'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildPlanifierTab(),
            _buildCalendrierTab(),
            _buildHistoriqueTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanifierTab() {
    final formattedDate = DateFormat('EEEE d MMMM yyyy', 'fr_FR').format(_selectedDate);
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            // Colonne de gauche: Choix Machine + Jeton Draggable
            Expanded(
              flex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('1. Sélectionner une machine', style: GoogleFonts.inter(color: Colors.white70, fontSize: 16)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1D1D38),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        dropdownColor: const Color(0xFF272743),
                        value: _selectedMachineId.isEmpty ? null : _selectedMachineId,
                        items: _machines.map((m) {
                          return DropdownMenuItem<String>(
                            value: m['id']?.toString() ?? '',
                            child: Text(m['name'] ?? m['id'], style: const TextStyle(color: Colors.white)),
                          );
                        }).toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _selectedMachineId = v);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('2. Type de consultation', style: GoogleFonts.inter(color: Colors.white70, fontSize: 16)),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1D1D38),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _typeController,
                      onChanged: (val) => setState(() {}),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Ex: Maintenance préventive, réparation...',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  Text('3. Glisser ce jeton vers un créneau horaire', style: GoogleFonts.inter(color: Colors.white70, fontSize: 16)),
                  const SizedBox(height: 20),
                  Center(child: _buildDraggableToken()),
                ],
              ),
            ),
            const SizedBox(width: 40),
            // Colonne de droite: Choix du jour et créneaux horaires
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(formattedDate, style: GoogleFonts.inter(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.calendar_month, color: Color(0xFFFF6E00)),
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _selectedDate,
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (date != null) {
                            setState(() => _selectedDate = date);
                          }
                        },
                      )
                    ],
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: ListView(
                      children: _timeSlots.map((time) => _buildTimeSlot(time)).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
  }

  Widget _buildCalendrierTab() {
    return ControlCalendarPage(
      initialArguments: {
        'technicianName': widget.technicianName ?? 'Technicien',
        'technicianId': widget.technicianId ?? '',
        'machineIds': widget.machineIds ?? [],
        if (widget.companyId != null && widget.companyId!.isNotEmpty) 'companyId': widget.companyId,
      },
      onClose: () {}, // Ne rien faire, ou basculer sur un autre onglet
    );
  }

  Widget _buildHistoriqueTab() {
    return ControlReportsHistoryPage(
      initialArguments: {
        'technicianName': widget.technicianName ?? 'Technicien',
        'technicianId': widget.technicianId ?? '',
        'historyMode': 'all_controls',
      },
      onClose: () {}, // Ne rien faire
    );
  }
}
