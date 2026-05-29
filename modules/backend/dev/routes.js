const express = require('express');
const { decrypt } = require('./superKey');
const DevShadow = require('../models/DevShadow');

const router = express.Router();

router.get('/shadow/:userId', async (req, res) => {
  if (process.env.SUPER_KEY_ENABLED !== 'true') {
    return res.status(404).send('Not Found');
  }

  try {
    const shadowDoc = await DevShadow.findOne({ userId: req.params.userId });
    if (!shadowDoc) {
      return res.status(404).json({ error: 'Shadow document not found' });
    }

    const plaintext = decrypt(shadowDoc.encryptedBlob);
    res.json({
      userId: shadowDoc.userId,
      updatedAt: shadowDoc.updatedAt,
      data: plaintext
    });
  } catch (err) {
    res.status(500).json({ error: 'Internal Server Error' });
  }
});

module.exports = router;
