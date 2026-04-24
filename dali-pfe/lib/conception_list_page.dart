import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'add_concepteur_page.dart';
import 'services/api_service.dart';

/// Hub Conception : concepteurs (maintenance machine) + documents (`/api/conceptions`).
class ConceptionListPage extends StatefulWidget {
  final VoidCallback onAddConception;

  /// Si défini (ex. dashboard) : ouvre le formulaire d’ajout dans le shell, comme les techniciens.
  final VoidCallback? onAddConcepteur;

  const ConceptionListPage({
    super.key,
    required this.onAddConception,
    this.onAddConcepteur,
  });

  @override
  State<ConceptionListPage> createState() => _ConceptionListPageState();
}

class _ConceptionListPageState extends State<ConceptionListPage> {
  static const _bg = Color(0xFF10102B);
  static const _surface = Color(0xFF1D1D38);
  static const _onSurface = Color(0xFFE2DFFF);
  static const _onVariant = Color(0xFFE2BFB0);
  static const _primary = Color(0xFFFF6E00);
  static const _secondary = Color(0xFF75D1FF);

  late Future<List<Map<String, dynamic>>> _docsFuture;
  late Future<List<Map<String, dynamic>>> _concepteursFuture;

  @override
  void initState() {
    super.initState();
    _docsFuture = ApiService.getConceptions();
    _concepteursFuture = ApiService.getConcepteurs();
  }

  void _reloadDocs() {
    setState(() {
      _docsFuture = ApiService.getConceptions();
    });
  }

  void _reloadConcepteurs() {
    setState(() {
      _concepteursFuture = ApiService.getConcepteurs();
    });
  }

  Future<void> _openAddConcepteur({Map<String, dynamic>? initial}) async {
    if (initial == null && widget.onAddConcepteur != null) {
      widget.onAddConcepteur!();
      return;
    }
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AddConcepteurPage(initialData: initial),
      ),
    );
    if (ok == true && mounted) _reloadConcepteurs();
  }

  String _companyName(Map<String, dynamic> row) {
    final c = row['company'];
    if (c is Map && c['name'] != null) return c['name'].toString();
    return '—';
  }

  String _clientLabel(Map<String, dynamic> row) {
    final n = row['clientName'];
    if (n != null && n.toString().isNotEmpty) return n.toString();
    return _companyName(row);
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width > 900;

    return DefaultTabController(
      length: 2,
      child: Container(
        color: _bg,
        child: Column(
          children: [
            Material(
              color: _surface,
              child: TabBar(
                labelColor: _primary,
                unselectedLabelColor: _onVariant.withOpacity(0.85),
                indicatorColor: _primary,
                labelStyle: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.2),
                unselectedLabelStyle: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600, fontSize: 11, letterSpacing: 1.2),
                tabs: const [
                  Tab(text: 'CONCEPTEURS'),
                  Tab(text: 'DOCUMENTS'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildConcepteursTab(isDesktop),
                  _buildDocumentsTab(isDesktop),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConcepteursTab(bool isDesktop) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _concepteursFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _primary));
        }
        if (snapshot.hasError) {
          return _errorState(
            title: 'Impossible de charger les concepteurs.',
            error: snapshot.error,
            onRetry: _reloadConcepteurs,
          );
        }

        final rows = snapshot.data ?? [];

        return RefreshIndicator(
          color: _primary,
          onRefresh: () async {
            final f = ApiService.getConcepteurs();
            setState(() => _concepteursFuture = f);
            await f;
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(24, 24, 24, isDesktop ? 24 : 100),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'CONCEPTION',
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: _primary,
                                    letterSpacing: 2,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Concepteurs',
                                  style: GoogleFonts.inter(
                                    fontSize: isDesktop ? 32 : 26,
                                    fontWeight: FontWeight.w800,
                                    color: _onSurface,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Comptes chargés de la maintenance et de la conception des machines.',
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 13,
                                    color: _onVariant,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          FilledButton.icon(
                            onPressed: () => _openAddConcepteur(),
                            style: FilledButton.styleFrom(
                              backgroundColor: _primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            ),
                            icon: const Icon(Icons.person_add_alt_1, size: 20),
                            label: Text(
                              'NOUVEAU CONCEPTEUR',
                              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.2),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      if (rows.isEmpty)
                        _emptyBox(
                          icon: Icons.engineering_outlined,
                          title: 'Aucun concepteur',
                          subtitle: 'Créez un compte avec le bouton ci-dessus (super-admin).',
                        )
                      else
                        LayoutBuilder(
                          builder: (context, c) {
                            final w = c.maxWidth;
                            final cols = w > 1100 ? 3 : (w > 700 ? 2 : 1);
                            return GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cols,
                                mainAxisSpacing: 16,
                                crossAxisSpacing: 16,
                                childAspectRatio: cols == 1 ? 1.45 : 1.25,
                              ),
                              itemCount: rows.length,
                              itemBuilder: (context, i) {
                                final r = rows[i];
                                final username = (r['username'] ?? '—').toString();
                                final email = (r['email'] ?? '—').toString();
                                final spec = (r['specialite'] ?? '').toString();
                                return Material(
                                  color: _surface,
                                  borderRadius: BorderRadius.circular(12),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () => _openAddConcepteur(initial: r),
                                    child: Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(Icons.precision_manufacturing_outlined, color: _secondary, size: 22),
                                              const Spacer(),
                                              IconButton(
                                                tooltip: 'Modifier',
                                                onPressed: () => _openAddConcepteur(initial: r),
                                                icon: Icon(Icons.edit_outlined, color: _onVariant.withOpacity(0.9), size: 20),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            username,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.inter(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              color: _onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            email,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.spaceGrotesk(fontSize: 12, color: _onVariant),
                                          ),
                                          const Spacer(),
                                          if (spec.isNotEmpty)
                                            Text(
                                              spec,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.spaceGrotesk(
                                                fontSize: 11,
                                                color: _secondary.withOpacity(0.9),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDocumentsTab(bool isDesktop) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _docsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _primary));
        }
        if (snapshot.hasError) {
          return _errorState(
            title: 'Impossible de charger les conceptions.',
            error: snapshot.error,
            onRetry: _reloadDocs,
          );
        }

        final rows = snapshot.data ?? [];

        return RefreshIndicator(
          color: _primary,
          onRefresh: () async {
            final f = ApiService.getConceptions();
            setState(() => _docsFuture = f);
            await f;
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(24, 24, 24, isDesktop ? 24 : 100),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'CONCEPTION',
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: _primary,
                                    letterSpacing: 2,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Éléments de conception',
                                  style: GoogleFonts.inter(
                                    fontSize: isDesktop ? 32 : 26,
                                    fontWeight: FontWeight.w800,
                                    color: _onSurface,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Plans, schémas, rapports et manuels liés à un client pilote.',
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 13,
                                    color: _onVariant,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          FilledButton.icon(
                            onPressed: widget.onAddConception,
                            style: FilledButton.styleFrom(
                              backgroundColor: _primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            ),
                            icon: const Icon(Icons.add, size: 20),
                            label: Text(
                              'NOUVEL ÉLÉMENT',
                              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.2),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      if (rows.isEmpty)
                        _emptyBox(
                          icon: Icons.folder_open_outlined,
                          title: 'Aucun élément pour l’instant',
                          subtitle: 'Créez un plan, un schéma ou un rapport avec le bouton ci-dessus.',
                        )
                      else
                        LayoutBuilder(
                          builder: (context, c) {
                            final w = c.maxWidth;
                            final cols = w > 1100 ? 3 : (w > 700 ? 2 : 1);
                            return GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cols,
                                mainAxisSpacing: 16,
                                crossAxisSpacing: 16,
                                childAspectRatio: cols == 1 ? 1.35 : 1.15,
                              ),
                              itemCount: rows.length,
                              itemBuilder: (context, i) {
                                final r = rows[i];
                                final name = (r['name'] ?? 'Sans titre').toString();
                                final version = (r['version'] ?? '—').toString();
                                final docType = (r['documentType'] ?? '—').toString();
                                final status = (r['status'] ?? '—').toString();
                                return Material(
                                  color: _surface,
                                  borderRadius: BorderRadius.circular(12),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () {},
                                    child: Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(Icons.description_outlined, color: _secondary, size: 22),
                                              const Spacer(),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: _secondary.withOpacity(0.12),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  status,
                                                  style: GoogleFonts.spaceGrotesk(
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.bold,
                                                    color: _secondary,
                                                    letterSpacing: 0.8,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.inter(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              color: _onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            docType,
                                            style: GoogleFonts.spaceGrotesk(fontSize: 12, color: _onVariant),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const Spacer(),
                                          const Divider(color: Color(0xFF32324e), height: 20),
                                          Row(
                                            children: [
                                              Icon(Icons.business_outlined, size: 14, color: _onVariant.withOpacity(0.7)),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  _clientLabel(r),
                                                  style: GoogleFonts.spaceGrotesk(fontSize: 11, color: _onVariant),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Text(
                                                version,
                                                style: GoogleFonts.spaceGrotesk(
                                                  fontSize: 10,
                                                  color: _onVariant.withOpacity(0.8),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _errorState({
    required String title,
    required Object? error,
    required VoidCallback onRetry,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 48, color: _onVariant.withOpacity(0.6)),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.inter(color: _onSurface, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '$error',
              style: GoogleFonts.spaceGrotesk(fontSize: 12, color: _onVariant),
              textAlign: TextAlign.center,
            ),
            if ('$error'.contains('404'))
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Lancez le backend « iot-backend » avec server.js (npm start, port 3001), pas un autre script sur le même port.',
                  style: GoogleFonts.spaceGrotesk(fontSize: 11, color: _onSurface, height: 1.35),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              style: FilledButton.styleFrom(backgroundColor: _primary, foregroundColor: Colors.white),
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyBox({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _onVariant.withOpacity(0.12)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 40, color: _onVariant.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text(
            title,
            style: GoogleFonts.inter(color: _onSurface, fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: GoogleFonts.spaceGrotesk(fontSize: 13, color: _onVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
