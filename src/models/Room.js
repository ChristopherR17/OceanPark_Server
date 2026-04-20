const mongoose = require('mongoose');

const roomSchema = new mongoose.Schema({
  roomId: { type: String, required: true, unique: true, uppercase: true },
  roomName: { type: String, default: 'Nueva Sala' },
  hostSocketId: { type: String, required: true },
  players: [{
    socketId: String,
    nickname: String,
    isReady: { type: Boolean, default: false },
    color: String
  }],
  maxPlayers: { type: Number, default: 8 },
  minPlayers: { type: Number, default: 2 },
  gameState: { 
    type: String, 
    enum: ['waiting', 'playing', 'finished'],
    default: 'waiting' 
  },
  createdAt: { type: Date, default: Date.now }
});

module.exports = mongoose.model('Room', roomSchema);