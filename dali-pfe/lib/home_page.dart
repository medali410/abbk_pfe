import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'client_dashboard_page.dart';
import 'login_page.dart';
import 'machine_detail_pro_page.dart';
import 'services/api_service.dart';
import 'utils/catalog_list_utils.dart';
import 'utils/client_auth_gate.dart';
import 'widgets/hero_looping_video_background.dart';

class HomePage extends StatefulWidget {
  final String? initialSection;
  const HomePage({super.key, this.initialSection});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<Map<String, dynamic>>> _machinesFuture;
  bool _animateIn = false;
  bool _canBuyAsClient = false;
  String _searchQuery = '';
  String? _catalogStatusFilter;
  String? _catalogBrandFilter;
  CatalogSortOption? _catalogSort;
  CatalogToolbarPanel _catalogPanel = CatalogToolbarPanel.none;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _homeSectionKey = GlobalKey();
  final GlobalKey _catalogSectionKey = GlobalKey();
  final GlobalKey _footerSectionKey = GlobalKey();
  String _activeSection = 'home';

  @override
  void initState() {
    super.initState();
    _machinesFuture = ApiService.getMachinesForHomeCatalog();
    _consumeGoogleOAuthReturnIfPresent();
    _hydrateAuthState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _animateIn = true;
      });
      // Handle initial scroll to section
      if (widget.initialSection == 'catalog') {
        _scrollToSection(_catalogSectionKey);
      }
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

  Future<void> _hydrateAuthState() async {
    await ApiService.loadSavedAuth();
    if (!mounted) return;
    final role = (ApiService.savedUserRole ?? '').toLowerCase().trim();
    final token = (ApiService.authToken ?? '').trim();
    setState(() {
      _canBuyAsClient = token.isNotEmpty && role == 'client';
    });
  }


  Future<void> _consumeGoogleOAuthReturnIfPresent() async {
    if (!kIsWeb) return;
    final qp = _readMergedWebQueryParams();
    if (qp['googleAuth'] == null) return;
    if (qp['googleAuth'] != '1') {
      final msg = (qp['error'] ?? 'Connexion Google refusée').trim();
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      });
      return;
    }

    final token = (qp['token'] ?? '').trim();
    var role = (qp['role'] ?? 'client').trim().toLowerCase();
    final oauthEmail = (qp['email'] ?? '').trim();
    if (ApiService.shouldOpenMaintenanceDashboard(oauthEmail)) {
      role = 'maintenance';
    } else if (ApiService.shouldOpenConcepteurDashboard(oauthEmail)) {
      role = 'concepteur';
    }
    if (token.isEmpty) return;

    await ApiService.saveAuth(token, role);

    if (role == 'super_admin') role = 'superadmin';
    if (role == 'company_admin') role = 'admin';

    if (role == 'technician') {
      final profile = ApiService.technicianProfileFromOAuthParams(qp);
      await ApiService.clearStoredClientSession();
      await ApiService.saveTechnicianSession(profile);
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/technician-profile', arguments: profile);
      });
      return;
    }
    if (role == 'maintenance') {
      await ApiService.clearStoredClientSession();
      await ApiService.clearSavedTechnicianProfile();
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/maintenance-dashboard');
      });
      return;
    }
    if (role == 'conception' || role == 'concepteur') {
      await ApiService.clearStoredClientSession();
      await ApiService.saveConcepteurSession({
        'email': oauthEmail,
        'name': (qp['name'] ?? '').trim(),
        'nom': (qp['name'] ?? '').trim(),
        'concepteurId': (qp['concepteurId'] ?? qp['id'] ?? '').toString(),
        'id': (qp['id'] ?? '').toString(),
        'adresse': (qp['adresse'] ?? '').trim(),
        'location': (qp['location'] ?? '').trim(),
      });
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/concepteur-dashboard');
      });
      return;
    }
    if (role == 'superadmin' || role == 'admin') {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/dashboard');
      });
      return;
    }

    await ApiService.saveClientSession(
      clientId: (qp['clientId'] ?? '').trim(),
      clientName: (qp['name'] ?? 'Client').trim(),
      clientEmail: (qp['email'] ?? '').trim(),
      clientLocation: (qp['location'] ?? '').trim(),
      clientPhotoUrl:
          (qp['photoUrl'] ??
                  qp['avatarUrl'] ??
                  qp['profilePhotoUrl'] ??
                  qp['imageUrl'] ??
                  qp['image'] ??
                  '')
              .trim(),
    );

    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder:
              (_) => ClientDashboardPage(
                clientName: (ApiService.savedClientName ?? 'Espace client').trim(),
                clientId: (ApiService.savedClientId ?? '').trim(),
                clientData: {
                  'clientId': (ApiService.savedClientId ?? '').trim(),
                  'id': (ApiService.savedClientId ?? '').trim(),
                  'name': (ApiService.savedClientName ?? 'Espace client').trim(),
                  'email': (ApiService.savedClientEmail ?? '').trim(),
                  'location': (ApiService.savedClientLocation ?? '').trim(),
                  'photoUrl': (ApiService.savedClientPhotoUrl ?? '').trim(),
                },
              ),
        ),
      );
    });
  }

  Map<String, String> _readMergedWebQueryParams() {
    final params = <String, String>{...Uri.base.queryParameters};
    final frag = Uri.base.fragment;
    if (frag.contains('?')) {
      final fragQuery = frag.split('?').skip(1).join('?');
      params.addAll(Uri.splitQueryString(fragQuery));
    }
    return params;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1100;
    final isTablet = width >= 760;
    final isMobile = width < 760;
    final isNarrow = width < 400;
    final stackedHeader = width < 980;
    final tightHeader = width < 560;
    final stickyHeaderHeight = !stackedHeader
        ? 78.0
        : (isNarrow ? 118.0 : 128.0);

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
              final filteredMachines = filterAndSortCatalogMachines(
                machines,
                searchQuery: _searchQuery,
                statusFilter: _catalogStatusFilter,
                brandFilter: _catalogBrandFilter,
                sort: _catalogSort,
              );
              final padding =
                  isDesktop ? 44.0 : (isTablet ? 26.0 : (isNarrow ? 12.0 : 16.0));
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
                              minHeight: stickyHeaderHeight,
                              maxHeight: stickyHeaderHeight,
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
                                        isMobile: isMobile,
                                        isNarrow: isNarrow,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  _buildEntrance(
                                    delayMs: 95,
                                    child: _buildToolbar(
                                      compact: isMobile,
                                      allMachines: machines,
                                    ),
                                  ),
                                  const SizedBox(height: 18),
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
                                    KeyedSubtree(
                                      key: _catalogSectionKey,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: (() {
                                          final Map<String, List<Map<String, dynamic>>> grouped = {};
                                          for (var m in filteredMachines) {
                                            final cName = (m['concepteurName'] ?? 'Inconnu').toString();
                                            if (!grouped.containsKey(cName)) grouped[cName] = [];
                                            grouped[cName]!.add(m);
                                          }
                                          return grouped.entries.map((entry) {
                                            return Padding(
                                              padding: const EdgeInsets.only(bottom: 30),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                                children: [
                                                  _buildEntrance(
                                                    delayMs: 105,
                                                    child: _buildSectionHeader(
                                                      title: 'Catalogue des systemes',
                                                      subtitle: '${entry.value.length} machine(s) affichee(s)',
                                                      largeTitle: 'Concepteur ${entry.key}',
                                                    ),
                                                  ),
                                                  const SizedBox(height: 14),
                                                  _buildEntrance(
                                                    delayMs: 120,
                                                    child: _buildGrid(
                                                      entry.value,
                                                      crossAxisCount: isDesktop ? 3 : (isTablet ? 2 : 1),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }).toList();
                                        })(),
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
    final w = MediaQuery.sizeOf(context).width;
    final showInlineNav = w >= 980;
    final tightHeader = w < 560;
    final logo = Container(
      constraints: BoxConstraints(maxWidth: w < 400 ? 100 : (tightHeader ? 130 : 190)),
      height: tightHeader ? 40 : 46,
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
    );

    final navRow = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildNavItem(
            label: 'Accueil',
            sectionId: 'home',
            baseStyle: navStyle,
            onTap: () {
              _scrollToSection(_homeSectionKey);
              if (ModalRoute.of(context)?.settings.name != '/') {
                Navigator.of(context).pushReplacementNamed('/');
              }
            },
          ),
          const SizedBox(width: 14),
          _buildNavItem(
            label: 'Machines',
            sectionId: 'catalog',
            baseStyle: navStyle,
            onTap: () {
              _scrollToSection(_catalogSectionKey);
              if (ModalRoute.of(context)?.settings.name != '/machines') {
                Navigator.of(context).pushReplacementNamed('/machines');
              }
            },
          ),
        ],
      ),
    );


    final clientBadge =
        _canBuyAsClient
            ? Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0x2238A169),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0x6659D18C)),
              ),
              child:
                  w < 380
                      ? const Icon(
                        Icons.verified_user_rounded,
                        size: 16,
                        color: Color(0xFF8BE9B3),
                      )
                      : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.verified_user_rounded,
                            size: 14,
                            color: Color(0xFF8BE9B3),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Client connecte',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFBEEFD4),
                            ),
                          ),
                        ],
                      ),
            )
            : const SizedBox.shrink();

    Future<void> onAuthPressed() async {
        if (_canBuyAsClient &&
            (ApiService.savedClientId ?? '').trim().isNotEmpty) {
          if (!context.mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder:
                  (_) => ClientDashboardPage(
                    clientName:
                        (ApiService.savedClientName ?? 'Espace client').trim(),
                    clientId: (ApiService.savedClientId ?? '').trim(),
                    clientData: {
                      'name': (ApiService.savedClientName ?? '').trim(),
                      'email': (ApiService.savedClientEmail ?? '').trim(),
                      'location':
                          (ApiService.savedClientLocation ?? '').trim(),
                    },
                  ),
            ),
          );
          return;
        }
        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
        );
        if (result == true) {
          await _hydrateAuthState();
        }
    }

    final connexionButton = ElevatedButton(
      onPressed: onAuthPressed,
      style: ElevatedButton.styleFrom(
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: const Color(0xFFFF6E00),
        foregroundColor: Colors.white,
        elevation: 0,
        padding: EdgeInsets.symmetric(
          horizontal: tightHeader ? 10 : (w < 360 ? 10 : 16),
          vertical: tightHeader ? 8 : 12,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ).copyWith(
        overlayColor: WidgetStateProperty.all(Colors.white.withOpacity(0.12)),
        shadowColor: WidgetStateProperty.all(
          const Color(0xFFFF6E00).withOpacity(0.4),
        ),
      ),
      child: Text(
        _canBuyAsClient ? 'Mon compte' : 'Connexion',
        style: TextStyle(fontSize: tightHeader ? 11 : (w < 360 ? 12 : 14)),
      ),
    );

    Future<void> onSignUpPressed() async {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => const LoginPage(showSignupTitle: true),
        ),
      );
    }

    final signUpButton = TextButton(
      onPressed: onSignUpPressed,
      style: TextButton.styleFrom(
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        foregroundColor: const Color(0xFFD7E7FF),
      ),
      child: Text(
        "s'inscrire",
        style: GoogleFonts.inter(
          fontSize: tightHeader ? 11 : 12,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
          decorationColor: const Color(0xFFD7E7FF),
        ),
      ),
    );

    final authActions = Row(
      mainAxisSize: MainAxisSize.min,
      textDirection: TextDirection.ltr,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (!_canBuyAsClient) ...[
          signUpButton,
          SizedBox(width: tightHeader ? 4 : 8),
        ],
        connexionButton,
      ],
    );

    Widget authCluster({bool scaleToFit = false}) {
      final cluster = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_canBuyAsClient) clientBadge,
          authActions,
        ],
      );
      if (!scaleToFit) return cluster;
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: cluster,
      );
    }

    if (!showInlineNav) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              logo,
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: authCluster(scaleToFit: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Center(child: navRow),
        ],
      );
    }

    return Row(
      children: [
        logo,
        const SizedBox(width: 24),
        ...[
          _buildNavItem(
            label: 'Accueil',
            sectionId: 'home',
            baseStyle: navStyle,
            onTap: () {
              _scrollToSection(_homeSectionKey);
              if (ModalRoute.of(context)?.settings.name != '/') {
                Navigator.of(context).pushReplacementNamed('/');
              }
            },
          ),
          const SizedBox(width: 14),
          _buildNavItem(
            label: 'Machines',
            sectionId: 'catalog',
            baseStyle: navStyle,
            onTap: () {
              _scrollToSection(_catalogSectionKey);
              if (ModalRoute.of(context)?.settings.name != '/machines') {
                Navigator.of(context).pushReplacementNamed('/machines');
              }
            },
          ),
        ],

        const Spacer(),
        Flexible(
          child: Align(
            alignment: Alignment.centerRight,
            child: authCluster(scaleToFit: w < 1100),
          ),
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

  Widget _buildHero({
    required int total,
    required bool isDesktop,
    required bool isMobile,
    required bool isNarrow,
  }) {
    final heroHeight = isDesktop ? 360.0 : (isNarrow ? 320.0 : 300.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(isMobile ? 14 : 20),
      child: Container(
        height: heroHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: const Color(0xFF141B31),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildHeroVisual(),

            // Couche de lisibilité : sombre à gauche + vignette sur les bords.
            Container(
              decoration: BoxDecoration(
                gradient: isMobile
                    ? const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x99131B32),
                          Color(0xEE131B32),
                          Color(0xF0131B32),
                        ],
                        stops: [0.0, 0.45, 1.0],
                      )
                    : const LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Color(0xEE131B32),
                          Color(0xB3161F38),
                          Color(0x66161F38),
                        ],
                        stops: [0.0, 0.48, 1.0],
                      ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.45, 0.0),
                  radius: 1.1,
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withOpacity(0.35),
                  ],
                  stops: const [0.0, 0.72, 1.0],
                ),
              ),
            ),

            Align(
              alignment:
                  isMobile ? Alignment.bottomCenter : Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.all(isDesktop ? 24 : (isNarrow ? 14 : 18)),
                child: SizedBox(
                  width: isDesktop ? 560 : double.infinity,
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: _buildHeroText(
                      total: total,
                      isDesktop: isDesktop,
                      isMobile: isMobile,
                      isNarrow: isNarrow,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroText({
    required int total,
    required bool isDesktop,
    required bool isMobile,
    required bool isNarrow,
  }) {
    final titleSize = isDesktop ? 38.0 : (isNarrow ? 22.0 : 26.0);
    final align =
        isMobile ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(
          'Catalogue machines',
          textAlign: isMobile ? TextAlign.center : TextAlign.start,
          style: GoogleFonts.inter(
            color: const Color(0xFFFFB87A),
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            fontSize: isNarrow ? 11 : 12,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'L\'efficacite predite par l\'IA',
          textAlign: isMobile ? TextAlign.center : TextAlign.start,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: titleSize,
            fontWeight: FontWeight.w800,
            height: 1.15,
            shadows: const [
              Shadow(
                color: Color(0xC0000000),
                blurRadius: 14,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Visualisez les equipements critiques en temps reel '
          'et accedez aux machines disponibles depuis la base.',
          textAlign: isMobile ? TextAlign.center : TextAlign.start,
          style: GoogleFonts.inter(
            color: const Color(0xFFD5DCEE),
            fontSize: isNarrow ? 12 : 14,
            height: 1.35,
            shadows: const [
              Shadow(
                color: Color(0xAA000000),
                blurRadius: 10,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: isMobile ? WrapAlignment.center : WrapAlignment.start,
          children: [
            _chip(Icons.precision_manufacturing_rounded, '$total machines'),
            _chip(Icons.update_rounded, 'Temps reel'),
          ],
        ),
      ],
    );
  }

  Widget _buildHeroVisual() {
    return const HeroLoopingVideoBackground(
      fallbackImageUrl:
          'https://images.unsplash.com/photo-1565043589221-1a6fd9ae45c7?auto=format&fit=crop&w=1200&q=80',
    );
  }

  Widget _buildToolbar({
    required bool compact,
    required List<Map<String, dynamic>> allMachines,
  }) {
    final searchRow = Row(
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
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: compact ? 12 : 13,
            ),
            decoration: InputDecoration(
              hintText: 'Rechercher par nom, ID ou marque...',
              hintStyle: GoogleFonts.inter(
                color: const Color(0x77A7B1C6),
                fontSize: compact ? 12 : 13,
              ),
              border: InputBorder.none,
              isDense: true,
            ),
          ),
        ),
      ],
    );

    final filterRow = Row(
      children: [
        Expanded(
          child: _chip(
            Icons.filter_alt_outlined,
            _catalogFilterChipLabel(),
            onTap: _toggleCatalogFilterPanel,
            active:
                _catalogPanel == CatalogToolbarPanel.filter ||
                _hasCatalogFilters,
            fillWidth: true,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _chip(
            Icons.tune,
            'Tri',
            onTap: _toggleCatalogSortPanel,
            active:
                _catalogPanel == CatalogToolbarPanel.sort ||
                _catalogSort != null,
            fillWidth: true,
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
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
              child: compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        searchRow,
                        const SizedBox(height: 8),
                        filterRow,
                      ],
                    )
                  : Row(
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
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                            decoration: InputDecoration(
                              hintText:
                                  'Rechercher par nom, ID ou marque...',
                              hintStyle: GoogleFonts.inter(
                                color: const Color(0x77A7B1C6),
                                fontSize: 13,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _chip(
                          Icons.filter_alt_outlined,
                          _catalogFilterChipLabel(),
                          onTap: _toggleCatalogFilterPanel,
                          active:
                              _catalogPanel == CatalogToolbarPanel.filter ||
                              _hasCatalogFilters,
                        ),
                        const SizedBox(width: 8),
                        _chip(
                          Icons.tune,
                          'Tri',
                          onTap: _toggleCatalogSortPanel,
                          active:
                              _catalogPanel == CatalogToolbarPanel.sort ||
                              _catalogSort != null,
                        ),
                      ],
                    ),
            ),
          ),
        ),
        CatalogFilterSortPanel(
            panel: _catalogPanel,
            brands: distinctCatalogBrands(allMachines),
            statusFilter: _catalogStatusFilter,
            brandFilter: _catalogBrandFilter,
            sort: _catalogSort,
            onStatusChanged: (status) {
              setState(() => _catalogStatusFilter = status);
            },
            onBrandChanged: (brand) {
              setState(() => _catalogBrandFilter = brand);
            },
            onSortChanged: (sort) {
              setState(() => _catalogSort = sort);
            },
          ),
      ],
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    String? largeTitle,
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
                largeTitle ?? 'Unites de surveillance haute precision',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: constraints.maxWidth < 400 ? 22 : 26,
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
                      fontSize: 12,
                      letterSpacing: 2.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    largeTitle ?? 'Unites de surveillance haute precision',
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

  bool get _hasCatalogFilters =>
      catalogFilterValueIsActive(_catalogStatusFilter) ||
      catalogFilterValueIsActive(_catalogBrandFilter);

  String _catalogFilterChipLabel() {
    if (!_hasCatalogFilters) return 'Filtre';
    final parts = <String>[];
    final st = catalogStatusFilterLabel(_catalogStatusFilter);
    if (st != null) parts.add(st);
    if (catalogFilterValueIsActive(_catalogBrandFilter)) {
      parts.add(_catalogBrandFilter!);
    }
    return parts.join(' · ');
  }

  void _toggleCatalogFilterPanel() {
    setState(() {
      _catalogPanel = _catalogPanel == CatalogToolbarPanel.filter
          ? CatalogToolbarPanel.none
          : CatalogToolbarPanel.filter;
    });
  }

  void _toggleCatalogSortPanel() {
    setState(() {
      _catalogPanel = _catalogPanel == CatalogToolbarPanel.sort
          ? CatalogToolbarPanel.none
          : CatalogToolbarPanel.sort;
    });
  }

  Widget _chip(
    IconData icon,
    String text, {
    VoidCallback? onTap,
    bool active = false,
    bool fillWidth = false,
  }) {
    final label = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.inter(
        color: const Color(0xFFD2E6FF),
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
    );
    final child = Container(
      width: fillWidth ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: active ? const Color(0x441D88E5) : const Color(0x221D88E5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active ? const Color(0xFF1D88E5) : const Color(0x3D7CB8FF),
        ),
      ),
      child: Row(
        mainAxisSize: fillWidth ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFFAED0FF)),
          const SizedBox(width: 6),
          if (fillWidth) Expanded(child: label) else label,
        ],
      ),
    );
    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: child,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        // Keep cards taller on narrow screens to avoid vertical overflow.
        final singleColumnRatio =
            constraints.maxWidth < 360
                ? 0.64
                : (constraints.maxWidth < 430 ? 0.70 : 0.76);
        final childAspectRatio =
            crossAxisCount == 1
                ? singleColumnRatio
                : (crossAxisCount == 2 ? 0.92 : 1.02);

        return GridView.builder(
          itemCount: machines.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: childAspectRatio,
          ),
          itemBuilder:
              (_, i) => _MachineCard(
                machine: machines[i],
                canBuy: _canBuyAsClient,
                onRequireLogin: () async {
                  final result = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder:
                          (_) =>
                              const LoginPage(returnToHomeAfterClientLogin: true),
                    ),
                  );
                  if (result == true) {
                    await _hydrateAuthState();
                  }
                },
              ),
        );
      },
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
    final w = MediaQuery.sizeOf(context).width;
    final lineStyle = GoogleFonts.inter(
      color: const Color(0x77A7B1C6),
      fontSize: 11,
    );
    return Container(
      padding: const EdgeInsets.only(top: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x33FFFFFF))),
      ),
      child: w < 520
          ? Column(
              children: [
                Text('© 2026 Predictive Cloud', textAlign: TextAlign.center, style: lineStyle),
                const SizedBox(height: 6),
                Text(
                  'Confidentialite • Conditions • Support',
                  textAlign: TextAlign.center,
                  style: lineStyle,
                ),
              ],
            )
          : Text(
              '© 2026 Predictive Cloud. Confidentialite • Conditions • Support',
              textAlign: TextAlign.center,
              style: lineStyle,
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
  const _MachineCard({
    required this.machine,
    required this.canBuy,
    this.onRequireLogin,
  });

  final Map<String, dynamic> machine;
  final bool canBuy;
  final Future<void> Function()? onRequireLogin;

  @override
  State<_MachineCard> createState() => _MachineCardState();
}

class _MachineCardState extends State<_MachineCard> {
  bool _isHovered = false;

  Future<void> _runIfAuthenticated(void Function() action) async {
    final ok = await ensureClientLoggedIn(
      context,
      openLogin: widget.onRequireLogin,
    );
    if (ok && mounted) action();
  }

  Widget _buildCustomTextField({
    required TextEditingController controller,
    required String labelText,
    required IconData icon,
    bool requiredField = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TextField(
        controller: controller,
        style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          labelText: labelText + (requiredField ? ' *' : ''),
          labelStyle: GoogleFonts.inter(color: const Color(0xFFA7B1C6), fontSize: 12),
          prefixIcon: Icon(icon, color: const Color(0xFFFF6E00), size: 18),
          filled: true,
          fillColor: const Color(0x22111A2F),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0x22FFFFFF)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFFF6E00)),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }

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
    final name = catalogMachineDisplayName(machine);
    final priceLabel = catalogMachinePriceLabel(machine);
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
              const SizedBox(height: 10),
              Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                priceLabel,
                style: GoogleFonts.inter(
                  color: const Color(0xFFFFBE86),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _runIfAuthenticated(() {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (context) => MachineDetailProPage(
                                  machine: machine,
                                ),
                          ),
                        );
                      }),
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
                      onPressed: () => _runIfAuthenticated(
                        () => _buyMachine(context, machineId: machineId),
                      ),
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
    final linkedClientId = (ApiService.savedClientId ?? '').trim();

    if (linkedClientId.isNotEmpty) {
      nameCtrl.text = (ApiService.savedClientName ?? '').trim();
      emailCtrl.text = (ApiService.savedClientEmail ?? '').trim();
      locationCtrl.text = (ApiService.savedClientLocation ?? '').trim();
    }

    final approved = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => Dialog(
            backgroundColor: const Color(0xFF111A2F),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 450,
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0x33FFFFFF)),
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.all(22),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.shopping_cart_checkout_rounded, color: Color(0xFFFF6E00), size: 24),
                          const SizedBox(width: 10),
                          Text(
                            "Demande d'achat",
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Soumettre une demande d'acquisition pour cet équipement",
                        style: GoogleFonts.inter(
                          color: const Color(0xFFA7B1C6),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _buildCustomTextField(
                        controller: nameCtrl,
                        labelText: 'Nom complet',
                        icon: Icons.person_outline_rounded,
                        requiredField: true,
                      ),
                      _buildCustomTextField(
                        controller: emailCtrl,
                        labelText: 'Email',
                        icon: Icons.email_outlined,
                      ),
                      _buildCustomTextField(
                        controller: phoneCtrl,
                        labelText: 'Téléphone',
                        icon: Icons.phone_android_rounded,
                      ),
                      _buildCustomTextField(
                        controller: locationCtrl,
                        labelText: 'Localisation',
                        icon: Icons.location_on_outlined,
                        requiredField: true,
                      ),
                      _buildCustomTextField(
                        controller: mapCtrl,
                        labelText: 'Lien Google Maps',
                        icon: Icons.map_outlined,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: TextField(
                          controller: noteCtrl,
                          minLines: 2,
                          maxLines: 3,
                          style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Note ou message particulier',
                            labelStyle: GoogleFonts.inter(color: const Color(0xFFA7B1C6), fontSize: 12),
                            prefixIcon: const Icon(Icons.note_alt_outlined, color: Color(0xFFFF6E00), size: 18),
                            filled: true,
                            fillColor: const Color(0x22111A2F),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Color(0x22FFFFFF)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Color(0xFFFF6E00)),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFD7E7FF),
                            ),
                            child: const Text('Annuler'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF6E00),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            ),
                            child: const Text('Envoyer'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
    if (locationCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La localisation est obligatoire.')),
      );
      return;
    }
    try {
      await ApiService.createPurchaseRequest({
        'machineId': machineId,
        'machineName': (widget.machine['name'] ?? '').toString(),
        if (linkedClientId.isNotEmpty) 'linkedClientId': linkedClientId,
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
