const logger = require("./logger");

function startGameLoop(room, world, broadcastState) {
    const TICK_RATE = 60;
    const NETWORK_RATE = 15;

    const DT = 1000 / TICK_RATE;
    const NET_DT = 1000 / NETWORK_RATE;

    const SPEED = 5;
    const GRAVITY = 0.8;
    const JUMP_FORCE = -12;
    const MAX_FALL_SPEED = 15;

    let lastTime = Date.now();

    setInterval(() => {
        if (room.state !== "playing" || room.players.size === 0) return;

        const now = Date.now();
        const deltaFrames = Math.min((now - lastTime) / DT, 5);
        lastTime = now;

        for (let f = 0; f < deltaFrames; f++) {
            updatePhysics(room, world);
        }

        updateAnimations(room);
    }, DT);

    setInterval(() => {
        if (room.state !== "playing" || room.players.size === 0) return;
        broadcastState();
    }, NET_DT);
}

function updatePhysics(room, world) {
    room.players.forEach((player) => {
        if (player.isVisor) return;

        // Movimiento horizontal
        if (player.input.left) {
            player.vx = -SPEED;
            player.facingRight = false;
            player.state = "RUN";
        } else if (player.input.right) {
            player.vx = SPEED;
            player.facingRight = true;
            player.state = "RUN";
        } else {
            player.vx *= 0.8;
            if (Math.abs(player.vx) < 0.1) {
                player.vx = 0;
                player.state = "IDLE";
            }
        }

        player.x += player.vx;

        // Salto
        if (player.input.jump && player.onGround) {
            player.vy = JUMP_FORCE;
            player.onGround = false;
            player.input.jump = false;
            player.state = "JUMP";
        }

        // Gravedad
        if (!player.onGround) {
            player.vy += GRAVITY;
            if (player.vy > MAX_FALL_SPEED) player.vy = MAX_FALL_SPEED;
        }

        player.y += player.vy;

        // Suelo
        const floorY = world.getFloorYAt(player.x) || world.height;
        if (player.y >= floorY) {
            player.y = floorY;
            player.vy = 0;
            player.onGround = true;
        } else {
            player.onGround = false;
        }

        // Límites
        player.x = Math.max(0, Math.min(world.width, player.x));
        player.y = Math.max(0, Math.min(world.height, player.y));

        // Llave
        if (!world.keyTaken && world.isPlayerTouchingKey(player)) {
            world.pickUpKey(player);
        }

        // Puerta
        if (world.doorOpen && world.isPlayerAtDoor(player)) {
            world.playerPassDoor(player);
        }

        // Monedas
        world.collectCoins(player);

        // Muerte
        if (world.isInDeathZone(player)) {
            world.respawnPlayer(player);
        }
    });

    // Colisiones entre jugadores
    resolvePlayerCollisions(room);

    // Verificar nivel completado
    if (world.doorOpen && world.allPlayersPassedDoor(room)) {
        world.completeLevel(room);
        logger.info("🎉 ¡Todos los jugadores pasaron la puerta!");
    }
}

function resolvePlayerCollisions(room) {
    const players = Array.from(room.players.values()).filter(p => !p.isVisor);
    
    for (let i = 0; i < players.length; i++) {
        for (let j = i + 1; j < players.length; j++) {
            const a = players[i];
            const b = players[j];
            
            const distX = Math.abs(a.x - b.x);
            const distY = Math.abs(a.y - b.y);
            
            if (distX < 28 && distY < 30) {
                const overlapX = 28 - distX;
                if (a.x < b.x) {
                    a.x -= overlapX / 2;
                    b.x += overlapX / 2;
                } else {
                    a.x += overlapX / 2;
                    b.x -= overlapX / 2;
                }
                
                if (a.y < b.y - 10) {
                    b.y = a.y + 30;
                    b.vy = 0;
                    b.onGround = true;
                } else if (b.y < a.y - 10) {
                    a.y = b.y + 30;
                    a.vy = 0;
                    a.onGround = true;
                }
            }
        }
    }
}

function updateAnimations(room) {
    room.players.forEach((player) => {
        if (!player.onGround) {
            player.state = "JUMP";
        } else if (Math.abs(player.vx) > 0.5) {
            player.state = "RUN";
        } else {
            player.state = "IDLE";
        }
    });
}

module.exports = startGameLoop;