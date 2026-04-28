const mongoose = require('mongoose');

const playerSchema = new mongoose.Schema({
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
    category: {
        type: String,
        enum: ['Junior', 'Senior', 'Expert'],
        default: 'Junior'
    },
    stats: {
        totalSessions: { type: Number, default: 0 },
        totalPlayTime: { type: Number, default: 0 },
        totalCoins: { type: Number, default: 0 },
        totalDeaths: { type: Number, default: 0 },
        levelsCompleted: { type: Number, default: 0 },
        bestScore: { type: Number, default: 0 },
        averageSessionTime: { type: Number, default: 0 },
        averageCoinsPerSession: { type: Number, default: 0 }
    },
    lastSession: {
        sessionId: String,
        startTime: Date,
        endTime: Date,
        duration: Number,
        coins: Number,
        deaths: Number,
        completed: Boolean,
        levelReached: Number
    },
    firstSeen: { type: Date, default: Date.now },
    lastSeen: { type: Date, default: Date.now }
}, {
    timestamps: true
});

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

playerSchema.methods.updateStats = async function(session) {
    this.stats.totalSessions += 1;
    this.stats.totalPlayTime += session.duration || 0;
    this.stats.totalCoins += session.coinsCollected || 0;
    this.stats.totalDeaths += session.deaths || 0;
    if (session.completed) this.stats.levelsCompleted += 1;
    if (session.score > this.stats.bestScore) this.stats.bestScore = session.score;
    
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
    await this.updateCategory();
    
    return this.save();
};

playerSchema.index({ 'stats.totalPlayTime': -1 });
playerSchema.index({ 'stats.levelsCompleted': -1 });
playerSchema.index({ category: 1 });

module.exports = mongoose.model('Player', playerSchema);