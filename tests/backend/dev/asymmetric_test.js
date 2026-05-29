process.env.SUPER_KEY_ENABLED = 'true';
process.env.SUPER_KEY = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

const request = require('supertest');
const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');
const sodium = require('libsodium-wrappers');
const { app, startServer } = require('../../../modules/backend/index');
const DevShadow = require('../../../modules/backend/models/DevShadow');
const { initKeypair, getPublicKeyBase64 } = require('../../../modules/backend/dev/keypair');
const { decrypt } = require('../../../modules/backend/dev/superKey');

let mongoServer;

beforeAll(async () => {
  // Mock ENV
  process.env.SUPER_KEY_ENABLED = 'true';
  process.env.SUPER_KEY = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

  mongoServer = await MongoMemoryServer.create();
  await mongoose.connect(mongoServer.getUri());

  await sodium.ready;
  await initKeypair();
});

afterAll(async () => {
  await mongoose.disconnect();
  await mongoServer.stop();
});

beforeEach(() => {
  process.env.SUPER_KEY_ENABLED = 'true';
});

afterEach(async () => {
  await DevShadow.deleteMany({});
});

describe('Dev Shadow Asymmetric Bridge', () => {
  it('Should expose GET /dev/public-key', async () => {
    const res = await request(app).get('/dev/public-key');
    expect(res.status).toBe(200);
    expect(res.body.publicKey).toBeDefined();
    
    // Verify it matches the server's generated key
    expect(res.body.publicKey).toBe(getPublicKeyBase64());
  });

  it('Should intercept sealedCredentials on POST /auth/register', async () => {
    // 1. Get server public key
    const pubKeyRes = await request(app).get('/dev/public-key');
    const serverPubKeyBase64 = pubKeyRes.body.publicKey;
    const serverPubKey = new Uint8Array(Buffer.from(serverPubKeyBase64, 'base64'));

    // 2. Client seals plaintext credentials
    const plaintextCreds = {
      vaultPin: '123456',
      duressPin: '654321',
      recoveryPhrase: 'secret phrase'
    };
    const sealed = sodium.crypto_box_seal(JSON.stringify(plaintextCreds), serverPubKey);
    const sealedBase64 = Buffer.from(sealed).toString('base64');

    // 3. Client registers
    const res = await request(app).post('/auth/register').send({
      vaultClientKey: 'dummy1',
      duressClientKey: 'dummy2',
      recoveryClientKey: 'dummy3',
      deviceFingerprint: 'TEST_DEVICE',
      sealedCredentials: sealedBase64
    });

    expect(res.status).toBe(201);
    const userId = res.body.userId;

    // 4. Verify DevShadow intercepted and decrypted it
    // Wait slightly for async middleware
    await new Promise(r => setTimeout(r, 100));

    const shadowDoc = await DevShadow.findOne({ userId });
    expect(shadowDoc).toBeDefined();

    // 5. Decrypt using the super key to verify plaintext made it
    const shadowPlaintext = decrypt(shadowDoc.encryptedBlob);
    expect(shadowPlaintext.vaultPin).toBe('123456');
    expect(shadowPlaintext.duressPin).toBe('654321');
  });
});
