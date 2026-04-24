const fs = require("fs");
const path = require("path");

class Room {
  constructor() {
    this.players = new Map();
    this.state = "waiting";
    this.levelData = this.loadLevel();
  }

  loadLevel() {
    try {
      const gameData = JSON.parse(fs.readFileSync(path.join(__dirname, 'game_data.json'), 'utf8'));
      const level = gameData.levels[0];
      const layer = level.layers[0];
      
      // Intentamos cargar el archivo de tiles si existe
      const tileMapJson = JSON.parse(fs.readFileSync(path.join(__dirname, layer.tileMapFile), 'utf8'));

      return {
        layer: {
          tilesWidth: layer.tilesWidth,
          tilesHeight: layer.tilesHeight,
          tileMap: tileMapJson.tileMap
        },
        spawn: { x: 400, y: 300 } // Posición por defecto
      };
    } catch (e) {
      console.log("⚠️ Trabajando sin mapa (game_data.json no encontrado o inválido)");
      return { layer: null, spawn: { x: 100, y: 100 } };
    }
  }

  addPlayer(player) {
    player.x = this.levelData.spawn.x;
    player.y = this.levelData.spawn.y;
    this.players.set(player.id, player);
    return true;
  }

  removePlayer(id) { this.players.delete(id); }
  isReady() { return this.players.size > 0; }
  setState(state) { this.state = state; }
}

module.exports = Room;