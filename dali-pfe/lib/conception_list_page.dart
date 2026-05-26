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

  Widget _concepteurListTile(Map<String, dynamic> r) {
    final username = (r['username'] ?? r['nom'] ?? '—').toString();
    final email = (r['email'] ?? '—').toString();
    final location = (r['location'] ?? r['adresse'] ?? '').toString().trim();
    final spec = (r['specialite'] ?? r['specialization'] ?? '').toString().trim();
    final id = r['id']?.toString() ?? '';
    final initial = username.isNotEmpty && username != '—'
        ? username.substring(0, 1).toUpperCase()
        : '?';

    return Dismissible(
      key: Key('concepteur-$id'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        await _deleteConcepteur(r);
        return false; // On gère le rechargement via _reloadConcepteurs
      },
      child: Material(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openAddConcepteur(initial: r),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: _primary.withValues(alpha: 0.15),
                  child: Text(
                    initial,
                    style: GoogleFonts.spaceGrotesk(
                      color: _primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.spaceGrotesk(fontSize: 12, color: _onVariant),
                      ),
                      if (location.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.location_on_outlined, size: 13, color: _onVariant.withValues(alpha: 0.8)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                location,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.spaceGrotesk(fontSize: 11, color: _onVariant.withValues(alpha: 0.85)),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (spec.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _secondary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            spec,
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 10,
                              color: _secondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Modifier',
                  onPressed: () => _openAddConcepteur(initial: r),
                  icon: Icon(Icons.edit_outlined, color: _onVariant.withValues(alpha: 0.9), size: 22),
                ),
              ],
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
                          subtitle: 'Créez un compte avec le bouton ci-dessus.',
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: rows.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, i) => _concepteurListTile(rows[i]),
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
