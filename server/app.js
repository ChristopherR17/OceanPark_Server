const WebSocket = require("ws");
const fs = require("fs");
const path = require("path");

const Player = require("./player");
const PlayerRegistry = require("./playerRegistry");
const Game = require("./game");

// Usamos el puerto del entorno o el 3000
const PORT = process.env.PORT || 3000;
const wss = new WebSocket.Server({ port: PORT, host: '0.0.0.0' });

const playerRegistry = new PlayerRegistry();
const game = new Game(playerRegistry);

// Valores de spawn por defecto (se usan si el cliente no envía posición)
let SPAWN_X = 107; 
let SPAWN_Y = 385; 

wss.on('connection', (ws) => {
    console.log("🔌 Cliente conectado");

    ws.on('message', (message) => {
        try {
            const data = JSON.parse(message);
            
            if (data.type === "JOIN") {
                if (playerRegistry.nameIsAlreadyTaken(data.name)) return;
                
                const newId = Math.random().toString(36).substr(2, 9);
                // Creamos el jugador con el spawn del servidor
                const newPlayer = new Player(newId, data.name, SPAWN_X, SPAWN_Y);
                
                playerRegistry.addPlayer(ws, newPlayer);
                ws.send(JSON.stringify({ 
                    type: "JOINED", 
                    playerId: newPlayer.id, 
                    name: newPlayer.name 
                }));
                
            } else if (data.type === "MOVE") {
                // Pasamos el movimiento al registro que ya tienes
                playerRegistry.setMovement(ws, data.dir);
                if (data.jump) playerRegistry.setJump(ws);
            }
        } catch (e) {
            console.error("❌ Error en mensaje:", e.message);
        }
    });

    ws.on('close', () => {
        const player = playerRegistry.getPlayer(ws);
        if (player) {
            // Si el jugador que se va tenía la llave, el motor la resetea
            if (game.gameEngine.leafKey && game.gameEngine.leafKey.pickedBy === player.id) {
                game.gameEngine.leafKey.pickedBy = null;
                game.gameEngine.leafKey.x = game.gameEngine.leafKey.initialX;
                game.gameEngine.leafKey.y = game.gameEngine.leafKey.initialY;
            }
            playerRegistry.removePlayer(ws);
        }
    });
});

// Bucle de lógica: 60 veces por segundo
setInterval(() => {
    // 1. Ejecuta la física (gameEngine.js)
    game.update();
    
    // 2. Envía el estado a todos los conectados
    broadcastState();
}, 1000 / 60);

function broadcastState() {
    const playersSnapshot = playerRegistry.getPlayersSnapshot().map(p => ({
        id: p.id,
        name: p.name,
        x: Math.round(p.playerGameState.x),
        y: Math.round(p.playerGameState.y),
        state: (p.playerGameState.isMovingLeft || p.playerGameState.isMovingRight) ? "RUN" : "IDLE",
        facingRight: !p.playerGameState.isMovingLeft
    }));

    const stateMsg = JSON.stringify({
        type: "STATE",
        players: playersSnapshot,
        // Accedemos a la llave a través de la ruta correcta de tu objeto 'game'
        leafKey: game.gameEngine.getKeyState() 
    });
    
    wss.clients.forEach(client => {
        if (client.readyState === WebSocket.OPEN) {
            client.send(stateMsg);
        }
    });
}

console.log(`🚀 Servidor Ocean Park en puerto ${PORT}`);