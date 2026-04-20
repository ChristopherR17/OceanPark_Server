function startGameLoop(room, broadcast) {

  const FPS = 20;

  setInterval(() => {

    if (room.state !== "playing") return;

    broadcast({
      type: "STATE",
      players: room.getPlayers()
    });

  }, 1000 / FPS);
}

module.exports = startGameLoop;