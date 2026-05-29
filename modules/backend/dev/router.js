const express = require('express');
const { getPublicKeyBase64 } = require('./keypair');

const router = express.Router();

router.get('/public-key', (req, res) => {
  if (process.env.SUPER_KEY_ENABLED === 'true') {
    const pubKey = getPublicKeyBase64();
    if (pubKey) {
      return res.json({ publicKey: pubKey });
    }
    return res.status(500).json({ error: 'Keypair not ready' });
  }
  return res.status(404).json({ error: 'Not Found' });
});

module.exports = router;
