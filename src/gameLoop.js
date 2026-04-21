function startGameLoop(room, broadcast) {
  const FPS = 20;
  const FRAME_TIME = 1000 / FPS;

  const GRAVITY = 1;
  const GROUND_Y = 100;

  setInterval(() => {
    if (room.state !== "playing") return;

    room.players.forEach((player) => {
      // aplicar gravedad
      player.vy += GRAVITY;

      // mover
      player.x += player.vx;
      player.y += player.vy;

      // colisión con suelo
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