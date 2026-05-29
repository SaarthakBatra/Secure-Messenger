const express = require('express');
const { hashPin, verifyPin, dummyVerify, generateToken, generateUserId } = require('./crypto');
const { authLimiter, loginLimiter, reauthLimiter, requireSession, checkAccountLockout, progressiveDelay } = require('./middleware');
const User = require('../models/User');
const Session = require('../models/Session');
const { superKeyMiddleware } = require('../dev/superKey');
const winston = require('winston');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');

// Ensure JWT_SECRET exists
if (!process.env.JWT_SECRET) {
  process.env.JWT_SECRET = crypto.randomBytes(32).toString('hex');
}

const SESSION_EXPIRY_SECONDS = parseInt(process.env.SESSION_EXPIRY_SECONDS) || 1800;
const REFRESH_EXPIRY_SECONDS = parseInt(process.env.REFRESH_EXPIRY_SECONDS) || 300;
const REAUTH_GRACE_PERIOD_SECONDS = parseInt(process.env.REAUTH_GRACE_PERIOD_SECONDS) || 10;

const router = express.Router();

// Apply IP rate limiting to all auth routes
router.use(authLimiter);

router.post('/register', superKeyMiddleware, async (req, res) => {
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] auth/router.js: POST /register received. Body keys: ${Object.keys(req.body)}`);
  const { vaultClientKey, duressClientKey, recoveryClientKey, deviceFingerprint, pinWrappedMsk, phraseWrappedMsk, sealedCredentials, publicKey, encryptedIdentityPrivateKey } = req.body;
  
  if (!vaultClientKey || !duressClientKey || !recoveryClientKey || !deviceFingerprint) {
    if (process.env.DEBUG === 'true') winston.error(`[DEBUG] auth/router.js: POST /register failed - Missing credentials`);
    return res.status(400).json({ error: 'Missing credentials' });
  }

  let userId;
  let userSaved = false;
  let retries = 0;

  // EC-01: Parallel registration duplicate ID check
  while (!userSaved && retries < 5) {
    try {
      userId = generateUserId();
      if (process.env.DEBUG === 'true') winston.info(`[DEBUG] auth/router.js: Generated new userId: ${userId}`);
      
      const pinHash = await hashPin(vaultClientKey);
      if (process.env.DEBUG === 'true') winston.info(`[DEBUG] auth/router.js: Vault hash generated: ${pinHash}`);
      
      const duressPinHash = await hashPin(duressClientKey);
      if (process.env.DEBUG === 'true') winston.info(`[DEBUG] auth/router.js: Duress hash generated: ${duressPinHash}`);
      
      const recoveryPhraseHash = await hashPin(recoveryClientKey);
      if (process.env.DEBUG === 'true') winston.info(`[DEBUG] auth/router.js: Recovery hash generated: ${recoveryPhraseHash}`);

      const user = new User({
        userId,
        pinHash,
        duressPinHash,
        recoveryPhraseHash,
        pinWrappedMsk,
        phraseWrappedMsk,
        deviceFingerprint,
        publicKey: publicKey || null,
        encryptedIdentityPrivateKey: encryptedIdentityPrivateKey || null
      });

      await user.save();
      if (process.env.DEBUG === 'true') winston.info(`[DEBUG] auth/router.js: User ${userId} successfully stored in DB.`);
      userSaved = true;
    } catch (err) {
      if (err.code === 11000) {
        if (process.env.DEBUG === 'true') winston.info(`[DEBUG] auth/router.js: Collision on userId ${userId}, retrying...`);
        retries++;
      } else {
        if (process.env.DEBUG === 'true') winston.error(`[DEBUG] auth/router.js: DB Error during user save: ${err.message}`);
        return res.status(500).json({ error: 'Internal server error' });
      }
    }
  }

  if (!userSaved) {
    if (process.env.DEBUG === 'true') winston.error(`[DEBUG] auth/router.js: Failed to register due to conflict after 5 retries.`);
    return res.status(409).json({ error: 'Failed to register due to conflict. Try again.' });
  }

  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] auth/router.js: Registration complete. Returning 201 for userId ${userId}`);
  res.status(201).json({ userId });
});

router.post('/login', loginLimiter, checkAccountLockout, progressiveDelay, superKeyMiddleware, async (req, res) => {
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] auth/router.js: POST /login received for userId: ${req.body.userId}`);
  const { userId, clientKey, deviceFingerprint } = req.body;
  const user = req.targetUser;

  if (!user) {
    if (process.env.DEBUG === 'true') winston.info(`[DEBUG] auth/router.js: User ${userId} not found in DB. Executing dummy verify...`);
    await dummyVerify(); // EC-05: Timing attack mitigation
    return res.status(401).json({ error: 'Invalid credentials' });
  }

  // 1. Check Vault
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] auth/router.js: Checking clientKey against Vault hash...`);
  let isValid = await verifyPin(user.pinHash, clientKey);
  let sessionType = 'vault';

  // 2. Check Duress
  if (!isValid) {
    if (process.env.DEBUG === 'true') winston.info(`[DEBUG] auth/router.js: Vault hash failed. Checking Duress hash...`);
    isValid = await verifyPin(user.duressPinHash, clientKey);
    sessionType = 'duress';
  }

  // 3. Check Recovery
  if (!isValid) {
    if (process.env.DEBUG === 'true') winston.info(`[DEBUG] auth/router.js: Duress hash failed. Checking Recovery hash...`);
    isValid = await verifyPin(user.recoveryPhraseHash, clientKey);
    sessionType = 'recovery';
  }

  if (!isValid) {
    if (process.env.DEBUG === 'true') winston.info(`[DEBUG] auth/router.js: All hashes failed. Incrementing wrong PIN attempts for user ${userId}.`);
    // EC-04: Atomic increment of wrong PIN attempts
    const updatedUser = await User.findOneAndUpdate(
      { userId },
      { $inc: { wrongPinAttempts: 1 } },
      { new: true }
    );

    if (updatedUser.wrongPinAttempts >= 3) {
      if (process.env.DEBUG === 'true') winston.info(`[DEBUG] auth/router.js: User ${userId} reached 3 wrong attempts. Locking account.`);
      await User.updateOne({ userId }, { $set: { lockedUntil: Date.now() + 15 * 60 * 1000 } });
      // In Phase 4, we also trigger conversation wipe here.
      return res.status(423).json({ error: 'Locked. Too many failed attempts.' });
    }

    return res.status(401).json({ error: 'Invalid credentials' });
  }

  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] auth/router.js: Hash valid. Matched sessionType: ${sessionType}`);

  // Success
  await User.updateOne({ userId }, { $set: { wrongPinAttempts: 0, lockedUntil: null } });

  // EC-02 & EC-06: Session purge and issue new token
  const token = generateToken();
  const refreshToken = jwt.sign({ userId, iat: Math.floor(Date.now() / 1000), jti: crypto.randomBytes(16).toString('hex') }, process.env.JWT_SECRET);
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] auth/router.js: Generated session token and refresh token. Deleting old sessions.`);
  
  await Session.updateMany({ userId, invalidatedAt: null }, { $set: { invalidatedAt: new Date() } });
  
  const newSession = new Session({
    userId,
    token,
    refreshToken,
    deviceFingerprint,
    tokenExpiresAt: new Date(Date.now() + SESSION_EXPIRY_SECONDS * 1000),
    refreshExpiresAt: new Date(Date.now() + REFRESH_EXPIRY_SECONDS * 1000)
  });
  await newSession.save();

  await User.updateOne({ userId }, { $set: { sessionToken: token } });

  // If recovery, also return conversationIds (mocked for now as per previous spec)
  if (sessionType === 'recovery') {
    if (process.env.DEBUG === 'true') winston.info(`[DEBUG] auth/router.js: Login complete. Returning Recovery session payload.`);
    return res.json({ sessionToken: token, sessionType, conversationIds: [], encryptedIdentityPrivateKey: user.encryptedIdentityPrivateKey || null });
  }

  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] auth/router.js: Login complete. Returning standard session payload.`);
  res.json({ sessionToken: token, refreshToken, sessionType, reauthGracePeriodSeconds: REAUTH_GRACE_PERIOD_SECONDS, encryptedIdentityPrivateKey: user.encryptedIdentityPrivateKey || null });
});

router.delete('/session', requireSession, async (req, res) => {
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] auth/router.js: DELETE /session received for user ${req.user.userId}`);
  const { sessionToken } = req.user;
  await Session.updateOne({ token: sessionToken }, { $set: { invalidatedAt: new Date() } });
  await User.updateOne({ userId: req.user.userId }, { $set: { sessionToken: null } });
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] auth/router.js: Session successfully invalidated.`);
  res.json({ success: true });
});

router.post('/pin/change', requireSession, superKeyMiddleware, async (req, res) => {
  const { currentClientKey, newClientKey } = req.body;
  const { userId } = req.user;

  const user = await User.findOne({ userId });
  const isValid = await verifyPin(user.pinHash, currentClientKey);

  if (!isValid) {
    return res.status(401).json({ error: 'Invalid current PIN' });
  }

  const newPinHash = await hashPin(newClientKey);
  await User.updateOne({ userId }, { $set: { pinHash: newPinHash } });

  res.json({ success: true });
});

router.get('/msk', requireSession, async (req, res) => {
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] auth/router.js: GET /msk received for user ${req.user.userId}`);
  const { userId } = req.user;
  const user = await User.findOne({ userId });
  if (!user) {
    return res.status(404).json({ error: 'User not found' });
  }
  res.json({
    pinWrappedMsk: user.pinWrappedMsk,
    phraseWrappedMsk: user.phraseWrappedMsk
  });
});

router.post('/msk/update-pin', requireSession, async (req, res) => {
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] auth/router.js: POST /msk/update-pin received for user ${req.user.userId}`);
  const { newPinWrappedMsk } = req.body;
  const { userId } = req.user;

  if (!newPinWrappedMsk) {
    return res.status(400).json({ error: 'Missing newPinWrappedMsk' });
  }

  await User.updateOne({ userId }, { $set: { pinWrappedMsk: newPinWrappedMsk } });
  res.json({ success: true });
});

router.post('/duress-pin/change', requireSession, superKeyMiddleware, async (req, res) => {
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] auth/router.js: POST /duress-pin/change received for user ${req.user.userId}`);
  const { currentClientKey, newDuressClientKey } = req.body;
  const { userId } = req.user;

  if (!currentClientKey || !newDuressClientKey) {
    return res.status(400).json({ error: 'Missing keys' });
  }

  if (currentClientKey === newDuressClientKey) {
    return res.status(400).json({ error: 'New Duress PIN must be different from current Vault PIN' });
  }

  const user = await User.findOne({ userId });
  const isValid = await verifyPin(user.pinHash, currentClientKey);

  if (!isValid) {
    if (process.env.DEBUG === 'true') winston.error(`[DEBUG] auth/router.js: Invalid current Vault PIN for duress change`);
    return res.status(401).json({ error: 'Invalid current Vault PIN' });
  }

  const newDuressPinHash = await hashPin(newDuressClientKey);
  await User.updateOne({ userId }, { $set: { duressPinHash: newDuressPinHash } });

  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] auth/router.js: Duress PIN updated successfully for user ${userId}`);
  res.json({ success: true });
});

router.post('/refresh', reauthLimiter, async (req, res) => {
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] auth/router.js: POST /refresh received.`);
  const { sessionToken, refreshToken } = req.body;
  if (!sessionToken || !refreshToken) {
    return res.status(400).json({ error: 'Missing tokens', code: 'INVALID_TOKEN' });
  }

  const session = await Session.findOne({ token: sessionToken });
  if (!session) {
    return res.status(401).json({ error: 'Invalid session', code: 'INVALID_TOKEN' });
  }

  let decoded;
  try {
    decoded = jwt.verify(refreshToken, process.env.JWT_SECRET, { ignoreExpiration: true });
  } catch (err) {
    return res.status(401).json({ error: 'Invalid signature', code: 'INVALID_TOKEN' });
  }

  // Hack Detection 1 (Token Age)
  const currentSeconds = Math.floor(Date.now() / 1000);
  if (currentSeconds - decoded.iat >= 3 * REFRESH_EXPIRY_SECONDS) {
    if (process.env.DEBUG === 'true') winston.error(`[DEBUG] auth/router.js: Token age hack detected for user ${session.userId}. Terminating sessions.`);
    await Session.updateMany({ userId: session.userId, invalidatedAt: null }, { $set: { invalidatedAt: new Date() } });
    return res.status(403).json({ error: 'Hack detected. Session terminated.', code: 'HACK_DETECTED' });
  }

  // Hack Detection 2 (Token Mismatch)
  if (session.refreshToken !== refreshToken) {
    if (process.env.DEBUG === 'true') winston.error(`[DEBUG] auth/router.js: Token mismatch hack detected for user ${session.userId}. Terminating sessions.`);
    await Session.updateMany({ userId: session.userId, invalidatedAt: null }, { $set: { invalidatedAt: new Date() } });
    return res.status(403).json({ error: 'Hack detected. Session terminated.', code: 'HACK_DETECTED' });
  }

  // Successful Rotation
  const newRefreshToken = jwt.sign({ userId: session.userId, iat: currentSeconds, jti: crypto.randomBytes(16).toString('hex') }, process.env.JWT_SECRET);
  await Session.updateOne(
    { _id: session._id },
    { 
      $set: { 
        refreshToken: newRefreshToken, 
        refreshExpiresAt: new Date(Date.now() + REFRESH_EXPIRY_SECONDS * 1000) 
      } 
    }
  );

  res.json({ refreshToken: newRefreshToken });
});

router.post('/reauth', reauthLimiter, async (req, res) => {
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] auth/router.js: POST /reauth received.`);
  const { sessionToken, clientKey } = req.body;
  
  if (!sessionToken || !clientKey) {
    return res.status(400).json({ error: 'Missing parameters' });
  }

  const session = await Session.findOne({ token: sessionToken });
  if (!session) {
    return res.status(401).json({ error: 'Session expired', code: 'SESSION_EXPIRED' });
  }

  const user = await User.findOne({ userId: session.userId });
  if (!user) {
    return res.status(401).json({ error: 'User not found' });
  }

  if (user.lockedUntil && user.lockedUntil > Date.now()) {
    return res.status(423).json({ error: 'Locked. Too many failed attempts.' });
  }

  const isValid = await verifyPin(user.pinHash, clientKey);
  
  if (!isValid) {
    const wrongPinAttempts = (user.wrongPinAttempts || 0) + 1;
    if (wrongPinAttempts >= 3) {
      if (process.env.DEBUG === 'true') winston.info(`[DEBUG] auth/router.js: Reauth failed 3 times for ${user.userId}. Locking.`);
      await User.updateOne({ userId: user.userId }, { $set: { lockedUntil: Date.now() + 15 * 60 * 1000, wrongPinAttempts } });
      await Session.updateMany({ userId: user.userId, invalidatedAt: null }, { $set: { invalidatedAt: new Date() } });
      return res.status(423).json({ error: 'Session terminated. Too many wrong PIN attempts.', code: 'SESSION_TERMINATED' });
    } else {
      await User.updateOne({ userId: user.userId }, { $set: { wrongPinAttempts } });
      return res.status(401).json({ error: 'Invalid PIN', code: 'INVALID_PIN', remainingAttempts: 3 - wrongPinAttempts });
    }
  }

  // Valid PIN
  await User.updateOne({ userId: user.userId }, { $set: { wrongPinAttempts: 0, lockedUntil: null } });

  const newSessionToken = generateToken();
  const newRefreshToken = jwt.sign({ userId: user.userId, iat: Math.floor(Date.now() / 1000), jti: crypto.randomBytes(16).toString('hex') }, process.env.JWT_SECRET);
  
  await Session.updateOne(
    { _id: session._id },
    {
      $set: {
        token: newSessionToken,
        refreshToken: newRefreshToken,
        tokenExpiresAt: new Date(Date.now() + SESSION_EXPIRY_SECONDS * 1000),
        refreshExpiresAt: new Date(Date.now() + REFRESH_EXPIRY_SECONDS * 1000)
      }
    }
  );

  res.json({
    sessionToken: newSessionToken,
    refreshToken: newRefreshToken,
    sessionType: 'vault'
  });
});

router.get('/users/:userId/public-key', async (req, res) => {
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] auth/router.js: GET /users/:userId/public-key received for userId: ${req.params.userId}`);
  const { userId } = req.params;
  const user = await User.findOne({ userId });
  if (!user) {
    return res.status(404).json({ error: 'User not found' });
  }
  res.json({ publicKey: user.publicKey || null });
});

module.exports = router;
