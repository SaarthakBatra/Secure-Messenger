process.env.SUPER_KEY_ENABLED = 'true';
process.env.SUPER_KEY = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

const request = require('supertest');
const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');
const sodium = require('libsodium-wrappers');
const WebSocket = require('ws');
const { app, server } = require('../../../modules/backend/index');
const User = require('../../../modules/backend/models/User');
const Conversation = require('../../../modules/backend/models/Conversation');

let mongoServer;
let port;
let aliceToken;
let aliceUserId;
let aliceKeys;
let bobToken;
let bobUserId;
let bobKeys;

beforeAll(async () => {
  await sodium.ready;
  mongoServer = await MongoMemoryServer.create();
  const uri = mongoServer.getUri();
  await mongoose.connect(uri);

  // Generate Keypairs
  const aliceKp = sodium.crypto_box_keypair();
  aliceKeys = {
    publicKey: sodium.to_base64(aliceKp.publicKey, sodium.base64_variants.ORIGINAL),
    privateKey: sodium.to_base64(aliceKp.privateKey, sodium.base64_variants.ORIGINAL)
  };

  const bobKp = sodium.crypto_box_keypair();
  bobKeys = {
    publicKey: sodium.to_base64(bobKp.publicKey, sodium.base64_variants.ORIGINAL),
    privateKey: sodium.to_base64(bobKp.privateKey, sodium.base64_variants.ORIGINAL)
  };

  // Register & Login Alice
  const regAlice = await request(app).post('/auth/register').send({
    vaultClientKey: 'alice_vault_key',
    duressClientKey: 'alice_duress_key',
    recoveryClientKey: 'alice_recovery_key',
    deviceFingerprint: 'alice_device',
    publicKey: aliceKeys.publicKey,
    encryptedIdentityPrivateKey: 'alice_enc_priv_key'
  });
  aliceUserId = regAlice.body.userId;

  const loginAlice = await request(app).post('/auth/login').send({
    userId: aliceUserId,
    clientKey: 'alice_vault_key',
    deviceFingerprint: 'alice_device'
  });
  aliceToken = loginAlice.body.sessionToken;

  // Register & Login Bob
  const regBob = await request(app).post('/auth/register').send({
    vaultClientKey: 'bob_vault_key',
    duressClientKey: 'bob_duress_key',
    recoveryClientKey: 'bob_recovery_key',
    deviceFingerprint: 'bob_device',
    publicKey: bobKeys.publicKey,
    encryptedIdentityPrivateKey: 'bob_enc_priv_key'
  });
  bobUserId = regBob.body.userId;

  const loginBob = await request(app).post('/auth/login').send({
    userId: bobUserId,
    clientKey: 'bob_vault_key',
    deviceFingerprint: 'bob_device'
  });
  bobToken = loginBob.body.sessionToken;

  // Listen on a random port for WS tests
  await new Promise(resolve => {
    server.listen(0, () => {
      port = server.address().port;
      resolve();
    });
  });
});

afterAll(async () => {
  server.close();
  await mongoose.disconnect();
  await mongoServer.stop();
});

afterEach(async () => {
  await Conversation.deleteMany({});
});

function connectWs(token, queryParam = false) {
  return new Promise((resolve, reject) => {
    let wsUrl = `ws://localhost:${port}`;
    let options = {};
    if (queryParam) {
      wsUrl += `/ws?token=${token}`;
    } else {
      options.headers = { Authorization: `Bearer ${token}` };
    }
    const ws = new WebSocket(wsUrl, options);
    ws.on('open', () => resolve(ws));
    ws.on('error', reject);
    ws.on('unexpected-response', (req, res) => {
      reject(new Error(`Unexpected response: ${res.statusCode}`));
    });
  });
}

describe('Phase 2b Covert Invitation & WS Tests', () => {
  it('Should expose public-key endpoint for registered users', async () => {
    const res = await request(app)
      .get(`/auth/users/${bobUserId}/public-key`)
      .set('Authorization', `Bearer ${aliceToken}`);
    
    expect(res.status).toBe(200);
    expect(res.body.publicKey).toBe(bobKeys.publicKey);
  });

  it('Should support legacy WS and query param WS auth', async () => {
    const wsHeader = await connectWs(aliceToken, false);
    expect(wsHeader).toBeDefined();
    wsHeader.close();

    const wsQuery = await connectWs(aliceToken, true);
    expect(wsQuery).toBeDefined();
    wsQuery.close();
  });

  it('Should support complete invite-flow: POST invite, GET pending, decrypt, and Join', async () => {
    // Connect Bob's socket using query param auth
    const bobWs = await connectWs(bobToken, true);
    
    const wsPromise = new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('WS timeout waiting for PENDING_INVITE')), 3000);
      bobWs.on('message', (data) => {
        const msg = JSON.parse(data.toString());
        if (msg.type === 'PENDING_INVITE') {
          clearTimeout(timeout);
          resolve(msg.payload);
        }
      });
    });

    // Alice creates the invite
    const inviteRes = await request(app)
      .post('/conversations')
      .set('Authorization', `Bearer ${aliceToken}`)
      .send({
        recipientUserId: bobUserId,
        invitationMessage: 'Secret Room 101'
      });

    expect(inviteRes.status).toBe(201);
    expect(inviteRes.body.conversationId).toBeDefined();
    expect(inviteRes.body.aliceInvite).toBeDefined();

    const conversationId = inviteRes.body.conversationId;

    // Verify Bob received WS push
    const wsPayload = await wsPromise;
    expect(wsPayload.conversationId).toBe(conversationId);
    expect(wsPayload.message).toBe('Secret Room 101');
    expect(wsPayload.bobInvite).toBeDefined();
    expect(wsPayload.senderUserId).toBe(aliceUserId);
    bobWs.close();

    // Verify Bob can retrieve the pending invite via REST
    const pendingRes = await request(app)
      .get('/conversations/pending')
      .set('Authorization', `Bearer ${bobToken}`);
    
    expect(pendingRes.status).toBe(200);
    expect(Array.isArray(pendingRes.body)).toBe(true);
    expect(pendingRes.body.length).toBe(1);
    expect(pendingRes.body[0].conversationId).toBe(conversationId);
    expect(pendingRes.body[0].message).toBe('Secret Room 101');
    
    const bobInvitePayload = pendingRes.body[0].bobInvite;
    expect(bobInvitePayload).toBeDefined();

    // Bob decrypts the invite
    const decryptedKeyBytes = sodium.crypto_box_seal_open(
      sodium.from_base64(bobInvitePayload, sodium.base64_variants.ORIGINAL),
      sodium.from_base64(bobKeys.publicKey, sodium.base64_variants.ORIGINAL),
      sodium.from_base64(bobKeys.privateKey, sodium.base64_variants.ORIGINAL)
    );
    const plaintextConversationKey = Buffer.from(decryptedKeyBytes).toString('utf8');

    // Bob joins with the decrypted key
    const joinRes = await request(app)
      .post(`/conversations/${conversationId}/join`)
      .set('Authorization', `Bearer ${bobToken}`)
      .send({
        conversationKey: plaintextConversationKey
      });

    expect(joinRes.status).toBe(200);
    expect(joinRes.body.success).toBe(true);

    // Verify state transition: status ACTIVE, bobInvitePayload is deleted/null
    const dbConvo = await Conversation.findOne({ conversationId });
    expect(dbConvo.status).toBe('ACTIVE');
    expect(dbConvo.bobInvitePayload).toBeNull();
  });
});
