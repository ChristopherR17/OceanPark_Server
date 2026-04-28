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

// EXTRAER EL SPAWN DESDE game_data.json
// En app.js
let SPAWN_X = 107; // El X que me diste
let SPAWN_Y = 385; // El Y que me diste

try {
    const gameDataPath = path.join(__dirname, "games-tool-assets", "game_data.json");
    if (fs.existsSync(gameDataPath)) {
        const gameData = JSON.parse(fs.readFileSync(gameDataPath, "utf-8"));
        
        // Buscamos tu sprite de mushroom en el JSON
        const sprites = gameData.levels[0].sprites;
        const spawnSprite = sprites.find(s => s.name === "mushroom idle" || s.type.includes("mushroom"));
        
        if (spawnSprite) {
            SPAWN_X = spawnSprite.x;
            SPAWN_Y = spawnSprite.y;
            console.log(`✅ Punto de Spawn detectado -> X:${SPAWN_X}, Y:${SPAWN_Y}`);
        }
    }
} catch (e) { console.error("⚠️ Error game_data.json:", e.message); }

console.log(`🚀 Servidor Ocean Park iniciado en puerto ${PORT}`);

wss.on("connection", (ws) => {
    ws.on("message", (raw) => {
        try {
            const data = JSON.parse(raw);
            handleMessage(ws, data);
        } catch (e) {} 
    });

    ws.on("close", () => {
        const player = playerRegistry.getPlayer(ws);
        if (player) {
            playerRegistry.removePlayer(ws);
            broadcastState();
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
        }))
    });
    
    playerRegistry.getAllSockets().forEach(s => {
        if (s.readyState === WebSocket.OPEN) s.send(stateMsg);
    });
}

// Bucle de juego a 60 FPS
setInterval(() => {
    game.update();
    broadcastState();
}, 1000 / 60);