process.env.SUPER_KEY_ENABLED = 'true';
process.env.SUPER_KEY = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

const request = require('supertest');
const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');
const { app } = require('../../../modules/backend/index');
const MediaRef = require('../../../modules/backend/models/MediaRef');

let mongoServer;
let userToken;
let conversationId;

beforeAll(async () => {
  mongoServer = await MongoMemoryServer.create();
  await mongoose.connect(mongoServer.getUri());

  const reg = await request(app).post('/auth/register').send({
    vaultClientKey: '11',
    duressClientKey: '22',
    recoveryClientKey: '33',
    deviceFingerprint: 'A'
  });
  const login = await request(app).post('/auth/login').send({
    userId: reg.body.userId,
    clientKey: '11',
    deviceFingerprint: 'A'
  });
  userToken = login.body.sessionToken;

  const conv = await request(app).post('/conversations').set('Authorization', `Bearer ${userToken}`);
  conversationId = conv.body.conversationId;
  await request(app).post(`/conversations/${conversationId}/join`).set('Authorization', `Bearer ${userToken}`).send({ conversationKey: conv.body.conversationKey });
});

afterAll(async () => {
  await mongoose.disconnect();
  await mongoServer.stop();
});

afterEach(async () => {
  await MediaRef.deleteMany({});
});

describe('Media Router', () => {
  it('Should generate mock upload URL without R2 credentials', async () => {
    // Ensure no R2 env vars
    delete process.env.R2_ACCOUNT_ID;

    const res = await request(app)
      .post('/media/upload-url')
      .set('Authorization', `Bearer ${userToken}`)
      .send({ conversationId, contentType: 'image/jpeg' });

    expect(res.status).toBe(200);
    expect(res.body.uploadUrl).toContain('mock-r2.local');
    expect(res.body.mockWarning).toBeDefined();

    const mediaRef = await MediaRef.findOne({ mediaId: res.body.mediaId });
    expect(mediaRef.encryptedMetaBlob).toBe('PENDING');
  });

  it('Should finalize media upload', async () => {
    const resUrl = await request(app)
      .post('/media/upload-url')
      .set('Authorization', `Bearer ${userToken}`)
      .send({ conversationId, contentType: 'image/jpeg' });

    const mediaId = resUrl.body.mediaId;

    const resFinalize = await request(app)
      .post('/media')
      .set('Authorization', `Bearer ${userToken}`)
      .send({ mediaId, encryptedMetaBlob: 'blobData' });

    expect(resFinalize.status).toBe(200);
    
    const mediaRef = await MediaRef.findOne({ mediaId });
    expect(mediaRef.encryptedMetaBlob).toBe('blobData');
  });
});
