const Hitbox = require("./hitbox");

class PlayerGameState {
    constructor(x, y) {
        this.x = x;
        this.y = y;

        this.verticalSpeed = 0;

        this.isMovingLeft = false;
        this.isMovingRight = false;
        this.facingRight = true;

        this.canJump = false;

        this.width = 32;
        this.height = 32;

        this.hitbox = new Hitbox(this.x, this.y, this.width, this.height);

        this.hasFinishedLevel = false;
    }
}

module.exports = PlayerGameState;