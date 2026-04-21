class Player {
  constructor(id, name, ws) {
    this.id = id;
    this.name = name;

    this.ws = ws; //conexion websocket

    this.x = 100;
    this.y = 100;

    this.vx = 0;
    this.vy = 0;
  }
}

module.exports = Player;