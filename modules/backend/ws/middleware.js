const winston = require('winston');

function createRateLimiter() {
  const limit = process.env.WS_MAX_MSGS_PER_SEC ? parseInt(process.env.WS_MAX_MSGS_PER_SEC, 10) : 50;
  
  // Each connection gets its own token bucket state
  let tokens = limit;
  let lastRefillTime = Date.now();

  return function rateLimitFilter() {
    const now = Date.now();
    // Refill logic: 1 token per (1000 / limit) ms
    const timePassed = now - lastRefillTime;
    const tokensToAdd = Math.floor(timePassed * (limit / 1000));
    
    if (tokensToAdd > 0) {
      tokens = Math.min(limit, tokens + tokensToAdd);
      lastRefillTime = now;
    }

    if (tokens >= 1) {
      tokens -= 1;
      return true; // allowed
    } else {
      return false; // rate limited
    }
  };
}

module.exports = { createRateLimiter };
