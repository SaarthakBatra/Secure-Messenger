const express = require('express');
const crypto = require('crypto');
const { requireSession } = require('../auth/middleware');
const Note = require('../models/Note');
const Conversation = require('../models/Conversation');

const router = express.Router();
router.use(requireSession);

const winston = require('winston');

// Fetch all notes for a conversation
router.get('/conversation/:conversationId', async (req, res) => {
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] notes/router.js: GET /conversation/${req.params.conversationId} received for user ${req.user.userId}`);
  const { conversationId } = req.params;
  const { userId } = req.user;

  const conversation = await Conversation.findOne({ conversationId });
  if (!conversation || !conversation.participantUserIds.includes(userId)) {
    if (process.env.DEBUG === 'true') winston.error(`[DEBUG] notes/router.js: Forbidden or conversation not found`);
    return res.status(403).json({ error: 'Forbidden' });
  }

  const notes = await Note.find({ conversationId });
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] notes/router.js: Returning ${notes.length} notes`);
  res.json({ notes });
});

// Create Note
router.post('/', async (req, res) => {
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] notes/router.js: POST / received for conversation ${req.body.conversationId} by user ${req.user.userId}`);
  const { conversationId, title, encryptedContentBlob } = req.body;
  const { userId } = req.user;

  if (!conversationId || !title || !encryptedContentBlob) {
    if (process.env.DEBUG === 'true') winston.error(`[DEBUG] notes/router.js: Missing fields`);
    return res.status(400).json({ error: 'Missing fields' });
  }

  const conversation = await Conversation.findOne({ conversationId });
  if (!conversation || !conversation.participantUserIds.includes(userId)) {
    return res.status(403).json({ error: 'Forbidden' });
  }

  const noteId = crypto.randomBytes(12).toString('hex');

  const note = new Note({
    noteId,
    conversationId,
    title,
    encryptedContentBlob,
    versions: [],
    editLock: null
  });

  await note.save();
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] notes/router.js: Note ${noteId} successfully created`);
  res.status(201).json({ noteId });
});

// Acquire Lock
router.post('/:id/lock', async (req, res) => {
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] notes/router.js: POST /:id/lock received for note ${req.params.id} by user ${req.user.userId}`);
  const { id } = req.params;
  const { userId } = req.user;

  const note = await Note.findOne({ noteId: id });
  if (!note) return res.status(404).json({ error: 'Note not found' });

  const conversation = await Conversation.findOne({ conversationId: note.conversationId });
  if (!conversation || !conversation.participantUserIds.includes(userId)) {
    return res.status(403).json({ error: 'Forbidden' });
  }

  const now = new Date();
  const timeoutMs = process.env.NOTE_LOCK_TIMEOUT_MS ? parseInt(process.env.NOTE_LOCK_TIMEOUT_MS, 10) : 60000;

  // Check if locked by someone else and not expired
  if (note.editLock && note.editLock.userId !== userId && note.editLock.expiresAt > now) {
    if (process.env.DEBUG === 'true') winston.error(`[DEBUG] notes/router.js: Note ${id} is locked by ${note.editLock.userId}`);
    return res.status(423).json({ error: 'Locked by another user' }); // 423 Locked
  }

  note.editLock = {
    userId,
    expiresAt: new Date(now.getTime() + timeoutMs)
  };

  await note.save();
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] notes/router.js: Lock acquired for note ${id} by user ${userId} until ${note.editLock.expiresAt}`);
  res.json({ success: true, expiresAt: note.editLock.expiresAt });
});

// Release Lock
router.post('/:id/unlock', async (req, res) => {
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] notes/router.js: POST /:id/unlock received for note ${req.params.id}`);
  const { id } = req.params;
  const { userId } = req.user;

  const note = await Note.findOne({ noteId: id });
  if (!note) return res.status(404).json({ error: 'Note not found' });

  if (note.editLock && note.editLock.userId === userId) {
    note.editLock = null;
    await note.save();
    if (process.env.DEBUG === 'true') winston.info(`[DEBUG] notes/router.js: Lock released for note ${id}`);
  }

  res.json({ success: true });
});

// Edit Note
router.put('/:id', async (req, res) => {
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] notes/router.js: PUT /:id received for note ${req.params.id} by user ${req.user.userId}`);
  const { id } = req.params;
  const { encryptedContentBlob } = req.body;
  const { userId } = req.user;

  if (!encryptedContentBlob) {
    return res.status(400).json({ error: 'Missing encryptedContentBlob' });
  }

  const note = await Note.findOne({ noteId: id });
  if (!note) return res.status(404).json({ error: 'Note not found' });

  // Verify Lock
  const now = new Date();
  if (!note.editLock || note.editLock.userId !== userId || note.editLock.expiresAt < now) {
    if (process.env.DEBUG === 'true') winston.error(`[DEBUG] notes/router.js: Edit rejected - Lock not held or expired for note ${id}`);
    return res.status(423).json({ error: 'Must acquire lock before editing' });
  }

  // Push to versions
  note.versions.push({
    encryptedContentBlob: note.encryptedContentBlob,
    editedAt: new Date(),
    editedByUserId: userId // In zero-knowledge, editedByUserId could be stripped, but keeping it for now
  });

  note.encryptedContentBlob = encryptedContentBlob;
  note.updatedAt = new Date();
  
  await note.save();
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] notes/router.js: Note ${id} updated successfully. Previous version archived.`);
  res.json({ success: true });
});

module.exports = router;
