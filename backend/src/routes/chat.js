const express = require('express');
const router = express.Router();
const chatController = require('../controllers/chatController');

// Messages
router.get('/messages/:roomId', chatController.getChatMessages);
router.post('/messages', chatController.postChatMessage);

// Conversations (sidebar lists)
router.get('/conversations/conception', chatController.getConceptionConversations);
router.get('/conversations/user/:userId', chatController.getConversationsByUser);
router.get('/conversations/role/:role', chatController.getConversationsByRole);

// Designer search
router.get('/concepteurs/search', chatController.searchConcepteurs);

// Room participants
router.get('/room/:roomId/participants', chatController.getRoomParticipants);
router.post('/room/:roomId/participants', chatController.addRoomParticipant);

// Uploads
router.post('/upload', chatController.uploadAttachment);

module.exports = router;
