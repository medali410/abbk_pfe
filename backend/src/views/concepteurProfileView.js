const { mergeUserProfile } = require('./userView');

function serializeConcepteurProfileDashboard(user, concepteur, projectTeam = null) {
    const base = mergeUserProfile(user, concepteur, { concepteurId: concepteur.id });
    const companyLabel = concepteur.companyId || '';

    return {
        ...base,
        concepteurId: concepteur.id,
        displayName: user.nom,
        username: user.nom,
        fullName: user.nom,
        address: user.adresse,
        street: user.adresse,
        speciality: concepteur.specialite,
        specialty: concepteur.specialite,
        poste: concepteur.specialite,
        title: concepteur.specialite,
        jobTitle: concepteur.specialite,
        companyName: companyLabel,
        company: companyLabel,
        organization: companyLabel,
        clientName: companyLabel,
        imageUrl: concepteur.imageUrl || '',
        photoUrl: concepteur.imageUrl || '',
        avatarUrl: concepteur.imageUrl || '',
        profilePhotoUrl: concepteur.imageUrl || '',
        phone: concepteur.phone || '',
        telephone: concepteur.phone || '',
        mobile: concepteur.phone || '',
        phoneNumber: concepteur.phone || '',
        city: concepteur.city || '',
        ville: concepteur.city || '',
        country: concepteur.country || '',
        pays: concepteur.country || '',
        status: concepteur.status || 'Actif',
        statut: concepteur.status || 'Actif',
        websiteUrl: concepteur.websiteUrl || '',
        siteWeb: concepteur.websiteUrl || '',
        website: concepteur.websiteUrl || '',
        url: concepteur.websiteUrl || '',
        profileUrl: concepteur.profileUrl || '',
        linkedinUrl: concepteur.profileUrl || '',
        portfolioUrl: concepteur.profileUrl || '',
        location: concepteur.location || user.adresse || '',
        createdAt: user.createdAt,
        updatedAt: user.updatedAt,
        projectTeam,
        stats: projectTeam
            ? {
                  clientsCount: projectTeam.clients.length,
                  machinesCount: projectTeam.clients.reduce(
                      (sum, c) => sum + (c.machines?.length || 0),
                      0,
                  ),
                  techniciansCount: projectTeam.technicians.length,
                  maintenanceAgentsCount: projectTeam.maintenanceAgents.length,
                  concepteursCount: projectTeam.concepteurs.length,
              }
            : null,
    };
}

module.exports = { serializeConcepteurProfileDashboard };
