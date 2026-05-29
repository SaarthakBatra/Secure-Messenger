const rateLimit = require('express-rate-limit');
const Session = require('../models/Session');
const User = require('../models/User');

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: process.env.NODE_ENV === 'test' ? 1000 : (parseInt(process.env.AUTH_LIMITER_MAX) || 10), // Limit each IP
  message: { error: 'Too many requests, please try again later.' },
  standardHeaders: true,
  legacyHeaders: false,
});

const loginLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: process.env.NODE_ENV === 'test' ? 1000 : 5, // 5 attempts per IP per minute
  message: { error: 'Too many login attempts, please try again after a minute.' },
  standardHeaders: true,
  legacyHeaders: false,
});

const reauthLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: process.env.NODE_ENV === 'test' ? 1000 : (parseInt(process.env.REAUTH_LIMITER_MAX) || 100),
  message: { error: 'Too many requests, please try again later.' },
  standardHeaders: true,
  legacyHeaders: false,
});

async function requireSession(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const token = authHeader.split(' ')[1];
  
  try {
    const session = await Session.findOne({ token });
    
    // EC-03: Token Replay check (invalidatedAt must be null)
    if (!session || session.invalidatedAt !== null) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    if (session.tokenExpiresAt && session.tokenExpiresAt < Date.now()) {
      return res.status(401).json({ error: 'Session expired', code: 'SESSION_EXPIRED' });
    }

    if (session.refreshExpiresAt && session.refreshExpiresAt < Date.now()) {
      return res.status(401).json({ error: 'Refresh token expired', code: 'REFRESH_EXPIRED' });
    }
    
    req.user = { userId: session.userId, sessionToken: token };
    next();
  } catch (error) {
    res.status(500).json({ error: 'Internal Server Error' });
  }
}

async function checkAccountLockout(req, res, next) {
  const { userId } = req.body;
  if (!userId) return next();

  try {
    const user = await User.findOne({ userId });
    if (!user) return next();

    if (user.lockedUntil && user.lockedUntil > Date.now()) {
      return res.status(423).json({ error: 'Locked. Too many failed attempts.' });
    }

    if (user.lockedUntil && user.lockedUntil <= Date.now()) {
      // Lock expired, reset
      await User.updateOne({ userId }, { $set: { wrongPinAttempts: 0, lockedUntil: null } });
    }

    req.targetUser = user;
    next();
  } catch (error) {
    res.status(500).json({ error: 'Internal Server Error' });
  }
}

// Progressive delay middleware to slow down parallel brute-force (EC-07)
function progressiveDelay(req, res, next) {
  if (req.targetUser && req.targetUser.wrongPinAttempts > 0) {
    const delay = req.targetUser.wrongPinAttempts * 500; // 500ms per failed attempt
    setTimeout(next, delay);
  } else {
    next();
  }
}

module.exports = {
  authLimiter,
  loginLimiter,
  reauthLimiter,
  requireSession,
  checkAccountLockout,
  progressiveDelay
};
