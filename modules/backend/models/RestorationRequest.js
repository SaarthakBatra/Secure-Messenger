const mongoose = require('mongoose');

const restorationRequestSchema = new mongoose.Schema({
  requestId: { type: String, required: true, unique: true, index: true },
  conversationId: { type: String, required: true, index: true },
  requestingUserId: { type: String, required: true },
  reasonBlob: { type: String, required: true },
  status: { type: String, enum: ['PENDING', 'APPROVED', 'DENIED'], default: 'PENDING' },
  timestamps: {
    requestedAt: { type: Date, default: Date.now },
    decidedAt: { type: Date, default: null }
  }
}, { timestamps: false });

module.exports = mongoose.model('RestorationRequest', restorationRequestSchema);
