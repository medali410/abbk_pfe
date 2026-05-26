const { prisma } = require('../lib/prisma');
const { nextBusinessId } = require('../lib/ids');
const { hashPassword } = require('../lib/auth');

async function findAll() {
    return prisma.document.findMany({ orderBy: { updatedAt: 'desc' } });
}

async function count() {
    return prisma.document.count();
}

async function create(data) {
    const pwd = String(data.password || '').trim();
    return prisma.document.create({
        data: {
            documentId: data.documentId || nextBusinessId('DOC'),
            name: String(data.name || '').trim(),
            version: String(data.version || 'v1.0').trim(),
            documentType: String(data.documentType || '').trim(),
            clientId: String(data.clientId || '').trim(),
            status: String(data.status || 'Actif').trim(),
            securityEmail: String(data.securityEmail || '').trim(),
            passwordHash: pwd ? await hashPassword(pwd) : '',
        },
    });
}

module.exports = { findAll, count, create };
