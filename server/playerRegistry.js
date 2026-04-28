class PlayerRegistry {
    constructor() { this.players = new Map(); }

    addPlayer(ws, player) { this.players.set(ws, player); }
    getPlayer(ws) { return this.players.get(ws); }
    removePlayer(ws) { this.players.delete(ws); }
    
    getPlayersSnapshot() { return Array.from(this.players.values()); }
    getAllSockets() { return Array.from(this.players.keys()); }
    
    nameIsAlreadyTaken(name) { 
        return this.getPlayersSnapshot().some(p => p.name === name); 
    }
    
    setMovement(ws, direction) {
        const p = this.getPlayer(ws);
        if (p) p.setThisMovement(direction);
    }
    
    setJump(ws) {
        const p = this.getPlayer(ws);
        if (p && p.playerGameState.canJump) {
            // Fuerza de salto hacia arriba (en Y-down, hacia arriba es negativo)
            p.playerGameState.verticalSpeed = -12; 
            p.playerGameState.canJump = false;
        }
    }
}
module.exports = PlayerRegistry;