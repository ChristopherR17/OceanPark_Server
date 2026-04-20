const mongoose = require('mongoose');

const playerSchema = new mongoose.Schema({
  socketId: { type: String, required: true, unique: true },
  nickname: { type: String, required: true },
  characters: { type: String, default: '#FF5733' },
  createdAt: { type: Date, default: Date.now }
});

module.exports = mongoose.model('Player', playerSchema);