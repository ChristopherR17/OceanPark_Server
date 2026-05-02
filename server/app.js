const WebSocket = require("ws");

const Player = require("./player");
const PlayerRegistry = require("./playerRegistry");
const Game = require("./game");

const PORT = process.env.PORT || 3000;
const wss = new WebSocket.Server({ port: PORT, host: "0.0.0.0" });

const playerRegistry = new PlayerRegistry();
const game = new Game(playerRegistry);

let SPAWN_X = 107;
let SPAWN_Y = 385 + 673;

wss.on("connection", (ws) => {
    console.log("Cliente conectado");

    ws.on("message", (message) => {
        try {
            const data = JSON.parse(message);

            if (data.type === "JOIN") {
                handleJoin(ws, data);
            } else if (data.type === "MOVE") {
                handleMove(ws, data);
            }
        } catch (e) {
            console.error("Error en mensaje:", e.message);
        }
    });

    ws.on("close", () => {
        const player = playerRegistry.getPlayer(ws);

        if (player) {
            if (
                game.gameEngine.leafKey &&
                game.gameEngine.leafKey.pickedBy === player.id
            ) {
                game.gameEngine.resetKey();
            }

            playerRegistry.removePlayer(ws);
            console.log(`Jugador desconectado: ${player.name}`);
        }
    });
});

function handleJoin(ws, data) {
    const name = String(data.name || "").trim();

    if (!name) {
        ws.send(JSON.stringify({
            type: "ERROR",
            message: "Nombre vacÃ­o"
        }));
        return;
    }

    if (playerRegistry.nameIsAlreadyTaken(name)) {
        ws.send(JSON.stringify({
            type: "ERROR",
            message: "Nombre ya usado"
        }));
        return;
    }

    const newId = Math.random().toString(36).substr(2, 9);

    const spawnIndex = playerRegistry.getPlayersSnapshot().length;
    const spawnX = SPAWN_X + spawnIndex * 40;
    const spawnY = SPAWN_Y;

    const newPlayer = new Player(newId, name, spawnX, spawnY);

    playerRegistry.addPlayer(ws, newPlayer);

    ws.send(JSON.stringify({
        type: "JOINED",
        playerId: newPlayer.id,
        name: newPlayer.name
    }));

    console.log(`Nuevo jugador: ${newPlayer.name} (${newPlayer.id})`);
}

function handleMove(ws, data) {
    playerRegistry.setMovement(ws, data.dir);

    if (data.jump) {
        playerRegistry.setJump(ws);
    }
}

setInterval(() => {
    game.update();
    broadcastState();
}, 1000 / 60);

function broadcastState() {
    const playersSnapshot = playerRegistry.getPlayersSnapshot().map(p => {
        const gs = p.playerGameState;

        let visualState = "IDLE";

        if (gs.verticalSpeed !== 0 || !gs.canJump) {
            visualState = "JUMP";
        }

        if ((gs.isMovingLeft || gs.isMovingRight) && gs.canJump) {
            visualState = "RUN";
        }

        return {
            id: p.id,
            name: p.name,
            x: Math.round(gs.x),
            y: Math.round(gs.y),
            state: visualState,
            facingRight: !gs.isMovingLeft,
            hasKey: game.gameEngine.leafKey.pickedBy === p.id,
            hasFinishedLevel: gs.hasFinishedLevel
        };
    });

    const stateMsg = JSON.stringify({
        type: "STATE",
        level: game.gameEngine.level,
        players: playersSnapshot,
        leafKey: game.gameEngine.getKeyState(),
        door: game.gameEngine.getDoorState(),
        exitZone: game.gameEngine.getExitZoneState()
    });

    wss.clients.forEach(client => {
        if (client.readyState === WebSocket.OPEN) {
            client.send(stateMsg);
        }
    });
}

console.log(`Servidor Ocean Park en puerto ${PORT}`);