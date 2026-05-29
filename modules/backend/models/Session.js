const mongoose = require('mongoose');

const sessionSchema = new mongoose.Schema({
  userId: { type: String, required: true, index: true },
  token: { type: String, required: true, unique: true },
  refreshToken: { type: String, required: true, unique: true },
  deviceFingerprint: { type: String, required: true },
  refreshExpiresAt: { type: Date, required: true, index: true },
  tokenExpiresAt: { type: Date, required: true },
  createdAt: { type: Date, default: Date.now },
  invalidatedAt: { type: Date, default: null }
}, { timestamps: false });

sessionSchema.index({ tokenExpiresAt: 1 }, { expireAfterSeconds: 3600 });

module.exports = mongoose.model('Session', sessionSchema);
