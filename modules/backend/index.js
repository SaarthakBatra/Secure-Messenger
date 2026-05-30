require('dotenv').config();
const express = require('express');
const mongoose = require('mongoose');
const http = require('http');
const { WebSocketServer } = require('ws');
const helmet = require('helmet');
const winston = require('winston');

// Configure Winston to avoid "no transports" warning
winston.add(new winston.transports.Console({
  format: winston.format.simple()
}));
const app = express();
const server = http.createServer(app);

// EC-10: Max Headers Count and Timeout for Slow HTTP Attacks
server.maxHeadersCount = 30;
server.headersTimeout = 10000; // 10 seconds

app.use(helmet());
app.use(express.json());

// Dev shadow routes
try {
  require('./dev/init')(app);
} catch (e) {
  // Ignore if dev folder is removed
}

const realAuthRouter = require('./auth/router');
app.use('/auth', realAuthRouter);

const realConversationsRouter = require('./conversations/router');
app.use('/conversations', realConversationsRouter);

const mediaRouter = require('./media/router');
const notesRouter = require('./notes/router');

app.use('/media', mediaRouter);
app.use('/notes', notesRouter);

const { initWsServer } = require('./ws/server');
const messagingRouter = require('./messaging/router');
app.use('/conversations', messagingRouter); // REST fallback routes attached to /conversations

// Initialize custom WS Server attached to HTTP server
initWsServer(server);

const { initSweeper } = require('./jobs/sweeper');

async function startServer() {
  try {
    await mongoose.connect(process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/multilingo_dev');
    winston.info('Connected to MongoDB');
    
    initSweeper();
    
    const PORT = process.env.PORT || 3000;
    server.listen(PORT, () => {
      winston.info(`Server listening on port ${PORT}`);
    });
  } catch (err) {
    winston.error('Failed to start server:', err);
    process.exit(1);
  }
}

if (require.main === module) {
  startServer();
}

module.exports = { app, server, startServer };
