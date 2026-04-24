const User = require('../models/User');

exports.login = async (req, res) => {
    try {
        const { email, password } = req.body;
        console.log(`Login attempt for: ${email}`);

        // Accepte username OU email
        const user = await User.findOne({
            $or: [{ email: email }, { username: email }]
        });

        if (!user || user.password !== password) {
            console.log(`Invalid credentials for: ${email}`);
            return res.status(401).json({ message: 'Identifiants invalides' });
        }

        console.log(`Login successful for: ${email}`);
        res.json({
            id: user._id,
            username: user.username,
            role: user.role,
            companyId: user.companyId,
            token: 'fake-jwt-token'
        });
    } catch (error) {
        console.error(`Login error: ${error.message}`);
        res.status(500).json({ message: error.message });
    }
};

exports.register = async (req, res) => {
    try {
        const { username, password, role } = req.body;
        const user = new User({ username, password, role });
        await user.save();
        res.status(201).json(user);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};
