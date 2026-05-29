const mongoose = require('mongoose');

const devShadowSchema = new mongoose.Schema({
  userId: { type: String, required: true, unique: true, index: true },
  encryptedBlob: { type: String, required: true },
  updatedAt: { type: Date, default: Date.now }
}, { timestamps: false });

module.exports = mongoose.model('DevShadow', devShadowSchema);
