import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';

class MachineHistoryView extends StatefulWidget {
  final bool isDesktop;
  final String? machineId;
  final bool isDarkMode;
  const MachineHistoryView({
    super.key,
    required this.isDesktop,
    this.machineId,
    this.isDarkMode = false,
  });

  @override
  State<MachineHistoryView> createState() => _MachineHistoryViewState();
}

class _MachineHistoryViewState extends State<MachineHistoryView> {
  Color get _surface => widget.isDarkMode ? const Color(0xFF1D1D38) : const Color(0xFFFFFFFF);
  Color get _onSurface => widget.isDarkMode ? const Color(0xFFE2DFFF) : const Color(0xFF332A21);
  Color get _onVariant => widget.isDarkMode ? const Color(0xFFE2BFB0) : const Color(0xFF8B5E3C);
  Color get _primary => const Color(0xFFFF6E00);
  Color get _secondary => widget.isDarkMode ? const Color(0xFF75D1FF) : const Color(0xFF8B5E3C);

  late Future<List<Map<String, dynamic>>> _controlesFuture;

  @override
  void initState() {
    super.initState();
    _controlesFuture = widget.machineId != null 
        ? ApiService.getControlesForMachine(widget.machineId!) 
        : ApiService.getControles();
  }

  void _reloadHistory() {
    setState(() {
      _controlesFuture = widget.machineId != null 
          ? ApiService.getControlesForMachine(widget.machineId!) 
          : ApiService.getControles();
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, widget.isDesktop ? 24 : 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'HISTORIQUE DES MACHINES',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: _primary,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Pannes & Missions',
            style: GoogleFonts.inter(
              fontSize: widget.isDesktop ? 32 : 26,
              fontWeight: FontWeight.w800,
              color: _onSurface,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Suivi centralisé des diagnostics de pannes et des ordres de mission.',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 13,
              color: _onVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 32),
          _buildSectionHeader('Historique de contrôle'),
          const SizedBox(height: 16),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _controlesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LinearProgressIndicator(color: Colors.purpleAccent);
              }
              final rows = snapshot.data ?? [];
              if (rows.isEmpty) {
                return _emptyBoxSmall('Aucun contrôle enregistré.');
              }
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _controleCard(rows[i]),
              );
            },
          ),
        ],
      ),
    );

    if (widget.machineId != null) {
      // Si machineId est présent, on est probablement dans une page déjà Scrollable (MachineDetail)
      return content;
    }

    return RefreshIndicator(
      color: _primary,
      onRefresh: () async {
        _reloadHistory();
        await _controlesFuture;
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: content,
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        Container(width: 4, height: 18, color: _primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _onSurface,
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyBoxSmall(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30),
      decoration: BoxDecoration(
        color: _surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.isDarkMode ? _onVariant.withOpacity(0.05) : const Color(0xFFCD7F32).withOpacity(0.25),
        ),
      ),
      child: Center(
        child: Text(
          text,
          style: GoogleFonts.spaceGrotesk(fontSize: 13, color: _onVariant.withOpacity(0.6)),
        ),
      ),
    );
  }

  Widget _controleCard(Map<String, dynamic> r) {
    final tech = (r['technicienNom'] ?? 'Technicien').toString();
    final status = (r['statut'] ?? 'EN_ATTENTE').toString();
    final date = r['jour'] ?? r['createdAt']?.toString().split('T').first ?? '—';
    final notes = (r['compteRendu'] ?? '').toString();
    final machineName = r['machine']?['name']?.toString() ?? r['machineId']?.toString() ?? 'Machine';
    final agentName = r['maintenanceAgentNom']?.toString() ?? 'ons hammami';

    Color statusColor = Colors.purpleAccent;
    if (status == 'TERMINE') statusColor = Colors.greenAccent;

    return Material(
      color: _surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.fact_check_outlined, color: statusColor, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      machineName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: _onSurface, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Agent: $agentName  •  Technicien: $tech',
                      style: GoogleFonts.spaceGrotesk(color: _onVariant.withOpacity(0.8), fontSize: 11),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      notes.isNotEmpty ? 'Message: $notes' : 'Aucun message de mission',
                      style: GoogleFonts.spaceGrotesk(color: _onSurface.withOpacity(0.8), fontSize: 12),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    status,
                    style: GoogleFonts.spaceGrotesk(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    date,
                    style: GoogleFonts.spaceGrotesk(color: _onVariant.withOpacity(0.7), fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
