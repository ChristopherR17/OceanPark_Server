const PlayerGameState = require("./playerGameState");

class Player {
    constructor(id, name, spawnX, spawnY) {
        this.id = id; 
        this.name = name;
        
        // Guardamos las coordenadas originales de nacimiento
        this.spawnX = spawnX;
        this.spawnY = spawnY;
        
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

    // NUEVO: Función para devolver al jugador al inicio
    resetPosition() {
        this.playerGameState.x = this.spawnX;
        this.playerGameState.y = this.spawnY;
        this.playerGameState.verticalSpeed = 0; // Le quitamos la velocidad de caída
    }
}
module.exports = Player;