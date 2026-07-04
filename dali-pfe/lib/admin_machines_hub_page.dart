import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'active_machines_page.dart';
import 'add_technician_page.dart';
import 'machine_detail_ai_page.dart';
import 'widgets/machine_history_view.dart';

/// Section Machines du dashboard admin : liste, terminal actif, onboarding technicien.
class AdminMachinesHubPage extends StatefulWidget {
  final bool isDarkMode;
  const AdminMachinesHubPage({super.key, this.isDarkMode = false});

  @override
  State<AdminMachinesHubPage> createState() => _AdminMachinesHubPageState();
}

enum _MachinesSubview { list, detail, history }

class _AdminMachinesHubPageState extends State<AdminMachinesHubPage> {
  // Color getters based on isDarkMode flag
  Color get _primary => widget.isDarkMode ? const Color(0xFFFF6E00) : const Color(0xFFB8860B);
  Color get _onSurface => widget.isDarkMode ? const Color(0xFFE2DFFF) : const Color(0xFF332A21);
  Color get _secondary => widget.isDarkMode ? const Color(0xFF75D1FF) : const Color(0xFF8B5E3C);

  _MachinesSubview _view = _MachinesSubview.list;
  String? _selectedMachineId;
  String? _selectedMachineName;
  String? _selectedClientId;
  String? _selectedLocation;


  void _openList() {
    setState(() {
      _view = _MachinesSubview.list;
      _selectedMachineId = null;
      _selectedMachineName = null;
      _selectedClientId = null;
    });
  }

  void _openHistory() {
    setState(() {
      _view = _MachinesSubview.history;
      _selectedMachineId = null;
      _selectedMachineName = null;
      _selectedClientId = null;
    });
  }

  void _openDetail(String id, String name, {String? clientId, String? location}) {
    setState(() {
      _view = _MachinesSubview.detail;
      _selectedMachineId = id;
      _selectedMachineName = name;
      _selectedClientId = clientId;
      _selectedLocation = location;
    });
  }


  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width > 900;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSubNav(),
        Expanded(
          child: switch (_view) {
            _MachinesSubview.list => ActiveMachinesPage(
                embedded: true,
                isDarkMode: widget.isDarkMode,
                onOpenMachine: _openDetail,
              ),
            _MachinesSubview.detail => MachineDetailAiPage(
                key: ValueKey('machine-$_selectedMachineId'),
                machineId: _selectedMachineId ?? '',
                machineName: _selectedMachineName,
                clientId: _selectedClientId,
                location: _selectedLocation,
                viewerRole: 'admin',
                viewerName: 'Administrateur',
                embedded: true,
                onBack: _openList,
              ),
            _MachinesSubview.history => MachineHistoryView(
                isDesktop: isDesktop,
                isDarkMode: widget.isDarkMode,
              ),
          },
        ),
      ],
    );
  }

  Widget _buildSubNav() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: widget.isDarkMode
              ? [
                  const Color(0xFF1E2243).withOpacity(0.95),
                  const Color(0xFF131730).withOpacity(0.85),
                ]
              : [
                  const Color(0xFFFFF8F0).withOpacity(0.98),
                  const Color(0xFFF5E0C3).withOpacity(0.92),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.isDarkMode
              ? Colors.white.withOpacity(0.08)
              : const Color(0xFFCD7F32).withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: widget.isDarkMode
                ? Colors.black.withOpacity(0.3)
                : const Color(0xFFB87333).withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _subNavChip(
              label: 'Parc machines',
              icon: Icons.precision_manufacturing_outlined,
              active: _view == _MachinesSubview.list,
              onTap: _openList,
            ),
            const SizedBox(width: 8),
            _subNavChip(
              label: 'Historique global',
              icon: Icons.history_outlined,
              active: _view == _MachinesSubview.history,
              onTap: _openHistory,
            ),
          ],
        ),
      ),
    );
  }

  Widget _subNavChip({
    required String label,
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            gradient: active
                ? LinearGradient(
                    colors: [
                      _primary.withOpacity(0.25),
                      _primary.withOpacity(0.08),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? _primary.withOpacity(0.5) : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: active ? _primary : _onSurface.withOpacity(0.6)),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  color: active ? _onSurface : _onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
