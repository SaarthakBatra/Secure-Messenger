const mongoose = require('mongoose');

const userConversationKeySchema = new mongoose.Schema({
  userId: { type: String, required: true, index: true },
  conversationId: { type: String, required: true, index: true },
  encryptedConversationKey: { type: String, required: true }, // Base64
  localAlias: { type: String, default: null },
  createdAt: { type: Date, default: Date.now }
}, { timestamps: false });

// Compound index to ensure uniqueness per user per conversation
userConversationKeySchema.index({ userId: 1, conversationId: 1 }, { unique: true });

module.exports = mongoose.model('UserConversationKey', userConversationKeySchema);
