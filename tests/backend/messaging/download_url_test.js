process.env.SUPER_KEY_ENABLED = 'true';
process.env.SUPER_KEY = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

const request = require('supertest');
const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');
const { app } = require('../../../modules/backend/index');
const Conversation = require('../../../modules/backend/models/Conversation');

let mongoServer;
let userAId, userAToken;
let userBId, userBToken;
let userCId, userCToken;
let conversationId;

beforeAll(async () => {
  mongoServer = await MongoMemoryServer.create();
  const uri = mongoServer.getUri();
  await mongoose.connect(uri);

  // Register User A
  const regA = await request(app).post('/auth/register').send({
    vaultClientKey: '11',
    duressClientKey: '22',
    recoveryClientKey: '33',
    deviceFingerprint: 'A'
  });
  userAId = regA.body.userId;
  const loginA = await request(app).post('/auth/login').send({
    userId: userAId,
    clientKey: '11',
    deviceFingerprint: 'A'
  });
  userAToken = loginA.body.sessionToken;

  // Register User B
  const regB = await request(app).post('/auth/register').send({
    vaultClientKey: '11',
    duressClientKey: '22',
    recoveryClientKey: '33',
    deviceFingerprint: 'B'
  });
  userBId = regB.body.userId;
  const loginB = await request(app).post('/auth/login').send({
    userId: userBId,
    clientKey: '11',
    deviceFingerprint: 'B'
  });
  userBToken = loginB.body.sessionToken;

  // Register User C (Non-participant)
  const regC = await request(app).post('/auth/register').send({
    vaultClientKey: '11',
    duressClientKey: '22',
    recoveryClientKey: '33',
    deviceFingerprint: 'C'
  });
  userCId = regC.body.userId;
  const loginC = await request(app).post('/auth/login').send({
    userId: userCId,
    clientKey: '11',
    deviceFingerprint: 'C'
  });
  userCToken = loginC.body.sessionToken;

  // Create conversation between A and B
  const conv = await request(app).post('/conversations').set('Authorization', `Bearer ${userAToken}`);
  conversationId = conv.body.conversationId;
  const convKey = conv.body.conversationKey;

  // Join User B
  await request(app).post(`/conversations/${conversationId}/join`)
    .set('Authorization', `Bearer ${userBToken}`)
    .send({ conversationKey: convKey });
});

afterAll(async () => {
  await mongoose.disconnect();
  await mongoServer.stop();
});

describe('POST /conversations/messages/download-chapter-url', () => {
  it('Should return 400 Bad Request if conversationId is missing', async () => {
    const res = await request(app)
      .post('/conversations/messages/download-chapter-url')
      .set('Authorization', `Bearer ${userAToken}`)
      .send({ chapter_hash: 'hash123' });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe('Missing conversationId or chapter_hash');
  });

  it('Should return 400 Bad Request if chapter_hash is missing', async () => {
    const res = await request(app)
      .post('/conversations/messages/download-chapter-url')
      .set('Authorization', `Bearer ${userAToken}`)
      .send({ conversationId });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe('Missing conversationId or chapter_hash');
  });

  it('Should return 404 Not Found if conversation does not exist', async () => {
    const res = await request(app)
      .post('/conversations/messages/download-chapter-url')
      .set('Authorization', `Bearer ${userAToken}`)
      .send({ conversationId: 'non-existent-id', chapter_hash: 'hash123' });
    expect(res.status).toBe(404);
    expect(res.body.error).toBe('Conversation not found');
  });

  it('Should return 403 Forbidden if user is not a participant', async () => {
    const res = await request(app)
      .post('/conversations/messages/download-chapter-url')
      .set('Authorization', `Bearer ${userCToken}`)
      .send({ conversationId, chapter_hash: 'hash123' });
    expect(res.status).toBe(403);
    expect(res.body.error).toBe('Forbidden');
  });

  it('Should return a valid mock downloadUrl when S3 is not configured', async () => {
    const res = await request(app)
      .post('/conversations/messages/download-chapter-url')
      .set('Authorization', `Bearer ${userAToken}`)
      .send({ conversationId, chapter_hash: 'hash123' });
    expect(res.status).toBe(200);
    expect(res.body.downloadUrl).toContain(`convo_${conversationId}/chapter_hash123`);
    expect(res.body.downloadUrl).toContain('mock-r2.local');
  });
});
