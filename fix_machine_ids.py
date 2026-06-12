import os
import re

filepath = r"C:\Users\ASUS\Documents\abbk_pfe\dali-pfe\lib\concepteur_dashboard_page.dart"
with open(filepath, "r", encoding="utf-8") as f:
    content = f.read()

# I need to change:
#            final raw = t['machineIds'];
#            final tIds = <String>[];
#            if (raw is List) {
#              for (final e in raw) {
#                final s = e.toString().trim();
#                if (s.isNotEmpty) tIds.add(s);
#              }
#            }
# To:
#            final raw = t['machineIds'];
#            final tIds = <String>[];
#            if (raw is List) {
#              for (final e in raw) {
#                final s = e.toString().trim();
#                if (s.isNotEmpty) tIds.add(s);
#              }
#            } else if (raw is String) {
#              try {
#                final l = jsonDecode(raw);
#                if (l is List) {
#                  for (final e in l) {
#                    final s = e.toString().trim();
#                    if (s.isNotEmpty) tIds.add(s);
#                  }
#                }
#              } catch(_) {}
#            }

target = """            final raw = t['machineIds'];
            final tIds = <String>[];
            if (raw is List) {
              for (final e in raw) {
                final s = e.toString().trim();
                if (s.isNotEmpty) tIds.add(s);
              }
            }
            // Then find matching machines from the client's machines"""

replacement = """            final raw = t['machineIds'];
            final tIds = <String>[];
            if (raw is List) {
              for (final e in raw) {
                final s = e.toString().trim();
                if (s.isNotEmpty) tIds.add(s);
              }
            } else if (raw is String) {
              try {
                final l = jsonDecode(raw);
                if (l is List) {
                  for (final e in l) {
                    final s = e.toString().trim();
                    if (s.isNotEmpty) tIds.add(s);
                  }
                }
              } catch (_) {}
            }
            // Then find matching machines from the client's machines"""

if target in content:
    content = content.replace(target, replacement)
    
    # Also fix _machinesForAssignedMachineIds to handle String
    target2 = """    final raw = doc['machineIds'];
    final ids = <String>[];
    if (raw is List) {
      for (final e in raw) {
        final s = e.toString().trim();
        if (s.isNotEmpty) ids.add(s);
      }
    }
    if (ids.isEmpty) return [];"""
    
    replacement2 = """    final raw = doc['machineIds'];
    final ids = <String>[];
    if (raw is List) {
      for (final e in raw) {
        final s = e.toString().trim();
        if (s.isNotEmpty) ids.add(s);
      }
    } else if (raw is String) {
      try {
        final l = jsonDecode(raw);
        if (l is List) {
          for (final e in l) {
            final s = e.toString().trim();
            if (s.isNotEmpty) ids.add(s);
          }
        }
      } catch (_) {}
    }
    if (ids.isEmpty) return [];"""
    
    content = content.replace(target2, replacement2)
    
    # Ensure jsonDecode is available (it's in dart:convert)
    if "import 'dart:convert';" not in content:
        content = "import 'dart:convert';\n" + content
        
    with open(filepath, "w", encoding="utf-8") as f:
        f.write(content)
    print("Replacement successful.")
else:
    print("Target not found.")
