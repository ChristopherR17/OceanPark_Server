class Player {
  // Añadimos startX y startY al constructor
  constructor(id, name, ws, startX, startY) {
    this.id = id;
    this.name = name;

    this.ws = ws; // conexion websocket

    // Asignamos las coordenadas iniciales dinámicamente
    this.x = startX;
    this.y = startY;

    this.vx = 0;
    this.vy = 0;
  }

  toJSON() {
    return {
      id: this.id,
      name: this.name,
      x: this.x,
      y: this.y,
      skin: this.skin
    };
  }
}

module.exports = Player;