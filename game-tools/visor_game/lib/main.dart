import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'game/visor_oceanpark.dart'; // Importamos tu juego organizado

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Arrancamos la app pasándole nuestro Visor
  runApp(
    GameWidget(game: VisorOceanPark()),
  );
}