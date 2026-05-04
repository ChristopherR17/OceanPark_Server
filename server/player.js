const PlayerGameState = require("./playerGameState");

class Player {
    constructor(id, name, spawnX, spawnY) {
        this.id = id;
        this.name = name;

        this.spawnX = spawnX;
        this.spawnY = spawnY;

        this.playerGameState = new PlayerGameState(spawnX, spawnY);
    }

    getGameState() {
        return this.playerGameState;
    }

    setThisMovement(direction) {
        if (direction === "LEFT") {
            this.playerGameState.isMovingLeft = true;
            this.playerGameState.isMovingRight = false;
        } else if (direction === "RIGHT") {
            this.playerGameState.isMovingLeft = false;
            this.playerGameState.isMovingRight = true;
        } else if (direction === "NONE") {
            this.playerGameState.isMovingLeft = false;
            this.playerGameState.isMovingRight = false;
        }
    }

    resetPosition() {
        this.playerGameState.x = this.spawnX;
        this.playerGameState.y = this.spawnY;
        this.playerGameState.verticalSpeed = 0;
        this.playerGameState.canJump = false;
        this.playerGameState.hasFinishedLevel = false;
        this.playerGameState.hitbox.updateHitboxPosition(this.playerGameState.x, this.playerGameState.y);
    }

    resetForNextLevel(spawnX, spawnY) {
        this.spawnX = spawnX;
        this.spawnY = spawnY;

        this.playerGameState.x = spawnX;
        this.playerGameState.y = spawnY;
        this.playerGameState.verticalSpeed = 0;
        this.playerGameState.isMovingLeft = false;
        this.playerGameState.isMovingRight = false;
        this.playerGameState.canJump = false;
        this.playerGameState.hasFinishedLevel = false;
        this.playerGameState.hitbox.updateHitboxPosition(spawnX, spawnY);
    }
}

module.exports = Player;