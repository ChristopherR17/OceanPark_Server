const logger = require("./logger");

class Room {
  constructor() {
    this.players = new Map();

    this.state = "waiting"; // waiting | playing

    this.maxPlayers = 8;
    this.minPlayers = 2;
  }

  addPlayer(player) {
    if (this.players.size >= this.maxPlayers) {
        logger.warn('Room is full');
        return false
    }

    this.players.set(player.id, player);
    logger.info('Player has been added');
    return true;
  }

  removePlayer(id) {
    this.players.delete(id);
  }

  getPlayers() {
    return Array.from(this.players.values());
  }

  isReady() {
    return this.players.size >= this.minPlayers;
  }

  setState(state) {
    this.state = state;
  }
}

module.exports = Room;