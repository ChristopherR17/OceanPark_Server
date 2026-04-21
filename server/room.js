const logger = require("./logger");

class Room {
  constructor() {
    this.players = new Map();
    this.state = "waiting"; // waiting | playing
    this.maxPlayers = 8;
    this.minPlayers = 2;

    this.availableSkins = [
      "mew",
      "doraemon",
      "creeper",
      "luigi",
      "egg"
      //poner mas skins
    ];
  }

  addPlayer(player) {
    if (this.players.size >= this.maxPlayers) {
      logger.warn("Room is full");
      return false;
    }

    if (this.availableSkins.length === 0) {
      logger.warn("No skins available");
      return false;
    }

    //Para hacer que las skins sean random
    const index = Math.floor(Math.random() * this.availableSkins.length);
    const skin = this.availableSkins.splice(index, 1)[0];

    player.skin = skin;

    this.players.set(player.id, player);
    logger.info(`Player added: ${player.id} (${player.name})`);
    return true;
  }

  removePlayer(id) {
    const player = this.players.get(id);

    if (player){
      this.availableSkins.push(player.skin);
    }

    const existed = this.players.delete(id);

    if (existed) {
      logger.info(`Player removed: ${id}`);
    }
  }

  getPlayers() {
    return Array.from(this.players.values());
  }

  isReady() {
    return this.players.size >= this.minPlayers;
  }

  setState(state) {
    this.state = state;
    logger.info(`Room state set to: ${state}`);
  }
}

module.exports = Room;