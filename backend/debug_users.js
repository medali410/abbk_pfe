const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

async function main() {
    const users = await prisma.user.findMany({ take: 20 });
    console.log('DEBUG_START');
    console.log(JSON.stringify(users, null, 2));
    console.log('DEBUG_END');
}

main()
    .catch(e => console.error(e))
    .finally(async () => await prisma.$disconnect());
