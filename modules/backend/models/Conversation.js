const mongoose = require('mongoose');

const conversationSchema = new mongoose.Schema({
  conversationId: { type: String, required: true, unique: true, index: true },
  adminUserId: { type: String, required: true },
  participantUserIds: [{ type: String }],
  status: { type: String, enum: ['PENDING', 'ACTIVE', 'ROTATING'], default: 'PENDING' },
  encryptedBlob: { type: String, required: false },
  aliceInvitePayload: { type: String, default: null },
  bobInvitePayload: { type: String, default: null },
  invitationMessage: { type: String, default: null },
  latestChapterHash: { type: String, default: null },
  createdAt: { type: Date, default: Date.now }
}, { timestamps: false });

module.exports = mongoose.model('Conversation', conversationSchema);
