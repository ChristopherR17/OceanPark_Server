class Player {
  constructor(id, name, ws) {
    this.id = id;
    this.name = name;
    this.ws = ws;
    this.x = 0;
    this.y = 0;
    this.input = { left: false, right: false, jump: false };
  }
}
module.exports = Player;