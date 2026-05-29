const express = require('express');
const { S3Client, PutObjectCommand, GetObjectCommand } = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
const { requireSession } = require('../auth/middleware');
const Message = require('../models/Message');
const Conversation = require('../models/Conversation');
const ActivePage = require('../models/ActivePage');
const winston = require('winston');

const router = express.Router();

let s3Client = null;
if (process.env.R2_ACCOUNT_ID && process.env.R2_ACCESS_KEY_ID && process.env.R2_SECRET_ACCESS_KEY) {
  s3Client = new S3Client({
    region: 'auto',
    endpoint: `https://${process.env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
    credentials: {
      accessKeyId: process.env.R2_ACCESS_KEY_ID,
      secretAccessKey: process.env.R2_SECRET_ACCESS_KEY,
    },
  });
}

router.use(requireSession);

// REST Fallback: Fetch missed messages
router.get('/:conversationId/messages', async (req, res) => {
  const { conversationId } = req.params;
  const { userId } = req.user;

  const conversation = await Conversation.findOne({ conversationId });
  if (!conversation || !conversation.participantUserIds.includes(userId)) {
    return res.status(404).json({ error: 'Conversation not found' });
  }

  // Optional: sync from a specific timestamp
  const since = req.query.since ? new Date(req.query.since) : new Date(0);

  const messages = await Message.find({
    conversationId,
    'timestamps.sent': { $gt: since }
  }).sort({ 'timestamps.sent': 1 });

  // Exclude internal Mongo ID
  const formatted = messages.map(m => ({
    messageId: m.messageId,
    senderUserId: m.senderUserId,
    encryptedBlob: m.encryptedBlob,
    tickStatus: m.tickStatus,
    timestamp: m.timestamps.sent
  }));

  res.json({ messages: formatted });
});

// REST Fallback: Post Read Receipt
router.post('/:conversationId/receipt', async (req, res) => {
  const { conversationId } = req.params;
  const { messageId } = req.body;
  const { userId } = req.user;

  const conversation = await Conversation.findOne({ conversationId });
  if (!conversation || !conversation.participantUserIds.includes(userId)) {
    return res.status(404).json({ error: 'Conversation not found' });
  }

  await Message.updateOne(
    { messageId, conversationId },
    { 
      $set: { 
        tickStatus: 'read',
        'timestamps.read': new Date()
      }
    }
  );

  res.json({ success: true });
});

router.post('/messages/upload-chapter-url', async (req, res) => {
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] messaging/router.js: POST /messages/upload-chapter-url received.`);
  const { conversationId, new_chapter_hash } = req.body;
  const { userId } = req.user;

  if (!conversationId || !new_chapter_hash) {
    return res.status(400).json({ error: 'Missing conversationId or new_chapter_hash' });
  }

  const conversation = await Conversation.findOne({ conversationId });
  if (!conversation) {
    return res.status(404).json({ error: 'Conversation not found' });
  }

  if (!conversation.participantUserIds.includes(userId)) {
    return res.status(403).json({ error: 'Forbidden' });
  }

  const r2Key = `convo_${conversationId}/chapter_${new_chapter_hash}`;

  if (s3Client) {
    try {
      const command = new PutObjectCommand({
        Bucket: process.env.R2_BUCKET_NAME || 'multilingo-media',
        Key: r2Key,
      });
      const signedUrl = await getSignedUrl(s3Client, command, { expiresIn: 900 }); // 15 mins
      return res.json({ uploadUrl: signedUrl });
    } catch (err) {
      if (process.env.DEBUG === 'true') winston.error(`[DEBUG] messaging/router.js: Failed to generate signed url: ${err.message}`);
      return res.status(500).json({ error: 'Failed to generate upload URL' });
    }
  } else {
    return res.json({ 
      uploadUrl: `https://mock-r2.local/upload/${r2Key}?token=mock`,
      mockWarning: 'R2 credentials missing, using mock upload URL.'
    });
  }
});

router.post('/messages/archive-chapter', async (req, res) => {
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] messaging/router.js: POST /messages/archive-chapter received.`);
  const { conversationId, new_chapter_hash } = req.body;
  const { userId } = req.user;

  if (!conversationId || !new_chapter_hash) {
    return res.status(400).json({ error: 'Missing conversationId or new_chapter_hash' });
  }

  const conversation = await Conversation.findOne({ conversationId });
  if (!conversation) {
    return res.status(404).json({ error: 'Conversation not found' });
  }

  if (!conversation.participantUserIds.includes(userId)) {
    return res.status(403).json({ error: 'Forbidden' });
  }

  conversation.latestChapterHash = new_chapter_hash;
  await conversation.save();

  await ActivePage.deleteOne({ conversationId });

  res.json({ success: true });
});

router.post('/messages/download-chapter-url', async (req, res) => {
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] messaging/router.js: POST /messages/download-chapter-url received.`);
  const { conversationId, chapter_hash } = req.body;
  const { userId } = req.user;

  if (!conversationId || !chapter_hash) {
    return res.status(400).json({ error: 'Missing conversationId or chapter_hash' });
  }

  const conversation = await Conversation.findOne({ conversationId });
  if (!conversation) {
    return res.status(404).json({ error: 'Conversation not found' });
  }

  if (!conversation.participantUserIds.includes(userId)) {
    return res.status(403).json({ error: 'Forbidden' });
  }

  const r2Key = `convo_${conversationId}/chapter_${chapter_hash}`;

  if (s3Client) {
    try {
      const command = new GetObjectCommand({
        Bucket: process.env.R2_BUCKET_NAME || 'multilingo-media',
        Key: r2Key,
      });
      const signedUrl = await getSignedUrl(s3Client, command, { expiresIn: 900 }); // 15 mins
      return res.json({ downloadUrl: signedUrl });
    } catch (err) {
      if (process.env.DEBUG === 'true') winston.error(`[DEBUG] messaging/router.js: Failed to generate signed download url: ${err.message}`);
      return res.status(500).json({ error: 'Failed to generate download URL' });
    }
  } else {
    return res.json({ 
      downloadUrl: `https://mock-r2.local/download/${r2Key}?token=mock`,
      mockWarning: 'R2 credentials missing, using mock download URL.'
    });
  }
});

module.exports = router;
