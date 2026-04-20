require('dotenv').config();
const http = require('http');
const WebSocket = require('ws');
const { v4: uuidv4 } = require('uuid');
const connectDB = require('./config/database');
const logger = require('./utils/logger');
const Player = require('./models/Player');
const Room = require('./models/Room');

// Conectar a MongoDB
connectDB();

// Crear servidor HTTP
const server = http.createServer((req, res) => {
  // Health check endpoint
  if (req.url === '/status') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: 'online',
      connections: wss.clients.size,
      timestamp: new Date().toISOString()
    }));
  } else {
    res.writeHead(404);
    res.end();
  }
});

// Crear servidor WebSocket
const wss = new WebSocket.Server({ server });

// Almacenamiento en memoria
const clients = new Map(); // socketId -> { ws, playerData, roomId }
const playerRooms = new Map(); // socketId -> roomId

// Generar código de sala
const generateRoomCode = () => uuidv4().substring(0, 6).toUpperCase();

// Broadcast a todos en una sala
const broadcastToRoom = (roomId, message, excludeSocketId = null) => {
  const messageStr = JSON.stringify(message);
  
  clients.forEach((client, socketId) => {
    if (client.roomId === roomId && 
        socketId !== excludeSocketId && 
        client.ws.readyState === WebSocket.OPEN) {
      client.ws.send(messageStr);
    }
  });
};

// ============ WEBSOCKET CONNECTION ============
wss.on('connection', (ws) => {
  const socketId = uuidv4();
  logger.info(`🔌 Nueva conexión: ${socketId}`);
  
  // Almacenar cliente
  clients.set(socketId, { 
    ws, 
    playerData: null, 
    roomId: null 
  });

  // Enviar ID de conexión
  ws.send(JSON.stringify({
    type: 'connected',
    data: { socketId }
  }));

  // Manejar mensajes
  ws.on('message', async (data) => {
    try {
      const message = JSON.parse(data);
      const client = clients.get(socketId);
      
      if (!client) return;
      
      await handleMessage(ws, socketId, message, client);
      
    } catch (error) {
      logger.error('Error procesando mensaje:', error);
      ws.send(JSON.stringify({
        type: 'error',
        data: { message: 'Error procesando mensaje' }
      }));
    }
  });

  // Manejar desconexión
  ws.on('close', async () => {
    logger.info(`🔌 Desconectado: ${socketId}`);
    
    const roomId = playerRooms.get(socketId);
    
    if (roomId) {
      try {
        const room = await Room.findOne({ roomId });
        
        if (room) {
          // Eliminar jugador de la sala
          room.players = room.players.filter(p => p.socketId !== socketId);
          
          if (room.players.length === 0) {
            await Room.deleteOne({ roomId });
            logger.info(`🗑️ Sala ${roomId} eliminada (vacía)`);
          } else {
            // Reasignar host si es necesario
            if (room.hostSocketId === socketId) {
              room.hostSocketId = room.players[0].socketId;
              
              // Notificar al nuevo host
              const newHostClient = clients.get(room.hostSocketId);
              if (newHostClient && newHostClient.ws.readyState === WebSocket.OPEN) {
                newHostClient.ws.send(JSON.stringify({
                  type: 'new-host',
                  data: { newHostId: room.hostSocketId }
                }));
              }
            }
            
            await room.save();
            
            // Notificar a la sala
            broadcastToRoom(roomId, {
              type: 'player-left',
              data: {
                playerId: socketId,
                players: room.players
              }
            });
          }
        }
        
        playerRooms.delete(socketId);
      } catch (error) {
        logger.error('Error en desconexión:', error);
      }
    }
    
    // Limpiar datos del jugador
    await Player.findOneAndUpdate(
      { socketId },
      { roomId: null, isReady: false }
    );
    
    clients.delete(socketId);
  });

  // Manejar errores
  ws.on('error', (error) => {
    logger.error(`Error WebSocket ${socketId}:`, error);
  });
});

// ============ MANEJADOR DE MENSAJES ============
async function handleMessage(ws, socketId, message, client) {
  const { type, data } = message;

  switch (type) {
    case 'register':
      await handleRegister(ws, socketId, data, client);
      break;
      
    case 'create-room':
      await handleCreateRoom(ws, socketId, data, client);
      break;
      
    case 'join-room':
      await handleJoinRoom(ws, socketId, data, client);
      break;
      
    case 'player-ready':
      await handlePlayerReady(ws, socketId, data, client);
      break;
      
    case 'leave-room':
      await handleLeaveRoom(ws, socketId, client);
      break;
      
    case 'ping':
      ws.send(JSON.stringify({ type: 'pong' }));
      break;
      
    default:
      ws.send(JSON.stringify({
        type: 'error',
        data: { message: `Tipo desconocido: ${type}` }
      }));
  }
}

// ============ HANDLERS ESPECÍFICOS ============
async function handleRegister(ws, socketId, data, client) {
  try {
    const { nickname, color } = data;
    
    const player = new Player({
      socketId,
      nickname,
      color: color || '#FF5733'
    });
    
    await player.save();
    client.playerData = player;
    
    ws.send(JSON.stringify({
      type: 'registered',
      data: {
        success: true,
        player: {
          socketId,
          nickname: player.nickname,
          color: player.color
        }
      }
    }));
    
    logger.info(`✅ ${nickname} registrado (${socketId})`);
  } catch (error) {
    ws.send(JSON.stringify({
      type: 'error',
      data: { message: 'Error al registrar jugador' }
    }));
  }
}

async function handleCreateRoom(ws, socketId, data, client) {
  try {
    if (!client.playerData) {
      ws.send(JSON.stringify({
        type: 'error',
        data: { message: 'Jugador no registrado' }
      }));
      return;
    }
    
    const { roomName, maxPlayers = 8 } = data;
    const roomId = generateRoomCode();
    
    const room = new Room({
      roomId,
      roomName: roomName || `Sala de ${client.playerData.nickname}`,
      hostSocketId: socketId,
      players: [{
        socketId,
        nickname: client.playerData.nickname,
        isReady: false,
        color: client.playerData.color
      }],
      maxPlayers
    });
    
    await room.save();
    
    client.roomId = roomId;
    playerRooms.set(socketId, roomId);
    
    client.playerData.roomId = roomId;
    await client.playerData.save();
    
    ws.send(JSON.stringify({
      type: 'room-created',
      data: {
        success: true,
        roomId: roomId,
        room: room
      }
    }));
    
    logger.info(`🏠 Sala ${roomId} creada por ${client.playerData.nickname}`);
  } catch (error) {
    ws.send(JSON.stringify({
      type: 'error',
      data: { message: 'Error al crear sala' }
    }));
  }
}

async function handleJoinRoom(ws, socketId, data, client) {
  try {
    if (!client.playerData) {
      ws.send(JSON.stringify({
        type: 'error',
        data: { message: 'Jugador no registrado' }
      }));
      return;
    }
    
    const { roomId } = data;
    const room = await Room.findOne({ roomId: roomId.toUpperCase() });
    
    if (!room) {
      ws.send(JSON.stringify({
        type: 'error',
        data: { message: 'Sala no encontrada' }
      }));
      return;
    }
    
    if (room.players.length >= room.maxPlayers) {
      ws.send(JSON.stringify({
        type: 'error',
        data: { message: 'Sala llena' }
      }));
      return;
    }
    
    if (room.gameState !== 'waiting') {
      ws.send(JSON.stringify({
        type: 'error',
        data: { message: 'Partida en curso' }
      }));
      return;
    }
    
    if (room.players.some(p => p.socketId === socketId)) {
      ws.send(JSON.stringify({
        type: 'error',
        data: { message: 'Ya estás en esta sala' }
      }));
      return;
    }
    
    room.players.push({
      socketId,
      nickname: client.playerData.nickname,
      isReady: false,
      color: client.playerData.color
    });
    
    await room.save();
    
    client.roomId = room.roomId;
    playerRooms.set(socketId, room.roomId);
    
    client.playerData.roomId = room.roomId;
    await client.playerData.save();
    
    ws.send(JSON.stringify({
      type: 'room-joined',
      data: {
        success: true,
        room: room
      }
    }));
    
    // Notificar a otros jugadores
    broadcastToRoom(room.roomId, {
      type: 'player-joined',
      data: {
        player: {
          socketId,
          nickname: client.playerData.nickname,
          color: client.playerData.color
        }
      }
    }, socketId);
    
    broadcastToRoom(room.roomId, {
      type: 'room-updated',
      data: { players: room.players }
    });
    
    logger.info(`👋 ${client.playerData.nickname} se unió a ${room.roomId}`);
  } catch (error) {
    ws.send(JSON.stringify({
      type: 'error',
      data: { message: 'Error al unirse a sala' }
    }));
  }
}

async function handlePlayerReady(ws, socketId, data, client) {
  try {
    const { isReady } = data;
    const roomId = client.roomId;
    
    if (!roomId) return;
    
    const room = await Room.findOne({ roomId });
    if (!room) return;
    
    const playerIndex = room.players.findIndex(p => p.socketId === socketId);
    if (playerIndex !== -1) {
      room.players[playerIndex].isReady = isReady;
      await room.save();
      
      await Player.findOneAndUpdate(
        { socketId },
        { isReady }
      );
      
      broadcastToRoom(roomId, {
        type: 'room-updated',
        data: { players: room.players }
      });
      
      // Verificar si todos están listos
      const allReady = room.players.every(p => p.isReady);
      const canStart = room.players.length >= room.minPlayers && allReady;
      
      if (canStart && room.hostSocketId === socketId) {
        ws.send(JSON.stringify({
          type: 'can-start',
          data: { canStart: true }
        }));
      }
    }
  } catch (error) {
    ws.send(JSON.stringify({
      type: 'error',
      data: { message: 'Error al cambiar estado' }
    }));
  }
}

async function handleLeaveRoom(ws, socketId, client) {
  try {
    const roomId = client.roomId;
    if (!roomId) return;
    
    const room = await Room.findOne({ roomId });
    if (!room) return;
    
    room.players = room.players.filter(p => p.socketId !== socketId);
    
    if (room.players.length === 0) {
      await Room.deleteOne({ roomId });
      logger.info(`🗑️ Sala ${roomId} eliminada`);
    } else {
      if (room.hostSocketId === socketId) {
        room.hostSocketId = room.players[0].socketId;
      }
      await room.save();
      
      broadcastToRoom(roomId, {
        type: 'player-left',
        data: {
          playerId: socketId,
          players: room.players
        }
      });
    }
    
    client.roomId = null;
    playerRooms.delete(socketId);
    
    await Player.findOneAndUpdate(
      { socketId },
      { roomId: null, isReady: false }
    );
    
    ws.send(JSON.stringify({
      type: 'room-left',
      data: { success: true }
    }));
    
  } catch (error) {
    ws.send(JSON.stringify({
      type: 'error',
      data: { message: 'Error al salir de sala' }
    }));
  }
}

// ============ INICIAR SERVIDOR ============
const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  logger.info(`🚀 Servidor WebSocket corriendo en puerto ${PORT}`);
  logger.info(`📡 Conexiones: ws://localhost:${PORT}`);
});