import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/api_service.dart';

class TechnicianCollaborationPage extends StatefulWidget {
  const TechnicianCollaborationPage({super.key});

  @override
  State<TechnicianCollaborationPage> createState() => _TechnicianCollaborationPageState();
}

class _TechnicianCollaborationPageState extends State<TechnicianCollaborationPage> {
  final TextEditingController _messageController = TextEditingController();
  List<Map<String, dynamic>> _maintenanceAgents = [];
  bool _loadingAgents = true;

  @override
  void initState() {
    super.initState();
    _fetchMaintenanceAgents();
  }

  Future<void> _fetchMaintenanceAgents() async {
    setState(() => _loadingAgents = true);
    try {
      final list = await ApiService.getMaintenanceAgents();
      if (mounted) {
        setState(() {
          _maintenanceAgents = list;
          _loadingAgents = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching maintenance agents: $e');
      if (mounted) setState(() => _loadingAgents = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      body: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _buildMainContent(),
                ),
                _buildChatSidebar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E1A),
        border: Border(bottom: BorderSide(color: Colors.cyanAccent.withOpacity(0.1))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Text(
            'TECH_OS V4.0',
            style: GoogleFonts.orbitron(
              color: Colors.cyanAccent,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(width: 40),
          _buildTopTab('TERMINAL', active: true),
          _buildTopTab('NETWORK'),
          _buildTopTab('SECURITY'),
          const Spacer(),
          Container(
            width: 250,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(4),
            ),
            child: TextField(
              style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, color: Colors.blueGrey, size: 16),
                hintText: 'QUERY_DB...',
                hintStyle: GoogleFonts.spaceGrotesk(color: Colors.blueGrey, fontSize: 10),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.only(top: -4),
              ),
            ),
          ),
          const SizedBox(width: 20),
          const Icon(Icons.notifications_none, color: Colors.blueGrey, size: 20),
          const SizedBox(width: 15),
          const Icon(Icons.settings_outlined, color: Colors.blueGrey, size: 20),
          const SizedBox(width: 15),
          const CircleAvatar(
            radius: 14,
            backgroundImage: NetworkImage('https://i.pravatar.cc/150?u=tech_admin'),
          ),
        ],
      ),
    );
  }

  Widget _buildTopTab(String title, {bool active = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: Text(
        title,
        style: GoogleFonts.spaceGrotesk(
          color: active ? Colors.cyanAccent : Colors.blueGrey,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SYSTEM_QUEUE_STATUS',
            style: GoogleFonts.spaceGrotesk(
              color: Colors.cyanAccent,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Maintenance Operations',
                style: GoogleFonts.orbitron(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'NODE_SYNC: ACTIVE',
                          style: GoogleFonts.spaceGrotesk(color: Colors.blueGrey, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 15),
                  ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD47A6A),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    child: Text(
                      'DEPLOY_RESOURCES',
                      style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),
          _buildStatsRow(),
          const SizedBox(height: 40),
          Row(
            children: [
              const Icon(Icons.list_alt, color: Colors.cyanAccent, size: 20),
              const SizedBox(width: 10),
              Text(
                'Personnel Maintenance - Machine DZLI',
                style: GoogleFonts.orbitron(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              _buildFilterChip('FILTER: ALL'),
              const SizedBox(width: 10),
              _buildFilterChip('SORT: PRIORITY'),
            ],
          ),
          const SizedBox(height: 24),
          if (_loadingAgents)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(color: Colors.cyanAccent),
              ),
            )
          else if (_maintenanceAgents.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Text(
                  'AUCUN PERSONNEL TROUVÉ',
                  style: GoogleFonts.spaceGrotesk(color: Colors.blueGrey, fontSize: 12, letterSpacing: 2),
                ),
              ),
            )
          else
            _buildOperationGrid(),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Text(
        label,
        style: GoogleFonts.spaceGrotesk(color: Colors.blueGrey, fontSize: 8, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        _buildStatCard('14', 'Active Field Units', Icons.precision_manufacturing, const Color(0xFF327AFF)),
        const SizedBox(width: 20),
        _buildStatCard('08', 'Queued Requests', Icons.assignment_late, const Color(0xFFFFA500)),
        const SizedBox(width: 20),
        _buildStatCard('4.2m', 'System Latency', Icons.speed, const Color(0xFFEFB1F9)),
        const SizedBox(width: 20),
        _buildStatCard('128', 'Success Protocols', Icons.check_circle, const Color(0xFF00FF7F)),
      ],
    );
  }

  Widget _buildStatCard(String value, String label, IconData icon, Color accentColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF0C1322),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: accentColor.withOpacity(0.7), size: 20),
                Text(
                  label.toUpperCase().replaceAll(' ', '_'),
                  style: GoogleFonts.spaceGrotesk(color: Colors.blueGrey, fontSize: 8, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 15),
            Text(
              value,
              style: GoogleFonts.orbitron(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(color: Colors.blueGrey, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOperationGrid() {
    // Filtrer pour ne garder que les agents s'occupant de la machine dzli (MAC-1775750118162)
    final dzliAgents = _maintenanceAgents.where((agent) {
      final machineIds = agent['machineIds'] as List? ?? [];
      return machineIds.contains('MAC-1775750118162');
    }).toList();

    if (dzliAgents.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Text(
            'AUCUN AGENT ASSIGNÉ À DZLI',
            style: GoogleFonts.spaceGrotesk(color: Colors.blueGrey, fontSize: 12, letterSpacing: 2),
          ),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: dzliAgents.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
        childAspectRatio: 1.8,
      ),
      itemBuilder: (context, index) {
        final agent = dzliAgents[index];
        final firstName = agent['firstName'] ?? '';
        final lastName = agent['lastName'] ?? '';
        final name = '$firstName $lastName'.trim();
        final email = agent['email'] ?? 'N/A';
        final loc = agent['location'] ?? 'N/A';
        final machineIds = agent['machineIds'] as List? ?? [];
        final machineCount = machineIds.length;
        final fullId = agent['maintenanceAgentId'] ?? agent['id'] ?? agent['_id'] ?? 'N/A';
        
        return _buildOpCard(
          name, 
          'MAINTENANCE AGENT', 
          email, // On affiche l'email à la place du nombre de machines
          loc, 
          1.0, 
          'https://i.pravatar.cc/150?u=$fullId',
          techId: fullId.toString(),
        );
      },
    );
  }

  Widget _buildOpCard(String name, String role, String task, String loc, double progress, String img, {String techId = '8829-X'}) {
    return InkWell(
      onTap: () {
        Navigator.pushNamed(
          context,
          '/technician-terminal',
          arguments: {
            'techId': techId,
            'name': name,
          },
        );
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF0C1322),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Stack(
                  children: [
                    CircleAvatar(radius: 20, backgroundImage: NetworkImage(img)),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle, border: Border.fromBorderSide(BorderSide(color: Color(0xFF0C1322), width: 2))),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 15),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TECH_ID: $techId',
                      style: GoogleFonts.spaceGrotesk(color: Colors.cyanAccent, fontSize: 8, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      name,
                      style: GoogleFonts.orbitron(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      role,
                      style: GoogleFonts.spaceGrotesk(color: Colors.blueGrey, fontSize: 8),
                    ),
                  ],
                ),
              ],
            ),
            const Spacer(),
            _buildInfoRow('TASK:', task),
            _buildInfoRow('LOCATION:', loc),
            const SizedBox(height: 15),
            Row(
              children: [
                Text(
                  '${(progress * 100).toInt()}% COMPLETE',
                  style: GoogleFonts.spaceGrotesk(color: Colors.cyanAccent, fontSize: 8, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                const Icon(Icons.more_horiz, color: Colors.blueGrey, size: 16),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 4,
              width: double.infinity,
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(2)),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: progress,
                child: Container(decoration: BoxDecoration(color: Colors.cyanAccent, borderRadius: BorderRadius.circular(2))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text(label, style: GoogleFonts.spaceGrotesk(color: Colors.blueGrey, fontSize: 8))),
          Text(value, style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildChatSidebar() {
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: const Color(0xFF090D18),
        border: Border(left: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                const Icon(Icons.chat_bubble_outline, color: Colors.cyanAccent, size: 20),
                const SizedBox(width: 10),
                Text(
                  'Chat Équipe',
                  style: GoogleFonts.orbitron(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFD47A6A), borderRadius: BorderRadius.circular(2)),
                  child: Text('3 NEW', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                _buildChatMessage('MARCUS THORNE', '10:42:01', 'Cooling bypass completed. Pressure returning to nominal levels in Vault_7.', active: true),
                _buildChatMessage('ELENA VANCE', '10:45:15', 'Experiencing interference on the Tower Alpha uplink. Requesting secondary signal scan.', active: true),
                _buildChatMessage('SYS_ADMIN', '11:00:00', 'Protocol G-12 initialized. All technicians must report status update in 5min.', active: true, system: true),
              ],
            ),
          ),
          _buildChatInput(),
        ],
      ),
    );
  }

  Widget _buildChatMessage(String user, String time, String text, {bool active = false, bool system = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(user, style: GoogleFonts.spaceGrotesk(color: Colors.blueGrey, fontSize: 8, fontWeight: FontWeight.bold)),
              Text(time, style: GoogleFonts.spaceGrotesk(color: Colors.blueGrey, fontSize: 8)),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: system ? Colors.cyanAccent.withOpacity(0.05) : const Color(0xFF0C1322),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: system ? Colors.cyanAccent.withOpacity(0.3) : Colors.white.withOpacity(0.05)),
              boxShadow: active ? [BoxShadow(color: Colors.cyanAccent.withOpacity(0.1), blurRadius: 10)] : [],
            ),
            child: Text(
              text,
              style: GoogleFonts.spaceGrotesk(
                color: Colors.white,
                fontSize: 10,
                fontStyle: system ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatInput() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E1A),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(4),
              ),
              child: TextField(
                controller: _messageController,
                style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 10),
                decoration: InputDecoration(
                  hintText: 'TYPE_MESSAGE...',
                  hintStyle: GoogleFonts.spaceGrotesk(color: Colors.blueGrey, fontSize: 10),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.only(bottom: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.send, color: Colors.cyanAccent, size: 18),
        ],
      ),
    );
  }
}
