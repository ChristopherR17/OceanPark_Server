const Hitbox = require("./hitbox");
const fs = require("fs");
const path = require("path");

class GameEngine {
    constructor(playerRegistry) {
        this.playerRegistry = playerRegistry;
        this.gravity = 0.8;
        this.speed = 5;
        this.platforms = [];
        this.deathZones = [];
        
        this.leafKey = {
            x: 0, y: 0, initialX: 0, initialY: 0,
            pickedBy: null, width: 32, height: 32
        };

        this.loadGameData();
    }

    loadGameData() {
        try {
            const assetsPath = path.join(__dirname, "games-tool-assets");
            const mainJson = JSON.parse(fs.readFileSync(path.join(assetsPath, "game_data.json"), "utf8"));
            const level = mainJson.levels[0];

            // Cargar posición de llave
            const keySprite = level.sprites.find(s => s.name.includes("leaf_key") || s.type.includes("leaf_key"));
            if (keySprite) {
                this.leafKey.x = this.leafKey.initialX = keySprite.x;
                this.leafKey.y = this.leafKey.initialY = keySprite.y;
            }

            // Cargar suelos
            const zonesData = JSON.parse(fs.readFileSync(path.join(assetsPath, level.zonesFile), "utf-8"));
            zonesData.zones.forEach(z => {
                const box = new Hitbox(z.x, z.y, z.width, z.height);
                if (z.type === "Floor") this.platforms.push(box);
                else if (z.type === "Player Death") this.deathZones.push(box);
            });
        } catch (e) { console.log("Error cargando mapa:", e.message); }
    }

    update() {
        const players = this.playerRegistry.getPlayersSnapshot();

        players.forEach(player => {
            const state = player.getGameState();
            
            // 1. MOVIMIENTO HORIZONTAL (Mantenemos el bloqueo lateral)
            let nextX = state.x;
            if (state.isMovingLeft) nextX -= this.speed;
            if (state.isMovingRight) nextX += this.speed;

            const testHitboxX = new Hitbox(nextX, state.y, state.width, state.height);
            if (this.canMoveTo(player.id, testHitboxX)) {
                state.x = nextX;
            }

            // 2. GRAVEDAD Y MOVIMIENTO VERTICAL
            state.verticalSpeed += this.gravity;
            let nextY = state.y + state.verticalSpeed;
            const testHitboxY = new Hitbox(state.x, nextY, state.width, state.height);

            // --- LÓGICA DE COLISIÓN ---
            
            // A. ¿Choca con el suelo?
            let platformCol = this.platforms.find(p => testHitboxY.intersects(p));

            // B. ¿Choca con otro jugador? (Solo si cae y no es él mismo)
            let otherPlayerCol = players.find(other => 
                other.id !== player.id && testHitboxY.intersects(other.playerGameState.hitbox)
            );

            // Si choca con plataforma O con la cabeza de otro jugador
            if (state.verticalSpeed > 0) {
                if (platformCol) {
                    state.y = platformCol.y - state.height;
                    state.verticalSpeed = 0;
                    state.canJump = true;
                } 
                else if (otherPlayerCol && state.y + state.height <= otherPlayerCol.playerGameState.y + 10) {
                    // Solo aterrizamos si estamos "encima" (el +10 es un margen de error)
                    state.y = otherPlayerCol.playerGameState.y - state.height;
                    state.verticalSpeed = 0;
                    state.canJump = true;
                    
                    // OPCIONAL: Si el de abajo se mueve, el de arriba se mueve con él
                    if (otherPlayerCol.playerGameState.isMovingLeft) state.x -= this.speed;
                    if (otherPlayerCol.playerGameState.isMovingRight) state.x += this.speed;
                } else {
                    state.y = nextY;
                }
            } else {
                state.y = nextY;
            }

            // 3. ACTUALIZAR HITBOX
            state.hitbox.updateHitboxPosition(state.x, state.y);

            // 4. LÓGICA DE LA LLAVE (Pegar a la cabeza)
            if (this.leafKey.pickedBy === player.id) {
                this.leafKey.x = state.x;
                this.leafKey.y = state.y - 35;
            } else if (!this.leafKey.pickedBy) {
                const keyHitbox = new Hitbox(this.leafKey.x, this.leafKey.y, 32, 32);
                if (state.hitbox.intersects(keyHitbox)) this.leafKey.pickedBy = player.id;
            }

            // 5. MUERTE
            if (this.deathZones.find(dz => state.hitbox.intersects(dz)) || state.y > 1500) {
                if (this.leafKey.pickedBy === player.id) {
                    this.leafKey.pickedBy = null;
                    this.leafKey.x = this.leafKey.initialX;
                    this.leafKey.y = this.leafKey.initialY;
                }
                player.resetPosition();
            }
        });
    }

    canMoveTo(playerId, hitbox) {
        // Evitamos que los jugadores se solapen lateralmente
        for (const other of this.playerRegistry.getPlayersSnapshot()) {
            if (other.id !== playerId) {
                // Solo bloqueamos X si NO estamos uno encima del otro
                const otherState = other.playerGameState;
                if (hitbox.intersects(otherState.hitbox)) {
                    // Si el jugador está intentando entrar en el cuerpo del otro lateralmente, bloqueamos
                    if (Math.abs(hitbox.y - otherState.y) < 20) return false;
                }
            }
        }
        return true;
    }

    getKeyState() {
        return { x: Math.round(this.leafKey.x), y: Math.round(this.leafKey.y), pickedBy: this.leafKey.pickedBy };
    }
}

module.exports = GameEngine;