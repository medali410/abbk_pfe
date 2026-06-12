// src/models/notificationModel.js
const { prisma } = require('../lib/prisma');

async function listForUser(userId) {
    return prisma.notification.findMany({
        where: { userId },
        orderBy: { createdAt: 'desc' },
        take: 50,
    });
}

async function countUnread(userId) {
    return prisma.notification.count({ where: { userId, isRead: false } });
}

async function create(data) {
    return prisma.notification.create({ data });
}

async function createMany(dataArray) {
    return prisma.notification.createMany({ data: dataArray });
}

async function markRead(id) {
    return prisma.notification.update({ where: { id }, data: { isRead: true } });
}

async function markAllRead(userId) {
    return prisma.notification.updateMany({
        where: { userId, isRead: false },
        data: { isRead: true },
    });
}

async function remove(id) {
    return prisma.notification.delete({ where: { id } });
}

module.exports = {
    listForUser,
    countUnread,
    create,
    createMany,
    markRead,
    markAllRead,
    remove,
};
