process.env.SUPER_KEY_ENABLED = 'true';
process.env.SUPER_KEY = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

const request = require('supertest');
const WebSocket = require('ws');
const http = require('http');
const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');
const { app, server } = require('../../../modules/backend/index');
const User = require('../../../modules/backend/models/User');
const Session = require('../../../modules/backend/models/Session');
const Conversation = require('../../../modules/backend/models/Conversation');
const Message = require('../../../modules/backend/models/Message');

let mongoServer;
let userAId, userAToken;
let userBId, userBToken;
let conversationId;
let port;

beforeAll(async () => {
  mongoServer = await MongoMemoryServer.create();
  const uri = mongoServer.getUri();
  await mongoose.connect(uri);

  // Set up users
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

  // Create conversation
  const conv = await request(app).post('/conversations').set('Authorization', `Bearer ${userAToken}`);
  conversationId = conv.body.conversationId;
  const convKey = conv.body.conversationKey;

  // Join User B
  await request(app).post(`/conversations/${conversationId}/join`)
    .set('Authorization', `Bearer ${userBToken}`)
    .send({ conversationKey: convKey });

  // Start server on random port for WS testing
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
  await Message.deleteMany({});
});

function connectWs(token) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://localhost:${port}`, {
      headers: { Authorization: `Bearer ${token}` }
    });
    ws.on('open', () => resolve(ws));
    ws.on('error', reject);
    ws.on('unexpected-response', (req, res) => {
      reject(new Error(`Unexpected server response: ${res.statusCode}`));
    });
  });
}

describe('Messaging WS & REST', () => {

  it('Handshake Rejection: Should reject WS without valid token', async () => {
    await expect(connectWs('invalid_token')).rejects.toThrow('Unexpected server response: 401');
  });

  it('E2E Message Delivery & Sync', async () => {
    const wsA = await connectWs(userAToken);
    const wsB = await connectWs(userBToken);

    // Promise to wait for B to receive message
    const bReceivesMsg = new Promise((resolve) => {
      wsB.on('message', (data) => {
        const msg = JSON.parse(data.toString());
        if (msg.type === 'chat') resolve(msg.payload);
      });
    });

    // Promise to wait for A to receive delivery receipt
    const aReceivesReceipt = new Promise((resolve) => {
      wsA.on('message', (data) => {
        const msg = JSON.parse(data.toString());
        if (msg.type === 'receipt' && msg.payload.tickStatus === 'delivered') {
          resolve(msg.payload);
        }
      });
    });

    const testMsgId = 'msg-123';
    wsA.send(JSON.stringify({
      type: 'chat',
      payload: {
        messageId: testMsgId,
        conversationId,
        encryptedBlob: 'blobData'
      }
    }));

    const receivedPayload = await bReceivesMsg;
    expect(receivedPayload.messageId).toBe(testMsgId);
    expect(receivedPayload.encryptedBlob).toBe('blobData');
    expect(receivedPayload.tickStatus).toBe('delivered');

    const receiptPayload = await aReceivesReceipt;
    expect(receiptPayload.messageId).toBe(testMsgId);

    // Verify REST Sync
    const restRes = await request(app).get(`/conversations/${conversationId}/messages`).set('Authorization', `Bearer ${userAToken}`);
    expect(restRes.status).toBe(200);
    expect(restRes.body.messages.length).toBe(1);
    expect(restRes.body.messages[0].messageId).toBe(testMsgId);
    expect(restRes.body.messages[0].tickStatus).toBe('delivered');

    wsA.close();
    wsB.close();
  });

  it('EC-09: Idempotency (Duplicate Messages)', async () => {
    const wsA = await connectWs(userAToken);
    
    // Send same ID twice
    const msg = JSON.stringify({
      type: 'chat',
      payload: {
        messageId: 'duplicate-id-001',
        conversationId,
        encryptedBlob: 'blob1'
      }
    });

    wsA.send(msg);
    wsA.send(msg);

    // Wait slightly for processing
    await new Promise(r => setTimeout(r, 200));
    
    const messages = await Message.find({ messageId: 'duplicate-id-001' });
    expect(messages.length).toBe(1); // Only 1 should be saved

    wsA.close();
  });

  it('EC-11: Flood Protection', async () => {
    // Set low limit for testing if environment variable was overridden, default 50
    // We send 60 to guarantee trip of 50 msgs/sec
    const wsA = await connectWs(userAToken);
    
    let closeCode = null;
    wsA.on('close', (code) => { closeCode = code; });

    for (let i = 0; i < 60; i++) {
      wsA.send(JSON.stringify({
        type: 'chat',
        payload: { messageId: `flood-${i}`, conversationId, encryptedBlob: 'data' }
      }));
    }

    await new Promise(r => setTimeout(r, 200));
    expect(closeCode).toBe(1008); // Policy Violation

    const savedCount = await Message.countDocuments({ messageId: /flood-/ });
    expect(savedCount).toBeLessThan(60);

    wsA.close();
  });

  it('Sent Status & Offline Recipient Handshake: Should return recipientOffline when peer is offline', async () => {
    const wsA = await connectWs(userAToken);
    // User B (recipient) is not connected

    const aReceivesReceipt = new Promise((resolve) => {
      wsA.on('message', (data) => {
        const msg = JSON.parse(data.toString());
        if (msg.type === 'receipt' && msg.payload.tickStatus === 'sent' && msg.payload.recipientOffline) {
          resolve(msg.payload);
        }
      });
    });

    const testMsgId = 'msg-offline-123';
    wsA.send(JSON.stringify({
      type: 'chat',
      payload: {
        messageId: testMsgId,
        conversationId,
        encryptedBlob: 'offlineBlob'
      }
    }));

    const receiptPayload = await aReceivesReceipt;
    expect(receiptPayload.messageId).toBe(testMsgId);
    expect(receiptPayload.tickStatus).toBe('sent');
    expect(receiptPayload.recipientOffline).toBe(true);

    // Verify DB state
    const dbMsg = await Message.findOne({ messageId: testMsgId });
    expect(dbMsg).toBeDefined();
    expect(dbMsg.tickStatus).toBe('sent');
    expect(dbMsg.timestamps.sent).toBeDefined();
    expect(dbMsg.timestamps.delivered).toBeUndefined();

    wsA.close();
  });

  it('WS Receipt Status Transition: Acknowledged & Read forwarding and database updates', async () => {
    const wsA = await connectWs(userAToken);
    const wsB = await connectWs(userBToken);

    // Step 1: Send message from A to B (B is online, should get delivered status)
    const testMsgId = 'msg-receipt-test-456';
    wsA.send(JSON.stringify({
      type: 'chat',
      payload: {
        messageId: testMsgId,
        conversationId,
        encryptedBlob: 'blobDataForTicks'
      }
    }));

    // Wait until B gets the message
    await new Promise((resolve) => {
      wsB.on('message', (data) => {
        const msg = JSON.parse(data.toString());
        if (msg.type === 'chat' && msg.payload.messageId === testMsgId) {
          resolve();
        }
      });
    });

    // Step 2: B sends 'acknowledged' receipt
    const aReceivesAck = new Promise((resolve) => {
      wsA.on('message', (data) => {
        const msg = JSON.parse(data.toString());
        if (msg.type === 'receipt' && msg.payload.messageId === testMsgId && msg.payload.tickStatus === 'acknowledged') {
          resolve(msg.payload);
        }
      });
    });

    wsB.send(JSON.stringify({
      type: 'receipt',
      payload: {
        messageId: testMsgId,
        tickStatus: 'acknowledged'
      }
    }));

    const ackPayload = await aReceivesAck;
    expect(ackPayload.tickStatus).toBe('acknowledged');

    // Verify DB
    let dbMsg = await Message.findOne({ messageId: testMsgId });
    expect(dbMsg.tickStatus).toBe('acknowledged');
    expect(dbMsg.timestamps.acknowledged).toBeDefined();

    // Step 3: B sends 'read' receipt
    const aReceivesRead = new Promise((resolve) => {
      wsA.on('message', (data) => {
        const msg = JSON.parse(data.toString());
        if (msg.type === 'receipt' && msg.payload.messageId === testMsgId && msg.payload.tickStatus === 'read') {
          resolve(msg.payload);
        }
      });
    });

    wsB.send(JSON.stringify({
      type: 'receipt',
      payload: {
        messageId: testMsgId,
        tickStatus: 'read'
      }
    }));

    const readPayload = await aReceivesRead;
    expect(readPayload.tickStatus).toBe('read');

    // Verify DB
    dbMsg = await Message.findOne({ messageId: testMsgId });
    expect(dbMsg.tickStatus).toBe('read');
    expect(dbMsg.timestamps.read).toBeDefined();

    wsA.close();
    wsB.close();
  });

  it('WS Receipt Status Race Conditions: Concurrent / Fast succession receipt ticks handling', async () => {
    const wsA = await connectWs(userAToken);
    const wsB = await connectWs(userBToken);

    const testMsgId = 'msg-race-999';
    wsA.send(JSON.stringify({
      type: 'chat',
      payload: {
        messageId: testMsgId,
        conversationId,
        encryptedBlob: 'raceBlob'
      }
    }));

    // Wait until delivered
    await new Promise((resolve) => {
      wsB.on('message', (data) => {
        const msg = JSON.parse(data.toString());
        if (msg.type === 'chat' && msg.payload.messageId === testMsgId) {
          resolve();
        }
      });
    });

    // Send acknowledged and read back-to-back to simulate network/UI race condition
    const receivedReceipts = [];
    wsA.on('message', (data) => {
      const msg = JSON.parse(data.toString());
      if (msg.type === 'receipt' && msg.payload.messageId === testMsgId) {
        receivedReceipts.push(msg.payload.tickStatus);
      }
    });

    wsB.send(JSON.stringify({ type: 'receipt', payload: { messageId: testMsgId, tickStatus: 'acknowledged' } }));
    wsB.send(JSON.stringify({ type: 'receipt', payload: { messageId: testMsgId, tickStatus: 'read' } }));

    // Wait for updates to settle
    await new Promise(resolve => setTimeout(resolve, 300));

    expect(receivedReceipts).toContain('acknowledged');
    expect(receivedReceipts).toContain('read');

    // Verify DB has the final 'read' status
    const dbMsg = await Message.findOne({ messageId: testMsgId });
    expect(dbMsg.tickStatus).toBe('read');
    expect(dbMsg.timestamps.acknowledged).toBeDefined();
    expect(dbMsg.timestamps.read).toBeDefined();

    wsA.close();
    wsB.close();
  });
});
