class Player {
  constructor(id, name) {
    this.id = id;
    this.name = name;

    // 👇 ya pensado para el juego
    this.x = 100;
    this.y = 100;

    this.vx = 0;
    this.vy = 0;
  }
}

module.exports = Player;