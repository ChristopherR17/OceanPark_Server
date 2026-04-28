const mongoose = require('mongoose');
const logger = require('../logger');

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/oceanpark';

async function connectDatabase() {
    try {
        mongoose.set('bufferCommands', false);
        await mongoose.connect(MONGODB_URI, { serverSelectionTimeoutMS: 3000 });
        logger.info('✅ MongoDB conectado: ' + MONGODB_URI);
        return true;
    } catch (error) {
        logger.error('❌ Error conectando a MongoDB: ' + error.message);
        logger.warn('⚠️ El servidor funcionará sin persistencia de datos');
        return false;
    }
}

mongoose.connection.on('disconnected', () => {
    logger.warn('⚠️ MongoDB desconectado');
});

mongoose.connection.on('reconnected', () => {
    logger.info('✅ MongoDB reconectado');
});

module.exports = { connectDatabase, mongoose };