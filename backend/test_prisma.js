const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

async function run() {
    try {
        console.log("Upserting room...");
        await prisma.chatRoom.upsert({
            where: { roomId: 'test_room' },
            create: { roomId: 'test_room' },
            update: { updatedAt: new Date() }
        });

        console.log("Creating message...");
        await prisma.chatMessage.create({
            data: {
                roomId: 'test_room',
                from: 'conception',
                senderName: 'Test Name',
                text: 'Hello DB!',
                attachmentUrl: null,
                attachmentType: null
            }
        });

        console.log("Success! Data added");
    } catch (e) {
        console.error("Prisma error:", e);
    } finally {
        await prisma.$disconnect();
    }
}
run();
