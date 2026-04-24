import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'services/api_service.dart';
import 'add_technician_page.dart';
import 'machine_detail_ai_page.dart';

class TechnicianProfilePage extends StatefulWidget {
  const TechnicianProfilePage({super.key});

  @override
  State<TechnicianProfilePage> createState() => _TechnicianProfilePageState();
}

class _TechnicianProfilePageState extends State<TechnicianProfilePage> {
  /// Les comptes User CONCEPTION doivent utiliser [ConceptionObservatoryPage], pas ce profil « technicien ».
  bool _conceptionRedirectScheduled = false;

  IO.Socket? _chatSocket;
  bool _chatInitialized = false;
  String _chatRoomId = '';
  String _chatSenderName = 'Technicien';
  String _technicianId = '';
  String _clientId = '';
  final TextEditingController _chatInputController = TextEditingController();
  final List<Map<String, dynamic>> _chatMessages = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _chatConversations = <Map<String, dynamic>>[];
  int _unreadChatCount = 0;
  final Set<String> _criticalAlertSentMachineIds = <String>{};

  static const _bg = Color(0xFF10102B);
  static const _surfaceContainerLow = Color(0xFF191934);
  static const _surfaceContainer = Color(0xFF1D1D38);
  static const _surfaceContainerHigh = Color(0xFF272743);
  static const _surfaceContainerHighest = Color(0xFF32324E);
  static const _primary = Color(0xFFFFB692);
  static const _primaryContainer = Color(0xFFFF6E00);
  static const _secondary = Color(0xFF75D1FF);
  static const _tertiary = Color(0xFFEFB1F9);
  static const _onSurface = Color(0xFFE2DFFF);
  static const _onSurfaceVariant = Color(0xFFE2BFB0);
  static const _outlineVariant = Color(0xFF594136);
  static const _error = Color(0xFFFFB4AB);
  static const _green = Color(0xFF66BB6A);

  @override
  void dispose() {
    _chatInputController.dispose();
    _chatSocket?.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_conceptionRedirectScheduled) return;
    final raw = ModalRoute.of(context)?.settings.arguments;
    if (raw is! Map) return;
    final vr = (raw['viewerRole'] ?? '').toString().toLowerCase();
    if (vr != 'conception') return;
    _conceptionRedirectScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(
        '/conception-observatory',
        arguments: Map<String, dynamic>.from(raw),
      );
    });
  }

  Future<void> _ensureTechnicianChat(Map<String, dynamic> args, String technicianName) async {
    if (_chatInitialized) return;
    final techId = (args['technicianId'] ?? args['id'] ?? '').toString();
    final clientId = (args['companyId'] ?? args['clientId'] ?? '').toString();
    _technicianId = techId;
    _clientId = clientId;
    if (techId.isEmpty || clientId.isEmpty) return;

    _chatConversations = await ApiService.getTechnicianConversations(techId);
    if (_chatConversations.isNotEmpty) {
      _chatRoomId = (_chatConversations.first['roomId'] ?? '').toString();
    } else {
      _chatRoomId = 'chat_${clientId}_$techId';
    }
    _chatSenderName = technicianName.trim().isEmpty ? 'Technicien' : technicianName.trim();
    try {
      final history = await ApiService.getChatMessages(_chatRoomId, limit: 200);
      _chatMessages
        ..clear()
        ..addAll(history);
    } catch (_) {}

    final socket = IO.io(ApiService.socketBaseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });
    _chatSocket = socket;

    socket.onConnect((_) {
      socket.emit('join_chat_room', {'roomId': _chatRoomId});
    });

    socket.on('chat_message', (raw) {
      try {
        final data = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
        if (data['roomId']?.toString() != _chatRoomId) return;
        if (!mounted) return;
        setState(() {
          _chatMessages.add(data);
          final senderName = (data['senderName'] ?? '').toString();
          if (senderName != _chatSenderName) {
            _unreadChatCount += 1;
          }
        });
      } catch (_) {}
    });

    _chatInitialized = true;
    if (mounted) {
      setState(() {});
      _checkPendingInterventions(techId);
    }
  }

  Future<void> _checkPendingInterventions(String techId) async {
    try {
      final interventions = await ApiService.getDiagnosticInterventions();
      // On cherche une intervention OPEN assignée à ce tech
      final pending = interventions.where((i) => 
        i['technicianId']?.toString() == techId && 
        i['status'] == 'OPEN'
      ).toList();

      if (pending.isNotEmpty && mounted) {
        final last = pending.first;
        _showAcceptAssignmentDialog(last);
      }
    } catch (e) {
      debugPrint('Error checking interventions: $e');
    }
  }

  void _showAcceptAssignmentDialog(Map<String, dynamic> intervention) {
    final machineId = (intervention['machineId'] ?? '').toString();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: _primaryContainer, width: 2)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: _primaryContainer, size: 28),
            const SizedBox(width: 12),
            Text('NOUVELLE MISSION', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w900)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vous avez été assigné à une maintenance critique sur la machine :',
              style: GoogleFonts.inter(color: _onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _surfaceContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.precision_manufacturing, color: _secondary, size: 20),
                  const SizedBox(width: 10),
                  Text(machineId, style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Résumé : ${intervention['summary'] ?? 'Contrôle de panne immédiat'}',
              style: GoogleFonts.inter(color: _onSurface, fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('PLUS TARD', style: GoogleFonts.inter(color: _onSurfaceVariant)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              // Optionnel: on pourrait passer le status en 'ACCEPTED' ici
              // Mais pour l'instant on ouvre directement la page de la machine
              if (mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MachineDetailAiPage(
                      machineId: machineId,
                      viewerRole: 'technician',
                      viewerName: _chatSenderName,
                    ),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryContainer,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: Text('ACCEPTER & OUVRIR', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _openTechnicianChatDialog() {
    if (_chatRoomId.isEmpty) return;
    setState(() => _unreadChatCount = 0);
    _chatSocket?.emit('join_chat_room', {'roomId': _chatRoomId});

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _surfaceContainerLow,
        title: Text(
          'Messages Client ↔ Technicien',
          style: GoogleFonts.inter(color: _onSurface),
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 220,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _surfaceContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView(
                  children: _chatMessages
                      .map(
                        (m) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            '${m['senderName'] ?? 'User'}: ${m['text'] ?? ''}',
                            style: GoogleFonts.inter(color: _onSurface, fontSize: 12),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _chatInputController,
                style: GoogleFonts.inter(color: _onSurface),
                decoration: const InputDecoration(
                  hintText: 'Écrire un message...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
          ElevatedButton(
            onPressed: () {
              final text = _chatInputController.text.trim();
              if (text.isEmpty || _chatRoomId.isEmpty) return;
              _chatSocket?.emit('chat_message', {
                'roomId': _chatRoomId,
                'from': 'technician',
                'senderName': _chatSenderName,
                'text': text,
              });
              _chatInputController.clear();
            },
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 992;

    final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
    final viewerRoleRaw = (args?['viewerRole'] ?? args?['role'] ?? '').toString().toLowerCase();
    final isSuperAdminViewer = ApiService.canManageFleet ||
        viewerRoleRaw == 'superadmin' ||
        viewerRoleRaw == 'admin' ||
        viewerRoleRaw == 'company_admin';
    final isTechnicianViewer = viewerRoleRaw == 'technician';
    final isConceptionViewer = viewerRoleRaw == 'conception';
    final canViewProfile = isSuperAdminViewer || isTechnicianViewer || isConceptionViewer;

    if (!canViewProfile) {
      return Scaffold(
        backgroundColor: _bg,
        body: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 560),
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: _surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _outlineVariant.withOpacity(0.3)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, color: _error, size: 36),
                const SizedBox(height: 12),
                Text(
                  'Accès réservé',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Cette page est disponible uniquement pour le super administrateur ou le technicien concerné.',
                  style: GoogleFonts.inter(
                    color: _onSurfaceVariant,
                    fontSize: 13,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Retour'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryContainer,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final String name = args?['name'] ?? 'Marc Lefebvre';
    final String id = args?['id'] ?? 'TC-9942-B';
    final String specialization = args?['specialization'] ?? 'Senior Technician — Industrial Systems & Robotics';
    final String statusLabel = args?['status'] ?? 'EN SERVICE';
    final String phone = args?['phone'] ?? '+33 6 42 18 90 22';
    final String email = args?['email'] ?? 'm.lefebvre@industry-cloud.com';
    final String loginPassword = args?['loginPassword'] ?? '********';
    final String location = args?['location'] ?? 'Bâtiment Central, Secteur Sud, Hall B';
    final String imageUrl = args?['imageUrl'] ?? 'https://lh3.googleusercontent.com/aida-public/AB6AXuBVqkqnUWBiLb0Zk31JerrE-Ke1jkLq2w23qu64tGR1PBHdL55WDZPq1xaW5VI5-N3Njpr4kjz41To1Hr7NbQ71oaHCu7d78Fayofl6_WNhcI0YsjjoM9eG-9dObtcoOQcMsx735B0ufEAemLbMhzj6rgh_05Hx8ny0G-QIQIvsg73okjpTwTjT_i4OP2f8Q1Y-Ao_Jm-hKOfdVTtUHlwPJ2X5WUpZFpoPic7RKsnUMvN_ZnlmmpWDtBieX_MwC0rwPn7juK2gD9Dw';
    final List<String> assignedMachineIds = ((args?['machineIds'] as List?) ?? const [])
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toList();
    _ensureTechnicianChat(args ?? {}, name);

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          Column(
            children: [
              _buildTopHeader(args),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 1200),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildProfileHeader(context, isDesktop, name, id, specialization, statusLabel, imageUrl, args ?? {}, canManageTechnician: isSuperAdminViewer),
                          const SizedBox(height: 40),
                          _buildMainGrid(
                            isDesktop,
                            context,
                            phone,
                            email,
                            loginPassword,
                            location,
                            id,
                            assignedMachineIds,
                            isConceptionViewer,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Container(
                margin: const EdgeInsets.only(left: 10, top: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0D9B5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1A1A)),
                  onPressed: () => Navigator.maybePop(context),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: null,
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 256,
      color: _surfaceContainerLow,
      child: Column(
        children: [
          // Profile section in sidebar
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: Image.network(
                    'https://lh3.googleusercontent.com/aida-public/AB6AXuD6XMHTc7EnuwpybN1a7M5-4ByK2xNIZiN_tfQlBnyREkmNG_daynil3m0nLFdLpMbg4DScyNGfT3Loz0tvwq2eYfDYmMBOmaeCRZGo2TQRUQ58chmYrzdqYuf8hrarTbDuKlLgGTy2rXZ9R0mza7SoAWjVX5upN5Hg8Wlj7xGzwjwlWqLxZx1qtFLruQjQz_SvXDpfU-WVse3fGP3OJsvkstlxx_f9VrutqsfJsF9HFU0sJrWmAx6RIr25RZrz3qE-xUmiogt7WU0',
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Marc Lefebvre',
                        style: GoogleFonts.spaceGrotesk(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        'Senior Technician - Zone B',
                        style: GoogleFonts.spaceGrotesk(
                          color: _onSurfaceVariant.withOpacity(0.7),
                          fontSize: 10,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white10),
          _buildSidebarTile(Icons.analytics_outlined, 'Overview'),
          _buildSidebarTile(Icons.route_outlined, 'Live Location'),
          _buildSidebarTile(Icons.precision_manufacturing_outlined, 'Machine Fleet'),
          _buildSidebarTile(Icons.history_edu, 'Service Logs', isActive: true),
          _buildSidebarTile(Icons.description_outlined, 'Documents'),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryContainer,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Update Status', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 16),
                _buildSidebarTile(Icons.help_outline, 'Support', isSmall: true),
                _buildSidebarTile(Icons.logout, 'Logout', isSmall: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarTile(IconData icon, String label, {bool isActive = false, bool isSmall = false}) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: isActive ? _surfaceContainerHighest : Colors.transparent,
        borderRadius: const BorderRadius.only(topRight: Radius.circular(24), bottomRight: Radius.circular(24)),
      ),
      child: ListTile(
        leading: Icon(icon, color: isActive ? Colors.white : _onSurfaceVariant.withOpacity(0.7), size: isSmall ? 18 : 22),
        title: Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            color: isActive ? Colors.white : _onSurfaceVariant.withOpacity(0.7),
            fontSize: isSmall ? 12 : 14,
          ),
        ),
        onTap: () {},
        dense: isSmall,
      ),
    );
  }

  Widget _buildTopHeader(Map<String, dynamic>? args) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      color: _bg,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'PREDICTIVE CLOUD',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
              fontSize: 20,
            ),
          ),
          Row(
            children: [
              InkWell(
                onTap: () {
                  final currentRole = (args?['viewerRole'] ?? args?['role'] ?? 'technician').toString().toLowerCase();
                  final msgRole = currentRole == 'conception' ? 'conception' : 'technician';
                  Navigator.pushNamed(
                    context,
                    '/message-equipe',
                    arguments: {
                      'role': msgRole,
                      'id': _technicianId,
                      'technicianId': _technicianId,
                      'companyId': _clientId,
                      'name': msgRole == 'conception' ? 'Maintenance' : _chatSenderName,
                    },
                  );
                },
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  width: 30,
                  height: 30,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Center(
                        child: Icon(Icons.mark_chat_unread_outlined, color: _onSurfaceVariant, size: 18),
                      ),
                      if (_unreadChatCount > 0)
                        Positioned(
                          right: -4,
                          top: -4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: _error,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              _unreadChatCount > 99 ? '99+' : '$_unreadChatCount',
                              style: GoogleFonts.inter(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 9,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              const Icon(Icons.notifications_outlined, color: _onSurfaceVariant),
              const SizedBox(width: 16),
              const Icon(Icons.settings_outlined, color: _onSurfaceVariant),
              const SizedBox(width: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(100),
                child: Image.network(
                  'https://lh3.googleusercontent.com/aida-public/AB6AXuCsTNFIkjKdXO2X5QRNlDjCHHeQgZBBtWMRjJ0v5I_zJPuWfIQDmn4BxwiCE9hSUkAE4vGspswZAyHf-VUcg6kNsBSwAp4udmh-ctA3VHt25MJWlOfsCPI07pIgO5p9d8MZY7d1BfBpfLBF8Gcba9eG37cMp79VN6773bLcGaXH0_lVmeIsl9qHhcHlwDYeJgrA2A_Adky2mhjbrAcQb_MtAMdXDleOZgoum5OXFnhfNkButAQB7oJiHj5ktJjMVBslJ5ex7zC89iQ',
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(BuildContext context, bool isDesktop, String name, String id, String specialization, String statusLabel, String imageUrl, Map<String, dynamic> rawArgs, {required bool canManageTechnician}) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: _surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Stack(
            children: [
              Container(
                width: isDesktop ? 160 : 100,
                height: isDesktop ? 160 : 100,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  border: Border.all(color: _primaryContainer.withOpacity(0.2), width: 2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Positioned(
                bottom: -8,
                right: -8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(color: _green, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        statusLabel,
                        style: GoogleFonts.spaceGrotesk(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 32),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: isDesktop ? 48 : 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: _tertiary.withOpacity(0.1),
                        border: Border.all(color: _tertiary.withOpacity(0.3)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'ZONE B EXPERT',
                        style: GoogleFonts.spaceGrotesk(
                          color: _tertiary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  specialization,
                  style: GoogleFonts.inter(
                    color: _onSurfaceVariant,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
          if (isDesktop && canManageTechnician)
            Row(
              children: [
                InkWell(
                  onTap: () async {
                    final updated = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AddTechnicianPage(initialData: rawArgs),
                      ),
                    );
                    if (updated == true && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Technicien mis à jour'), backgroundColor: Colors.green),
                      );
                      Navigator.pop(context, true);
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: _buildActionButton(Icons.edit, 'Modifier', _surfaceContainerHighest, Colors.white),
                ),
                const SizedBox(width: 12),
                InkWell(
                  onTap: () => _confirmDelete(context, id, name),
                  borderRadius: BorderRadius.circular(8),
                  child: _buildActionButton(Icons.delete_outline, 'Supprimer', _error.withOpacity(0.1), _error, isBordered: true),
                ),
              ],
            ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, String techId, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceContainerLow,
        title: Text('Supprimer $name ?', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Cette action est irréversible. Voulez-vous continuer ?', style: GoogleFonts.spaceGrotesk(color: _onSurfaceVariant)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Annuler', style: GoogleFonts.inter(color: _onSurfaceVariant)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx); // close dialog
              try {
                await ApiService.deleteTechnician(techId);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('$name supprimé avec succès.', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                    backgroundColor: _green,
                    behavior: SnackBarBehavior.floating,
                  ));
                  Navigator.pop(context, true); // back to list + refresh
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Erreur: $e', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                    backgroundColor: Colors.redAccent,
                    behavior: SnackBarBehavior.floating,
                  ));
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: _error),
            child: Text('Supprimer', style: GoogleFonts.inter(color: Colors.black87, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, Color bgColor, Color textColor, {bool isBordered = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: isBordered ? Border.all(color: textColor.withOpacity(0.3)) : null,
      ),
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 20),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.inter(color: textColor, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildMainGrid(
    bool isDesktop,
    BuildContext context,
    String phone,
    String email,
    String loginPassword,
    String location,
    String technicianId,
    List<String> assignedMachineIds,
    bool isConceptionProfile,
  ) {
    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Column(
              children: [
                _buildContactCard(phone, email, loginPassword, technicianId, location),
                const SizedBox(height: 24),
                _buildLocationCard(),
              ],
            ),
          ),
          const SizedBox(width: 32),
          Expanded(
            flex: 8,
            child: Column(
              children: [
                _buildMachinesSection(context, assignedMachineIds, isConceptionProfile),
                const SizedBox(height: 32),
                _buildPerformanceSection(),
                const SizedBox(height: 24),
                _buildTechnicianHistorySection(assignedMachineIds),
                const SizedBox(height: 24),
                _buildClientTechnicianMessengerZone(),
              ],
            ),
          ),
        ],
      );
    } else {
      return Column(
        children: [
          _buildContactCard(phone, email, loginPassword, technicianId, location),
          const SizedBox(height: 24),
          _buildLocationCard(),
          const SizedBox(height: 24),
          _buildMachinesSection(context, assignedMachineIds, isConceptionProfile),
          const SizedBox(height: 24),
          _buildPerformanceSection(),
          const SizedBox(height: 24),
          _buildTechnicianHistorySection(assignedMachineIds),
          const SizedBox(height: 24),
          _buildClientTechnicianMessengerZone(),
        ],
      );
    }
  }

  Widget _buildContactCard(String phone, String email, String loginPassword, String id, String location) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'COORDONNÉES',
            style: GoogleFonts.spaceGrotesk(
              color: _primaryContainer,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 24),
          _buildContactItem(Icons.phone_iphone_outlined, 'TÉLÉPHONE', phone),
          const SizedBox(height: 20),
          _buildContactItem(Icons.mail_outline, 'EMAIL', email),
          const SizedBox(height: 20),
          _buildContactItem(Icons.lock_outline, 'MOT DE PASSE', loginPassword),
          const SizedBox(height: 20),
          _buildContactItem(Icons.badge_outlined, 'ID TECHNIQUE', id),
          const SizedBox(height: 20),
          _buildContactItem(Icons.location_on_outlined, 'ANTENNE TECHNIQUE', location),
        ],
      ),
    );
  }

  Widget _buildContactItem(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: _secondary, size: 20),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: GoogleFonts.spaceGrotesk(color: _onSurfaceVariant, fontSize: 10)),
            Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    );
  }

  Widget _buildLocationCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'TEMPS RÉEL',
                style: GoogleFonts.spaceGrotesk(
                  color: _primaryContainer,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.my_location, color: _secondary, size: 14),
                  const SizedBox(width: 4),
                  Text('Hall B - 12m', style: GoogleFonts.spaceGrotesk(color: _secondary, fontSize: 10)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                Image.network(
                  'https://lh3.googleusercontent.com/aida-public/AB6AXuD1yncyqE-QteYwr7oV8HPgyCe_0sRXDbqdKSMphq31KkFagCqL71FsCn33Bd8C-_UeTPWOcRFpiRjNTBHkwnMClbgxbfHFqWZwcogDxb88D85M0xdAK6JF_T0onyJB9H1HR7zuomXZnHJnWpJecPlY1TLz3ObbgNP_k53ZDvhzysq8aKlG2JhNZzc_K5h3LyvGt65YM_cqeEvPES3hcz-nydb0GhPowswe7XQWC5-9TuudxfnI3eassSkQn4Ta-OY-n2--2Qxj0ac',
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  color: Colors.black.withOpacity(0.5),
                  colorBlendMode: BlendMode.darken,
                ),
                Positioned.fill(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _primaryContainer,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: _primaryContainer.withOpacity(0.5), blurRadius: 20, spreadRadius: 5)],
                      ),
                      child: const Icon(Icons.navigation, color: Colors.white, size: 24),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMachinesSection(BuildContext context, List<String> assignedMachineIds, bool isConceptionProfile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'UNITÉS SOUS SUPERVISION',
                  style: GoogleFonts.spaceGrotesk(
                    color: _tertiary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isConceptionProfile
                      ? 'Machines assignées à ce compte conception'
                      : 'Machines assignées à ce technicien',
                  style: TextStyle(color: _onSurfaceVariant, fontSize: 13),
                ),
              ],
            ),
            Text(
              '${assignedMachineIds.length} machine(s)',
              style: GoogleFonts.spaceGrotesk(color: _secondary, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 24),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _loadAssignedMachinesWithRisk(assignedMachineIds),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(strokeWidth: 2),
              ));
            }
            if (snapshot.hasError) {
              return Text(
                'Impossible de charger les machines assignées',
                style: GoogleFonts.inter(color: _error),
              );
            }

            final controlledMachines = snapshot.data ?? const <Map<String, dynamic>>[];

            if (controlledMachines.isEmpty) {
              return Text(
                isConceptionProfile
                    ? 'Aucune machine actuellement assignée à ce concepteur.'
                    : 'Aucune machine actuellement assignée à ce technicien.',
                style: GoogleFonts.inter(color: _onSurfaceVariant),
              );
            }

            final critical = controlledMachines.where((m) {
              final risk = (m['_riskPercent'] as int?) ?? 0;
              final status = (m['status'] ?? '').toString().toUpperCase();
              final requiresStop = m['_requiresStop'] == true;
              return requiresStop || risk > 60 || status == 'PANNE';
            }).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (critical.isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: _error.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _error.withOpacity(0.45)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: _error, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Notification panne: ${critical.length} machine(s) en alerte (IA > 60% ou panne détectée).',
                            style: GoogleFonts.inter(color: _error, fontWeight: FontWeight.w700, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                LayoutBuilder(builder: (context, constraints) {
                  return GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: constraints.maxWidth > 600 ? 2 : 1,
                    mainAxisSpacing: 24,
                    crossAxisSpacing: 24,
                    childAspectRatio: 1.5,
                    children: controlledMachines.map((m) {
                      final machineId = (m['id'] ?? m['_id'] ?? m['machineId'] ?? '').toString();
                      final machineName = (m['name'] ?? 'Machine').toString();
                      final status = (m['status'] ?? '').toString();
                      final risk = (m['_riskPercent'] as int?) ?? _machineHealthFromStatus(status);
                      final requiresStop = m['_requiresStop'] == true;
                      final isAlert = requiresStop || risk > 60 || status.toUpperCase() == 'PANNE';
                      final riskNote = (m['_riskLabel'] ?? '').toString();

                      return _buildMachineCard(
                        Icons.precision_manufacturing,
                        machineName,
                        (m['companyId'] ?? 'Client').toString(),
                        risk,
                        isAlert ? _error : (status.toUpperCase() == 'RUNNING' ? _secondary : _error),
                        isAlert: isAlert,
                        alertText: riskNote,
                        onTap: () {
                          if (machineId.isEmpty) return;
                          
                          // Redirection vers la page de détails IA pour toutes les machines dans le profil
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MachineDetailAiPage(
                                machineId: machineId,
                                viewerRole: 'technician',
                                viewerName: 'Technicien',
                              ),
                            ),
                          );
                        },
                      );
                    }).toList(),
                  );
                }),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<List<Map<String, dynamic>>> _loadAssignedMachinesWithRisk(List<String> assignedMachineIds) async {
    final allMachines = await ApiService.getMachines();
    final assignedSet = assignedMachineIds.toSet();
    final controlledMachines = allMachines.where((m) {
      final machineId = (m['id'] ?? m['_id'] ?? m['machineId'] ?? '').toString();
      return assignedSet.contains(machineId);
    }).toList();

    for (final m in controlledMachines) {
      final machineId = (m['id'] ?? m['_id'] ?? m['machineId'] ?? '').toString();
      if (machineId.isEmpty) continue;
      try {
        final latest = await ApiService.getLatestTelemetry(machineId);
        final riskRaw = latest?['prob_panne'] ?? latest?['panne_probability'] ?? latest?['scenarioProbPanne'];
        final num? riskNum = riskRaw is num ? riskRaw : num.tryParse(riskRaw?.toString() ?? '');
        final int riskPercent = riskNum == null ? 0 : (riskNum <= 1 ? (riskNum * 100).round() : riskNum.round());
        m['_riskPercent'] = riskPercent.clamp(0, 100);
        m['_requiresStop'] = latest?['requires_stop'] == true;
        m['_riskLabel'] = riskPercent > 60
            ? 'Risque IA ${riskPercent}%'
            : (latest?['notification_message'] ?? '').toString();
        final status = (m['status'] ?? '').toString().toUpperCase();
        final critical = (m['_requiresStop'] == true) || riskPercent > 60 || status == 'PANNE';
        if (critical && !_criticalAlertSentMachineIds.contains(machineId)) {
          final reason = status == 'PANNE'
              ? 'Panne détectée sur la machine.'
              : 'Risque de panne élevé détecté par IA.';
          _sendCriticalAlertToClient(
            machineId: machineId,
            riskPercent: riskPercent,
            reason: reason,
          );
          _criticalAlertSentMachineIds.add(machineId);
        } else if (!critical) {
          _criticalAlertSentMachineIds.remove(machineId);
        }
      } catch (_) {
        m['_riskPercent'] = _machineHealthFromStatus((m['status'] ?? '').toString());
        m['_requiresStop'] = false;
        m['_riskLabel'] = '';
        _criticalAlertSentMachineIds.remove(machineId);
      }
    }
    return controlledMachines;
  }

  int _machineHealthFromStatus(String status) {
    final s = status.toUpperCase();
    if (s == 'RUNNING') return 92;
    if (s == 'STOPPED') return 58;
    return 75;
  }

  Widget _buildTechnicianHistorySection(List<String> assignedMachineIds) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _outlineVariant.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'HISTORIQUE DES VALEURS MACHINES',
                style: GoogleFonts.spaceGrotesk(
                  color: _secondary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.4,
                ),
              ),
              const Spacer(),
              Text(
                '${assignedMachineIds.length} machine(s) liées',
                style: GoogleFonts.inter(color: _onSurfaceVariant, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _loadTechnicianHistoryRows(assignedMachineIds),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(14),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              if (snapshot.hasError) {
                return Text(
                  'Erreur chargement historique',
                  style: GoogleFonts.inter(color: _error),
                );
              }
              final rows = snapshot.data ?? const <Map<String, dynamic>>[];
              if (rows.isEmpty) {
                return Text(
                  'Pas encore de mesures historiques pour ces machines.',
                  style: GoogleFonts.inter(color: _onSurfaceVariant),
                );
              }
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingTextStyle: GoogleFonts.spaceGrotesk(color: _onSurfaceVariant, fontSize: 10),
                  dataTextStyle: GoogleFonts.inter(color: _onSurface, fontSize: 12),
                  columns: const [
                    DataColumn(label: Text('Machine')),
                    DataColumn(label: Text('Heure')),
                    DataColumn(label: Text('Temp °C')),
                    DataColumn(label: Text('Pression')),
                    DataColumn(label: Text('Puissance')),
                    DataColumn(label: Text('Risque IA %')),
                  ],
                  rows: rows.map((r) {
                    final machineId = (r['_machineId'] ?? '').toString();
                    final dt = _fmtDate((r['createdAt'] ?? '').toString());
                    final temp = _n(r['temperature'] ?? r['thermal']);
                    final pressure = _n(r['pressure']);
                    final power = _n(r['power']);
                    final riskRaw = r['prob_panne'] ?? r['panne_probability'] ?? r['scenarioProbPanne'] ?? 0;
                    final risk = _riskPercent(riskRaw);
                    return DataRow(cells: [
                      DataCell(Text(machineId)),
                      DataCell(Text(dt)),
                      DataCell(Text(temp.toStringAsFixed(1))),
                      DataCell(Text(pressure.toStringAsFixed(2))),
                      DataCell(Text(power.toStringAsFixed(2))),
                      DataCell(Text('$risk')),
                    ]);
                  }).toList(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _loadTechnicianHistoryRows(List<String> machineIds) async {
    final rows = <Map<String, dynamic>>[];
    for (final id in machineIds) {
      if (id.isEmpty) continue;
      try {
        final hist = await ApiService.getTelemetryHistory(id, limit: 8);
        for (final item in hist) {
          final map = Map<String, dynamic>.from(item);
          map['_machineId'] = id;
          rows.add(map);
        }
      } catch (_) {}
    }
    rows.sort((a, b) {
      final ad = DateTime.tryParse((a['createdAt'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = DateTime.tryParse((b['createdAt'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });
    if (rows.length > 25) return rows.take(25).toList();
    return rows;
  }

  double _n(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  int _riskPercent(dynamic riskRaw) {
    final n = riskRaw is num ? riskRaw.toDouble() : double.tryParse(riskRaw?.toString() ?? '') ?? 0;
    final p = n <= 1 ? (n * 100) : n;
    return p.round().clamp(0, 100);
  }

  String _fmtDate(String raw) {
    if (raw.isEmpty) return '--';
    final d = DateTime.tryParse(raw)?.toLocal();
    if (d == null) return raw;
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return '$dd/$mm $hh:$mi';
  }

  Widget _buildClientTechnicianMessengerZone() {
    final sortedMessages = [..._chatMessages]
      ..sort((a, b) {
        final ad = DateTime.tryParse((a['createdAt'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bd = DateTime.tryParse((b['createdAt'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return ad.compareTo(bd);
      });

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _outlineVariant.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.forum_outlined, color: _secondary, size: 18),
              const SizedBox(width: 8),
              Text(
                'MESSAGERIE CLIENT ↔ TECHNICIEN',
                style: GoogleFonts.spaceGrotesk(
                  color: _secondary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              if (_chatRoomId.isNotEmpty)
                Text(
                  _chatRoomId,
                  style: GoogleFonts.inter(color: _onSurfaceVariant, fontSize: 10),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: _surfaceContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 220,
                  height: 350,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _surfaceContainerHighest.withOpacity(0.25),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DISCUSSIONS RÉCENTES',
                        style: GoogleFonts.spaceGrotesk(
                          color: _onSurfaceVariant,
                          fontSize: 10,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: _chatConversations.isEmpty
                            ? Center(
                                child: Text(
                                  'Aucun client',
                                  style: GoogleFonts.inter(color: _onSurfaceVariant, fontSize: 11),
                                ),
                              )
                            : ListView.builder(
                                itemCount: _chatConversations.length,
                                itemBuilder: (context, index) {
                                  final c = _chatConversations[index];
                                  final room = (c['roomId'] ?? '').toString();
                                  final active = room == _chatRoomId;
                                  final clientName = (c['clientName'] ?? 'Client').toString();
                                  final lastText = (c['lastText'] ?? '').toString();
                                  return InkWell(
                                    onTap: () async {
                                      if (room.isEmpty) return;
                                      setState(() => _chatRoomId = room);
                                      _chatSocket?.emit('join_chat_room', {'roomId': room});
                                      try {
                                        final history = await ApiService.getChatMessages(room, limit: 200);
                                        if (!mounted) return;
                                        setState(() {
                                          _chatMessages
                                            ..clear()
                                            ..addAll(history);
                                        });
                                      } catch (_) {}
                                    },
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: active ? _surfaceContainerHighest : _surfaceContainer,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: active
                                              ? _secondary.withOpacity(0.45)
                                              : Colors.transparent,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            clientName,
                                            style: GoogleFonts.inter(
                                              color: _onSurface,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            lastText.isEmpty ? 'Aucun message' : lastText,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.inter(
                                              color: _onSurfaceVariant,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SizedBox(
                    height: 350,
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: _surfaceContainerHighest.withOpacity(0.55),
                            borderRadius: const BorderRadius.only(
                              topRight: Radius.circular(12),
                            ),
                          ),
                          child: Row(
                            children: [
                              const CircleAvatar(
                                radius: 15,
                                backgroundColor: _primaryContainer,
                                child: Icon(Icons.engineering, color: Colors.white, size: 14),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _chatSenderName,
                                style: GoogleFonts.inter(
                                  color: _onSurface,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _primaryContainer.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'TECHNICIEN',
                                  style: GoogleFonts.spaceGrotesk(
                                    color: _primary,
                                    fontSize: 9,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: sortedMessages.isEmpty
                                ? Center(
                                    child: Text(
                                      'Aucun message pour le moment.',
                                      style: GoogleFonts.inter(color: _onSurfaceVariant),
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: sortedMessages.length,
                                    itemBuilder: (context, i) {
                                      final m = sortedMessages[i];
                                      final sender = (m['senderName'] ?? 'User').toString();
                                      final text = (m['text'] ?? '').toString();
                                      final mine = sender == _chatSenderName;
                                      final isCritical =
                                          sender.toLowerCase().contains('alerte') ||
                                          text.toLowerCase().contains('alerte critique');
                                      return Align(
                                        alignment:
                                            mine ? Alignment.centerRight : Alignment.centerLeft,
                                        child: Container(
                                          constraints: const BoxConstraints(maxWidth: 420),
                                          margin: const EdgeInsets.symmetric(vertical: 5),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isCritical
                                                ? _error.withOpacity(0.2)
                                                : (mine
                                                    ? _primaryContainer.withOpacity(0.88)
                                                    : _surfaceContainerHighest),
                                            borderRadius: BorderRadius.circular(10),
                                            border: isCritical
                                                ? Border.all(color: _error.withOpacity(0.7))
                                                : null,
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              if (!mine)
                                                Text(
                                                  sender,
                                                  style: GoogleFonts.inter(
                                                    color: _onSurfaceVariant,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              Text(
                                                text,
                                                style: GoogleFonts.inter(
                                                  color: _onSurface,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatInputController,
                  style: GoogleFonts.inter(color: _onSurface),
                  decoration: const InputDecoration(
                    hintText: 'Écrire un message au client...',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  maxLines: 2,
                  minLines: 1,
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: _sendTechnicianMessage,
                icon: const Icon(Icons.send, size: 16),
                label: const Text('Envoyer'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _sendTechnicianMessage() {
    final text = _chatInputController.text.trim();
    if (text.isEmpty || _chatRoomId.isEmpty) return;
    _chatSocket?.emit('chat_message', {
      'roomId': _chatRoomId,
      'from': 'technician',
      'senderName': _chatSenderName,
      'text': text,
    });
    _chatInputController.clear();
  }

  void _sendCriticalAlertToClient({
    required String machineId,
    required int riskPercent,
    required String reason,
  }) {
    if (_chatRoomId.isEmpty) return;
    final alertText =
        'ALERTE CRITIQUE : $machineId\n$reason\nRisque IA: $riskPercent%.\nAction immédiate recommandée.';
    _chatSocket?.emit('chat_message', {
      'roomId': _chatRoomId,
      'from': 'system',
      'senderName': 'Alerte Système',
      'text': alertText,
    });
  }

  Widget _buildMachineCard(
    IconData icon,
    String name,
    String client,
    int score,
    Color color, {
    VoidCallback? onTap,
    bool isAlert = false,
    String alertText = '',
  }) {
    Widget card(double pulse) => Material(
          color: isAlert ? _error.withOpacity(0.07 + (0.08 * pulse)) : _surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isAlert ? _error.withOpacity(0.45 + (0.45 * pulse)) : Colors.transparent,
                  width: isAlert ? 1.8 : 0,
                ),
              ),
              child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: _surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: color, size: 24),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: '$score',
                          style: GoogleFonts.spaceGrotesk(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        TextSpan(
                          text: '%',
                          style: GoogleFonts.spaceGrotesk(fontSize: 14, color: _onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Text('HEALTH SCORE', style: GoogleFonts.spaceGrotesk(fontSize: 8, color: _onSurfaceVariant, letterSpacing: 1)),
                ],
              ),
            ],
          ),
          const Spacer(),
          Text(name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          Text('Client: $client', style: TextStyle(color: _onSurfaceVariant, fontSize: 13)),
          if (isAlert) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.notifications_active, color: _error, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    alertText.isEmpty ? 'Alerte panne détectée' : alertText,
                    style: GoogleFonts.inter(color: _error, fontSize: 11, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: score / 100,
              backgroundColor: _surfaceContainerLow,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 2,
            ),
          ),
        ],
      ),
            ),
          ),
        );

    if (!isAlert) {
      return card(0);
    }

    return StreamBuilder<int>(
      stream: Stream.periodic(const Duration(milliseconds: 550), (x) => x),
      builder: (context, snapshot) {
        final pulse = ((snapshot.data ?? 0) % 2 == 0) ? 0.15 : 1.0;
        return card(pulse);
      },
    );
  }

  Widget _buildAddMachineCard() {
    return Container(
      decoration: BoxDecoration(
        color: _surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white10, style: BorderStyle.none), // dashed in CSS
              ),
              child: const Icon(Icons.add, color: _onSurfaceVariant, size: 32),
            ),
            const SizedBox(height: 12),
            const Text('Assigner Nouvelle Machine', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            Text('Mise à jour du protocole requis', style: TextStyle(color: _onSurfaceVariant, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildPerformanceSection() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: _surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          Positioned(
            right: 0,
            top: 0,
            child: Icon(Icons.query_stats, size: 100, color: Colors.white.withOpacity(0.05)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Performance Hebdomadaire', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildStatItem('24', 'Interventions', _secondary),
                  _buildStatItem('98.2%', 'Taux Succès', _primaryContainer),
                  _buildStatItem('02h', 'Délai Moyen', _tertiary),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String val, String label, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(val, style: GoogleFonts.spaceGrotesk(fontSize: 32, fontWeight: FontWeight.bold, color: color)),
        Text(label.toUpperCase(), style: GoogleFonts.spaceGrotesk(fontSize: 9, color: _onSurfaceVariant, letterSpacing: 1.5)),
      ],
    );
  }

  Widget _buildMobileBottomNav() {
    return Container(
      height: 72,
      decoration: const BoxDecoration(
        color: _surfaceContainerLow,
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildMobileNavIcon(Icons.analytics_outlined, 'Overview'),
          _buildMobileNavIcon(Icons.route_outlined, 'Location'),
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(color: _primaryContainer, shape: BoxShape.circle),
            child: const Icon(Icons.person, color: Colors.black87),
          ),
          _buildMobileNavIcon(Icons.precision_manufacturing_outlined, 'Fleet'),
          _buildMobileNavIcon(Icons.description_outlined, 'Docs'),
        ],
      ),
    );
  }

  Widget _buildMobileNavIcon(IconData icon, String label) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: _onSurfaceVariant, size: 20),
        const SizedBox(height: 4),
        Text(label, style: GoogleFonts.spaceGrotesk(color: _onSurfaceVariant, fontSize: 9)),
      ],
    );
  }
}
