const mongoose = require('mongoose');

const clientSchema = new mongoose.Schema({
    clientId: { type: String, required: true, unique: true },
    name: { type: String, required: true },
    motorType: { type: String, default: 'Général' },
    location: { type: String, default: 'Inconnu' },
    address: { type: String, default: '' },
    // Identifiants tableau de bord client (définis par le super admin) — email unique
    email: { type: String, trim: true, lowercase: true, sparse: true, unique: true },
    password: { type: String },
    status: { type: String, default: 'operational' }, // operational, optimal, warning, critical
    lastSync: { type: String, default: 'il y a qq instants' },
    machines: { type: Number, default: 0 },
    techs: { type: Number, default: 0 },
    alerts: { type: Number, default: 0 },
    health: { type: Number, default: 1.0 },
    imageUrl: { type: String, default: 'https://lh3.googleusercontent.com/aida-public/AB6AXuAC78OPMt_an7mPJmtM60IxdM_eZaPk7I85lMuYPG4UOCggmrViweZNyf5SB44WrcoFcUbT-gPmwED_py_D7gXsiT1MNqAxGoZK7_LFMN7KaUWr2dD0eA870cVcoPCAKAga3QahI4DaEX7Nbj2DC-UqCvoyazf7FEk_3TF4_eqdHRZkEYzLBUTH-oHhtVlM21tgwPbz9QQUgg0pTd4rECwEdiRNrmzJjffuUqZ5QGUvLiotc3x4Zhs9NnOhWSxg366qNdGNCatP9Q0' }
}, {
    timestamps: true,
    toJSON: {
        transform(_doc, ret) {
            delete ret.password;
            return ret;
        }
    },
    toObject: {
        transform(_doc, ret) {
            delete ret.password;
            return ret;
        }
    }
});

module.exports = mongoose.model('Client', clientSchema);
