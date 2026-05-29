const request = require('supertest');
const express = require('express');
const mongoose = require('mongoose');
const jwt = require('jsonwebtoken');
const { MongoMemoryServer } = require('mongodb-memory-server');

const authRouter = require('../../../modules/backend/auth/router');
const User = require('../../../modules/backend/models/User');
const Session = require('../../../modules/backend/models/Session');
const { hashPin } = require('../../../modules/backend/auth/crypto');

const app = express();
app.use(express.json());
app.use('/auth', authRouter);

let mongoServer;

beforeAll(async () => {
  mongoServer = await MongoMemoryServer.create();
  await mongoose.connect(mongoServer.getUri());
  process.env.JWT_SECRET = 'test_secret';
  process.env.SESSION_EXPIRY_SECONDS = '1800';
  process.env.REFRESH_EXPIRY_SECONDS = '300';
  process.env.REAUTH_LIMITER_MAX = '1000';
});

afterAll(async () => {
  await mongoose.disconnect();
  await mongoServer.stop();
});

describe('Session Management & Hack Detection', () => {
  let user;
  let clientKey = 'test_vault_key';
  let pinHash;
  let sessionToken;
  let refreshToken;

  beforeEach(async () => {
    await User.deleteMany({});
    await Session.deleteMany({});
    
    pinHash = await hashPin(clientKey);
    
    user = new User({
      userId: 'user123',
      pinHash,
      duressPinHash: 'duress_hash',
      recoveryPhraseHash: 'recovery_hash',
      pinWrappedMsk: 'wrapped_msk',
      phraseWrappedMsk: 'phrase_wrapped_msk',
      deviceFingerprint: 'dev1'
    });
    await user.save();
  });

  describe('POST /auth/login', () => {
    it('should login and return session and refresh tokens', async () => {
      const res = await request(app)
        .post('/auth/login')
        .send({ userId: 'user123', clientKey, deviceFingerprint: 'dev1' });
      
      expect(res.status).toBe(200);
      expect(res.body).toHaveProperty('sessionToken');
      expect(res.body).toHaveProperty('refreshToken');
      expect(res.body.sessionType).toBe('vault');
      
      sessionToken = res.body.sessionToken;
      refreshToken = res.body.refreshToken;
      
      const session = await Session.findOne({ userId: 'user123', invalidatedAt: null });
      expect(session).not.toBeNull();
      expect(session.token).toBe(sessionToken);
      expect(session.refreshToken).toBe(refreshToken);
      expect(session.tokenExpiresAt).toBeDefined();
      expect(session.refreshExpiresAt).toBeDefined();
    });

    it('should delete old sessions on new login', async () => {
      // First login
      await request(app).post('/auth/login').send({ userId: 'user123', clientKey, deviceFingerprint: 'dev1' });
      const sessions1 = await Session.find({ userId: 'user123', invalidatedAt: null });
      expect(sessions1.length).toBe(1);
      
      // Second login
      await request(app).post('/auth/login').send({ userId: 'user123', clientKey, deviceFingerprint: 'dev2' });
      const sessions2 = await Session.find({ userId: 'user123', invalidatedAt: null });
      expect(sessions2.length).toBe(1); // Only one active session remains
      expect(sessions2[0].deviceFingerprint).toBe('dev2');
    });
  });

  describe('POST /auth/refresh', () => {
    beforeEach(async () => {
      const res = await request(app)
        .post('/auth/login')
        .send({ userId: 'user123', clientKey, deviceFingerprint: 'dev1' });
      sessionToken = res.body.sessionToken;
      refreshToken = res.body.refreshToken;
    });

    it('should return a new refresh token on valid request', async () => {
      const res = await request(app)
        .post('/auth/refresh')
        .send({ sessionToken, refreshToken });
      
      expect(res.status).toBe(200);
      expect(res.body).toHaveProperty('refreshToken');
      expect(res.body.refreshToken).not.toBe(refreshToken);

      const session = await Session.findOne({ token: sessionToken, invalidatedAt: null });
      expect(session.refreshToken).toBe(res.body.refreshToken);
    });

    it('should return 403 HACK_DETECTED if token mismatch', async () => {
      // Rotate token once
      const rot1 = await request(app).post('/auth/refresh').send({ sessionToken, refreshToken });
      const newRefreshToken = rot1.body.refreshToken;
      
      // Use old token (Replay)
      const res = await request(app).post('/auth/refresh').send({ sessionToken, refreshToken });
      expect(res.status).toBe(403);
      expect(res.body.code).toBe('HACK_DETECTED');
      
      // Verify session terminated
      const session = await Session.findOne({ userId: 'user123', invalidatedAt: null });
      expect(session).toBeNull();
    });

    it('should return 403 HACK_DETECTED if token age > 15 mins (3 * refresh window)', async () => {
      // Create a spoofed old token
      const oldIat = Math.floor(Date.now() / 1000) - 1000; // > 15 mins
      const oldToken = jwt.sign({ userId: 'user123', iat: oldIat }, process.env.JWT_SECRET);
      
      // Update session to hold old token
      await Session.updateOne({ token: sessionToken }, { $set: { refreshToken: oldToken } });

      const res = await request(app).post('/auth/refresh').send({ sessionToken, refreshToken: oldToken });
      expect(res.status).toBe(403);
      expect(res.body.code).toBe('HACK_DETECTED');
      
      const session = await Session.findOne({ userId: 'user123', invalidatedAt: null });
      expect(session).toBeNull();
    });
  });

  describe('POST /auth/reauth', () => {
    beforeEach(async () => {
      const res = await request(app)
        .post('/auth/login')
        .send({ userId: 'user123', clientKey, deviceFingerprint: 'dev1' });
      sessionToken = res.body.sessionToken;
    });

    it('should issue new tokens on valid PIN', async () => {
      const res = await request(app).post('/auth/reauth').send({ sessionToken, clientKey });
      
      expect(res.status).toBe(200);
      expect(res.body).toHaveProperty('sessionToken');
      expect(res.body).toHaveProperty('refreshToken');
      expect(res.body.sessionToken).not.toBe(sessionToken);
      
      const session = await Session.findOne({ userId: 'user123', invalidatedAt: null });
      expect(session.token).toBe(res.body.sessionToken);
    });

    it('should lock and terminate on 3 failed attempts', async () => {
      await request(app).post('/auth/reauth').send({ sessionToken, clientKey: 'wrong' }); // attempt 1
      await request(app).post('/auth/reauth').send({ sessionToken, clientKey: 'wrong' }); // attempt 2
      const res = await request(app).post('/auth/reauth').send({ sessionToken, clientKey: 'wrong' }); // attempt 3
      
      expect(res.status).toBe(423);
      expect(res.body.code).toBe('SESSION_TERMINATED');
      
      const session = await Session.findOne({ userId: 'user123', invalidatedAt: null });
      expect(session).toBeNull(); // Terminated
      
      const updatedUser = await User.findOne({ userId: 'user123' });
      expect(updatedUser.lockedUntil).not.toBeNull();
    });
  });
});
