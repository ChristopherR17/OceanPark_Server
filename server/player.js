const PlayerGameState = require("./playerGameState");

class Player {
    constructor(id, name, spawnX, spawnY) {
        this.id = id; 
        this.name = name;
        this.playerGameState = new PlayerGameState(spawnX, spawnY);
    }

    getGameState() { return this.playerGameState; }

    setThisMovement(direction) {
        if (direction === 'LEFT') {
            this.playerGameState.isMovingLeft = true; 
            this.playerGameState.isMovingRight = false;
        } else if (direction === 'RIGHT') {
            this.playerGameState.isMovingLeft = false; 
            this.playerGameState.isMovingRight = true;
        } else if (direction === 'NONE') {
            this.playerGameState.isMovingLeft = false; 
            this.playerGameState.isMovingRight = false;
        }
    }
}
module.exports = Player;