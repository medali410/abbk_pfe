import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/api_service.dart';
import 'machine_detail_ai_page.dart';

class ConcepteurDashboardPage extends StatefulWidget {
  const ConcepteurDashboardPage({super.key});

  @override
  State<ConcepteurDashboardPage> createState() => _ConcepteurDashboardPageState();
}

class _ConcepteurDashboardPageState extends State<ConcepteurDashboardPage> {
  // Theme Colors
  static const Color bgColor = Color(0xFF0A0A1B);
  static const Color sidebarColor = Color(0xFF111122);
  static const Color cardColor = Color(0xFF1A1A2E);
  static const Color primaryColor = Color(0xFFFF9F64);
  static const Color accentColor = Color(0xFF7B61FF);
  static const Color textColor = Color(0xFFF4F4F9);
  static const Color mutedTextColor = Color(0xFF9E9EAE);
  static const Color successColor = Color(0xFF4CAF50);
  static const Color alertColor = Color(0xFFFF4B4B);

  String selectedMenu = 'DASHBOARD';
  
  // State variables
  List<Map<String, dynamic>> _allMachines = [];
  bool _loading = true;
  String? _error;
  
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'Toutes les catégories';
  String _selectedStatus = 'Tous';
  
  @override
  void initState() {
    super.initState();
    _fetchMachines();
  }

  Future<void> _fetchMachines() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getMachines();
      if (mounted) {
        setState(() {
          _allMachines = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Impossible de charger les machines: $e';
        });
      }
    }
  }

  List<Map<String, dynamic>> get _filteredMachines {
    final query = _searchController.text.toLowerCase();
    return _allMachines.where((m) {
      final name = (m['name'] ?? '').toString().toLowerCase();
      final ref = (m['machineId'] ?? m['id'] ?? '').toString().toLowerCase();
      final cat = (m['type'] ?? m['category'] ?? '').toString();
      final status = (m['status'] ?? '').toString();
      
      bool matchesSearch = name.contains(query) || ref.contains(query);
      bool matchesCategory = _selectedCategory == 'Toutes les catégories' || cat == _selectedCategory;
      bool matchesStatus = _selectedStatus == 'Tous' || 
          (_selectedStatus == 'Publié' && (m['isPublished'] == true || status == 'active')) ||
          (_selectedStatus == 'Non publié' && (m['isPublished'] != true && status != 'active'));
          
      return matchesSearch && matchesCategory && matchesStatus;
    }).toList();
  }

  int get _publishedCount => _allMachines.where((m) => m['isPublished'] == true || m['status'] == 'active').length;
  int get _notPublishedCount => _allMachines.length - _publishedCount;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: Row(
        children: [
          // Sidebar
          _buildSidebar(),
          // Main Content
          Expanded(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: _loading 
                    ? const Center(child: CircularProgressIndicator(color: primaryColor))
                    : _error != null
                      ? _buildErrorView()
                      : _buildMainContent(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: alertColor, size: 64),
          const SizedBox(height: 16),
          Text(_error!, style: GoogleFonts.inter(color: textColor, fontSize: 16)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _fetchMachines,
            style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
            child: Text('Réessayer', style: GoogleFonts.inter(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return RefreshIndicator(
      onRefresh: _fetchMachines,
      color: primaryColor,
      backgroundColor: cardColor,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatsGrid(),
            const SizedBox(height: 32),
            _buildMainSectionHeader(),
            const SizedBox(height: 24),
            _buildFilterBar(),
            const SizedBox(height: 24),
            if (_filteredMachines.isEmpty)
              _buildEmptyView()
            else
              _buildMachineGrid(),
            const SizedBox(height: 32),
            _buildPagination(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: sidebarColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Icon(Icons.search_off, color: mutedTextColor.withOpacity(0.3), size: 64),
          const SizedBox(height: 16),
          Text(
            'Aucune machine trouvée',
            style: GoogleFonts.spaceGrotesk(fontSize: 20, color: mutedTextColor, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Essayez de modifier vos filtres ou votre recherche.',
            style: GoogleFonts.inter(color: mutedTextColor.withOpacity(0.7)),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 260,
      color: sidebarColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'KINETIC',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 2,
                  ),
                ),
                Text(
                  'PREDICTIVE INTELLIGENCE',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          _sidebarItem(Icons.grid_view_rounded, 'DASHBOARD'),
          _sidebarItem(Icons.precision_manufacturing_outlined, 'MY MACHINES'),
          _sidebarItem(Icons.add_circle_outline, 'ADD MACHINE'),
          _sidebarItem(Icons.settings_input_component_outlined, 'COMPONENTS'),
          _sidebarItem(Icons.people_outline_rounded, 'TECHNICIANS'),
          _sidebarItem(Icons.support_agent_rounded, 'AGENTS'),
          _sidebarItem(Icons.menu_book_rounded, 'CLIENT CATALOG'),
          _sidebarItem(Icons.settings_outlined, 'SETTINGS'),
          const Spacer(),
          _buildUserCard(),
        ],
      ),
    );
  }

  Widget _sidebarItem(IconData icon, String title) {
    bool isSelected = selectedMenu == title;
    return InkWell(
      onTap: () => setState(() => selectedMenu = title),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          border: isSelected
              ? const Border(right: BorderSide(color: primaryColor, width: 3))
              : null,
          color: isSelected ? primaryColor.withOpacity(0.05) : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? primaryColor : mutedTextColor,
              size: 20,
            ),
            const SizedBox(width: 16),
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? primaryColor : mutedTextColor,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCard() {
    final role = (ApiService.savedUserRole ?? 'Concepteur').toUpperCase();
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 20,
            backgroundImage: NetworkImage('https://i.pravatar.cc/150?u=concepteur'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Equipe Design',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  role,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: mutedTextColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Row(
        children: [
          // Search in TopBar (Optional, we have one in filter bar too)
          Container(
            width: 300,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.search, color: mutedTextColor, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Rechercher une machine...',
                      hintStyle: GoogleFonts.inter(color: mutedTextColor, fontSize: 13),
                      border: InputBorder.none,
                    ),
                    style: GoogleFonts.inter(color: textColor, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 32),
          Text(
            'INDUSTRIAL INTELLIGENCE',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: mutedTextColor,
              letterSpacing: 2,
            ),
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () => _showAddMachineDialog(),
            icon: const Icon(Icons.add_circle, size: 18),
            label: const Text('Ajouter une machine'),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              textStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          const SizedBox(width: 24),
          Stack(
            children: [
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.notifications_outlined, color: Colors.white),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: primaryColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () {
              ApiService.clearAuth();
              Navigator.of(context).pushReplacementNamed('/');
            },
            icon: const Icon(Icons.logout_rounded, color: alertColor, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid() {
    return Row(
      children: [
        _statCard('TOTAL MACHINES', _allMachines.length.toString(), null, primaryColor),
        const SizedBox(width: 16),
        _statCard('PUBLIÉES', _publishedCount.toString(), null, accentColor),
        const SizedBox(width: 16),
        _statCard('NON PUBLIÉES', _notPublishedCount.toString(), _notPublishedCount > 0 ? 'Attention' : null, alertColor),
        const SizedBox(width: 16),
        _statCard('FILTRÉES', _filteredMachines.length.toString(), null, Colors.cyan),
        const SizedBox(width: 16),
        _statCard('MODÈLES 3D', _allMachines.where((m) => m['has3D'] == true || m['threeDModel'] != null).length.toString(), null, successColor),
        const SizedBox(width: 16),
        _statCard('MAINTENANCE', '12', 'Actifs', Colors.amber),
      ],
    );
  }

  Widget _statCard(String title, String value, String? badge, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: sidebarColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: mutedTextColor,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      badge,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainSectionHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'RÉPERTOIRE DES MACHINES',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(width: 40, height: 2, color: primaryColor),
                const SizedBox(width: 12),
                Text(
                  'SYNC MONGO DB ATLAS // ${_allMachines.length} UNITÉS',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: mutedTextColor,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ],
        ),
        ElevatedButton.icon(
          onPressed: _showAddMachineDialog,
          icon: const Icon(Icons.add, size: 20),
          label: const Text('NOUVELLE MACHINE'),
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            textStyle: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    final categories = ['Toutes les catégories', ..._allMachines.map((e) => (e['type'] ?? e['category'] ?? 'Inconnu').toString()).toSet()];
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sidebarColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          const Icon(Icons.filter_list, color: primaryColor, size: 20),
          const SizedBox(width: 16),
          Expanded(
            child: _filterInput('Rechercher par nom ou référence...'),
          ),
          const SizedBox(width: 24),
          _filterDropdown('CATÉGORIE', _selectedCategory, categories.toList(), (v) => setState(() => _selectedCategory = v!)),
          const SizedBox(width: 24),
          _filterDropdown('STATUS PUBLICATION', _selectedStatus, ['Tous', 'Publié', 'Non publié'], (v) => setState(() => _selectedStatus = v!)),
        ],
      ),
    );
  }

  Widget _filterInput(String hint) {
    return TextField(
      controller: _searchController,
      onChanged: (v) => setState(() {}),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(color: mutedTextColor.withOpacity(0.5), fontSize: 13),
        border: InputBorder.none,
      ),
      style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
    );
  }

  Widget _filterDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: mutedTextColor, letterSpacing: 0.5),
        ),
        const SizedBox(height: 4),
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: items.contains(value) ? value : items.first,
            dropdownColor: sidebarColor,
            style: GoogleFonts.inter(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500),
            icon: const Icon(Icons.keyboard_arrow_down, color: mutedTextColor, size: 16),
            items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildMachineGrid() {
    final machines = _filteredMachines;
    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = 3;
        if (constraints.maxWidth < 600) crossAxisCount = 1;
        else if (constraints.maxWidth < 1000) crossAxisCount = 2;
        
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 0.72,
            crossAxisSpacing: 24,
            mainAxisSpacing: 24,
          ),
          itemCount: machines.length,
          itemBuilder: (context, index) => _buildMachineCard(machines[index]),
        );
      },
    );
  }

  Widget _buildMachineCard(Map<String, dynamic> m) {
    final id = (m['id'] ?? m['_id'] ?? '').toString();
    final name = (m['name'] ?? 'Machine sans nom').toString();
    final ref = (m['machineId'] ?? m['reference'] ?? 'REF-000').toString();
    final type = (m['type'] ?? m['category'] ?? 'Non catégorisé').toString();
    final location = (m['location'] ?? 'Localisation inconnue').toString();
    
    // --- STEP 5: DATA EXTRACTION ---
    final tempsMarcheData = m['tempsMarche'] ?? {};
    final totalHeures = (tempsMarcheData['totalHeures'] ?? 0).toDouble();
    final h = totalHeures.toInt();
    final min = ((totalHeures - h) * 60).round();
    final enMarche = tempsMarcheData['enMarche'] == true;
    // -------------------------------
    
    String dateStr = 'Date non définie';
    final rawDate = m['createdAt'] ?? m['dateAjout'];
    if (rawDate != null && rawDate.toString().isNotEmpty) {
      dateStr = rawDate.toString().split('T')[0];
    }
    
    final isPublished = m['isPublished'] == true || m['status'] == 'active' || m['status'] == 'Publié';
    final statusLabel = isPublished ? 'Publié' : 'Non publié';
    final has3D = m['has3D'] == true || m['threeDModel'] != null;
    final imageUrl = (m['imageUrl'] ?? '').toString().isNotEmpty 
        ? m['imageUrl'] 
        : 'https://images.unsplash.com/photo-1581091226825-a6a2a5aee158?q=80&w=800';

    return Container(
      decoration: BoxDecoration(
        color: sidebarColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image Section
          Stack(
            children: [
              Image.network(imageUrl, height: 180, width: double.infinity, fit: BoxFit.cover, 
                errorBuilder: (_, __, ___) => Container(color: cardColor, height: 180, child: const Icon(Icons.precision_manufacturing, color: mutedTextColor, size: 48))),
              Positioned(
                top: 12,
                left: 12,
                child: Row(
                  children: [
                    _statusBadge(statusLabel.toUpperCase(), isPublished ? successColor : alertColor),
                    const SizedBox(width: 8),
                    _statusBadge(has3D ? '3D' : 'NO 3D', has3D ? accentColor : mutedTextColor),
                  ],
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withOpacity(0.6)],
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      ref.toUpperCase(),
                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: primaryColor, letterSpacing: 0.5),
                    ),
                    _buildMachineActions(m),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _infoItem('CATÉGORIE', type),
                    const SizedBox(width: 16),
                    _infoItem('LOCALISATION', location),
                  ],
                ),
                const SizedBox(height: 12),
                _infoItem('DATE D\'AJOUT', dateStr),
                const SizedBox(height: 16),
                
                // --- STEP 5: TEMPS DE MARCHE ---
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: bgColor.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.timer_outlined, color: primaryColor, size: 14),
                              const SizedBox(width: 6),
                              Text(
                                'Temps de marche',
                                style: GoogleFonts.inter(fontSize: 11, color: mutedTextColor, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: enMarche ? successColor : alertColor,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: (enMarche ? successColor : alertColor).withOpacity(0.5),
                                      blurRadius: 4,
                                      spreadRadius: 1,
                                    )
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                enMarche ? 'EN MARCHE' : 'ARRÊTÉE',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: enMarche ? successColor : alertColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${h}h ${min}min',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: (totalHeures % 100) / 100, // Visual progress relative to 100h cycles
                          backgroundColor: Colors.white.withOpacity(0.05),
                          valueColor: AlwaysStoppedAnimation<Color>(enMarche ? primaryColor : mutedTextColor.withOpacity(0.3)),
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ),
                ),
                // -------------------------------

                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _cardButton(Icons.visibility_outlined, 'DÉTAILS', cardColor, () => _openDetails(id)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _cardButton(Icons.view_in_ar_outlined, 'VOIR 3D', cardColor, has3D ? () {} : null),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _miniButton(Icons.edit_outlined, () => _showEditMachineDialog(m)),
                    const SizedBox(width: 8),
                    _miniButton(Icons.delete_outline, () => _confirmDelete(id, name), color: alertColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        height: 36,
                        decoration: BoxDecoration(
                          color: isPublished ? cardColor : primaryColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: InkWell(
                          onTap: () => _togglePublish(id, isPublished),
                          child: Center(
                            child: Text(
                              isPublished ? 'DÉPUBLIER' : 'PUBLIER',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isPublished ? mutedTextColor : Colors.black,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMachineActions(Map<String, dynamic> m) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: mutedTextColor, size: 18),
      color: sidebarColor,
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'edit', child: Text('Modifier', style: TextStyle(color: textColor, fontSize: 13))),
        const PopupMenuItem(value: 'delete', child: Text('Supprimer', style: TextStyle(color: alertColor, fontSize: 13))),
        const PopupMenuItem(value: 'publish', child: Text('Publier/Dépublier', style: TextStyle(color: primaryColor, fontSize: 13))),
      ],
      onSelected: (val) {
        if (val == 'edit') _showEditMachineDialog(m);
        if (val == 'delete') _confirmDelete(m['id'] ?? m['_id'], m['name']);
      },
    );
  }

  Widget _statusBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _infoItem(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.bold, color: mutedTextColor, letterSpacing: 0.5),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _cardButton(IconData icon, String label, Color color, VoidCallback? onTap) {
    bool disabled = onTap == null;
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: color.withOpacity(disabled ? 0.3 : 1.0),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: accentColor.withOpacity(0.1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: Colors.white.withOpacity(disabled ? 0.3 : 1.0)),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white.withOpacity(disabled ? 0.3 : 1.0)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniButton(IconData icon, VoidCallback onTap, {Color? color}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, size: 16, color: color ?? mutedTextColor),
      ),
    );
  }

  Widget _buildPagination() {
    final count = _filteredMachines.length;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Affichage de $count sur ${_allMachines.length} machines au total',
          style: GoogleFonts.inter(fontSize: 12, color: mutedTextColor),
        ),
        Row(
          children: [
            _pageArrow(Icons.keyboard_arrow_left),
            const SizedBox(width: 8),
            _pageNumber('1', true),
            const SizedBox(width: 8),
            _pageArrow(Icons.keyboard_arrow_right),
          ],
        ),
      ],
    );
  }

  Widget _pageArrow(IconData icon) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(icon, size: 16, color: mutedTextColor),
    );
  }

  Widget _pageNumber(String num, bool isActive) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isActive ? primaryColor : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.center,
      child: Text(
        num,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: isActive ? Colors.black : mutedTextColor,
        ),
      ),
    );
  }

  // --- ACTIONS ---

  void _openDetails(String id) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => MachineDetailAiPage(machineId: id))
    );
  }

  Future<void> _confirmDelete(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: sidebarColor,
        title: Text('Supprimer $name ?', style: GoogleFonts.spaceGrotesk(color: textColor)),
        content: Text('Cette action est irréversible.', style: GoogleFonts.inter(color: mutedTextColor)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ANNULER')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('SUPPRIMER', style: TextStyle(color: alertColor))),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ApiService.deleteMachine(id);
        _fetchMachines();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Machine supprimée')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e'), backgroundColor: alertColor));
        }
      }
    }
  }

  Future<void> _togglePublish(String id, bool currentStatus) async {
    try {
      await ApiService.updateMachine(id, {'isPublished': !currentStatus, 'status': !currentStatus ? 'active' : 'inactive'});
      _fetchMachines();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur publication: $e'), backgroundColor: alertColor));
      }
    }
  }

  void _showAddMachineDialog() {
    // Navigate to add client view if we need a client, but here we just show a message
    // as addMachine requires a clientId in ApiService.
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: sidebarColor,
        title: Text('Ajouter une machine', style: GoogleFonts.spaceGrotesk(color: textColor)),
        content: Text('Pour ajouter une machine, veuillez utiliser le catalogue client ou contacter l\'administrateur.', style: GoogleFonts.inter(color: mutedTextColor)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  void _showEditMachineDialog(Map<String, dynamic> m) {
    // Similar to add machine, but with prefilled data
    final id = (m['id'] ?? m['_id'] ?? '').toString();
    final nameController = TextEditingController(text: m['name'] ?? '');
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: sidebarColor,
        title: Text('Éditer machine', style: GoogleFonts.spaceGrotesk(color: textColor)),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Nom de la machine'),
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ANNULER')),
          TextButton(
            onPressed: () async {
              try {
                await ApiService.updateMachine(id, {'name': nameController.text.trim()});
                Navigator.pop(context);
                _fetchMachines();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e'), backgroundColor: alertColor));
              }
            }, 
            child: const Text('ENREGISTRER', style: TextStyle(color: primaryColor))
          ),
        ],
      ),
    );
  }
}
