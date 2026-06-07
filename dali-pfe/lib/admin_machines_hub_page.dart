import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'active_machines_page.dart';
import 'add_technician_page.dart';
import 'machine_detail_ai_page.dart';
import 'widgets/machine_history_view.dart';

/// Section Machines du dashboard admin : liste, terminal actif, onboarding technicien.
class AdminMachinesHubPage extends StatefulWidget {
  const AdminMachinesHubPage({super.key});

  @override
  State<AdminMachinesHubPage> createState() => _AdminMachinesHubPageState();
}

enum _MachinesSubview { list, detail, history }

class _AdminMachinesHubPageState extends State<AdminMachinesHubPage> {
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
            _MachinesSubview.history => MachineHistoryView(isDesktop: isDesktop),
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
        color: const Color(0xFF191934),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF32324E)),
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
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: active ? const Color(0x22FF6E00) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? const Color(0x55FF6E00) : const Color(0xFF32324E),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: active ? const Color(0xFFFFB692) : const Color(0xFF9AA3B8)),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  color: active ? const Color(0xFFF4F4F9) : const Color(0xFF9AA3B8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
