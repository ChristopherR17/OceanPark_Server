class Player {
  constructor(id, name, ws) {
    this.id = id;
    this.name = name;
    this.ws = ws;

    this.x = 100;
    this.y = 100;

    this.vx = 0;
    this.vy = 0;

    this.input = {
      left: false,
      right: false,
      jump: false
    };
  }

  toJSON() {
    return {
      id: this.id,
      name: this.name,
      x: this.x,
      y: this.y
    };
  }
}

module.exports = Player;