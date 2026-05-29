process.env.SUPER_KEY_ENABLED = 'true';
process.env.SUPER_KEY = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

const request = require('supertest');
const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');
const { app } = require('../../../modules/backend/index');
const Note = require('../../../modules/backend/models/Note');
const Conversation = require('../../../modules/backend/models/Conversation');

let mongoServer;
let userAToken, userBToken;
let conversationId;

beforeAll(async () => {
  mongoServer = await MongoMemoryServer.create();
  await mongoose.connect(mongoServer.getUri());

  const regA = await request(app).post('/auth/register').send({
    vaultClientKey: '11',
    duressClientKey: '22',
    recoveryClientKey: '33',
    deviceFingerprint: 'A'
  });
  const loginA = await request(app).post('/auth/login').send({
    userId: regA.body.userId,
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
  const loginB = await request(app).post('/auth/login').send({
    userId: regB.body.userId,
    clientKey: '11',
    deviceFingerprint: 'B'
  });
  userBToken = loginB.body.sessionToken;

  const conv = await request(app).post('/conversations').set('Authorization', `Bearer ${userAToken}`);
  conversationId = conv.body.conversationId;
  await request(app).post(`/conversations/${conversationId}/join`).set('Authorization', `Bearer ${userBToken}`).send({ conversationKey: conv.body.conversationKey });
});

afterAll(async () => {
  await mongoose.disconnect();
  await mongoServer.stop();
});

afterEach(async () => {
  await Note.deleteMany({});
});

describe('Notes Router & Burn Protocol', () => {
  let noteId;

  it('Should create a note', async () => {
    const res = await request(app)
      .post('/notes')
      .set('Authorization', `Bearer ${userAToken}`)
      .send({ conversationId, title: 'Shared Note', encryptedContentBlob: 'v1' });

    expect(res.status).toBe(201);
    noteId = res.body.noteId;
  });

  it('EC-13: Should enforce Note Concurrency Lock', async () => {
    // Recreate note
    const resCreate = await request(app).post('/notes').set('Authorization', `Bearer ${userAToken}`).send({ conversationId, title: 'Shared Note', encryptedContentBlob: 'v1' });
    const nId = resCreate.body.noteId;

    // User A acquires lock
    const lockA = await request(app).post(`/notes/${nId}/lock`).set('Authorization', `Bearer ${userAToken}`);
    expect(lockA.status).toBe(200);

    // User B attempts to edit (fails)
    const editB = await request(app).put(`/notes/${nId}`).set('Authorization', `Bearer ${userBToken}`).send({ encryptedContentBlob: 'v2' });
    expect(editB.status).toBe(423); // Locked

    // User A edits (succeeds)
    const editA = await request(app).put(`/notes/${nId}`).set('Authorization', `Bearer ${userAToken}`).send({ encryptedContentBlob: 'v2' });
    expect(editA.status).toBe(200);

    const note = await Note.findOne({ noteId: nId });
    expect(note.encryptedContentBlob).toBe('v2');
    expect(note.versions.length).toBe(1); // Saved v1 history
    expect(note.versions[0].encryptedContentBlob).toBe('v1');
    
    // User A unlocks
    await request(app).post(`/notes/${nId}/unlock`).set('Authorization', `Bearer ${userAToken}`);

    // User B locks
    const lockB = await request(app).post(`/notes/${nId}/lock`).set('Authorization', `Bearer ${userBToken}`);
    expect(lockB.status).toBe(200);
  });

  it('EC-14: Burn Protocol Should Wipe Everything', async () => {
    // Ensure data exists
    await request(app).post('/notes').set('Authorization', `Bearer ${userAToken}`).send({ conversationId, title: 'To Burn', encryptedContentBlob: 'x' });
    
    let convCheck = await Conversation.findOne({ conversationId });
    expect(convCheck).toBeDefined();

    const res = await request(app)
      .delete(`/conversations/${conversationId}/burn`)
      .set('Authorization', `Bearer ${userAToken}`);
    
    expect(res.status).toBe(200);

    // Assert wipe
    convCheck = await Conversation.findOne({ conversationId });
    expect(convCheck).toBeNull();

    const noteCheck = await Note.findOne({ conversationId });
    expect(noteCheck).toBeNull();
  });
});
