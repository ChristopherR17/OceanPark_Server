const mongoose = require('mongoose');

const gameSessionSchema = new mongoose.Schema({
    sessionId: {
        type: String,
        required: true,
        unique: true,
        index: true
    },
    
    // Jugadores que participaron
    players: [{
        playerId: String,
        nickname: String,
        category: {
            type: String,
            enum: ['Junior', 'Senior', 'Expert'],
            default: 'Junior'
        },
        coinsCollected: { type: Number, default: 0 },
        deaths: { type: Number, default: 0 },
        completed: { type: Boolean, default: false },
        score: { type: Number, default: 0 },
        timePlayed: { type: Number, default: 0 }  // segundos individual
    }],
    
    // Datos de la partida
    levelName: { type: String, default: 'Ocean World' },
    levelIndex: { type: Number, default: 0 },
    playerCount: { type: Number, default: 1 },
    completed: { type: Boolean, default: false },
    
    // Tiempos
    startTime: { type: Date, default: Date.now },
    endTime: { type: Date },
    duration: { type: Number, default: 0 },        // segundos
    
    // Resultados
    totalCoinsCollected: { type: Number, default: 0 },
    totalCoinsAvailable: { type: Number, default: 0 },
    totalDeaths: { type: Number, default: 0 },
    bestPlayerScore: { type: Number, default: 0 },
    
    // Métricas para KPIs
    averagePlayerTime: { type: Number, default: 0 }  // tiempo medio por jugador
}, {
    timestamps: true
});

// Índices para consultas
gameSessionSchema.index({ startTime: -1 });
gameSessionSchema.index({ completed: 1 });
gameSessionSchema.index({ 'players.playerId': 1 });

// Método para finalizar sesión
gameSessionSchema.methods.finalize = async function(playersData) {
    this.endTime = new Date();
    this.duration = Math.round((this.endTime - this.startTime) / 1000);
    
    // Actualizar datos de jugadores
    this.players = playersData.map(p => ({
        playerId: p.id,
        nickname: p.name,
        category: p.category || 'Junior',
        coinsCollected: p.coins || 0,
        deaths: p.deaths || 0,
        completed: p.passedDoor || false,
        score: (p.coins || 0) * 10,
        timePlayed: this.duration
    }));
    
    this.totalCoinsCollected = this.players.reduce((sum, p) => sum + p.coinsCollected, 0);
    this.totalDeaths = this.players.reduce((sum, p) => sum + p.deaths, 0);
    this.bestPlayerScore = Math.max(...this.players.map(p => p.score), 0);
    this.completed = this.players.every(p => p.completed);
    this.averagePlayerTime = this.players.length > 0 ? Math.round(this.duration / this.players.length) : 0;
    
    return this.save();
};

module.exports = mongoose.model('GameSession', gameSessionSchema);