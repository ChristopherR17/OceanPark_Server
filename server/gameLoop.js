function startGameLoop(room, broadcast) {
  const FPS = 20;
  const FRAME_TIME = 1000 / FPS;

  const GRAVITY = 1;
  const GROUND_Y = 100;

  const JUMP_FORCE = -12;

  setInterval(() => {
    if (room.state !== "playing") return;

    room.players.forEach((player) => {
      // movimiento horizontal
      if (player.input.left) player.vx = -5;
      else if (player.input.right) player.vx = 5;
      else player.vx = 0;

      // salto
      if (player.input.jump && player.y >= GROUND_Y) {
        player.vy = JUMP_FORCE;
      }

      // reset jump (evita salto infinito)
      player.input.jump = false;

      // gravedad
      player.vy += GRAVITY;

      // movimiento
      player.x += player.vx;
      player.y += player.vy;

      // suelo
      if (player.y > GROUND_Y) {
        player.y = GROUND_Y;
        player.vy = 0;
      }
    });

    broadcast({
      type: "STATE",
      players: room.getPlayers(),
    });
  }, FRAME_TIME);
}

module.exports = startGameLoop;