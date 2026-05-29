const mongoose = require('mongoose');

const eventSchema = new mongoose.Schema({
  eventId: { type: String, required: true, unique: true, index: true },
  conversationId: { type: String, required: true, index: true },
  type: { type: String, required: true },
  encryptedPayloadBlob: { type: String, required: true },
  timestamp: { type: Date, default: Date.now }
}, { timestamps: false });

module.exports = mongoose.model('Event', eventSchema);
