import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum CatalogSortOption {
  nameAsc,
  nameDesc,
  brandAsc,
  priceAsc,
  priceDesc,
}

enum CatalogToolbarPanel { none, filter, sort }

/// Valeur interne : aucun filtre actif et aucun bouton statut/marque sélectionné.
const String catalogFilterCleared = '__cleared__';

bool catalogFilterValueIsActive(String? value) =>
    value != null && value.isNotEmpty && value != catalogFilterCleared;

String catalogNormalizeStatus(String raw) {
  final value = raw.toLowerCase().trim();
  if (value.contains('maintenance')) return 'maintenance';
  if (value.contains('indispo') || value.contains('offline')) {
    return 'indisponible';
  }
  return 'disponible';
}

String catalogMachineName(Map<String, dynamic> m) =>
    (m['name'] ?? m['model'] ?? '').toString();

String catalogMachineBrand(Map<String, dynamic> m) =>
    (m['brand'] ?? m['marque'] ?? '').toString();

String catalogMachineId(Map<String, dynamic> m) =>
    (m['machineId'] ?? m['_id'] ?? m['id'] ?? '').toString();

String catalogMachineDisplayName(Map<String, dynamic> m) {
  final name = (m['name'] ?? m['model'] ?? '').toString().trim();
  if (name.isNotEmpty) return name;
  return 'Machine';
}

/// Libellé prix pour les cartes catalogue (toujours affiché).
String catalogMachinePriceLabel(Map<String, dynamic> m) {
  final raw = m['price'] ?? m['prix'];
  if (raw == null) return 'Prix non renseigné';
  if (raw is num) {
    if (raw == 0) return 'Prix non renseigné';
    final v = raw == raw.roundToDouble() ? raw.toInt().toString() : raw.toString();
    return '$v €';
  }
  final s = raw.toString().trim();
  if (s.isEmpty) return 'Prix non renseigné';
  final lower = s.toLowerCase();
  if (lower.contains('€') || lower.contains('eur') || lower.contains('dt')) {
    return s;
  }
  return '$s €';
}

double catalogMachinePrice(Map<String, dynamic> m) {
  final raw = m['price'] ?? m['prix'];
  if (raw is num) return raw.toDouble();
  if (raw is String) {
    final cleaned = raw.replaceAll(RegExp(r'[^\d.,]'), '').replaceAll(',', '.');
    return double.tryParse(cleaned) ?? 0;
  }
  return 0;
}

List<String> distinctCatalogBrands(List<Map<String, dynamic>> machines) {
  final set = <String>{};
  for (final m in machines) {
    final b = catalogMachineBrand(m).trim();
    if (b.isNotEmpty) set.add(b);
  }
  final list = set.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return list;
}

List<Map<String, dynamic>> filterAndSortCatalogMachines(
  List<Map<String, dynamic>> source, {
  required String searchQuery,
  String? statusFilter,
  String? brandFilter,
  CatalogSortOption? sort,
}) {
  final effectiveSort = sort ?? CatalogSortOption.nameAsc;
  final q = searchQuery.toLowerCase().trim();
  final status = statusFilter?.trim();
  final brand = brandFilter?.trim();

  var list = source.where((m) {
    if (catalogFilterValueIsActive(status)) {
      final st = catalogNormalizeStatus(
        (m['status'] ?? m['etat'] ?? m['state'] ?? 'disponible').toString(),
      );
      if (st != status) return false;
    }
    if (catalogFilterValueIsActive(brand)) {
      final activeBrand = brand!;
      if (catalogMachineBrand(m).toLowerCase() != activeBrand.toLowerCase()) {
        return false;
      }
    }
    if (q.isEmpty) return true;
    final machineId = catalogMachineId(m).toLowerCase();
    final name = catalogMachineName(m).toLowerCase();
    final marque = catalogMachineBrand(m).toLowerCase();
    return machineId.contains(q) || name.contains(q) || marque.contains(q);
  }).toList();

  int compareName(Map<String, dynamic> a, Map<String, dynamic> b) {
    final na = catalogMachineName(a).toLowerCase();
    final nb = catalogMachineName(b).toLowerCase();
    final c = na.compareTo(nb);
    if (c != 0) return c;
    return catalogMachineId(a).compareTo(catalogMachineId(b));
  }

  switch (effectiveSort) {
    case CatalogSortOption.nameDesc:
      list.sort((a, b) => compareName(b, a));
      break;
    case CatalogSortOption.brandAsc:
      list.sort((a, b) {
        final c = catalogMachineBrand(a).toLowerCase().compareTo(
          catalogMachineBrand(b).toLowerCase(),
        );
        return c != 0 ? c : compareName(a, b);
      });
      break;
    case CatalogSortOption.priceAsc:
      list.sort((a, b) {
        final c = catalogMachinePrice(a).compareTo(catalogMachinePrice(b));
        return c != 0 ? c : compareName(a, b);
      });
      break;
    case CatalogSortOption.priceDesc:
      list.sort((a, b) {
        final c = catalogMachinePrice(b).compareTo(catalogMachinePrice(a));
        return c != 0 ? c : compareName(a, b);
      });
      break;
    case CatalogSortOption.nameAsc:
      list.sort(compareName);
      break;
  }
  return list;
}

String catalogSortLabel(CatalogSortOption sort) {
  switch (sort) {
    case CatalogSortOption.nameAsc:
      return 'Nom (A → Z)';
    case CatalogSortOption.nameDesc:
      return 'Nom (Z → A)';
    case CatalogSortOption.brandAsc:
      return 'Marque (A → Z)';
    case CatalogSortOption.priceAsc:
      return 'Prix croissant';
    case CatalogSortOption.priceDesc:
      return 'Prix décroissant';
  }
}

String? catalogStatusFilterLabel(String? status) {
  if (!catalogFilterValueIsActive(status)) return null;
  switch (status) {
    case 'indisponible':
      return 'Indisponible';
    default:
      return 'Disponible';
  }
}

/// Panneau filtre / tri affiché sous la barre de recherche (pas de modal).
class CatalogFilterSortPanel extends StatelessWidget {
  const CatalogFilterSortPanel({
    super.key,
    required this.panel,
    required this.brands,
    required this.statusFilter,
    required this.brandFilter,
    required this.sort,
    required this.onStatusChanged,
    required this.onBrandChanged,
    required this.onSortChanged,
  });

  final CatalogToolbarPanel panel;
  final List<String> brands;
  final String? statusFilter;
  final String? brandFilter;
  final CatalogSortOption? sort;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<String?> onBrandChanged;
  final ValueChanged<CatalogSortOption?> onSortChanged;

  @override
  Widget build(BuildContext context) {
    if (panel == CatalogToolbarPanel.none) return const SizedBox.shrink();

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: const Color(0x44131B32),
          border: Border.all(color: const Color(0x33FFFFFF)),
        ),
        child: panel == CatalogToolbarPanel.filter
            ? _buildFilterContent()
            : _buildSortContent(),
      ),
    );
  }

  Widget _buildFilterContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelTitle('Filtrer'),
        const SizedBox(height: 10),
        _sectionLabel('Statut'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            CatalogChoiceButton(
              label: 'Tous',
              selected: statusFilter == null,
              onTap: () => _toggleStatus(null),
            ),
            CatalogChoiceButton(
              label: 'Disponible',
              selected: statusFilter == 'disponible',
              onTap: () => _toggleStatus('disponible'),
            ),
            CatalogChoiceButton(
              label: 'Indisponible',
              selected: statusFilter == 'indisponible',
              onTap: () => _toggleStatus('indisponible'),
            ),
          ],
        ),
        if (brands.isNotEmpty) ...[
          const SizedBox(height: 12),
          _sectionLabel('Marque'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              CatalogChoiceButton(
                label: 'Toutes',
                selected: brandFilter == null,
                onTap: () => _toggleBrand(null),
              ),
              for (final b in brands)
                CatalogChoiceButton(
                  label: b,
                  selected: brandFilter?.toLowerCase() == b.toLowerCase(),
                  onTap: () => _toggleBrand(b),
                ),
            ],
          ),
        ],
      ],
    );
  }

  void _toggleStatus(String? value) {
    final isTous = value == null;
    final selected =
        isTous ? statusFilter == null : statusFilter == value;
    onStatusChanged(selected ? catalogFilterCleared : value);
  }

  void _toggleBrand(String? value) {
    final isToutes = value == null;
    final selected = isToutes
        ? brandFilter == null
        : brandFilter?.toLowerCase() == value.toLowerCase();
    onBrandChanged(selected ? catalogFilterCleared : value);
  }

  void _toggleSort(CatalogSortOption option) {
    onSortChanged(sort == option ? null : option);
  }

  Widget _buildSortContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelTitle('Trier'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in CatalogSortOption.values)
              CatalogChoiceButton(
                label: catalogSortLabel(option),
                selected: sort == option,
                onTap: () => _toggleSort(option),
              ),
          ],
        ),
      ],
    );
  }

  Widget _panelTitle(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        color: const Color(0xFFA7B1C6),
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
    );
  }
}

class CatalogChoiceButton extends StatelessWidget {
  const CatalogChoiceButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0x331D88E5) : const Color(0x14FFFFFF),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? const Color(0xFF1D88E5)
                  : const Color(0x33FFFFFF),
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              color: selected
                  ? const Color(0xFFD2E6FF)
                  : const Color(0xFFC5CEDF),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
