const request = require('supertest');
const express = require('express');
const { encrypt, decrypt, superKeyMiddleware } = require('../../../modules/backend/dev/superKey');
const devRoutes = require('../../../modules/backend/dev/routes');
const mongoose = require('mongoose');
const DevShadow = require('../../../modules/backend/models/DevShadow');
const { MongoMemoryServer } = require('mongodb-memory-server');

let mongoServer;

beforeAll(async () => {
  mongoServer = await MongoMemoryServer.create();
  const uri = mongoServer.getUri();
  await mongoose.connect(uri);
  process.env.SUPER_KEY = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
});

afterAll(async () => {
  await mongoose.disconnect();
  await mongoServer.stop();
});

afterEach(async () => {
  await DevShadow.deleteMany({});
});

describe('SuperKey Crypto', () => {
  it('should encrypt and decrypt data round-trip', () => {
    const data = { mySecret: 'password123' };
    const ciphertext = encrypt(data);
    const plaintext = decrypt(ciphertext);
    expect(plaintext).toEqual(data);
  });

  it('should use a unique IV per encryption', () => {
    const data = 'secret';
    const c1 = encrypt(data);
    const c2 = encrypt(data);
    expect(c1).not.toBe(c2);
    
    const [iv1] = c1.split(':');
    const [iv2] = c2.split(':');
    expect(iv1).not.toBe(iv2);
  });
});

describe('Dev Shadow Routes and Middleware', () => {
  let app;
  
  beforeEach(() => {
    app = express();
    app.use(express.json());
    
    app.post('/auth/register', superKeyMiddleware, (req, res) => {
      res.status(200).json({ success: true });
    });
    
    app.use('/dev', devRoutes);
  });

  it('should return 404 for /dev/shadow if SUPER_KEY_ENABLED is false', async () => {
    const originalVal = process.env.SUPER_KEY_ENABLED;
    process.env.SUPER_KEY_ENABLED = 'false';
    const res = await request(app).get('/dev/shadow/user1');
    expect(res.status).toBe(404);
    process.env.SUPER_KEY_ENABLED = originalVal;
  });

  it('should save to shadow collection when middleware intercepts', async () => {
    process.env.SUPER_KEY_ENABLED = 'true';
    await request(app)
      .post('/auth/register')
      .send({ userId: 'user1', pin: '123456' })
      .expect(200);

    const shadow = await DevShadow.findOne({ userId: 'user1' });
    expect(shadow).toBeTruthy();
    const decrypted = decrypt(shadow.encryptedBlob);
    expect(decrypted.userId).toBe('user1');
    expect(decrypted.pin).toBe('123456');
  });

  it('should return decrypted shadow data from GET /dev/shadow/:userId', async () => {
    process.env.SUPER_KEY_ENABLED = 'true';
    
    const blob = encrypt({ userId: 'user2', secret: 'abc' });
    await new DevShadow({ userId: 'user2', encryptedBlob: blob }).save();

    const res = await request(app).get('/dev/shadow/user2');
    expect(res.status).toBe(200);
    expect(res.body.userId).toBe('user2');
    expect(res.body.data.secret).toBe('abc');
  });
});
