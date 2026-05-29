const express = require('express');
const crypto = require('crypto');
const argon2 = require('argon2');
const { requireSession } = require('../auth/middleware');
const { ARGON2_OPTIONS } = require('../auth/crypto');
const { superKeyMiddleware } = require('../dev/superKey');
const Conversation = require('../models/Conversation');
const UserConversationKey = require('../models/UserConversationKey');
const ActivePage = require('../models/ActivePage');
const User = require('../models/User');
const sodium = require('libsodium-wrappers');

const router = express.Router();

router.use(requireSession);

// Generate random ID (alphanumeric, e.g. 12 chars)
function generateConversationId() {
  return crypto.randomBytes(6).toString('hex');
}

// Generate secure 256-bit key
function generateConversationKey() {
  return crypto.randomBytes(32).toString('hex');
}

const winston = require('winston');

router.post('/', superKeyMiddleware, async (req, res) => {
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] conversations/router.js: POST / received for adminUserId: ${req.user.userId}`);
  const adminUserId = req.user.userId;
  const { recipientUserId, invitationMessage } = req.body;

  await sodium.ready;

  if (recipientUserId) {
    // New asymmetric invite flow
    const recipientUser = await User.findOne({ userId: recipientUserId });
    if (!recipientUser || !recipientUser.publicKey) {
      return res.status(404).json({ error: 'Recipient not found or lacks public key' });
    }

    const aliceUser = await User.findOne({ userId: adminUserId });
    if (!aliceUser || !aliceUser.publicKey) {
      return res.status(404).json({ error: 'Sender public key not found' });
    }

    const conversationId = generateConversationId();
    const lessonKeyBytes = sodium.randombytes_buf(32);
    const lessonKeyHex = sodium.to_hex(lessonKeyBytes);
    const lessonKeyHexBuffer = Buffer.from(lessonKeyHex);

    try {
      const aliceInviteCiphertext = sodium.crypto_box_seal(lessonKeyHexBuffer, sodium.from_base64(aliceUser.publicKey, sodium.base64_variants.ORIGINAL));
      const bobInviteCiphertext = sodium.crypto_box_seal(lessonKeyHexBuffer, sodium.from_base64(recipientUser.publicKey, sodium.base64_variants.ORIGINAL));

      const aliceInvitePayload = sodium.to_base64(aliceInviteCiphertext, sodium.base64_variants.ORIGINAL);
      const bobInvitePayload = sodium.to_base64(bobInviteCiphertext, sodium.base64_variants.ORIGINAL);

      const keyHash = await argon2.hash(lessonKeyHex, ARGON2_OPTIONS);
      const encryptedBlob = Buffer.from(JSON.stringify({ keyHash })).toString('base64');

      const conversation = new Conversation({
        conversationId,
        adminUserId,
        participantUserIds: [adminUserId, recipientUserId],
        status: 'PENDING',
        encryptedBlob,
        aliceInvitePayload,
        bobInvitePayload,
        invitationMessage: invitationMessage || null
      });

      await conversation.save();

      // Send WebSocket notification if Bob is online
      const { activeConnections } = require('../ws/server');
      if (activeConnections && activeConnections.has(recipientUserId)) {
        const ws = activeConnections.get(recipientUserId);
        ws.send(JSON.stringify({
          type: 'PENDING_INVITE',
          payload: {
            conversationId,
            message: invitationMessage || null,
            bobInvite: bobInvitePayload,
            senderUserId: adminUserId
          }
        }));
      }

      res.status(201).json({
        conversationId,
        aliceInvite: aliceInvitePayload
      });
    } finally {
      // Memory security: zero/purge key from RAM
      lessonKeyBytes.fill(0);
      lessonKeyHexBuffer.fill(0);
    }
  } else {
    // Legacy flow
    const conversationId = generateConversationId();
    const conversationKey = generateConversationKey();
    
    if (process.env.DEBUG === 'true') winston.info(`[DEBUG] conversations/router.js: Hashing conversation key for conversationId: ${conversationId}`);
    // Hash the conversation key
    const keyHash = await argon2.hash(conversationKey, ARGON2_OPTIONS);
    
    // Payload for the encryptedBlob (normally this would be client-side zero-knowledge encrypted,
    // but for the backend Phase 0.3 schema requirement, we store the hashed key here to verify joins)
    const metadata = {
      keyHash: keyHash
    };
    
    // Encode the metadata into a string (mocking the encrypted payload for the backend logic)
    const encryptedBlob = Buffer.from(JSON.stringify(metadata)).toString('base64');
    
    const conversation = new Conversation({
      conversationId,
      adminUserId,
      participantUserIds: [adminUserId],
      status: 'PENDING',
      encryptedBlob
    });

    await conversation.save();
    if (process.env.DEBUG === 'true') winston.info(`[DEBUG] conversations/router.js: Conversation ${conversationId} stored in DB. Returning plaintext key once.`);

    // Return the plaintext key EXACTLY ONCE (EC-15)
    // It is never stored in plaintext in the DB.
    res.status(201).json({
      conversationId,
      conversationKey
    });
  }
});

router.get('/pending', async (req, res) => {
  const { userId } = req.user;
  try {
    const pendingConvos = await Conversation.find({
      status: 'PENDING',
      participantUserIds: userId,
      adminUserId: { $ne: userId }
    });

    const response = pendingConvos.map(convo => ({
      conversationId: convo.conversationId,
      message: convo.invitationMessage,
      bobInvite: convo.bobInvitePayload,
      senderUserId: convo.adminUserId
    }));

    res.json(response);
  } catch (err) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/:id/join', superKeyMiddleware, async (req, res) => {
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] conversations/router.js: POST /:id/join received for conversationId: ${req.params.id}`);
  const { id } = req.params;
  const { conversationKey } = req.body;
  const { userId } = req.user;

  if (!conversationKey) {
    if (process.env.DEBUG === 'true') winston.error(`[DEBUG] conversations/router.js: Missing conversationKey`);
    return res.status(400).json({ error: 'Missing conversationKey' });
  }

  const conversation = await Conversation.findOne({ conversationId: id });
  
  if (!conversation) {
    if (process.env.DEBUG === 'true') winston.error(`[DEBUG] conversations/router.js: Conversation ${id} not found`);
    return res.status(404).json({ error: 'Conversation not found' });
  }

  if (conversation.status !== 'PENDING') {
    if (process.env.DEBUG === 'true') winston.error(`[DEBUG] conversations/router.js: Conversation ${id} is not PENDING`);
    return res.status(403).json({ error: 'Conversation is not pending' });
  }

  // Extract the keyHash from the blob (as designed in the mock zero-knowledge structure)
  const metadata = JSON.parse(Buffer.from(conversation.encryptedBlob, 'base64').toString('utf8'));
  
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] conversations/router.js: Verifying conversationKey against keyHash`);
  const isValid = await argon2.verify(metadata.keyHash, conversationKey);
  
  if (!isValid) {
    if (process.env.DEBUG === 'true') winston.error(`[DEBUG] conversations/router.js: Invalid conversation key for ${id}`);
    return res.status(401).json({ error: 'Invalid conversation key' });
  }

  conversation.status = 'ACTIVE';
  conversation.bobInvitePayload = null;
  if (!conversation.participantUserIds.includes(userId)) {
    conversation.participantUserIds.push(userId);
  }
  
  await conversation.save();
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] conversations/router.js: User ${userId} joined conversation ${id}`);

  res.json({ success: true, conversationId: conversation.conversationId });
});

router.delete('/:id/pending', superKeyMiddleware, async (req, res) => {
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] conversations/router.js: DELETE /:id/pending received for conversationId: ${req.params.id}`);
  const { id } = req.params;
  const { userId } = req.user;

  const conversation = await Conversation.findOne({ conversationId: id });
  
  if (!conversation) {
    return res.status(404).json({ error: 'Conversation not found' });
  }

  if (conversation.adminUserId !== userId) {
    return res.status(403).json({ error: 'Forbidden' });
  }

  if (conversation.status !== 'PENDING') {
    return res.status(400).json({ error: 'Cannot delete active conversation' });
  }

  await Conversation.deleteOne({ conversationId: id });
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] conversations/router.js: Conversation ${id} deleted by admin`);

  res.json({ success: true });
});

router.get('/', async (req, res) => {
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] conversations/router.js: GET / received for user ${req.user.userId}`);
  const { userId } = req.user;

  const conversations = await Conversation.find({
    participantUserIds: userId
  }).select('conversationId status adminUserId createdAt -_id');

  res.json({ conversations });
});

const { burnConversation } = require('./burn');

router.delete('/:id/burn', async (req, res) => {
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] conversations/router.js: DELETE /:id/burn received for conversationId: ${req.params.id} by user ${req.user.userId}`);
  const { id } = req.params;
  const { userId } = req.user;

  const conversation = await Conversation.findOne({ conversationId: id });
  
  if (!conversation) {
    return res.status(404).json({ error: 'Conversation not found' });
  }

  if (!conversation.participantUserIds.includes(userId)) {
    return res.status(403).json({ error: 'Forbidden' });
  }

  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] conversations/router.js: Invoking burnConversation(${id})`);
  await burnConversation(id);
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] conversations/router.js: BURN PROTOCOL executed for conversation ${id}`);

  res.json({ success: true, message: 'BURN PROTOCOL executed' });
});

router.post('/escrow', async (req, res) => {
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] conversations/router.js: POST /escrow received for user ${req.user.userId}`);
  const { conversationId, encryptedConversationKey, localAlias } = req.body;
  const { userId } = req.user;

  if (!conversationId || !encryptedConversationKey) {
    return res.status(400).json({ error: 'Missing required fields' });
  }

  try {
    const escrowRecord = new UserConversationKey({
      userId,
      conversationId,
      encryptedConversationKey,
      localAlias
    });

    await escrowRecord.save();
    if (process.env.DEBUG === 'true') winston.info(`[DEBUG] conversations/router.js: Escrow record saved for user ${userId}, conversation ${conversationId}`);
    res.status(201).json({ success: true });
  } catch (err) {
    if (err.code === 11000) {
      return res.status(409).json({ error: 'Escrow record already exists' });
    }
    if (process.env.DEBUG === 'true') winston.error(`[DEBUG] conversations/router.js: Error saving escrow record: ${err.message}`);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/escrow', async (req, res) => {
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] conversations/router.js: GET /escrow received for user ${req.user.userId}`);
  const { userId } = req.user;

  const escrows = await UserConversationKey.find({ userId }).select('-_id -__v');
  res.json({ escrows });
});

router.post('/:id/active-page', async (req, res) => {
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] conversations/router.js: POST /:id/active-page received for conversationId: ${req.params.id}`);
  const { id } = req.params;
  const { encryptedActivePage, updatedAt } = req.body;
  const { userId } = req.user;

  if (!encryptedActivePage || !updatedAt) {
    return res.status(400).json({ error: 'Missing encryptedActivePage or updatedAt' });
  }

  const conversation = await Conversation.findOne({ conversationId: id });
  if (!conversation) {
    return res.status(404).json({ error: 'Conversation not found' });
  }

  if (!conversation.participantUserIds.includes(userId)) {
    return res.status(403).json({ error: 'Forbidden' });
  }

  await ActivePage.findOneAndUpdate(
    { conversationId: id },
    { 
      $set: { 
        encryptedActivePage, 
        updatedAt: new Date(updatedAt) 
      } 
    },
    { new: true, upsert: true }
  );

  res.json({ success: true, conversationId: id });
});

router.get('/:id/active-page', async (req, res) => {
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] conversations/router.js: GET /:id/active-page received for conversationId: ${req.params.id}`);
  const { id } = req.params;
  const { userId } = req.user;

  const conversation = await Conversation.findOne({ conversationId: id });
  if (!conversation) {
    return res.status(404).json({ error: 'Conversation not found' });
  }

  if (!conversation.participantUserIds.includes(userId)) {
    return res.status(403).json({ error: 'Forbidden' });
  }

  const activePage = await ActivePage.findOne({ conversationId: id });
  if (!activePage) {
    return res.status(404).json({ error: 'Active page backup not found' });
  }

  res.json({
    encryptedActivePage: activePage.encryptedActivePage,
    updatedAt: activePage.updatedAt
  });
});

router.get('/:id/latest-chapter', async (req, res) => {
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] conversations/router.js: GET /:id/latest-chapter received for conversationId: ${req.params.id}`);
  const { id } = req.params;
  const { userId } = req.user;

  const conversation = await Conversation.findOne({ conversationId: id });
  if (!conversation) {
    return res.status(404).json({ error: 'Conversation not found' });
  }

  if (!conversation.participantUserIds.includes(userId)) {
    return res.status(403).json({ error: 'Forbidden' });
  }

  res.json({ latestChapterHash: conversation.latestChapterHash || null });
});

module.exports = router;
