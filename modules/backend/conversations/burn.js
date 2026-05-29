const Conversation = require('../models/Conversation');
const Message = require('../models/Message');
const MediaRef = require('../models/MediaRef');
const Note = require('../models/Note');
const Event = require('../models/Event');
const RestorationRequest = require('../models/RestorationRequest');
const winston = require('winston');

async function burnConversation(conversationId) {
  try {
    // EC-14: The Burn Protocol - Atomic Wipe
    // Sequential deletion prevents orphaned records and cascading failures
    
    // 1. Wipe Messages
    await Message.deleteMany({ conversationId });
    
    // 2. Wipe MediaRefs
    await MediaRef.deleteMany({ conversationId });
    
    // 3. Wipe Notes
    await Note.deleteMany({ conversationId });
    
    // 4. Wipe Events
    await Event.deleteMany({ conversationId });
    
    // 5. Wipe RestorationRequests
    await RestorationRequest.deleteMany({ conversationId });
    
    // 6. Finally, destroy the Conversation itself
    const result = await Conversation.deleteOne({ conversationId });
    
    if (result.deletedCount === 1) {
      winston.info(`BURN PROTOCOL executed successfully for conversation ${conversationId}`);
    } else {
      winston.warn(`BURN PROTOCOL executed but conversation ${conversationId} was not found.`);
    }

    return true;
  } catch (err) {
    winston.error(`BURN PROTOCOL failed for conversation ${conversationId}:`, err);
    throw err;
  }
}

module.exports = { burnConversation };
