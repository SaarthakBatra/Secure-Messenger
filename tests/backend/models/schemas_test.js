const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');
const User = require('../../../modules/backend/models/User');

let mongoServer;

beforeAll(async () => {
  mongoServer = await MongoMemoryServer.create();
  const uri = mongoServer.getUri();
  await mongoose.connect(uri);
});

afterAll(async () => {
  await mongoose.disconnect();
  await mongoServer.stop();
});

afterEach(async () => {
  await User.deleteMany({});
});

describe('User Schema Validation', () => {
  it('should successfully save a valid user', async () => {
    const validUser = new User({
      userId: '1234567890',
      pinHash: 'hash1',
      duressPinHash: 'hash2',
      recoveryPhraseHash: 'hash3',
      deviceFingerprint: 'fingerprint1'
    });
    
    const savedUser = await validUser.save();
    expect(savedUser.userId).toBe('1234567890');
    expect(savedUser.wrongPinAttempts).toBe(0); // default
  });

  it('should fail if required fields are missing', async () => {
    const invalidUser = new User({
      userId: '1234567890',
      // missing pinHash, etc.
    });

    let error;
    try {
      await invalidUser.save();
    } catch (err) {
      error = err;
    }
    
    expect(error).toBeDefined();
    expect(error.name).toBe('ValidationError');
  });

  it('should fail on duplicate userId due to unique index', async () => {
    const user1 = new User({
      userId: 'dup-id',
      pinHash: 'hash1',
      duressPinHash: 'hash2',
      recoveryPhraseHash: 'hash3',
      deviceFingerprint: 'fingerprint1'
    });
    
    const user2 = new User({
      userId: 'dup-id',
      pinHash: 'hash1',
      duressPinHash: 'hash2',
      recoveryPhraseHash: 'hash3',
      deviceFingerprint: 'fingerprint1'
    });

    await user1.save();

    let error;
    try {
      await user2.save();
    } catch (err) {
      error = err;
    }
    
    expect(error).toBeDefined();
    expect(error.code).toBe(11000); // duplicate key error code in mongodb
  });
});
