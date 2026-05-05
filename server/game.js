const GameEngine = require("./gameEngine");

class Game {
    constructor(playerRegistry) {
        this.gameEngine = new GameEngine(playerRegistry);
    }
    update() {
        this.gameEngine.update();
    }
}
module.exports = Game;