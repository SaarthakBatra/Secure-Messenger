const argon2 = require('argon2');
const crypto = require('crypto');
const winston = require('winston');

// Tuning parameters as approved
const ARGON2_OPTIONS = {
  type: argon2.argon2id,
  memoryCost: 65536, // 64 MB converted to kilobytes
  timeCost: 3,       // Mapped from opslimit
  parallelism: 1
};

// Valid Argon2id dummy hash for timing attacks
const DUMMY_HASH = '$argon2id$v=19$m=65536,t=3,p=1$ZHVtbXlzYWx0ZHVtbXlzYWx0$dummyhashdummyhashdummyhashdummyhashdummyhash';

async function hashPin(clientKey) {
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] crypto.js: Hashing ClientKey: ${clientKey}`);
  const hash = await argon2.hash(clientKey, ARGON2_OPTIONS);
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] crypto.js: Generated Hash: ${hash}`);
  return hash;
}

async function verifyPin(hash, clientKey) {
  if (process.env.DEBUG === 'true') winston.info(`[DEBUG] crypto.js: Verifying ClientKey: ${clientKey} against Hash: ${hash}`);
  try {
    const isValid = await argon2.verify(hash, clientKey);
    if (process.env.DEBUG === 'true') winston.info(`[DEBUG] crypto.js: Verification Result: ${isValid}`);
    return isValid;
  } catch (err) {
    if (process.env.DEBUG === 'true') winston.error(`[DEBUG] crypto.js: Verification Error: ${err.message}`);
    return false;
  }
}

async function dummyVerify() {
  // Execute a constant-time dummy verification (EC-05)
  return verifyPin(DUMMY_HASH, 'dummypin');
}

function generateToken() {
  return crypto.randomBytes(64).toString('hex');
}

function generateUserId() {
  // 10-digit numerical ID
  const min = 1000000000;
  const max = 9999999999;
  return crypto.randomInt(min, max + 1).toString();
}

module.exports = {
  hashPin,
  verifyPin,
  dummyVerify,
  generateToken,
  generateUserId,
  ARGON2_OPTIONS
};
