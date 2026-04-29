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
            x: 45, y: 261, // Valores por defecto del JSON
            initialX: 45, initialY: 261,
            pickedBy: null,
            width: 32, height: 32
        };
        
        this.loadGameData();
    }

    loadGameData() {
        try {
            const assetsPath = path.join(__dirname, "games-tool-assets");
            const gameData = JSON.parse(fs.readFileSync(path.join(assetsPath, "game_data.json"), "utf-8"));
            const level = gameData.levels[0];

            // Buscar posición de la llave en el JSON
            const keySprite = level.sprites.find(s => s.name.includes("leaf_key") || s.type.includes("leaf_key"));
            if (keySprite) {
                this.leafKey.x = keySprite.x;
                this.leafKey.y = keySprite.y;
                this.leafKey.initialX = keySprite.x;
                this.leafKey.initialY = keySprite.y;
            }

            // Cargar zonas
            const zonesData = JSON.parse(fs.readFileSync(path.join(assetsPath, level.zonesFile), "utf-8"));
            zonesData.zones.forEach(z => {
                const box = new Hitbox(z.x, z.y, z.width, z.height);
                if (z.type === "Floor") this.platforms.push(box);
                else if (z.type === "Player Death") this.deathZones.push(box);
            });
        } catch (e) { console.log("Error cargando datos:", e.message); }
    }

    getKeyState() {
        return { x: Math.round(this.leafKey.x), y: Math.round(this.leafKey.y), pickedBy: this.leafKey.pickedBy };
    }

    update() {
        const keyHitbox = new Hitbox(this.leafKey.x, this.leafKey.y, 32, 32);

        this.playerRegistry.getPlayersSnapshot().forEach(player => {
            const state = player.getGameState();
            const pBox = new Hitbox(state.x, state.y, 32, 32);

            // Lógica de la llave
            if (!this.leafKey.pickedBy && pBox.intersects(keyHitbox)) {
                this.leafKey.pickedBy = player.id;
            }

            if (this.leafKey.pickedBy === player.id) {
                this.leafKey.x = state.x;
                this.leafKey.y = state.y - 35; // Encima de la cabeza
            }

            // Colisiones y Muerte
            if (this.deathZones.find(dz => pBox.intersects(dz)) || state.y > 1200) {
                if (this.leafKey.pickedBy === player.id) {
                    this.leafKey.pickedBy = null;
                    this.leafKey.x = this.leafKey.initialX;
                    this.leafKey.y = this.leafKey.initialY;
                }
                player.resetPosition();
                return;
            }

            // Física básica
            state.verticalSpeed += this.gravity;
            state.y += state.verticalSpeed;
            let col = this.platforms.find(plat => new Hitbox(state.x, state.y, 32, 32).intersects(plat));
            if (col && state.verticalSpeed > 0) {
                state.y = col.y - 32;
                state.verticalSpeed = 0;
                state.canJump = true;
            }
            if (state.isMovingLeft) state.x -= this.speed;
            if (state.isMovingRight) state.x += this.speed;
        });
    }
}
module.exports = GameEngine;