import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'services/api_service.dart';
import 'control_calendar_page.dart';
import 'control_reports_history_page.dart';

// ─── Design Tokens ────────────────────────────────────────────────────────────
const _bg           = Color(0xFF0B0B1A);
const _surface      = Color(0xFF141428);
const _surfaceHigh  = Color(0xFF1C1C35);
const _surfaceLow   = Color(0xFF111122);
const _primary      = Color(0xFFFF6E00);
const _primaryLight = Color(0xFFFF8C3A);
const _secondary    = Color(0xFF00D4FF);
const _green        = Color(0xFF00E5A0);
const _onSurface    = Color(0xFFE8E8FF);
const _onVariant    = Color(0xFF9090B0);
const _outline      = Color(0xFF2A2A48);

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

class _MachineConsultationPageState extends State<MachineConsultationPage>
    with TickerProviderStateMixin {
  DateTime _selectedDate = DateTime.now();
  String _selectedMachineId = '';
  List<Map<String, dynamic>> _machines = [];
  bool _isLoading = true;
  final TextEditingController _typeController = TextEditingController();
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  // Track booked slots
  final Set<String> _bookedSlots = {};

  final List<String> _timeSlots = [
    '08:00', '09:00', '10:00', '11:00',
    '14:00', '15:00', '16:00', '17:00'
  ];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fetchMachines();
  }

  @override
  void dispose() {
    _typeController.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchMachines() async {
    try {
      final machines = await ApiService.getMachines();
      setState(() {
        _machines = machines;
        if (_machines.isNotEmpty) {
          _selectedMachineId = _machines.first['id']?.toString() ?? '';
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _machines = [
          {'id': 'MAC_001', 'name': 'Compresseur Atlas'},
          {'id': 'MAC_002', 'name': 'Moteur Hyperion'},
        ];
        _selectedMachineId = 'MAC_001';
        _isLoading = false;
      });
    }
    _fadeCtrl.forward();
  }

  Future<void> _scheduleConsultation(String timeSlot) async {
    if (_selectedMachineId.isEmpty) return;

    final parts = timeSlot.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    final dt = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, hour, minute);

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => Center(
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(color: _surfaceHigh, borderRadius: BorderRadius.circular(20)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(color: _primary),
              const SizedBox(height: 16),
              Text('Planification…', style: GoogleFonts.inter(color: _onSurface)),
            ]),
          ),
        ),
      );

      final type = _typeController.text.trim();
      final noteText = type.isNotEmpty
          ? 'Type : $type\nConsultation programmée via drag & drop'
          : 'Consultation programmée via drag & drop';

      await ApiService.createConsultation({
        'machineId': _selectedMachineId,
        'scheduledDate': dt.toIso8601String(),
        'durationMinutes': 60,
        'note': noteText,
      });

      if (mounted) Navigator.pop(context);
      setState(() => _bookedSlots.add(timeSlot));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: _green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Row(children: [
              const Icon(Icons.check_circle_rounded, color: Colors.black),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Consultation planifiée avec succès !',
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Text('Erreur : $e', style: const TextStyle(color: Colors.white)),
          ),
        );
      }
    }
  }

  // ─── Draggable Token ──────────────────────────────────────────────────────
  Widget _buildDraggableToken() {
    final typeText = _typeController.text.trim().isNotEmpty
        ? _typeController.text.trim()
        : 'Nouvelle Consultation';

    return Draggable<String>(
      data: 'consultation_token',
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_primary, _primaryLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(color: _primary.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 8)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.drag_indicator_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(typeText, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: _outline,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.drag_indicator_rounded, color: _onVariant, size: 18),
              const SizedBox(width: 8),
              Text('En déplacement…', style: GoogleFonts.inter(color: _onVariant, fontSize: 14)),
            ],
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_primary, _primaryLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(color: _primary.withOpacity(0.35), blurRadius: 16, offset: const Offset(0, 6)),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.event_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Nouvelle Consultation',
                style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Time Slot Card ───────────────────────────────────────────────────────
  Widget _buildTimeSlot(String time) {
    final isBooked = _bookedSlots.contains(time);

    return DragTarget<String>(
      onAccept: (data) {
        if (data == 'consultation_token' && !isBooked) {
          _scheduleConsultation(time);
        }
      },
      builder: (context, candidateData, rejectedData) {
        final isHovered = candidateData.isNotEmpty && !isBooked;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: isBooked
                ? _primary.withOpacity(0.08)
                : isHovered
                    ? _primary.withOpacity(0.15)
                    : _surfaceHigh,
            border: Border.all(
              color: isBooked
                  ? _primary.withOpacity(0.5)
                  : isHovered
                      ? _primary
                      : _outline,
              width: isHovered ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              // Time badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isBooked ? _primary.withOpacity(0.2) : _surfaceLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  time,
                  style: GoogleFonts.spaceGrotesk(
                    color: isBooked ? _primaryLight : _onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const Spacer(),
              // Status
              if (isBooked)
                Row(children: [
                  const Icon(Icons.check_circle_rounded, color: _primary, size: 14),
                  const SizedBox(width: 4),
                  Text('Réservé', style: GoogleFonts.inter(color: _primary, fontWeight: FontWeight.w600, fontSize: 11)),
                ])
              else if (isHovered)
                Row(children: [
                  Flexible(
                    child: Text(
                      _typeController.text.trim().isNotEmpty ? _typeController.text.trim() : 'Déposer',
                      style: GoogleFonts.inter(color: _primary, fontWeight: FontWeight.bold, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.add_circle_rounded, color: _primary, size: 18),
                ])
              else
                Row(children: [
                  Container(width: 6, height: 6, decoration: const BoxDecoration(color: _green, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text('Dispo', style: GoogleFonts.inter(color: _green, fontWeight: FontWeight.w600, fontSize: 11)),
                ]),
            ],
          ),
        );
      },
    );
  }

  // ─── Step Label ───────────────────────────────────────────────────────────
  Widget _buildStepLabel(String number, String label) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_primary, _primaryLight]),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(number, style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            label,
            style: GoogleFonts.inter(color: _onVariant, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.3),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }

  // ─── Left Column (Form) ───────────────────────────────────────────────────
  Widget _buildLeftColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Card: Machine
        _buildCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStepLabel('1', 'Sélectionner une machine'),
              const SizedBox(height: 6),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  dropdownColor: const Color(0xFF1E1E36),
                  style: GoogleFonts.inter(color: _onSurface, fontWeight: FontWeight.w600),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _primary),
                  value: _selectedMachineId.isEmpty ? null : _selectedMachineId,
                  items: _machines.map((m) {
                    return DropdownMenuItem<String>(
                      value: m['id']?.toString() ?? '',
                      child: Row(
                        children: [
                          const Icon(Icons.precision_manufacturing_rounded, color: _secondary, size: 16),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              m['name'] ?? m['id'] ?? '',
                              style: GoogleFonts.inter(color: _onSurface, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedMachineId = v);
                  },
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Card: Type de consultation
        _buildCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStepLabel('2', 'Type de consultation'),
              const SizedBox(height: 14),
              TextField(
                controller: _typeController,
                onChanged: (val) => setState(() {}),
                style: GoogleFonts.inter(color: _onSurface, fontSize: 14),
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Ex: Maintenance préventive, réparation…',
                  hintStyle: GoogleFonts.inter(color: _onVariant, fontSize: 13),
                  filled: true,
                  fillColor: _surfaceLow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _outline),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _primary, width: 1.5),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _outline),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Card: Token
        _buildCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStepLabel('3', 'Glisser vers un créneau'),
              const SizedBox(height: 16),
              Center(child: _buildDraggableToken()),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Faites glisser ce jeton sur un créneau disponible',
                  style: GoogleFonts.inter(color: _onVariant, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Right Column (Calendar) ──────────────────────────────────────────────
  Widget _buildRightColumn() {
    final formattedDate = DateFormat('EEEE d MMMM yyyy', 'fr_FR').format(_selectedDate);
    final availableCount = _timeSlots.length - _bookedSlots.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date header card
        _buildCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formattedDate,
                      style: GoogleFonts.spaceGrotesk(
                        color: _onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(children: [
                      Container(width: 6, height: 6, decoration: const BoxDecoration(color: _green, shape: BoxShape.circle)),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          '$availableCount créneaux libres',
                          style: GoogleFonts.inter(color: _onVariant, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    builder: (context, child) => Theme(
                      data: ThemeData.dark().copyWith(
                        colorScheme: const ColorScheme.dark(primary: _primary, surface: _surfaceHigh),
                      ),
                      child: child!,
                    ),
                  );
                  if (date != null) setState(() => _selectedDate = date);
                },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _primary.withOpacity(0.3)),
                  ),
                  child: const Icon(Icons.calendar_month_rounded, color: _primary, size: 20),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Time slots
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: _timeSlots.length,
            itemBuilder: (_, i) => _buildTimeSlot(_timeSlots[i]),
          ),
        ),
      ],
    );
  }

  // ─── Card wrapper ─────────────────────────────────────────────────────────
  Widget _buildCard({required Widget child, EdgeInsets padding = const EdgeInsets.all(16)}) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: _surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _outline),
      ),
      child: child,
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: _bg,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(color: _primary),
            const SizedBox(height: 16),
            Text('Chargement…', style: GoogleFonts.inter(color: _onVariant)),
          ]),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _surface,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          titleSpacing: 16,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_primary, _primaryLight]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.calendar_today_rounded, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Gestion des Consultations',
                  style: GoogleFonts.spaceGrotesk(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: _onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(52),
            child: Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: _outline)),
              ),
              child: TabBar(
                labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
                unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w400, fontSize: 13),
                labelColor: _primary,
                unselectedLabelColor: _onVariant,
                indicatorColor: _primary,
                indicatorWeight: 2.5,
                tabs: const [
                  Tab(icon: Icon(Icons.add_task_rounded, size: 18), text: 'Planifier'),
                  Tab(icon: Icon(Icons.calendar_month_rounded, size: 18), text: 'Calendrier'),
                ],
              ),
            ),
          ),
        ),
        body: FadeTransition(
          opacity: _fadeAnim,
          child: TabBarView(
            children: [
              _buildPlanifierTab(),
              _buildCalendrierTab(),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Planifier Tab ────────────────────────────────────────────────────────
  Widget _buildPlanifierTab() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Sidebar ──────────────────────────────────────────────────────────
        SizedBox(
          width: 190,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: _surface,
              border: Border(right: BorderSide(color: _outline)),
            ),
            child: ClipRect(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: _buildLeftColumn(),
              ),
            ),
          ),
        ),
        // ── Main content ─────────────────────────────────────────────────────
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _buildRightColumn(),
          ),
        ),
      ],
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
      onClose: () {},
    );
  }

  Widget _buildHistoriqueTab() {
    return ControlReportsHistoryPage(
      initialArguments: {
        'technicianName': widget.technicianName ?? 'Technicien',
        'technicianId': widget.technicianId ?? '',
        'historyMode': 'all_controls',
      },
      onClose: () {},
    );
  }
}
