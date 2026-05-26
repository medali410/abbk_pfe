const { prisma } = require('../lib/prisma');
const bcrypt = require('bcryptjs');

async function findAllWithUsers() {
    return prisma.client.findMany({
        include: { user: true },
        orderBy: { id: 'desc' },
    });
}

async function findByParam(param) {
    const idStr = String(param);
    return (
        (await prisma.client.findFirst({
            where: { clientId: idStr },
            include: { user: true },
        })) ||
        (await prisma.client.findFirst({
            where: { userId: parseInt(idStr, 10) || -1 },
            include: { user: true },
        }))
    );
}

async function updateClient(param, { nom, adresse, email, password, location }) {
    const existing = await findByParam(param);
    if (!existing) return null;

    const userUpdate = {};
    if (nom !== undefined) userUpdate.nom = nom;
    if (adresse !== undefined) userUpdate.adresse = adresse;
    if (email !== undefined) userUpdate.email = email.trim().toLowerCase();
    if (password !== undefined && password !== '') {
        userUpdate.password = await bcrypt.hash(password, 10);
    }

    const clientUpdate = {};
    if (location !== undefined) clientUpdate.location = location;

    const operations = [];
    if (Object.keys(userUpdate).length > 0) {
        operations.push(prisma.user.update({
            where: { id: existing.userId },
            data: userUpdate,
        }));
    }
    if (Object.keys(clientUpdate).length > 0) {
        operations.push(prisma.client.update({
            where: { userId: existing.userId },
            data: clientUpdate,
        }));
    }

    const results = await prisma.$transaction(operations);

    const updatedUser = Object.keys(userUpdate).length > 0 ? results[0] : existing.user;
    const updatedClient = Object.keys(clientUpdate).length > 0 ? (Object.keys(userUpdate).length > 0 ? results[1] : results[0]) : existing;

    return { ...updatedClient, user: updatedUser };
}

async function deleteClient(param) {
    const existing = await findByParam(param);
    if (!existing) return false;

    // Supprimer les machines du client (cascade manuelle)
    // existing.clientId contient l'ID textuel de la boite (companyId dans Machine)
    await prisma.machine.deleteMany({
        where: { companyId: existing.clientId },
    });

    // Deleting the User cascades to the Client row (onDelete: Cascade in schema)
    await prisma.user.delete({ where: { id: existing.userId } });
    return true;
}

module.exports = { findAllWithUsers, findByParam, updateClient, deleteClient };

