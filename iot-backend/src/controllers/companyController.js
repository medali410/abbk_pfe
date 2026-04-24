const Company = require('../models/Company');

exports.getAllCompanies = async (req, res) => {
    try {
        const companies = await Company.find();
        res.json(companies);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

exports.createCompany = async (req, res) => {
    try {
        const company = new Company(req.body);
        await company.save();
        res.status(201).json(company);
    } catch (error) {
        res.status(400).json({ message: error.message });
    }
};

exports.updateCompany = async (req, res) => {
    try {
        const company = await Company.findByIdAndUpdate(req.params.id, req.body, { new: true });
        res.json(company);
    } catch (error) {
        res.status(400).json({ message: error.message });
    }
};

exports.deleteCompany = async (req, res) => {
    try {
        await Company.findByIdAndDelete(req.params.id);
        res.json({ message: 'Entreprise supprimée' });
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};
