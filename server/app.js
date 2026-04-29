const WebSocket = require("ws");

const Player = require("./player");
const PlayerRegistry = require("./playerRegistry");
const Game = require("./game");

const PORT = process.env.PORT || 3000;
const wss = new WebSocket.Server({ port: PORT, host: "0.0.0.0" });

const playerRegistry = new PlayerRegistry();
const game = new Game(playerRegistry);

const SPAWN_X = 127;
const SPAWN_Y = 386;

wss.on("connection", (ws) => {
    console.log("🔌 Cliente conectado");

    ws.on("message", (message) => {
        try {
            const data = JSON.parse(message.toString());

            if (data.type === "JOIN") {
                handleJoin(ws, data);
                return;
            }

            if (data.type === "INPUT") {
                handleInput(ws, data);
                return;
            }

            if (data.type === "MOVE") {
                handleMove(ws, data);
                return;
            }
        } catch (e) {
            console.error("❌ Error en mensaje:", e.message);
        }
    });

    ws.on("close", () => {
        const player = playerRegistry.getPlayer(ws);
        if (player && game.gameEngine.leafKey && game.gameEngine.leafKey.pickedBy === player.id) {
            game.gameEngine.leafKey.pickedBy = null;
            game.gameEngine.leafKey.x = game.gameEngine.leafKey.initialX;
            game.gameEngine.leafKey.y = game.gameEngine.leafKey.initialY;
        }
        playerRegistry.removePlayer(ws);
        console.log("🔌 Cliente desconectado");
    });
});

function handleJoin(ws, data) {
    const isViewer = data.viewer === true || data.client === "viewer";
    if (isViewer) {
        ws.isViewer = true;
        ws.send(JSON.stringify({
            type: "WELCOME",
            id: "viewer",
            playerId: "viewer",
            nickname: "viewer",
            name: "viewer",
            viewer: true
        }));
        return;
    }

    const rawName = data.nickname || data.name || "Player";
    const safeName = sanitizeName(rawName);

    if (playerRegistry.nameIsAlreadyTaken(safeName)) {
        ws.send(JSON.stringify({
            type: "ERROR",
            message: "Nom ja utilitzat"
        }));
        return;
    }

    const newId = Math.random().toString(36).substr(2, 9);
    const newPlayer = new Player(newId, safeName, SPAWN_X, SPAWN_Y);

    playerRegistry.addPlayer(ws, newPlayer);

    ws.send(JSON.stringify({
        type: "WELCOME",
        id: newPlayer.id,
        playerId: newPlayer.id,
        nickname: newPlayer.name,
        name: newPlayer.name
    }));

    ws.send(JSON.stringify({
        type: "JOINED",
        id: newPlayer.id,
        playerId: newPlayer.id,
        nickname: newPlayer.name,
        name: newPlayer.name
    }));
}

function handleInput(ws, data) {
    const moveX = Number(data.moveX || 0);

    if (moveX < -0.12) {
        playerRegistry.setMovement(ws, "LEFT");
    } else if (moveX > 0.12) {
        playerRegistry.setMovement(ws, "RIGHT");
    } else {
        playerRegistry.setMovement(ws, "NONE");
    }

    if (data.jumpPressed === true || data.jump === true) {
        playerRegistry.setJump(ws);
    }
}

function handleMove(ws, data) {
    if (data.dir) {
        playerRegistry.setMovement(ws, data.dir);
    }

    if (data.input) {
        if (data.input === "LEFT") playerRegistry.setMovement(ws, "LEFT");
        else if (data.input === "RIGHT") playerRegistry.setMovement(ws, "RIGHT");
        else playerRegistry.setMovement(ws, "NONE");
    }

    if (data.jump === true) {
        playerRegistry.setJump(ws);
    }
}

setInterval(() => {
    game.update();
    broadcastState();
}, 1000 / 60);

function broadcastState() {
    const players = playerRegistry.getPlayersSnapshot();
    const keyState = game.gameEngine.getKeyState();
    const doorState = game.gameEngine.getDoorState();

    const playersSnapshot = players.map((p, index) => ({
        id: p.id,
        playerId: p.id,
        name: p.name,
        nickname: p.name,
        slot: index + 1,
        x: Math.round(p.playerGameState.x),
        y: Math.round(p.playerGameState.y),
        vx: 0,
        vy: Math.round(p.playerGameState.verticalSpeed || 0),
        state: (p.playerGameState.isMovingLeft || p.playerGameState.isMovingRight) ? "RUNNING" : "IDLE",
        anim: (p.playerGameState.isMovingLeft || p.playerGameState.isMovingRight) ? "walk" : "idle",
        facingRight: !p.playerGameState.isMovingLeft,
        grounded: !!p.playerGameState.canJump,
        hasKey: game.gameEngine.leafKey.pickedBy === p.id,
        crossedDoor: !!p.playerGameState.crossedDoor
    }));

    const world = {
        keyTaken: !!keyState.pickedBy,
        keyCarrierId: keyState.pickedBy || "",
        keyX: keyState.x,
        keyY: keyState.y,

        doorOpen: doorState.open,
        doorX: doorState.x,
        doorY: doorState.y,
        doorWidth: doorState.width,
        doorHeight: doorState.height,

        allPlayersPassed: doorState.allPlayersPassed,
        shouldChangeScreen: doorState.allPlayersPassed,
        totalPlayers: playersSnapshot.length,
        passedPlayers: doorState.passedPlayers,

        platforms: game.gameEngine.getPlatformsState(),
        key: {
            x: keyState.x,
            y: keyState.y,
            taken: !!keyState.pickedBy,
            pickedBy: keyState.pickedBy
        },
        door: doorState
    };

    const stateMsg = JSON.stringify({
        type: "STATE",
        players: playersSnapshot,
        world,
        leafKey: keyState
    });

    wss.clients.forEach(client => {
        if (client.readyState === WebSocket.OPEN) {
            client.send(stateMsg);
        }
    });
}

function sanitizeName(name) {
    return String(name || "Player")
        .trim()
        .replace(/[^a-zA-Z0-9_-]/g, "")
        .substring(0, 16) || "Player";
}

console.log(`🚀 Servidor Ocean Park en puerto ${PORT}`);
