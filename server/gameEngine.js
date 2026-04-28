const Hitbox = require("./hitbox");
const fs = require("fs");
const path = require("path");

class GameEngine {
    constructor(playerRegistry) {
        this.playerRegistry = playerRegistry;
        this.gravity = 0.8;
        this.speed = 5;
        this.platforms = [];
        this.deathZones = []; // <-- NUEVO: Array para las zonas de muerte
        this.hitboxesAnim = { IDLE: {w: 32, h: 32}, RIGHT: {w: 32, h: 32}, LEFT: {w: 32, h: 32} };
        
        this.loadGameData();
    }

    loadGameData() {
        try {
            let zonesPath = path.join(__dirname, "games-tool-assets", "zones", "level_000_zones.json");
            
            if (!fs.existsSync(zonesPath)) {
                zonesPath = path.join(__dirname, "games-tool-assets", "level_000_zones.json");
            }
            const zoneData = JSON.parse(fs.readFileSync(zonesPath, "utf-8"));
            zoneData.zones.forEach(z => {
                        // Usamos las coordenadas puras del JSON (z.x y z.y)
                        if (z.type === "Floor") {
                            this.platforms.push(new Hitbox(z.x, z.y, z.width, z.height));
                        } 
                        else if (z.type === "Player Death") {
                            this.deathZones.push(new Hitbox(z.x, z.y, z.width, z.height));
                        }
                    });
                    console.log("✅ Servidor cargado con coordenadas originales.");
                } catch (e) { 
                    console.error("⚠️ Error game_data.json:", e.message);
                }
            }

    update() {
        this.playerRegistry.getPlayersSnapshot().forEach(player => {
            const state = player.getGameState();

            let currentAnim = "IDLE";
            if (state.isMovingLeft) currentAnim = "LEFT";
            if (state.isMovingRight) currentAnim = "RIGHT";
            state.width = this.hitboxesAnim[currentAnim].w;
            state.height = this.hitboxesAnim[currentAnim].h;
            state.hitbox.width = state.width;
            state.hitbox.height = state.height;

            // Movimiento X
            let nextX = state.x;
            if (state.isMovingLeft) nextX -= this.speed;
            if (state.isMovingRight) nextX += this.speed;

            const testHitboxX = new Hitbox(nextX, state.y, state.width, state.height);
            if (this.canMoveTo(player.id, testHitboxX)) {
                state.x = nextX;
            }

            // Movimiento Y (Gravedad hacia abajo)
            state.verticalSpeed += this.gravity;
            let nextY = state.y + state.verticalSpeed;

            const testHitboxY = new Hitbox(state.x, nextY, state.width, state.height);
            let collision = this.getPlatformCollision(testHitboxY);

            if (collision && state.verticalSpeed > 0) { 
                state.y = collision.y - state.height;
                state.verticalSpeed = 0;
                state.canJump = true;
            } else {
                state.y = nextY;
                if (state.verticalSpeed !== 0) state.canJump = false;
            }

            // Actualizamos la hitbox a su posición final en este frame
            state.hitbox.updateHitboxPosition(state.x, state.y);

            // NUEVO: Comprobamos si el jugador ha tocado una zona de muerte
            if (this.getDeathCollision(state.hitbox)) {
                player.resetPosition(); // ¡Teletransporte al inicio!
                state.hitbox.updateHitboxPosition(state.x, state.y); // Actualizamos la hitbox para que no muera en bucle
            }
        });
    }

    canMoveTo(playerId, hitbox) {
        for (const other of this.playerRegistry.getPlayersSnapshot()) {
            if (other.id !== playerId && hitbox.intersects(other.playerGameState.hitbox)) {
                return false;
            }
        }
        return true;
    }

    getPlatformCollision(hitbox) {
        return this.platforms.find(p => hitbox.intersects(p));
    }

    // NUEVO: Función para comprobar choques con la muerte
    getDeathCollision(hitbox) {
        return this.deathZones.find(dz => hitbox.intersects(dz));
    }
}
module.exports = GameEngine;