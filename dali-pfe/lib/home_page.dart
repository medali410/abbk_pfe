import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'machine_detail_pro_page.dart';
import 'services/api_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<Map<String, dynamic>>> _machinesFuture;
  bool _animateIn = false;
  String _searchQuery = '';
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _homeSectionKey = GlobalKey();
  final GlobalKey _catalogSectionKey = GlobalKey();
  final GlobalKey _analyticsSectionKey = GlobalKey();
  final GlobalKey _footerSectionKey = GlobalKey();
  String _activeSection = 'home';

  @override
  void initState() {
    super.initState();
    _machinesFuture = ApiService.getMachinesForHomeCatalog();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _animateIn = true;
      });
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _reloadMachines() async {
    setState(() {
      _machinesFuture = ApiService.getMachinesForHomeCatalog();
    });
    await _machinesFuture;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1100;
    final isTablet = width >= 760;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0B1020), Color(0xFF141D34), Color(0xFF1A1730)],
          ),
        ),
        child: SafeArea(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _machinesFuture,
            builder: (context, snapshot) {
              final machines = snapshot.data ?? const <Map<String, dynamic>>[];
              final filteredMachines =
                  machines.where((m) {
                    final machineId =
                        (m['machineId'] ?? m['_id'] ?? m['id'] ?? '')
                            .toString();
                    final name = (m['name'] ?? m['model'] ?? '').toString();
                    final brand = (m['brand'] ?? m['marque'] ?? '').toString();
                    final q = _searchQuery.toLowerCase().trim();
                    if (q.isEmpty) return true;
                    return machineId.toLowerCase().contains(q) ||
                        name.toLowerCase().contains(q) ||
                        brand.toLowerCase().contains(q);
                  }).toList();
              final padding = isDesktop ? 44.0 : (isTablet ? 26.0 : 16.0);
              return RefreshIndicator(
                onRefresh: _reloadMachines,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1380),
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        _updateActiveSectionFromScroll();
                        return false;
                      },
                      child: CustomScrollView(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          const SliverToBoxAdapter(child: SizedBox(height: 8)),
                          SliverPersistentHeader(
                            pinned: true,
                            delegate: _StickyHeaderDelegate(
                              minHeight: 78,
                              maxHeight: 78,
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: padding,
                                ),
                                child: _buildHeaderShell(context),
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                padding,
                                18,
                                padding,
                                26,
                              ),
                              child: Column(
                                children: [
                                  _buildEntrance(
                                    delayMs: 80,
                                    child: KeyedSubtree(
                                      key: _homeSectionKey,
                                      child: _buildHero(
                                        total: filteredMachines.length,
                                        isDesktop: isDesktop,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  _buildEntrance(
                                    delayMs: 95,
                                    child: _buildToolbar(isDesktop),
                                  ),
                                  const SizedBox(height: 18),
                                  _buildEntrance(
                                    delayMs: 105,
                                    child: KeyedSubtree(
                                      key: _catalogSectionKey,
                                      child: _buildSectionHeader(
                                        title: 'Catalogue des systemes',
                                        subtitle:
                                            '${filteredMachines.length} machine(s) affichee(s)',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  if (snapshot.connectionState ==
                                      ConnectionState.waiting)
                                    _buildEntrance(
                                      delayMs: 120,
                                      child: const Padding(
                                        padding: EdgeInsets.only(top: 30),
                                        child: Center(
                                          child: CircularProgressIndicator(),
                                        ),
                                      ),
                                    )
                                  else if (snapshot.hasError)
                                    _buildEntrance(
                                      delayMs: 120,
                                      child: _buildError(
                                        snapshot.error.toString(),
                                      ),
                                    )
                                  else if (filteredMachines.isEmpty)
                                    _buildEntrance(
                                      delayMs: 120,
                                      child: _buildEmpty(),
                                    )
                                  else
                                    _buildEntrance(
                                      delayMs: 120,
                                      child: _buildGrid(
                                        filteredMachines,
                                        crossAxisCount:
                                            isDesktop ? 3 : (isTablet ? 2 : 1),
                                      ),
                                    ),
                                  const SizedBox(height: 20),
                                  _buildEntrance(
                                    delayMs: 150,
                                    child: KeyedSubtree(
                                      key: _analyticsSectionKey,
                                      child: _buildRealtimeAnalytics(isDesktop),
                                    ),
                                  ),
                                  const SizedBox(height: 26),
                                  _buildEntrance(
                                    delayMs: 190,
                                    child: KeyedSubtree(
                                      key: _footerSectionKey,
                                      child: _buildFooter(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildEntrance({required Widget child, int delayMs = 0}) {
    return _EntranceItem(animateIn: _animateIn, delayMs: delayMs, child: child);
  }

  Widget _buildHeaderShell(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xAA121A30),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x33FFFFFF)),
          ),
          child: _buildHeader(context),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final navStyle = GoogleFonts.inter(
      fontSize: 11,
      color: const Color(0xFFA7B1C6),
      fontWeight: FontWeight.w500,
    );
    return Row(
      children: [
        Container(
          width: 190,
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Image.asset(
            'assets/images/abbk_logo.png',
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
        const SizedBox(width: 24),
        if (MediaQuery.of(context).size.width >= 980) ...[
          _buildNavItem(
            label: 'Accueil',
            sectionId: 'home',
            baseStyle: navStyle,
            onTap: () => _scrollToSection(_homeSectionKey),
          ),
          const SizedBox(width: 14),
          _buildNavItem(
            label: 'Machines',
            sectionId: 'catalog',
            baseStyle: navStyle,
            onTap: () => _scrollToSection(_catalogSectionKey),
          ),
          const SizedBox(width: 14),
          _buildNavItem(
            label: 'Analyse',
            sectionId: 'analytics',
            baseStyle: navStyle,
            onTap: () => _scrollToSection(_analyticsSectionKey),
          ),
          const SizedBox(width: 14),
          _buildNavItem(
            label: 'Support',
            sectionId: 'footer',
            baseStyle: navStyle,
            onTap: () => _scrollToSection(_footerSectionKey),
          ),
        ],
        const Spacer(),
        ElevatedButton.icon(
          onPressed: () => Navigator.pushNamed(context, '/login'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF6E00),
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ).copyWith(
            overlayColor: WidgetStateProperty.all(
              Colors.white.withOpacity(0.12),
            ),
            shadowColor: WidgetStateProperty.all(
              const Color(0xFFFF6E00).withOpacity(0.4),
            ),
          ),
          icon: const Icon(Icons.login_rounded),
          label: const Text('Connexion'),
        ),
      ],
    );
  }

  Widget _buildNavItem({
    required String label,
    required String sectionId,
    required TextStyle baseStyle,
    required VoidCallback onTap,
  }) {
    final isActive = _activeSection == sectionId;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: isActive ? const Color(0x22FF6E00) : Colors.transparent,
          border: Border.all(
            color: isActive ? const Color(0x44FFB87A) : Colors.transparent,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: baseStyle.copyWith(
                color: isActive ? const Color(0xFFFFBE86) : baseStyle.color,
                fontWeight: isActive ? FontWeight.w700 : baseStyle.fontWeight,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              height: 2.2,
              width: isActive ? 18 : 0,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF6E00), Color(0xFFFFB87A)],
                ),
                boxShadow:
                    isActive
                        ? [
                          BoxShadow(
                            color: const Color(0xFFFF6E00).withOpacity(0.45),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                        : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _scrollToSection(GlobalKey key) {
    final context = key.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      alignment: 0.05,
    );
  }

  void _updateActiveSectionFromScroll() {
    final ordered = <String, GlobalKey>{
      'home': _homeSectionKey,
      'catalog': _catalogSectionKey,
      'analytics': _analyticsSectionKey,
      'footer': _footerSectionKey,
    };
    String next = _activeSection;
    for (final entry in ordered.entries) {
      final ctx = entry.value.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject();
      if (box is! RenderBox) continue;
      final dy = box.localToGlobal(Offset.zero).dy;
      if (dy <= 150) {
        next = entry.key;
      }
    }
    if (next != _activeSection && mounted) {
      setState(() {
        _activeSection = next;
      });
    }
  }

  Widget _buildHero({required int total, required bool isDesktop}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.all(isDesktop ? 26 : 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xCC1E2641), Color(0xCC171D33)],
            ),
            border: Border.all(color: const Color(0x3DFFFFFF)),
          ),
          child:
              isDesktop
                  ? Row(
                    children: [
                      Expanded(
                        child: _buildHeroText(
                          total: total,
                          isDesktop: isDesktop,
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(child: _buildHeroVisual()),
                    ],
                  )
                  : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeroText(total: total, isDesktop: isDesktop),
                      const SizedBox(height: 14),
                      _buildHeroVisual(),
                    ],
                  ),
        ),
      ),
    );
  }

  Widget _buildHeroText({required int total, required bool isDesktop}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Catalogue machines',
          style: GoogleFonts.inter(
            color: const Color(0xFFFFB87A),
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'L\'efficacite predite par l\'IA',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: isDesktop ? 38 : 28,
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Visualisez les equipements critiques en temps reel '
          'et accedez aux machines disponibles depuis la base.',
          style: GoogleFonts.inter(
            color: const Color(0xFFA7B1C6),
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip(Icons.precision_manufacturing_rounded, '$total machines'),
            _chip(Icons.storage_rounded, 'Source: DB'),
            _chip(Icons.update_rounded, 'Temps reel'),
          ],
        ),
      ],
    );
  }

  Widget _buildHeroVisual() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 1.38,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              'https://images.unsplash.com/photo-1565043589221-1a6fd9ae45c7?auto=format&fit=crop&w=1200&q=80',
              fit: BoxFit.cover,
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.2),
                    Colors.black.withOpacity(0.5),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar(bool isDesktop) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: const Color(0x55182236),
            border: Border.all(color: const Color(0x33FFFFFF)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.search_rounded,
                size: 18,
                color: Color(0xFFA7B1C6),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Rechercher par nom, ID ou marque...',
                    hintStyle: GoogleFonts.inter(
                      color: const Color(0x77A7B1C6),
                      fontSize: 13,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              if (isDesktop) ...[
                _chip(Icons.filter_alt_outlined, 'Filtre'),
                const SizedBox(width: 8),
                _chip(Icons.tune, 'Tri'),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 860;
        if (!isWide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                style: GoogleFonts.inter(
                  color: const Color(0xFFFFB87A),
                  fontSize: 11,
                  letterSpacing: 2.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Unites de surveillance haute precision',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 29,
                  fontWeight: FontWeight.w800,
                  height: 1.08,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: GoogleFonts.inter(
                  color: const Color(0xFFA7B1C6),
                  fontSize: 13,
                ),
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.toUpperCase(),
                    style: GoogleFonts.inter(
                      color: const Color(0xFFFFB87A),
                      fontSize: 11,
                      letterSpacing: 2.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Unites de surveillance haute precision',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      height: 1.05,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Text(
              subtitle,
              style: GoogleFonts.inter(
                color: const Color(0xFFA7B1C6),
                fontSize: 13,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _chip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x221D88E5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x3D7CB8FF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFFAED0FF)),
          const SizedBox(width: 6),
          Text(
            text,
            style: GoogleFonts.inter(
              color: const Color(0xFFD2E6FF),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String error) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0x33C62828),
        border: Border.all(color: const Color(0x66EF5350)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFFF8A80),
            size: 34,
          ),
          const SizedBox(height: 8),
          Text(
            'Erreur de chargement des machines',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: const Color(0xFFFFCDD2),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: _reloadMachines,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6E00),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.refresh),
            label: const Text('Reessayer'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0x33212A43),
        border: Border.all(color: const Color(0x3DA7B1C6)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.inventory_2_outlined,
            color: Color(0xFFA7B1C6),
            size: 34,
          ),
          const SizedBox(height: 8),
          Text(
            'Aucune machine disponible pour le moment.',
            style: GoogleFonts.inter(color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(
    List<Map<String, dynamic>> machines, {
    required int crossAxisCount,
  }) {
    return GridView.builder(
      itemCount: machines.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: crossAxisCount == 1 ? 1.18 : 1.02,
      ),
      itemBuilder: (_, i) => _MachineCard(machine: machines[i]),
    );
  }

  Widget _buildRealtimeAnalytics(bool isDesktop) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0x44182236),
        border: Border.all(color: const Color(0x3DFFFFFF)),
      ),
      child:
          isDesktop
              ? Row(
                children: [
                  Expanded(child: _analyticsText()),
                  const SizedBox(width: 14),
                  Expanded(child: _analyticsVisual()),
                ],
              )
              : Column(
                children: [
                  _analyticsText(),
                  const SizedBox(height: 14),
                  _analyticsVisual(),
                ],
              ),
    );
  }

  Widget _analyticsText() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Analyse Cinetique en Temps Reel',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 28,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Suivi vibration, temperature et rendement pour anticiper les pannes.',
          style: GoogleFonts.inter(
            color: const Color(0xFFA7B1C6),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _metricBox('0.02ms', 'Temps de cycle'),
            const SizedBox(width: 8),
            _metricBox('99.9%', 'Fiabilite modele'),
          ],
        ),
      ],
    );
  }

  Widget _analyticsVisual() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 1.5,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              'https://images.unsplash.com/photo-1518770660439-4636190af475?auto=format&fit=crop&w=1200&q=80',
              fit: BoxFit.cover,
            ),
            Container(color: Colors.black.withOpacity(0.35)),
            const Center(
              child: CircleAvatar(
                radius: 28,
                backgroundColor: Color(0xFFFF6E00),
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 34,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricBox(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: const Color(0x33111A2F),
          border: Border.all(color: const Color(0x33FFFFFF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: GoogleFonts.inter(
                color: const Color(0xFFFFB87A),
                fontWeight: FontWeight.w800,
                fontSize: 19,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label.toUpperCase(),
              style: GoogleFonts.inter(
                color: const Color(0xFFA7B1C6),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.only(top: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x33FFFFFF))),
      ),
      child: Text(
        '© 2026 Predictive Cloud. Confidentialite • Conditions • Support',
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(color: const Color(0x77A7B1C6), fontSize: 11),
      ),
    );
  }
}

class _EntranceItem extends StatefulWidget {
  const _EntranceItem({
    required this.animateIn,
    required this.child,
    this.delayMs = 0,
  });

  final bool animateIn;
  final Widget child;
  final int delayMs;

  @override
  State<_EntranceItem> createState() => _EntranceItemState();
}

class _EntranceItemState extends State<_EntranceItem> {
  bool _visible = false;

  @override
  void didUpdateWidget(covariant _EntranceItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.animateIn && widget.animateIn) {
      _runAnimation();
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.animateIn) {
      _runAnimation();
    }
  }

  Future<void> _runAnimation() async {
    if (widget.delayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: widget.delayMs));
    }
    if (!mounted) return;
    setState(() {
      _visible = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      offset: _visible ? Offset.zero : const Offset(0, 0.08),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
        opacity: _visible ? 1 : 0,
        child: widget.child,
      ),
    );
  }
}

class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  _StickyHeaderDelegate({
    required this.minHeight,
    required this.maxHeight,
    required this.child,
  });

  final double minHeight;
  final double maxHeight;
  final Widget child;

  @override
  double get minExtent => minHeight;

  @override
  double get maxExtent => maxHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: Colors.transparent,
      alignment: Alignment.center,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _StickyHeaderDelegate oldDelegate) {
    return oldDelegate.minHeight != minHeight ||
        oldDelegate.maxHeight != maxHeight ||
        oldDelegate.child != child;
  }
}

class _MachineCard extends StatefulWidget {
  const _MachineCard({required this.machine});

  final Map<String, dynamic> machine;

  @override
  State<_MachineCard> createState() => _MachineCardState();
}

class _MachineCardState extends State<_MachineCard> {
  bool _isHovered = false;

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

  @override
  Widget build(BuildContext context) {
    final machine = widget.machine;
    final machineId =
        (machine['machineId'] ?? machine['_id'] ?? machine['id'] ?? '')
            .toString();
    final name = (machine['name'] ?? machine['model'] ?? machineId).toString();
    final brand = (machine['brand'] ?? machine['marque'] ?? '').toString();
    final description =
        (machine['description'] ?? machine['type'] ?? 'Machine industrielle')
            .toString();
    final price = (machine['price'] ?? machine['prix'] ?? '').toString();
    final imageUrl = _normalizeMachineImageValue(
      (machine['imageUrl'] ?? machine['image'] ?? machine['photo'] ?? '')
          .toString(),
    );
    final status = _normalizeStatus(
      (machine['status'] ?? machine['etat'] ?? machine['state'] ?? 'disponible')
          .toString(),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.015 : 1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xE61B2238), Color(0xE6151B2E)],
            ),
            border: Border.all(
              color:
                  _isHovered
                      ? const Color(0x66FFB87A)
                      : const Color(0x3DFFFFFF),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(
                  0xFF000000,
                ).withOpacity(_isHovered ? 0.28 : 0.18),
                blurRadius: _isHovered ? 24 : 12,
                offset: Offset(0, _isHovered ? 12 : 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 16 / 7.2,
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
                                  imageUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _fallbackBanner(),
                                )),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _statusColor(status),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _statusLabel(status),
                    style: GoogleFonts.inter(
                      color: _statusColor(status),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                name.isEmpty ? 'Machine' : name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                machineId.isEmpty ? 'ID: -' : 'ID: $machineId',
                style: GoogleFonts.inter(
                  color: const Color(0xFFA7B1C6),
                  fontSize: 12,
                ),
              ),
              if (brand.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  'Marque: $brand',
                  style: GoogleFonts.inter(
                    color: const Color(0xFFA7B1C6),
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: const Color(0xFFD5DDF0),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const Spacer(),
              if (price.isNotEmpty)
                Text(
                  'Prix: $price',
                  style: GoogleFonts.inter(
                    color: const Color(0xFFFFBE86),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) => MachineDetailProPage(
                                    machine: machine,
                                  ),
                            ),
                          ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0x557AA7E8)),
                        foregroundColor: const Color(0xFFD7E7FF),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ).copyWith(
                        overlayColor: WidgetStateProperty.all(
                          const Color(0x337AA7E8),
                        ),
                      ),
                      child: const Text('Voir detail'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed:
                          () => _buyMachine(context, machineId: machineId),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6E00),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ).copyWith(
                        overlayColor: WidgetStateProperty.all(
                          Colors.white.withOpacity(0.12),
                        ),
                        shadowColor: WidgetStateProperty.all(
                          const Color(0xFFFF6E00).withOpacity(0.4),
                        ),
                      ),
                      child: const Text('Acheter'),
                    ),
                  ),
                ],
              ),
            ],
          ),
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
          size: 34,
        ),
      ),
    );
  }

  void _showMachineDetails(
    BuildContext context,
    String name,
    String machineId,
  ) {
    showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A2E),
            title: Text(
              name.isEmpty ? 'Machine' : name,
              style: GoogleFonts.inter(color: Colors.white),
            ),
            content: SingleChildScrollView(
              child: Text(
                const JsonEncoder.withIndent('  ').convert(widget.machine),
                style: GoogleFonts.inter(
                  color: const Color(0xFFD8E0F1),
                  fontSize: 12,
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fermer'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _buyMachine(context, machineId: machineId);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6E00),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Acheter'),
              ),
            ],
          ),
    );
  }

  Future<void> _buyMachine(BuildContext context, {String machineId = ''}) async {
    if (machineId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Machine invalide.')),
      );
      return;
    }
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final mapCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    final approved = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Demande d\'achat'),
            content: SizedBox(
              width: 430,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Nom complet'),
                    ),
                    TextField(
                      controller: emailCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Email (optionnel)',
                      ),
                    ),
                    TextField(
                      controller: phoneCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Telephone (optionnel)',
                      ),
                    ),
                    TextField(
                      controller: locationCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Localisation',
                      ),
                    ),
                    TextField(
                      controller: mapCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Lien Google Maps (optionnel)',
                      ),
                    ),
                    TextField(
                      controller: noteCtrl,
                      minLines: 2,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Note'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Envoyer'),
              ),
            ],
          ),
    );

    if (!mounted) return;
    if (approved != true) return;
    if (nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le nom est obligatoire.')),
      );
      return;
    }
    try {
      await ApiService.createPurchaseRequest({
        'machineId': machineId,
        'machineName': (widget.machine['name'] ?? '').toString(),
        'requesterName': nameCtrl.text.trim(),
        'requesterEmail': emailCtrl.text.trim(),
        'requesterPhone': phoneCtrl.text.trim(),
        'location': locationCtrl.text.trim(),
        'googleMapsUrl': mapCtrl.text.trim(),
        'note': noteCtrl.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Demande envoyee au Concepteur pour validation et creation du client.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Echec envoi demande: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _normalizeStatus(String raw) {
    final value = raw.toLowerCase().trim();
    if (value.contains('maintenance')) return 'maintenance';
    if (value.contains('indispo') || value.contains('offline')) {
      return 'indisponible';
    }
    return 'disponible';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'maintenance':
        return const Color(0xFFFFB74D);
      case 'indisponible':
        return const Color(0xFFE57373);
      default:
        return const Color(0xFF81C784);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'maintenance':
        return 'EN MAINTENANCE';
      case 'indisponible':
        return 'INDISPONIBLE';
      default:
        return 'DISPONIBLE';
    }
  }
}
