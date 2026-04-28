const mongoose = require('mongoose');

const playerSchema = new mongoose.Schema({
    // Identificación
    playerId: {
        type: String,
        required: true,
        unique: true,
        index: true
    },
    nickname: {
        type: String,
        required: true,
        trim: true,
        maxlength: 16
    },
    
    // Categoría del jugador (para ERP Navision)
    category: {
        type: String,
        enum: ['Junior', 'Senior', 'Expert'],
        default: 'Junior'
    },
    
    // Estadísticas acumuladas
    stats: {
        totalSessions: { type: Number, default: 0 },
        totalPlayTime: { type: Number, default: 0 },     // segundos
        totalCoins: { type: Number, default: 0 },
        totalDeaths: { type: Number, default: 0 },
        levelsCompleted: { type: Number, default: 0 },
        bestScore: { type: Number, default: 0 },
        averageSessionTime: { type: Number, default: 0 }, // segundos
        averageCoinsPerSession: { type: Number, default: 0 }
    },
    
    // Historial de partidas
    lastSession: {
        sessionId: String,
        startTime: Date,
        endTime: Date,
        duration: Number,     // segundos
        coins: Number,
        deaths: Number,
        completed: Boolean,
        levelReached: Number
    },
    
    // Fechas
    firstSeen: { type: Date, default: Date.now },
    lastSeen: { type: Date, default: Date.now }
}, {
    timestamps: true
});

// Método para actualizar categoría basado en estadísticas
playerSchema.methods.updateCategory = function() {
    const stats = this.stats;
    
    if (stats.totalPlayTime > 7200 && stats.levelsCompleted >= 5 && stats.totalCoins > 500) {
        this.category = 'Expert';
    } else if (stats.totalPlayTime > 1800 || stats.levelsCompleted >= 2) {
        this.category = 'Senior';
    } else {
        this.category = 'Junior';
    }
    
    return this.save();
};

// Método para calcular estadísticas después de una sesión
playerSchema.methods.updateStats = async function(session) {
    this.stats.totalSessions += 1;
    this.stats.totalPlayTime += session.duration || 0;
    this.stats.totalCoins += session.coinsCollected || 0;
    this.stats.totalDeaths += session.deaths || 0;
    if (session.completed) this.stats.levelsCompleted += 1;
    if (session.score > this.stats.bestScore) this.stats.bestScore = session.score;
    
    // Promedios
    this.stats.averageSessionTime = Math.round(this.stats.totalPlayTime / this.stats.totalSessions);
    this.stats.averageCoinsPerSession = Math.round(this.stats.totalCoins / this.stats.totalSessions);
    
    this.lastSession = {
        sessionId: session.sessionId,
        startTime: session.startTime,
        endTime: session.endTime,
        duration: session.duration,
        coins: session.coinsCollected,
        deaths: session.deaths,
        completed: session.completed,
        levelReached: session.levelReached
    };
    
    this.lastSeen = new Date();
    
    // Actualizar categoría
    await this.updateCategory();
    
    return this.save();
};

// Índices para consultas del ERP
playerSchema.index({ 'stats.totalPlayTime': -1 });
playerSchema.index({ 'stats.levelsCompleted': -1 });
playerSchema.index({ category: 1 });

module.exports = mongoose.model('Player', playerSchema);