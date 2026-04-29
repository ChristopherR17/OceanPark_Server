const Hitbox = require("./hitbox");

class PlayerGameState {
    constructor(x, y) {
        this.x = x;
        this.y = y;

        this.verticalSpeed = 0;

        this.isMovingLeft = false;
        this.isMovingRight = false;
        this.canJump = false;

        this.width = 32;
        this.height = 32;

        this.hitbox = new Hitbox(this.x, this.y, this.width, this.height);

        // Sprint 2: saber si este jugador ya ha cruzado la puerta
        this.hasFinishedLevel = false;
    }
}

module.exports = PlayerGameState;