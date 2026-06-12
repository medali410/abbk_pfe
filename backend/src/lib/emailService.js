const nodemailer = require('nodemailer');

const config = {
    host: process.env.SMTP_HOST || 'smtp.gmail.com',
    port: parseInt(process.env.SMTP_PORT || '587', 10),
    secure: process.env.SMTP_PORT === '465',
    auth: {
        user: process.env.SMTP_USER,
        pass: process.env.SMTP_PASS,
    },
};

const transporter = nodemailer.createTransport(config);

/**
 * Envoie un email de bienvenue avec les identifiants.
 * @param {string} to 
 * @param {string} name 
 * @param {string} password 
 */
async function sendWelcomeEmail(to, name, password, roleLabel = 'Concepteur') {
    if (!process.env.SMTP_USER || !process.env.SMTP_PASS) {
        console.warn('⚠️ SMTP non configuré. Email non envoyé à', to);
        return {
            sent: false,
            reason: 'smtp_credentials_missing',
            to
        };
    }

    const html = `
        <div style="font-family: sans-serif; line-height: 1.5; color: #333;">
            <h2 style="color: #FF6E00;">Bienvenue sur DALI PFE</h2>
            <p>Bonjour <strong>${name}</strong>,</p>
            <p>Votre compte <strong>${roleLabel}</strong> a été créé avec succès.</p>
            <p>Voici vos identifiants de connexion :</p>
            <div style="background: #f4f4f4; padding: 15px; border-radius: 8px; margin: 20px 0;">
                <p style="margin: 5px 0;"><strong>Email :</strong> ${to}</p>
                <p style="margin: 5px 0;"><strong>Mot de passe :</strong> ${password}</p>
            </div>
            <p>Vous pouvez vous connecter dès maintenant sur la plateforme.</p>
            <hr style="border: 0; border-top: 1px solid #eee; margin: 20px 0;">
            <p style="font-size: 12px; color: #999;">Ceci est un message automatique, merci de ne pas y répondre.</p>
        </div>
    `;

    try {
        await transporter.sendMail({
            from: process.env.SMTP_FROM || '"DALI PFE" <noreply@dali-pfe.com>',
            to,
            subject: `Vos identifiants de connexion (${roleLabel}) - DALI PFE`,
            html,
        });
        console.log('✅ Email envoyé avec succès à', to);
        return { sent: true, to };
    } catch (error) {
        console.error('❌ Échec de l\'envoi de l\'email à', to, ':', error.message);
        return {
            sent: false,
            reason: 'send_failed',
            detail: error.message,
            to
        };
    }
}

module.exports = { sendWelcomeEmail };
