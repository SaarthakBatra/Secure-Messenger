const winston = require('winston');
const Conversation = require('../models/Conversation');

function initSweeper() {
  const DEFAULT_INTERVAL = 6 * 60 * 60 * 1000; // 6 hours
  const intervalMs = process.env.SWEEP_INTERVAL_MS 
    ? parseInt(process.env.SWEEP_INTERVAL_MS, 10) 
    : DEFAULT_INTERVAL;

  winston.info(`Initializing Pending Conversation Sweeper (Interval: ${intervalMs}ms)`);

  setInterval(async () => {
    try {
      const twentyFourHoursAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);
      
      const result = await Conversation.deleteMany({
        status: 'PENDING',
        createdAt: { $lt: twentyFourHoursAgo }
      });

      if (result.deletedCount > 0) {
        winston.info(`Sweeper: Purged ${result.deletedCount} expired PENDING conversations.`);
      }
    } catch (error) {
      winston.error('Sweeper Error:', error);
    }
  }, intervalMs);
}

module.exports = { initSweeper };
