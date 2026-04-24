const mongoose = require('mongoose');
const Alert = require('./src/models/Alert');
require('dotenv').config();

async function cleanDuplicateAlerts() {
    try {
        await mongoose.connect(process.env.MONGODB_URI);
        console.log('Connected to MongoDB');

        // Find all unresolved temperature alerts
        const duplicates = await Alert.find({
            resolved: false,
            message: { $regex: /TEMPÉRATURE ÉLEVÉE.*Compresseur B2/ }
        }).sort({ createdAt: -1 });

        console.log(`Found ${duplicates.length} temperature alerts for Compresseur B2`);

        if (duplicates.length > 1) {
            // Keep the most recent one, delete the rest
            const toKeep = duplicates[0];
            const toDelete = duplicates.slice(1);

            console.log(`Keeping alert ID: ${toKeep._id}`);
            console.log(`Deleting ${toDelete.length} duplicate alerts...`);

            for (const alert of toDelete) {
                await Alert.findByIdAndDelete(alert._id);
                console.log(`  Deleted: ${alert._id}`);
            }

            console.log('✅ Cleanup complete!');
        } else {
            console.log('No duplicates to clean');
        }

        process.exit(0);
    } catch (error) {
        console.error('Error:', error);
        process.exit(1);
    }
}

cleanDuplicateAlerts();
