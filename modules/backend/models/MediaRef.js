const mongoose = require('mongoose');

const mediaRefSchema = new mongoose.Schema({
  mediaId: { type: String, required: true, unique: true, index: true },
  conversationId: { type: String, required: true, index: true },
  r2Key: { type: String, required: true },
  encryptedMetaBlob: { type: String, required: true }
}, { timestamps: false });

module.exports = mongoose.model('MediaRef', mediaRefSchema);
