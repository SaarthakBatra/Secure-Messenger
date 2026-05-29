process.env.SUPER_KEY_ENABLED = 'true';
process.env.SUPER_KEY = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

const request = require('supertest');
const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');
const { app } = require('../../../modules/backend/index');
const User = require('../../../modules/backend/models/User');
const Session = require('../../../modules/backend/models/Session');
const Conversation = require('../../../modules/backend/models/Conversation');
const ActivePage = require('../../../modules/backend/models/ActivePage');

let mongoServer;
let aliceToken;
let aliceUserId;
let bobToken;
let bobUserId;
let charlieToken;
let charlieUserId;
let conversationId;

beforeAll(async () => {
  mongoServer = await MongoMemoryServer.create();
  const uri = mongoServer.getUri();
  await mongoose.connect(uri);

  // Register Alice (admin/participant)
  const regAlice = await request(app).post('/auth/register').send({
    vaultClientKey: 'alice_vault',
    duressClientKey: 'alice_duress',
    recoveryClientKey: 'alice_phrase',
    deviceFingerprint: 'device_alice'
  });
  aliceUserId = regAlice.body.userId;
  const loginAlice = await request(app).post('/auth/login').send({
    userId: aliceUserId,
    clientKey: 'alice_vault',
    deviceFingerprint: 'device_alice'
  });
  aliceToken = loginAlice.body.sessionToken;

  // Register Bob (participant)
  const regBob = await request(app).post('/auth/register').send({
    vaultClientKey: 'bob_vault',
    duressClientKey: 'bob_duress',
    recoveryClientKey: 'bob_phrase',
    deviceFingerprint: 'device_bob'
  });
  bobUserId = regBob.body.userId;
  const loginBob = await request(app).post('/auth/login').send({
    userId: bobUserId,
    clientKey: 'bob_vault',
    deviceFingerprint: 'device_bob'
  });
  bobToken = loginBob.body.sessionToken;

  // Register Charlie (non-participant)
  const regCharlie = await request(app).post('/auth/register').send({
    vaultClientKey: 'charlie_vault',
    duressClientKey: 'charlie_duress',
    recoveryClientKey: 'charlie_phrase',
    deviceFingerprint: 'device_charlie'
  });
  charlieUserId = regCharlie.body.userId;
  const loginCharlie = await request(app).post('/auth/login').send({
    userId: charlieUserId,
    clientKey: 'charlie_vault',
    deviceFingerprint: 'device_charlie'
  });
  charlieToken = loginCharlie.body.sessionToken;
});

afterAll(async () => {
  await mongoose.disconnect();
  await mongoServer.stop();
});

afterEach(async () => {
  await Conversation.deleteMany({});
  await ActivePage.deleteMany({});
});

describe('Conversation Infrastructure Endpoints', () => {
  beforeEach(async () => {
    // Create conversation between Alice and Bob
    const res = await request(app)
      .post('/conversations')
      .set('Authorization', `Bearer ${aliceToken}`);
    conversationId = res.body.conversationId;

    // Join Bob
    await request(app)
      .post(`/conversations/${conversationId}/join`)
      .set('Authorization', `Bearer ${bobToken}`)
      .send({ conversationKey: res.body.conversationKey });
  });

  it('Should initially return latestChapterHash as null', async () => {
    const res = await request(app)
      .get(`/conversations/${conversationId}/latest-chapter`)
      .set('Authorization', `Bearer ${aliceToken}`);
    expect(res.status).toBe(200);
    expect(res.body.latestChapterHash).toBeNull();
  });

  it('Should reject non-participants for latest-chapter', async () => {
    const res = await request(app)
      .get(`/conversations/${conversationId}/latest-chapter`)
      .set('Authorization', `Bearer ${charlieToken}`);
    expect(res.status).toBe(403);
  });

  it('Should upsert and fetch active-page backup successfully', async () => {
    const updateTime = new Date().toISOString();
    // Alice backups
    const postRes = await request(app)
      .post(`/conversations/${conversationId}/active-page`)
      .set('Authorization', `Bearer ${aliceToken}`)
      .send({
        encryptedActivePage: 'encrypted_active_page_blob',
        updatedAt: updateTime
      });
    expect(postRes.status).toBe(200);
    expect(postRes.body.success).toBe(true);

    // Bob retrieves
    const getRes = await request(app)
      .get(`/conversations/${conversationId}/active-page`)
      .set('Authorization', `Bearer ${bobToken}`);
    expect(getRes.status).toBe(200);
    expect(getRes.body.encryptedActivePage).toBe('encrypted_active_page_blob');
    expect(new Date(getRes.body.updatedAt).toISOString()).toBe(updateTime);
  });

  it('Should reject non-participants for active-page endpoints', async () => {
    const postRes = await request(app)
      .post(`/conversations/${conversationId}/active-page`)
      .set('Authorization', `Bearer ${charlieToken}`)
      .send({
        encryptedActivePage: 'blob',
        updatedAt: new Date().toISOString()
      });
    expect(postRes.status).toBe(403);

    const getRes = await request(app)
      .get(`/conversations/${conversationId}/active-page`)
      .set('Authorization', `Bearer ${charlieToken}`);
    expect(getRes.status).toBe(403);
  });

  it('Should generate presigned upload url for participants', async () => {
    const res = await request(app)
      .post('/conversations/messages/upload-chapter-url')
      .set('Authorization', `Bearer ${aliceToken}`)
      .send({
        conversationId,
        new_chapter_hash: 'hash123'
      });
    expect(res.status).toBe(200);
    expect(res.body.uploadUrl).toBeDefined();
    expect(res.body.uploadUrl).toContain('hash123');
  });

  it('Should reject upload url for non-participants', async () => {
    const res = await request(app)
      .post('/conversations/messages/upload-chapter-url')
      .set('Authorization', `Bearer ${charlieToken}`)
      .send({
        conversationId,
        new_chapter_hash: 'hash123'
      });
    expect(res.status).toBe(403);
  });

  it('Should archive chapter, update latestChapterHash, and delete ActivePage document', async () => {
    // 1. Set active page
    await request(app)
      .post(`/conversations/${conversationId}/active-page`)
      .set('Authorization', `Bearer ${aliceToken}`)
      .send({
        encryptedActivePage: 'active_page_blob',
        updatedAt: new Date().toISOString()
      });

    // 2. Archive
    const archRes = await request(app)
      .post('/conversations/messages/archive-chapter')
      .set('Authorization', `Bearer ${aliceToken}`)
      .send({
        conversationId,
        new_chapter_hash: 'chapter_hash_xyz'
      });
    expect(archRes.status).toBe(200);
    expect(archRes.body.success).toBe(true);

    // 3. Check latestChapterHash updated
    const chapterRes = await request(app)
      .get(`/conversations/${conversationId}/latest-chapter`)
      .set('Authorization', `Bearer ${bobToken}`);
    expect(chapterRes.status).toBe(200);
    expect(chapterRes.body.latestChapterHash).toBe('chapter_hash_xyz');

    // 4. Check active page is reset/deleted
    const getRes = await request(app)
      .get(`/conversations/${conversationId}/active-page`)
      .set('Authorization', `Bearer ${aliceToken}`);
    expect(getRes.status).toBe(404);
  });

  it('Should reject archive-chapter for non-participants', async () => {
    const res = await request(app)
      .post('/conversations/messages/archive-chapter')
      .set('Authorization', `Bearer ${charlieToken}`)
      .send({
        conversationId,
        new_chapter_hash: 'hash123'
      });
    expect(res.status).toBe(403);
  });
});
