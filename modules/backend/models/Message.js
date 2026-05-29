const mongoose = require('mongoose');

const messageSchema = new mongoose.Schema({
  messageId: { type: String, required: true, unique: true, index: true },
  conversationId: { type: String, required: true, index: true },
  senderUserId: { type: String, required: true },
  encryptedBlob: { type: String, required: true },
  tickStatus: { type: String, enum: ['sent', 'delivered', 'read', 'acknowledged'], default: 'sent' },
  timestamps: {
    sent: { type: Date },
    delivered: { type: Date },
    read: { type: Date },
    acknowledged: { type: Date }
  },
  hidden_flags: [{ type: String }]
}, { timestamps: false });

module.exports = mongoose.model('Message', messageSchema);
