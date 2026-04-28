class Player {
    constructor(id, name, ws) {
        this.id = id;
        this.name = name;
        this.ws = ws;

        // Posición
        this.x = 0;
        this.y = 0;

        // Velocidad
        this.vx = 0;
        this.vy = 0;

        // Input
        this.input = { 
            left: false, 
            right: false, 
            jump: false 
        };

        // Estado
        this.onGround = true;
        this.state = "IDLE";
        this.facingRight = true;
        this.isVisor = false;
        
        // Progreso
        this.coins = 0;
        this.deaths = 0;
        this.passedDoor = false;
        this.category = "Junior";
    }
}

module.exports = Player;