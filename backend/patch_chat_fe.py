import sys

file_path = r'c:\Users\Administrator\abbk_pfe_new\dali-pfe\lib\widgets\message_equipe_view.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

# find starting point
start_idx = -1
for i, line in enumerate(lines):
    if "if (_senderRole == 'client') {" in line:
        start_idx = i
        break

# find ending point (the block ends before "for (final conv in _conversations) {")
end_idx = -1
for i in range(start_idx, len(lines)):
    if "for (final conv in _conversations) {" in lines[i] and "// Load last message and resolve names for ALL roles" in lines[i-1]:
        end_idx = i - 1
        break

if start_idx == -1 or end_idx == -1:
    print("Could not find blocks. start:", start_idx, "end:", end_idx)
    sys.exit(1)

new_content = """      final isAdmin = ApiService.isSuperAdmin || ApiService.savedUserRole?.toLowerCase() == 'admin';
      final list = <Map<String, dynamic>>[];
      List<Map<String, dynamic>> contacts = [];

      if (!isAdmin) {
        String adminRoomId = 'chat_admin';
        if (_senderRole == 'client' && _clientId.isNotEmpty) {
           adminRoomId = 'chat_client_${_clientId}_admin';
        } else if ((_senderRole == 'conception' || _senderRole == 'concepteur')) {
           final profile = ApiService.savedConcepteurProfile;
           final cId = profile != null ? (profile['id'] ?? profile['_id'] ?? '').toString() : '';
           if (cId.isNotEmpty) adminRoomId = 'chat_conception_$cId';
        } else if (_senderRole == 'maintenance') {
           try {
             final ws = await ApiService.getMaintenanceWorkspace();
             final agent = ws['agent'] as Map?;
             final aId = (agent?['maintenanceAgentId'] ?? agent?['id'] ?? '').toString();
             adminRoomId = aId.isNotEmpty ? 'chat_maintenance_${aId}_admin' : 'chat_maintenance_admin';
           } catch (_) {}
        } else if (_technicianId.isNotEmpty) {
           adminRoomId = 'chat_technicien_$_technicianId';
        }

        list.add({
          'roomId': adminRoomId,
          'name': 'Admin',
          'lastText': 'Discuter avec l\\'administrateur',
          'lastAt': DateTime.now().toIso8601String(),
          'senderName': 'Admin',
          'roleLabel': 'Admin',
          'role': 'admin',
        });
      }

      try {
        if (isAdmin) {
          final rawConcepteurs = await ApiService.getConcepteurs();
          contacts.addAll(rawConcepteurs.map((c) => {
            'id': c['id'] ?? c['_id'],
            'name': c['username'] ?? c['name'] ?? 'Concepteur',
            'role': 'concepteurs', 
            'roleLabel': c['roleLabel'] ?? 'Concepteur',
            'machines': c['machines'] ?? <String>[],
          }).map((m) { m['role'] = 'conception'; return m; }).toList());
          contacts.addAll(await ApiService.getTechnicianContacts());
          contacts.addAll(await ApiService.getClientContacts());
          contacts.addAll(await ApiService.getMaintenanceAgentContacts());
        } else if (_senderRole == 'client') {
          contacts = await ApiService.getClientContacts();
        } else if (_senderRole == 'conception' || _senderRole == 'concepteur') {
          contacts = await ApiService.getConcepteurContacts();
        } else if (_senderRole == 'maintenance') {
          contacts = await ApiService.getMaintenanceAgentContacts();
        } else {
          contacts = await ApiService.getTechnicianContacts();
        }
      } catch (e) {
        debugPrint('Erreur chargement contacts unifiés: $e');
      }

      final concepteurs = contacts.where((c) => c['role'] == 'conception' || c['role'] == 'concepteur').toList();
      final techs = contacts.where((c) => c['role'] == 'technician').toList();
      final agents = contacts.where((c) => c['role'] == 'maintenance').toList();
      final clients = contacts.where((c) => c['role'] == 'client').toList();

      final seenIds = <String>{};

      void addSection(String headerId, String label, String icon, String color, List sectionContacts) {
        if (sectionContacts.isEmpty) return;
        list.add({
          'roomId': headerId,
          'isSectionHeader': true,
          'sectionLabel': label,
          'sectionIcon': icon,
          'sectionColor': color,
        });

        for (final c in sectionContacts) {
          final idStr = c['id'].toString();
          final idKey = '${c['role']}_${idStr}';
          if (seenIds.contains(idKey)) continue;
          seenIds.add(idKey);
          
          String roomId = '';
          if (isAdmin) {
             roomId = 'chat_${c['role'] == 'concepteur' ? 'conception' : c['role']}_${idStr}';
          } else {
             final intId = int.tryParse(idStr) ?? 0;
             roomId = _generateDirectRoomId(intId);
          }

          list.add({
            'roomId': roomId,
            'name': c['name'] ?? 'Contact',
            'subId': idStr,
            'roleLabel': c['roleLabel'] ?? '',
            'machines': c['machines'] ?? <String>[],
            'lastText': 'Ouvrir la discussion',
            'lastAt': DateTime.now().toIso8601String(),
            'senderName': '',
            'role': c['role'] ?? '',
          });
        }
      }

      addSection('__section_concep__', 'CONCEPTEURS', 'engineering', 'orange', concepteurs);
      addSection('__section_tech__', 'TECHNICIENS', 'build', 'purple', techs);
      addSection('__section_maint__', 'AGENTS DE MAINTENANCE', 'support_agent', 'blue', agents);
      addSection('__section_clients__', 'CLIENTS', 'groups', 'green', clients);

      _conversations = list;
"""

new_lines = lines[:start_idx] + [new_content] + lines[end_idx:]

with open(file_path, 'w', encoding='utf-8') as f:
    f.writelines(new_lines)

print("success!")
