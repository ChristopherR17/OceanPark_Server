// scripts/sync_to_navision.js
// Este script se ejecuta periódicamente para exportar datos de MongoDB a CSV
// que luego Navision puede importar

const mongoose = require('mongoose');
const PlayerModel = require('../models/Player');
const GameSession = require('../models/GameSession');
const Movement = require('../models/Movement');
const fs = require('fs');
const path = require('path');

const OUTPUT_DIR = path.join(__dirname, '..', 'exports', 'navision');

async function syncToNavision() {
    await mongoose.connect(process.env.MONGODB_URI || 'mongodb://localhost:27017/oceanpark');
    
    // Crear directorio de exportación
    if (!fs.existsSync(OUTPUT_DIR)) {
        fs.mkdirSync(OUTPUT_DIR, { recursive: true });
    }
    
    // 1. Exportar Jugadores
    await exportJugadores();
    
    // 2. Exportar Partidas
    await exportPartidas();
    
    // 3. Exportar Partidas-Jugadores
    await exportPartidasJugadores();
    
    // 4. Exportar Movimientos
    await exportMovimientos();
    
    // 5. Exportar Récords de Niveles
    await exportNivelesRecords();
    
    console.log('✅ Sincronización completada');
    console.log(`📂 Archivos en: ${OUTPUT_DIR}`);
    
    await mongoose.disconnect();
}

async function exportJugadores() {
    const players = await PlayerModel.find({}).lean();
    
    const headers = [
        'Player_ID', 'Nickname', 'Categoria',
        'Total_Sesiones', 'Total_Tiempo_Seg', 'Total_Monedas', 'Total_Muertes',
        'Niveles_Completados', 'Mejor_Puntuacion',
        'Promedio_Tiempo_Sesion', 'Promedio_Monedas_Sesion',
        'Ultima_Sesion_ID', 'Fecha_Registro', 'Ultima_Conexion'
    ];
    
    const rows = players.map(p => [
        p.playerId, p.nickname, p.category,
        p.stats.totalSessions, p.stats.totalPlayTime, p.stats.totalCoins, p.stats.totalDeaths,
        p.stats.levelsCompleted, p.stats.bestScore,
        p.stats.averageSessionTime, p.stats.averageCoinsPerSession,
        p.lastSession?.sessionId || '', p.firstSeen?.toISOString() || '', p.lastSeen?.toISOString() || ''
    ]);
    
    writeCSV('OCEAN_Jugadores.csv', headers, rows);
}

async function exportPartidas() {
    const sessions = await GameSession.find({}).lean();
    
    const headers = [
        'Sesion_ID', 'Nivel_Nombre', 'Nivel_Indice', 'Numero_Jugadores',
        'Completada', 'Estado',
        'Fecha_Inicio', 'Fecha_Fin', 'Duracion_Segundos',
        'Total_Monedas_Recogidas', 'Total_Monedas_Disponibles',
        'Total_Muertes', 'Mejor_Puntuacion', 'Tiempo_Promedio_Jugador'
    ];
    
    const rows = sessions.map(s => [
        s.sessionId, s.levelName, s.levelIndex, s.playerCount,
        s.completed ? 1 : 0, 'completed',
        s.startTime?.toISOString() || '', s.endTime?.toISOString() || '', s.duration,
        s.totalCoinsCollected, s.totalCoinsAvailable,
        s.totalDeaths, s.bestPlayerScore, s.averagePlayerTime
    ]);
    
    writeCSV('OCEAN_Partidas.csv', headers, rows);
}

async function exportPartidasJugadores() {
    const sessions = await GameSession.find({}).lean();
    
    const headers = [
        'Sesion_ID', 'Player_ID', 'Nickname', 'Categoria',
        'Monedas_Recogidas', 'Muertes', 'Puntuacion', 'Completo_Nivel', 'Tiempo_Jugado_Seg'
    ];
    
    const rows = [];
    for (const session of sessions) {
        for (const player of session.players) {
            rows.push([
                session.sessionId,
                player.playerId, player.nickname, player.category,
                player.coinsCollected, player.deaths, player.score,
                player.completed ? 1 : 0, player.timePlayed
            ]);
        }
    }
    
    writeCSV('OCEAN_Partidas_Jugadores.csv', headers, rows);
}

async function exportMovimientos() {
    // Solo exportar los últimos 10000 movimientos para no sobrecargar
    const movements = await Movement.find({})
        .sort({ timestamp: -1 })
        .limit(10000)
        .lean();
    
    const headers = [
        'Sesion_ID', 'Player_ID', 'Player_Nombre', 'Accion',
        'Posicion_X', 'Posicion_Y', 'Datos_Adicionales', 'Fecha_Accion'
    ];
    
    const rows = movements.map(m => [
        m.sessionId, m.playerId, m.playerName, m.action,
        m.position?.x || '', m.position?.y || '',
        JSON.stringify(m.data || {}), m.timestamp?.toISOString() || ''
    ]);
    
    writeCSV('OCEAN_Movimientos.csv', headers, rows);
}

async function exportNivelesRecords() {
    // Agregar desde MongoDB
    const records = await GameSession.aggregate([
        { $match: { completed: true } },
        { $group: {
            _id: { level: '$levelName', players: '$playerCount' },
            mejorTiempo: { $min: '$duration' },
            mejorPuntuacion: { $max: '$bestPlayerScore' },
            totalPartidas: { $sum: 1 },
            tiempoPromedio: { $avg: '$duration' },
            puntuacionPromedio: { $avg: '$bestPlayerScore' }
        }},
        { $sort: { '_id.level': 1, '_id.players': 1 } }
    ]);
    
    const headers = [
        'Nivel_Nombre', 'Numero_Jugadores',
        'Mejor_Tiempo_Seg', 'Mejor_Puntuacion',
        'Total_Partidas', 'Total_Completadas',
        'Tiempo_Promedio_Seg', 'Puntuacion_Promedio'
    ];
    
    const rows = records.map(r => [
        r._id.level, r._id.players,
        r.mejorTiempo, r.mejorPuntuacion,
        r.totalPartidas, r.totalPartidas, // Total = completadas (todas son completadas)
        Math.round(r.tiempoPromedio), Math.round(r.puntuacionPromedio)
    ]);
    
    writeCSV('OCEAN_Niveles_Records.csv', headers, rows);
}

function writeCSV(filename, headers, rows) {
    const filepath = path.join(OUTPUT_DIR, filename);
    const headerLine = headers.join(';') + '\n';
    const dataLines = rows.map(row => 
        row.map(cell => {
            // Escapar valores que contengan punto y coma
            const str = String(cell ?? '');
            return str.includes(';') ? `"${str}"` : str;
        }).join(';')
    ).join('\n');
    
    fs.writeFileSync(filepath, headerLine + dataLines, 'utf8');
    console.log(`   📄 ${filename}: ${rows.length} registros`);
}

// Ejecutar si se llama directamente
if (require.main === module) {
    syncToNavision()
        .then(() => process.exit(0))
        .catch(err => {
            console.error('Error:', err);
            process.exit(1);
        });
}

module.exports = syncToNavision;