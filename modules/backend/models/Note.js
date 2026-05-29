const mongoose = require('mongoose');

const noteSchema = new mongoose.Schema({
  noteId: { type: String, required: true, unique: true, index: true },
  conversationId: { type: String, required: true, index: true },
  title: { type: String, required: true },
  encryptedContentBlob: { type: String, required: true },
  versions: [{
    versionId: { type: String },
    timestamp: { type: Date },
    encryptedContentBlob: { type: String }
  }],
  editLock: {
    userId: { type: String, default: null },
    expiresAt: { type: Date, default: null }
  }
}, { timestamps: false });

module.exports = mongoose.model('Note', noteSchema);
