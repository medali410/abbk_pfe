import sys

content = open('concepteur_dashboard_page.dart', 'r', encoding='utf-8').read()
target = '''  Widget _buildProjectTeamPanel() {
    return const SizedBox.shrink();
  }'''

replacement = '''  Widget _buildProjectTeamPanel() {
    if (_profileLoading && _concepteurProjectTeam == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: sidebarColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 42),
          child: Center(child: CircularProgressIndicator(color: primaryColor)),
        ),
      );
    }

    final clients =
        (_concepteurProjectTeam?['clients'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        const <Map<String, dynamic>>[];
    final techs =
        (_concepteurProjectTeam?['technicians'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        const <Map<String, dynamic>>[];
    final agents =
        (_concepteurProjectTeam?['maintenanceAgents'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        const <Map<String, dynamic>>[];

    if (clients.isEmpty) {
      return _maintenanceEmptyPane(
        icon: Icons.business_outlined,
        message: 'Aucun client n\\'a encore achete une de vos machines.',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = 3;
        if (constraints.maxWidth < 600)
          crossAxisCount = 1;
        else if (constraints.maxWidth < 1000)
          crossAxisCount = 2;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 0.85,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: clients.length,
          itemBuilder: (context, index) {
            final c = clients[index];
            final clientKeys = _clientLinkedIdKeys(c);
            
            final embeddedTechs = (c['technicians'] as List?)?.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
            final embeddedAgents = (c['maintenanceAgents'] as List?)?.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
            final embeddedMachines = (c['machines'] as List?)?.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
            
            final t = embeddedTechs ?? _techniciansForClientKeys(techs, clientKeys);
            final m = embeddedAgents ?? _maintenanceAgentsForClientKeys(agents, clientKeys);
            final machinesList = embeddedMachines ?? const <Map<String, dynamic>>[];

            return _buildClientGalleryCard(c, machinesList, t, m);
          },
        );
      },
    );
  }

  Widget _buildClientGalleryCard(
    Map<String, dynamic> client,
    List<Map<String, dynamic>> machines,
    List<Map<String, dynamic>> techs,
    List<Map<String, dynamic>> agents,
  ) {
    final cid = _clientIdOf(client);
    final cname = _clientNameOf(client);
    final location = (client['location'] ?? 'Localisation inconnue').toString();
    final email = (client['email'] ?? 'Email non specifie').toString();
    final isActive = client['loginDisabled'] != true;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF171733),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Container(
                height: 154,
                width: double.infinity,
                color: const Color(0xFF1E1E2D),
                alignment: Alignment.center,
                child: _entityAvatar(client, cname, radius: 45),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.15),
                        Colors.black.withOpacity(0.55),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 10,
                left: 10,
                child: Row(
                  children: [
                    _statusBadge(
                      isActive ? 'ACTIF' : 'INACTIF',
                      isActive ? const Color(0xFF4CAF50) : const Color(0xFFE53935),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ID: ' + (cid.isEmpty ? 'INCONNU' : cid.toUpperCase()),
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: primaryColor,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    cname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Email\\n' + email,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: mutedTextColor,
                            height: 1.25,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Localisation\\n' + location,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: mutedTextColor,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Machines: ${machines.length} • Tech: ${techs.length} • Maint: ${agents.length}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: mutedTextColor,
                      height: 1.25,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: _cardButton(
                          Icons.edit_outlined,
                          'MODIFIER',
                          const Color(0xFF212142),
                          () => _openEditClient(client),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _cardButton(
                          Icons.delete_outline,
                          'EFFACER',
                          const Color(0xFF422121),
                          () => _deleteClientEntity(client),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }'''

if target in content:
    content = content.replace(target, replacement)
    open('concepteur_dashboard_page.dart', 'w', encoding='utf-8').write(content)
    print('Successfully replaced')
else:
    print('Target not found')
