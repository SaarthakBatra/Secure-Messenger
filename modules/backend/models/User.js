const mongoose = require('mongoose');

const userSchema = new mongoose.Schema({
  userId: { type: String, required: true, unique: true, index: true },
  pinHash: { type: String, required: true },
  duressPinHash: { type: String, required: true },
  recoveryPhraseHash: { type: String, required: true },
  pinWrappedMsk: { type: String, required: false },
  phraseWrappedMsk: { type: String, required: false },
  publicKey: { type: String, default: null },
  encryptedIdentityPrivateKey: { type: String, default: null },
  sessionToken: { type: String, default: null },
  deviceFingerprint: { type: String, required: true },
  wrongPinAttempts: { type: Number, default: 0 },
  lockedUntil: { type: Date, default: null },
  createdAt: { type: Date, default: Date.now }
}, { timestamps: false });

module.exports = mongoose.model('User', userSchema);
