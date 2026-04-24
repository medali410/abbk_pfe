const mongoose = require('mongoose');

const ChatMessageSchema = new mongoose.Schema(
  {
    roomId: { type: String, required: true, index: true },
    from: { type: String, default: 'client' },
    senderName: { type: String, default: 'Utilisateur' },
    text: { type: String, required: true, trim: true },
  },
  { timestamps: true }
);

ChatMessageSchema.index({ roomId: 1, createdAt: -1 });

module.exports = mongoose.model('ChatMessage', ChatMessageSchema);
