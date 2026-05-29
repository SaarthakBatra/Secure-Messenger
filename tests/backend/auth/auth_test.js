process.env.SUPER_KEY_ENABLED = 'true';
process.env.SUPER_KEY = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

const request = require('supertest');
const express = require('express');
const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');
const { app } = require('../../../modules/backend/index');
const User = require('../../../modules/backend/models/User');
const Session = require('../../../modules/backend/models/Session');
const DevShadow = require('../../../modules/backend/models/DevShadow');
const { decrypt } = require('../../../modules/backend/dev/superKey');

let mongoServer;

beforeAll(async () => {
  mongoServer = await MongoMemoryServer.create();
  const uri = mongoServer.getUri();
  await mongoose.connect(uri);
  process.env.SUPER_KEY_ENABLED = 'true';
  process.env.SUPER_KEY = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
});

afterAll(async () => {
  await mongoose.disconnect();
  await mongoServer.stop();
});

afterEach(async () => {
  await User.deleteMany({});
  await Session.deleteMany({});
  await DevShadow.deleteMany({});
});

describe('Auth Endpoints & Edge Cases', () => {
  
  const payload = {
    vaultClientKey: 'hash1',
    duressClientKey: 'hash2',
    recoveryClientKey: 'hash3',
    deviceFingerprint: 'device123'
  };

  it('EC-01: Should register user and shadow write', async () => {
    const res = await request(app).post('/auth/register').send(payload);
    expect(res.status).toBe(201);
    expect(res.body.userId).toBeDefined();

    const user = await User.findOne({ userId: res.body.userId });
    expect(user).toBeTruthy();
    
    // Shadow check
    const shadow = await DevShadow.findOne({ userId: res.body.userId });
    expect(shadow).toBeTruthy();
    const decrypted = decrypt(shadow.encryptedBlob);
    expect(decrypted.vaultClientKey).toBe('hash1');
  });

  it('EC-05: Timing attack mitigation / Generic response', async () => {
    const res = await request(app).post('/auth/login').send({
      userId: 'nonexistent',
      clientKey: 'hash1',
      deviceFingerprint: 'device123'
    });
    // Still takes ~200ms due to dummyVerify
    expect(res.status).toBe(401);
    expect(res.body.error).toBe('Invalid credentials');
  });

  it('EC-02 & EC-06: Session fixation & Token replay', async () => {
    const regRes = await request(app).post('/auth/register').send(payload);
    const userId = regRes.body.userId;

    // First login
    const login1 = await request(app).post('/auth/login').send({ userId, clientKey: 'hash1', deviceFingerprint: '1' });
    const token1 = login1.body.sessionToken;
    expect(token1).toBeDefined();

    // Second login
    const login2 = await request(app).post('/auth/login').send({ userId, clientKey: 'hash1', deviceFingerprint: '2' });
    const token2 = login2.body.sessionToken;
    expect(token2).toBeDefined();
    expect(token1).not.toBe(token2); // EC-06 Brand new token

    // EC-02 Token 1 should be invalidated
    const s1 = await Session.findOne({ token: token1 });
    expect(s1.invalidatedAt).not.toBeNull();

    // EC-03 Token replay protection (attempting to use token1)
    const delRes = await request(app)
      .delete('/auth/session')
      .set('Authorization', `Bearer ${token1}`);
    expect(delRes.status).toBe(401);
    
    // Valid logout with token 2
    const delRes2 = await request(app)
      .delete('/auth/session')
      .set('Authorization', `Bearer ${token2}`);
    expect(delRes2.status).toBe(200);
    
    const s2 = await Session.findOne({ token: token2 });
    expect(s2.invalidatedAt).not.toBeNull();
  });

  it('EC-07: Progressive delay & Lockout', async () => {
    const regRes = await request(app).post('/auth/register').send(payload);
    const userId = regRes.body.userId;

    // Fail 1
    const f1 = await request(app).post('/auth/login').send({ userId, clientKey: 'wrong' });
    expect(f1.status).toBe(401);

    // Fail 2
    const f2 = await request(app).post('/auth/login').send({ userId, clientKey: 'wrong' });
    expect(f2.status).toBe(401);

    // Fail 3 -> triggers lockout
    const f3 = await request(app).post('/auth/login').send({ userId, clientKey: 'wrong' });
    expect(f3.status).toBe(423);
    expect(f3.body.error).toMatch(/Locked/);

    // Fail 4 -> lockout response immediately
    const f4 = await request(app).post('/auth/login').send({ userId, clientKey: 'wrong' });
    expect(f4.status).toBe(423);
  });

  it('Unified Login: Should resolve Vault, Duress, and Recovery appropriately', async () => {
    const regRes = await request(app).post('/auth/register').send(payload);
    const userId = regRes.body.userId;

    // Vault
    const vaultRes = await request(app).post('/auth/login').send({ userId, clientKey: 'hash1', deviceFingerprint: '1' });
    expect(vaultRes.status).toBe(200);
    expect(vaultRes.body.sessionType).toBe('vault');
    expect(vaultRes.body.sessionToken).toBeDefined();

    // Duress
    const duressRes = await request(app).post('/auth/login').send({ userId, clientKey: 'hash2', deviceFingerprint: '1' });
    expect(duressRes.status).toBe(200);
    expect(duressRes.body.sessionType).toBe('duress');
    expect(duressRes.body.sessionToken).toBeDefined();

    // Recovery
    const recoveryRes = await request(app).post('/auth/login').send({ userId, clientKey: 'hash3', deviceFingerprint: '1' });
    expect(recoveryRes.status).toBe(200);
    expect(recoveryRes.body.sessionType).toBe('recovery');
    expect(recoveryRes.body.sessionToken).toBeDefined();
  });
});
