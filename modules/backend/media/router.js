const express = require('express');
const crypto = require('crypto');
const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
const { requireSession } = require('../auth/middleware');
const MediaRef = require('../models/MediaRef');
const Conversation = require('../models/Conversation');

const router = express.Router();
router.use(requireSession);

// Initialize S3 Client conditionally
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

router.post('/upload-url', async (req, res) => {
  const { conversationId, contentType } = req.body;
  const { userId } = req.user;

  if (!conversationId || !contentType) {
    return res.status(400).json({ error: 'Missing conversationId or contentType' });
  }

  const conversation = await Conversation.findOne({ conversationId });
  if (!conversation || !conversation.participantUserIds.includes(userId)) {
    return res.status(403).json({ error: 'Forbidden' });
  }

  const mediaId = crypto.randomBytes(16).toString('hex');
  const r2Key = `media/${conversationId}/${mediaId}`;
  
  // Persist as PENDING initially
  const mediaRef = new MediaRef({
    mediaId,
    conversationId,
    r2Key,
    // Empty blob until confirmed
    encryptedMetaBlob: 'PENDING'
  });
  await mediaRef.save();

  if (s3Client) {
    // Generate real presigned URL
    try {
      const command = new PutObjectCommand({
        Bucket: process.env.R2_BUCKET_NAME || 'multilingo-media',
        Key: r2Key,
        ContentType: contentType,
      });
      const signedUrl = await getSignedUrl(s3Client, command, { expiresIn: 900 }); // 15 mins
      return res.json({ mediaId, uploadUrl: signedUrl });
    } catch (err) {
      return res.status(500).json({ error: 'Failed to generate upload URL' });
    }
  } else {
    // Mock fallback
    return res.json({ 
      mediaId, 
      uploadUrl: `https://mock-r2.local/upload/${r2Key}?token=mock`,
      mockWarning: 'R2 credentials missing, using mock upload URL.'
    });
  }
});

// Finalize upload
router.post('/', async (req, res) => {
  const { mediaId, encryptedMetaBlob } = req.body;
  const { userId } = req.user;

  if (!mediaId || !encryptedMetaBlob) {
    return res.status(400).json({ error: 'Missing mediaId or encryptedMetaBlob' });
  }

  const mediaRef = await MediaRef.findOne({ mediaId });
  if (!mediaRef) {
    return res.status(404).json({ error: 'MediaRef not found' });
  }

  const conversation = await Conversation.findOne({ conversationId: mediaRef.conversationId });
  if (!conversation || !conversation.participantUserIds.includes(userId)) {
    return res.status(403).json({ error: 'Forbidden' });
  }

  mediaRef.encryptedMetaBlob = encryptedMetaBlob;
  await mediaRef.save();

  res.json({ success: true, mediaId });
});

module.exports = router;
