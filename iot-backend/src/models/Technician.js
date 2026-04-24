const mongoose = require('mongoose');

const technicianSchema = new mongoose.Schema({
    name: { type: String, required: true },
    technicianId: { type: String, required: true, unique: true },
    email: { type: String, required: true, trim: true, lowercase: true },
    password: { type: String, required: true },
    phone: { type: String },
    specialization: { type: String },
    technicalDescription: { type: String, default: '' },
    companyId: { type: String, required: true },
    /** IDs machines (_id Mongo) que ce technicien supervise — au moins une si le client a déjà des machines */
    machineIds: { type: [String], default: [] },
    status: { type: String, default: 'Disponible' },
    imageUrl: { type: String, default: 'https://lh3.googleusercontent.com/aida-public/AB6AXuD6XMHTc7EnuwpybN1a7M5-4ByK2xNIZiN_tfQlBnyREkmNG_daynil3m0nLFdLpMbg4DScyNGfT3Loz0tvwq2eYfDYmMBOmaeCRZGo2TQRUQ58chmYrzdqYuf8hrarTbDuKlLgGTy2rXZ9R0mza7SoAWjVX5upN5Hg8Wlj7xGzwjwlWqLxZx1qtFLruQjQz_SvXDpfU-WVse3fGP3OJsvkstlxx_f9VrutqsfJsF9HFU0sJrWmAx6RIr25RZrz3qE-xUmiogt7WU0' }
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

module.exports = mongoose.model('Technician', technicianSchema);
