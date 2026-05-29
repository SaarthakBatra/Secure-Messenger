const winston = require('winston');
const Message = require('../models/Message');
const Conversation = require('../models/Conversation');

// This handles incoming WS messages
async function handleWsMessage(ws, parsedMessage, userId, activeConnections) {
  try {
    const { type, payload } = parsedMessage;

    if (type === 'chat') {
      const { messageId, conversationId, encryptedBlob } = payload;
      
      if (!messageId || !conversationId || !encryptedBlob) {
        return; // malformed
      }

      // 1. Verify user is participant
      const conversation = await Conversation.findOne({ conversationId });
      if (!conversation || !conversation.participantUserIds.includes(userId)) {
        return; // Not authorized
      }

      // 2. Persist to DB (EC-09 Idempotency check)
      let messageRecord;
      try {
        messageRecord = new Message({
          messageId,
          conversationId,
          senderUserId: userId,
          encryptedBlob,
          tickStatus: 'sent',
          timestamps: {
            sent: new Date()
          }
        });
        await messageRecord.save();
      } catch (err) {
        if (err.code === 11000) {
          // Idempotent: Ignore duplicate insertion, but might still need to forward it
          messageRecord = await Message.findOne({ messageId });
        } else {
          throw err;
        }
      }

      // 3. Find recipient and forward if online
      const recipientIds = conversation.participantUserIds.filter(id => id !== userId);
      
      let wasDelivered = false;
      let hasOfflineRecipient = false;
      for (const recId of recipientIds) {
        const recWs = activeConnections.get(recId);
        if (recWs && recWs.readyState === 1 /* WebSocket.OPEN */) {
          recWs.send(JSON.stringify({
            type: 'chat',
            payload: {
              messageId: messageRecord.messageId,
              conversationId: messageRecord.conversationId,
              senderUserId: messageRecord.senderUserId,
              encryptedBlob: messageRecord.encryptedBlob,
              tickStatus: 'delivered',
              timestamp: messageRecord.timestamps.sent
            }
          }));
          wasDelivered = true;
        } else {
          hasOfflineRecipient = true;
        }
      }

      // 4. Update tick status
      if (wasDelivered) {
        await Message.updateOne(
          { messageId },
          { 
            $set: { 
              tickStatus: 'delivered',
              'timestamps.delivered': new Date()
            } 
          }
        );
        
        // Notify sender it was delivered
        ws.send(JSON.stringify({
          type: 'receipt',
          payload: { messageId, tickStatus: 'delivered' }
        }));
      }

      if (hasOfflineRecipient) {
        ws.send(JSON.stringify({
          type: 'receipt',
          payload: {
            messageId,
            tickStatus: 'sent',
            recipientOffline: true
          }
        }));
      }

    } else if (type === 'receipt') {
      const { messageId, tickStatus } = payload;
      
      if (tickStatus === 'acknowledged' || tickStatus === 'read') {
        const updateObj = {
          $set: {
            tickStatus,
            [`timestamps.${tickStatus}`]: new Date()
          }
        };

        const msg = await Message.findOneAndUpdate(
          { messageId },
          updateObj,
          { new: true }
        );

        if (msg) {
          // Forward receipt to original sender
          const senderWs = activeConnections.get(msg.senderUserId);
          if (senderWs && senderWs.readyState === 1) {
            senderWs.send(JSON.stringify({
              type: 'receipt',
              payload: { messageId, tickStatus }
            }));
          }
        }
      }
    }
  } catch (err) {
    winston.error('WS Handler Error:', err);
  }
}

module.exports = { handleWsMessage };
