function startGameLoop(room, broadcast) {
  const FPS = 60;
  const step = 1000 / FPS;
  const speed = 5;

  setInterval(() => {
    if (room.state !== "playing") return;

    const playersState = [];

    room.players.forEach((player) => {
      // Lógica de movimiento
      if (player.input.left) player.x -= speed;
      if (player.input.right) player.x += speed;
      if (player.input.jump) player.y += speed * 2; // Salto básico

      playersState.push({
        id: player.id,
        name: player.name,
        x: player.x,
        y: player.y
      });
    });

    // Enviamos el estado a todos
    broadcast({
      type: "STATE",
      players: playersState
    });
  }, step);

  // Dentro de tu gameLoop.js (en la función de actualización)

function updatePhysics(room) {
  room.players.forEach((player) => {
    // 1. APLICAR MOVIMIENTO (Física)
    if (player.input.left) {
      player.x -= 5; // O la velocidad que tengas
    }
    if (player.input.right) {
      player.x += 5;
    }
    if (player.input.jump) {
      // Lógica de salto...
    }

    // 2. 🛑 RESETEAR CONTROLES AUTOMÁTICAMENTE (NUEVO)
    // El servidor asume que está parado a menos que llegue un paquete nuevo
    // antes del siguiente tick.
    player.input.left = false;
    player.input.right = false;
    player.input.jump = false;
  });
}
}

module.exports = startGameLoop;