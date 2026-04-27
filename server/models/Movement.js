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
    
    // Acción realizada
    action: {
        type: String,
        enum: ['JOIN', 'MOVE', 'JUMP', 'KEY_PICKUP', 'DOOR_PASS', 'DEATH', 'COIN_COLLECT', 'LEAVE', 'LEVEL_COMPLETE'],
        required: true
    },
    
    // Posición en el momento de la acción
    position: {
        x: Number,
        y: Number
    },
    
    // Datos adicionales según acción
    data: {
        direction: String,      // LEFT, RIGHT, JUMP
        coinValue: Number,
        deathCause: String,
        keyHolder: String
    },
    
    timestamp: {
        type: Date,
        default: Date.now
    }
}, {
    timestamps: true
});

// Índices para consultas
movementSchema.index({ sessionId: 1, playerId: 1, timestamp: 1 });
movementSchema.index({ action: 1 });
movementSchema.index({ timestamp: -1 });

module.exports = mongoose.model('Movement', movementSchema);