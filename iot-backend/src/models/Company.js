const mongoose = require('mongoose');

const CompanySchema = new mongoose.Schema({
    name: { type: String, required: true, unique: true },
    address: { type: String, required: true },
    logo: { type: String }, // URL or base64
    techs: { type: Number, default: 0 },
}, {
    timestamps: true,
    toJSON: {
        virtuals: true,
        versionKey: false,
        transform: function (doc, ret) {
            delete ret._id;
        }
    }
});

module.exports = mongoose.model('Company', CompanySchema);
