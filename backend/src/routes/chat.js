const express = require('express');
const router = express.Router();
const chatController = require('../controllers/chatController');

// Messages
router.get('/messages/:roomId', chatController.getChatMessages);
router.post('/messages', chatController.postChatMessage);
router.delete('/messages/:messageId', chatController.deleteChatMessage);

const { requireAuth } = require('../lib/auth');

// Conversations (sidebar lists)
router.get('/conversations/conception', requireAuth, chatController.getConceptionConversations);
router.get('/conversations/user/:userId', requireAuth, chatController.getConversationsByUser);
router.get('/conversations/role/:role', requireAuth, chatController.getConversationsByRole);

// Designer search
router.get('/concepteurs/search', requireAuth, chatController.searchConcepteurs);
router.get('/contacts/concepteur', requireAuth, chatController.getConcepteurContacts);
router.get('/contacts/technician', requireAuth, chatController.getTechnicianContacts);
router.get('/contacts/client', requireAuth, chatController.getClientContacts);
router.get('/contacts/maintenance', requireAuth, chatController.getMaintenanceAgentContacts);

// Room participants
router.get('/room/:roomId/participants', chatController.getRoomParticipants);
router.post('/room/:roomId/participants', chatController.addRoomParticipant);

// Room management
router.delete('/rooms/:roomId', chatController.deleteChatRoom);

// New features with requireAuth
router.put('/rooms/:roomId/pin', requireAuth, chatController.togglePinRoom);
router.put('/rooms/:roomId/mute', requireAuth, chatController.toggleMuteRoom);
router.post('/rooms/:roomId/clear', requireAuth, chatController.clearRoomHistory);
router.post('/blocks', requireAuth, chatController.blockUser);
router.delete('/blocks/:blockedId', requireAuth, chatController.unblockUser);
router.get('/blocks', requireAuth, chatController.getBlockedUsers);

// Uploads
router.post('/upload', chatController.uploadAttachment);

module.exports = router;
