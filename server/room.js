class Room {
    constructor() {
        this.players = new Map();
        this.state = "waiting"; // waiting, playing, completed
        this.startTime = null;
    }

    addPlayer(player) {
        if (this.players.has(player.id)) return false;
        this.players.set(player.id, player);
        
        if (this.state === "waiting" && this.players.size >= 1) {
            this.state = "playing";
            this.startTime = Date.now();
        }
        
        return true;
    }

    removePlayer(id) { 
        this.players.delete(id); 
        
        if (this.players.size === 0) {
            this.state = "waiting";
            this.startTime = null;
        }
    }
    
    isReady() { 
        return this.players.size > 0; 
    }
    
    setState(state) { 
        this.state = state; 
    }
    
    getPlayersArray() {
        return Array.from(this.players.values());
    }
}

module.exports = Room;