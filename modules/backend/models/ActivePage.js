const mongoose = require('mongoose');

const activePageSchema = new mongoose.Schema({
  conversationId: { type: String, required: true, unique: true, index: true },
  encryptedActivePage: { type: String, required: true },
  updatedAt: { type: Date, required: true }
}, { timestamps: false });

module.exports = mongoose.model('ActivePage', activePageSchema);
