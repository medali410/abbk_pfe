const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

const fs = require('fs');

async function main() {
    let output = '';
    output += '--- All Users ---\n';
    const users = await prisma.user.findMany({ select: { id: true, nom: true, role: true } });
    output += JSON.stringify(users, null, 2) + '\n';

    output += '--- Participants ---\n';
    const participants = await prisma.chatRoomParticipant.findMany({ take: 20 });
    output += JSON.stringify(participants, null, 2) + '\n';

    fs.writeFileSync('debug_output.txt', output);
}

main()
    .catch(e => console.error(e))
    .finally(async () => await prisma.$disconnect());
