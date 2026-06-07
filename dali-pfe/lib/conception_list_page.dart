import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'add_concepteur_page.dart';
import 'services/api_service.dart';

/// Hub Conception : concepteurs (maintenance machine) + documents (`/api/conceptions`).
class ConceptionListPage extends StatefulWidget {
  final VoidCallback onAddConception;

  /// Si défini (ex. dashboard) : ouvre le formulaire d’ajout dans le shell, comme les techniciens.
  final VoidCallback? onAddConcepteur;

  /// Édition embarquée dashboard (évite une route vide sans données).
  final void Function(Map<String, dynamic> initial)? onEditConcepteur;

  /// 0 = concepteurs, 1 = documents
  final int initialTabIndex;

  const ConceptionListPage({
    super.key,
    required this.onAddConception,
    this.onAddConcepteur,
    this.onEditConcepteur,
    this.initialTabIndex = 0,
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

  late Future<List<Map<String, dynamic>>> _concepteursFuture;

  @override
  void initState() {
    super.initState();
    _concepteursFuture = ApiService.getConcepteurs();
  }

  void _reloadConcepteurs() {
    setState(() {
      _concepteursFuture = ApiService.getConcepteurs();
    });
  }

  Future<void> _openAddConcepteur({Map<String, dynamic>? initial}) async {
    if (initial != null && widget.onEditConcepteur != null) {
      widget.onEditConcepteur!(Map<String, dynamic>.from(initial));
      return;
    }
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

  Future<void> _deleteConcepteur(Map<String, dynamic> r) async {
    final username = (r['username'] ?? r['nom'] ?? '—').toString();
    final id = r['id']?.toString() ?? '';
    if (id.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _surface,
        title: Text('Supprimer $username?', style: GoogleFonts.inter(color: Colors.white)),
        content: const Text(
          'Cela supprimera définitivement le compte du concepteur.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ANNULER', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('SUPPRIMER', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ApiService.deleteConcepteur(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Concepteur $username supprimé')),
        );
        _reloadConcepteurs();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Widget _concepteurCard(Map<String, dynamic> r, bool isDesktop) {
    final username = (r['username'] ?? r['nom'] ?? '—').toString();
    final email = (r['email'] ?? '—').toString();
    final location = (r['location'] ?? r['adresse'] ?? '').toString().trim();
    final spec = (r['specialite'] ?? r['specialization'] ?? '').toString().trim();
    final id = r['id']?.toString() ?? '';
    final initial = username.isNotEmpty && username != '—'
        ? username.substring(0, 1).toUpperCase()
        : '?';

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _openAddConcepteur(initial: r),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _primary,
                              _primary.withOpacity(0.6),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _primary.withOpacity(0.3),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            initial,
                            style: GoogleFonts.spaceGrotesk(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 22,
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => _deleteConcepteur(r),
                        icon: Icon(Icons.delete_outline, color: Colors.redAccent.withOpacity(0.6), size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.email_outlined, size: 14, color: _onVariant.withOpacity(0.6)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.spaceGrotesk(fontSize: 13, color: _onVariant.withOpacity(0.7)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 12),
                  if (location.isNotEmpty) ...[
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined, size: 14, color: _secondary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            location,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.spaceGrotesk(fontSize: 12, color: _onSurface.withOpacity(0.85)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (spec.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _secondary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _secondary.withOpacity(0.3)),
                      ),
                      child: Text(
                        spec.toUpperCase(),
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 10,
                          color: _secondary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width > 900;
    return Container(
      color: _bg,
      child: _buildConcepteursTab(isDesktop),
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
          child: Builder(builder: (context) {
            final screenWidth = MediaQuery.sizeOf(context).width;
            final aspect = isDesktop ? 1.4 : (screenWidth < 400 ? 1.15 : 1.4);
            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(24, 24, 24, isDesktop ? 24 : 100),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // — Responsive header layout
                      Builder(builder: (context) {
                        final w = screenWidth;
                        final titleFontSize = w < 380 ? 18.0 : w < 600 ? 22.0 : isDesktop ? 32.0 : 26.0;
                        final subtitleFontSize = w < 380 ? 11.0 : 13.0;
                        final labelFontSize = w < 380 ? 9.0 : 11.0;
                        final btnLabel = w < 380 ? 'AJOUTER' : 'NOUVEAU CONCEPTEUR';

                        final titleBlock = Column(
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
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: titleFontSize,
                                fontWeight: FontWeight.w800,
                                color: _onSurface,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Comptes chargés de la maintenance et de la conception des machines.',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: subtitleFontSize,
                                color: _onVariant,
                                height: 1.4,
                              ),
                            ),
                          ],
                        );

                        final addBtn = FilledButton.icon(
                          onPressed: () => _openAddConcepteur(),
                          style: FilledButton.styleFrom(
                            backgroundColor: _primary,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              horizontal: w < 380 ? 12 : 20,
                              vertical: w < 380 ? 10 : 16,
                            ),
                          ),
                          icon: const Icon(Icons.person_add_alt_1, size: 18),
                          label: Text(
                            btnLabel,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              fontSize: labelFontSize,
                              letterSpacing: 1.2,
                            ),
                          ),
                        );

                        if (w < 600) {
                          // Mobile: stack vertically
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: titleBlock),
                                  addBtn,
                                ],
                              ),
                            ],
                          );
                        }

                        // Tablet / Desktop: side by side
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: titleBlock),
                            const SizedBox(width: 16),
                            addBtn,
                          ],
                        );
                      }),
                      const SizedBox(height: 32),
                      if (rows.isEmpty)
                        _emptyBox(
                          icon: Icons.engineering_outlined,
                          title: 'Aucun concepteur',
                          subtitle: 'Créez un compte avec le bouton ci-dessus.',
                        )
                      else
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: rows.length,
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: isDesktop ? 3 : (screenWidth > 600 ? 2 : 1),
                            crossAxisSpacing: 20,
                            mainAxisSpacing: 20,
                            childAspectRatio: aspect,
                          ),
                          itemBuilder: (context, i) => _concepteurCard(rows[i], isDesktop),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
          }),
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
