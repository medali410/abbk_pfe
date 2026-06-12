import os

filepath = r"C:\Users\ASUS\Documents\abbk_pfe\dali-pfe\lib\concepteur_dashboard_page.dart"
with open(filepath, "r", encoding="utf-8") as f:
    content = f.read()

target = """        Text(
          'Techniciens: ${technicians.isEmpty ? '—' : technicians.map((e) => _technicianNameOf(e)).join(', ')}',
          style: GoogleFonts.inter(
            color: mutedTextColor,
            fontSize: 12,
          ),
        ),"""

replacement = """        if (technicians.isNotEmpty) ...[
          const SizedBox(height: 4),
          ...technicians.map((t) {
            final name = _technicianNameOf(t);
            final loc = (t['location'] ?? t['address'] ?? t['city'] ?? 'Localisation non spécifiée').toString();
            
            // Get all machines associated with this technician
            // First get their machineIds if any
            final raw = t['machineIds'];
            final tIds = <String>[];
            if (raw is List) {
              for (final e in raw) {
                final s = e.toString().trim();
                if (s.isNotEmpty) tIds.add(s);
              }
            }
            // Then find matching machines from the client's machines
            final techM = machines.where((m) => tIds.contains(_machineIdOf(m))).toList();
            
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF14141F),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: Row(
                children: [
                  _entityAvatar(t, name, radius: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined, color: mutedTextColor, size: 12),
                            const SizedBox(width: 4),
                            Expanded(child: Text(loc, style: GoogleFonts.inter(color: mutedTextColor, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                        if (techM.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('Machines ajoutées: ${techM.map((m) => _machineNameOf(m)).join(', ')}', style: GoogleFonts.inter(color: primaryColor, fontSize: 11, fontWeight: FontWeight.w500)),
                        ]
                      ]
                    )
                  )
                ]
              )
            );
          }).toList(),
          const SizedBox(height: 4),
        ] else ...[
          Text(
            'Techniciens: —',
            style: GoogleFonts.inter(
              color: mutedTextColor,
              fontSize: 12,
            ),
          ),
        ],"""

if target in content:
    content = content.replace(target, replacement)
    with open(filepath, "w", encoding="utf-8") as f:
        f.write(content)
    print("Replacement successful.")
else:
    print("Target not found.")
