const Hitbox = require("./hitbox");
const fs = require("fs");
const path = require("path");

class GameEngine {
    constructor(playerRegistry) {
        this.playerRegistry = playerRegistry;
        this.gravity = 0.8;
        this.speed = 5;
        this.platforms = [];
        this.hitboxesAnim = { IDLE: {w: 32, h: 32}, RIGHT: {w: 32, h: 32}, LEFT: {w: 32, h: 32} };
        
        this.loadGameData();
    }

    loadGameData() {
        // 1. Cargar Hitboxes
        try {
            const animPath = path.join(__dirname, "games-tool-assets", "animations", "animations.json");
            if (fs.existsSync(animPath)) {
                console.log("✅ animations.json detectado");
            }
        } catch (e) { }

        // 2. Cargar Zonas (Suelos)
        try {
            // Buscamos en la ruta exacta de tu JSON
            let zonesPath = path.join(__dirname, "games-tool-assets", "zones", "level_000_zones.json");
            
            // Fallback por si lo tienes en la carpeta raíz de assets
            if (!fs.existsSync(zonesPath)) {
                zonesPath = path.join(__dirname, "games-tool-assets", "level_000_zones.json");
            }

            if (fs.existsSync(zonesPath)) {
                const zoneData = JSON.parse(fs.readFileSync(zonesPath, "utf-8"));
                zoneData.zones.forEach(z => {
                    if (z.type === "Floor") {
                        this.platforms.push(new Hitbox(z.x, z.y, z.width, z.height));
                    }
                });
                console.log(`✅ Zonas de colisión cargadas: ${this.platforms.length} plataformas.`);
            } else {
                console.log("⚠️ No se encontró el JSON de zonas. Usando suelo por defecto.");
                this.platforms = [new Hitbox(13, 402, 275, 12), new Hitbox(335, 401, 168, 14)];
            }
        } catch (e) { console.error("⚠️ Error leyendo zones:", e.message); }
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

            // Si choca cayendo (velocidad positiva en Y-down)
            if (collision && state.verticalSpeed > 0) { 
                state.y = collision.y - state.height; // Se apoya justo encima
                state.verticalSpeed = 0;
                state.canJump = true;
            } else {
                state.y = nextY;
                if (state.verticalSpeed !== 0) state.canJump = false;
            }

            state.hitbox.updateHitboxPosition(state.x, state.y);
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
}
module.exports = GameEngine;