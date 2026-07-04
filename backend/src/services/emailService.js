// src/services/emailService.js
// Service d'envoi d'e-mails de bienvenue via Nodemailer + Gmail SMTP
const nodemailer = require('nodemailer');

const transporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST || 'smtp.gmail.com',
  port: parseInt(process.env.SMTP_PORT || '587'),
  secure: false,
  auth: {
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASS,
  },
});

/**
 * Envoie un e-mail de bienvenue à un nouveau technicien ou agent de maintenance.
 * @param {object} options
 * @param {string} options.to         - L'adresse email du nouveau compte
 * @param {string} options.name       - Le nom complet
 * @param {string} options.password   - Le mot de passe initial (en clair, avant hachage)
 * @param {string} options.role       - 'Technicien' | 'Agent de Maintenance'
 * @param {string} options.appUrl     - URL de l'application (optionnel)
 */
async function sendWelcomeEmail({ to, name, password, role }) {
  const appUrl = 'https://dali-pfe.app'; // à adapter si besoin

  const roleColor = role === 'Technicien' ? '#6C63FF' : '#F59E0B';
  const roleIcon  = role === 'Technicien' ? '🔧' : '⚙️';

  const html = `
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Bienvenue sur DALI</title>
</head>
<body style="margin:0;padding:0;background:#0F0F1A;font-family:'Segoe UI',Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background:#0F0F1A;padding:40px 0;">
    <tr>
      <td align="center">
        <table width="560" cellpadding="0" cellspacing="0"
               style="background:#1A1A2E;border-radius:16px;overflow:hidden;
                      box-shadow:0 8px 32px rgba(0,0,0,0.5);border:1px solid #2A2A4A;">

          <!-- Header -->
          <tr>
            <td style="background:linear-gradient(135deg,#1E1B4B 0%,${roleColor}33 100%);
                       padding:36px 40px;text-align:center;">
              <div style="font-size:48px;margin-bottom:12px;">${roleIcon}</div>
              <h1 style="margin:0;color:#FFFFFF;font-size:26px;font-weight:700;letter-spacing:0.5px;">
                Bienvenue sur <span style="color:${roleColor}">DALI</span>
              </h1>
              <p style="margin:8px 0 0;color:#A0A0C0;font-size:14px;">
                Plateforme de Maintenance Prédictive
              </p>
            </td>
          </tr>

          <!-- Body -->
          <tr>
            <td style="padding:36px 40px;">
              <p style="color:#E0E0FF;font-size:16px;margin:0 0 8px;">
                Bonjour <strong style="color:#FFFFFF;">${name}</strong>,
              </p>
              <p style="color:#A0A0C0;font-size:14px;line-height:1.6;margin:0 0 28px;">
                Un compte <strong style="color:${roleColor};">${role}</strong> vient d'être créé
                pour vous sur la plateforme <strong style="color:#FFFFFF;">DALI</strong>.
                Voici vos identifiants de connexion :
              </p>

              <!-- Credentials Box -->
              <div style="background:#0F0F1A;border:1px solid ${roleColor}55;border-radius:12px;
                          padding:24px 28px;margin-bottom:28px;">
                <table width="100%" cellpadding="0" cellspacing="0">
                  <tr>
                    <td style="padding:8px 0;color:#A0A0C0;font-size:13px;width:130px;">📧 Email</td>
                    <td style="padding:8px 0;color:#FFFFFF;font-size:13px;font-weight:600;">${to}</td>
                  </tr>
                  <tr>
                    <td style="padding:8px 0;color:#A0A0C0;font-size:13px;">🔑 Mot de passe</td>
                    <td style="padding:8px 0;">
                      <span style="background:${roleColor}22;color:${roleColor};
                                   padding:4px 12px;border-radius:6px;font-size:14px;
                                   font-weight:700;letter-spacing:1px;font-family:monospace;">
                        ${password}
                      </span>
                    </td>
                  </tr>
                  <tr>
                    <td style="padding:8px 0;color:#A0A0C0;font-size:13px;">👤 Rôle</td>
                    <td style="padding:8px 0;color:#FFFFFF;font-size:13px;">${role}</td>
                  </tr>
                </table>
              </div>

              <!-- Security note -->
              <div style="background:#1E1B4B;border-left:4px solid ${roleColor};
                          border-radius:0 8px 8px 0;padding:14px 18px;margin-bottom:28px;">
                <p style="margin:0;color:#A0A0C0;font-size:13px;line-height:1.5;">
                  🔒 <strong style="color:#FFFFFF;">Sécurité :</strong>
                  Pour des raisons de sécurité, nous vous recommandons de changer votre
                  mot de passe dès votre première connexion depuis votre profil.
                </p>
              </div>

              <p style="color:#A0A0C0;font-size:13px;line-height:1.6;margin:0 0 6px;">
                Pour toute question, contactez votre administrateur.
              </p>
            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td style="background:#0F0F1A;padding:20px 40px;text-align:center;
                       border-top:1px solid #2A2A4A;">
              <p style="margin:0;color:#505070;font-size:12px;">
                © 2026 DALI — Plateforme de Maintenance Prédictive
              </p>
              <p style="margin:6px 0 0;color:#505070;font-size:11px;">
                Cet e-mail a été envoyé automatiquement. Ne pas répondre.
              </p>
            </td>
          </tr>

        </table>
      </td>
    </tr>
  </table>
</body>
</html>
  `;

  await transporter.sendMail({
    from: process.env.SMTP_FROM || '"DALI Platform" <abbkentreprise@gmail.com>',
    to,
    subject: `${roleIcon} Bienvenue sur DALI — Vos identifiants ${role}`,
    html,
  });
}

module.exports = { sendWelcomeEmail };
