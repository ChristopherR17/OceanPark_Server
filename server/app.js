const WebSocket = require("ws");
const fs = require("fs");
const path = require("path");

const Player = require("./player");
const PlayerRegistry = require("./playerRegistry");
const Game = require("./game");

const PORT = process.env.PORT || 3000;
const wss = new WebSocket.Server({ port: PORT, host: '0.0.0.0' });

const playerRegistry = new PlayerRegistry();
const game = new Game(playerRegistry);

// SPAWN POR DEFECTO
let SPAWN_X = 107; 
let SPAWN_Y = 385; 

wss.on('connection', (ws) => {
    ws.on('message', (message) => {
        try {
            const data = JSON.parse(message);
            handleMessage(ws, data);
        } catch (e) { console.error("Error:", e); }
    });

    ws.on('close', () => {
        const player = playerRegistry.getPlayer(ws);
        if (player) {
            // Si el jugador tenía la llave, la suelta
            if (game.gameEngine.leafKey.pickedBy === player.id) {
                game.gameEngine.leafKey.pickedBy = null;
                game.gameEngine.leafKey.x = game.gameEngine.leafKey.initialX;
                game.gameEngine.leafKey.y = game.gameEngine.leafKey.initialY;
            }
            playerRegistry.removePlayer(ws);
        }
    });
});

function handleMessage(ws, data) {
    if (data.type === "JOIN") {
        if (playerRegistry.nameIsAlreadyTaken(data.name)) return;
        const newId = Math.random().toString(36).substr(2, 9);
        const newPlayer = new Player(newId, data.name, SPAWN_X, SPAWN_Y);
        playerRegistry.addPlayer(ws, newPlayer);
        ws.send(JSON.stringify({ type: "JOINED", playerId: newPlayer.id, name: newPlayer.name }));
    } else if (data.type === "MOVE") {
        playerRegistry.setMovement(ws, data.dir);
        if (data.jump) playerRegistry.setJump(ws);
    }
}

// Bucle de física y red
setInterval(() => {
    game.update();
    broadcastState();
}, 1000 / 60);

function broadcastState() {
    const stateMsg = JSON.stringify({
        type: "STATE",
        players: playerRegistry.getPlayersSnapshot().map(p => ({
            id: p.id,
            name: p.name,
            x: Math.round(p.playerGameState.x),
            y: Math.round(p.playerGameState.y),
            state: (p.playerGameState.isMovingLeft || p.playerGameState.isMovingRight) ? "RUN" : "IDLE",
            facingRight: !p.playerGameState.isMovingLeft
        })),
        leafKey: game.gameEngine.getKeyState() // <--- CORREGIDO: Usamos game.gameEngine
    });
    
    wss.clients.forEach(client => {
        if (client.readyState === WebSocket.OPEN) client.send(stateMsg);
    });
}

console.log("🚀 Servidor Ocean Park iniciado en puerto 3000");