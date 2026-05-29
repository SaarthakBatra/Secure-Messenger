const { WebSocketServer } = require('ws');
const winston = require('winston');
const Session = require('../models/Session');
const { createRateLimiter } = require('./middleware');
const { handleWsMessage } = require('./handlers');

const activeConnections = new Map();

function initWsServer(server) {
  // noServer: true because we manually handle upgrade to perform Auth
  const wss = new WebSocketServer({ noServer: true });

  server.on('upgrade', async (request, socket, head) => {
    try {
      let token;
      const authHeader = request.headers['authorization'];
      
      if (authHeader && authHeader.startsWith('Bearer ')) {
        token = authHeader.split(' ')[1];
      } else {
        const parsedUrl = new URL(request.url, 'http://localhost');
        token = parsedUrl.searchParams.get('token');
      }

      if (!token) {
        socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
        socket.destroy();
        return;
      }

      const session = await Session.findOne({ token, invalidatedAt: null });

      if (!session) {
        socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
        socket.destroy();
        return;
      }

      // Add userId to request context
      request.userId = session.userId;

      wss.handleUpgrade(request, socket, head, (ws) => {
        wss.emit('connection', ws, request);
      });
    } catch (err) {
      socket.write('HTTP/1.1 500 Internal Server Error\r\n\r\n');
      socket.destroy();
    }
  });

  wss.on('connection', (ws, request) => {
    const userId = request.userId;
    
    // Kick existing connection for this user (only 1 active device session per socket)
    if (activeConnections.has(userId)) {
      const oldWs = activeConnections.get(userId);
      oldWs.close(1008, 'Session overwritten');
    }
    
    activeConnections.set(userId, ws);
    const checkRateLimit = createRateLimiter();

    ws.on('message', async (message) => {
      // EC-11: Rate Limit Check
      if (!checkRateLimit()) {
        winston.warn(`WS Flood detected from user ${userId}. Terminating connection.`);
        ws.close(1008, 'Policy Violation');
        return;
      }

      try {
        const parsed = JSON.parse(message.toString());
        await handleWsMessage(ws, parsed, userId, activeConnections);
      } catch (err) {
        // Drop malformed
      }
    });

    ws.on('close', () => {
      if (activeConnections.get(userId) === ws) {
        activeConnections.delete(userId);
      }
    });
  });

  return wss;
}

module.exports = { initWsServer, activeConnections };
