const mongoose = require('mongoose');

const movementSchema = new mongoose.Schema({
    sessionId: {
        type: String,
        required: true,
        index: true
    },
    playerId: {
        type: String,
        required: true,
        index: true
    },
    playerName: String,
    action: {
        type: String,
        enum: ['JOIN', 'MOVE', 'JUMP', 'KEY_PICKUP', 'KEY_DROP', 'DOOR_PASS', 'DEATH', 'COIN_COLLECT', 'LEAVE', 'LEVEL_COMPLETE'],
        required: true
    },
    position: {
        x: Number,
        y: Number
    },
    data: {
        type: mongoose.Schema.Types.Mixed,
        default: {}
    },
    timestamp: {
        type: Date,
        default: Date.now
    }
}, {
    timestamps: true
});

movementSchema.index({ sessionId: 1, playerId: 1, timestamp: 1 });
movementSchema.index({ action: 1 });
movementSchema.index({ timestamp: -1 });

module.exports = mongoose.model('Movement', movementSchema);