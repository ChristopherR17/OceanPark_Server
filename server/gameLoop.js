function startGameLoop(room, broadcast) {
  const FPS = 60;
  const FRAME_TIME = 1000 / FPS;

  const SPEED = 5;
  const GRAVITY = 1;
  const JUMP_FORCE = -15;
  const GROUND_Y = 300;

  setInterval(() => {
    if (room.state !== "playing") return;

    const playersState = [];

    room.players.forEach((player) => {

      // 1. MOVIMIENTO HORIZONTAL
      if (player.input.left) {
        player.vx = -SPEED;
        player.dir = "LEFT";
      } else if (player.input.right) {
        player.vx = SPEED;
        player.dir = "RIGHT";
      } else {
        player.vx = 0;
      }

      player.x += player.vx;

      // 2. SALTO
      if (player.input.jump && player.onGround) {
        player.vy = JUMP_FORCE;
        player.onGround = false;
        player.input.jump = false;
      }

      // 3. GRAVEDAD
      player.vy += GRAVITY;
      player.y += player.vy;

      // 4. SUELO
      if (player.y >= GROUND_Y) {
        player.y = GROUND_Y;
        player.vy = 0;
        player.onGround = true;
      } else {
        player.onGround = false;
      }

      // 5. ESTADO
      if (!player.onGround) {
        player.state = "JUMP";
      } else if (Math.abs(player.vx) > 0) {
        player.state = "RUN";
      } else {
        player.state = "IDLE";
      }

      // 6. DATA PARA CLIENTE
      playersState.push({
        id: player.id,
        name: player.name,
        x: player.x,
        y: player.y,
        state: player.state,
        facingRight: player.dir === "RIGHT"
      });
    });

    broadcast({
      type: "STATE",
      players: playersState
    });

  }, FRAME_TIME);
}

module.exports = startGameLoop;