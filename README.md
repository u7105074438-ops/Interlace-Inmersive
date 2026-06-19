# Roquet Redemption by Areces

Juego de fútbol arcade 2D con coches para móvil, inspirado en **Rocket League Sideswipe**.
Todo el juego (motor, físicas, IA, render y UI) vive en un único archivo: **`index.html`**.
No requiere build ni dependencias: ábrelo en cualquier navegador moderno (móvil o escritorio).

## Cómo jugar

Abre `index.html` directamente, o sírvelo localmente:

```bash
python3 -m http.server 8080
# luego visita http://localhost:8080
```

## Controles

| Acción | Móvil | Teclado |
| --- | --- | --- |
| Mover / Pitch aéreo | Joystick virtual (izquierda) | Flechas / A D |
| Saltar / Flip | Botón verde | Espacio / K |
| Turbo | Botón naranja | Shift / L |
| Air Roll | Botón violeta | J / Alt |
| Pausa | Botón superior derecho | — |

- **Doble salto = Flip** (dirige el joystick para flips diagonales/backflips).
- Mantén **Turbo en el aire** y apunta el morro hacia la bola para volar.

## Mecánicas avanzadas (emergen de la física, no son animaciones)

- **Air Roll**: rotación continua 360° en el aire, combinable con turbo.
- **Flip Reset**: toca la bola con las ruedas en el aire para recuperar el flip.
- **Pinch**: aprisiona la bola contra un muro a alta velocidad → disparo explosivo.
- **Musty Flick**: golpea la bola con el techo durante un backflip para elevarla.
- **Stall**: pulsa salto + air roll en el aire para cancelar tu momentum.
- **Demoliciones**: a velocidad supersónica puedes destruir al rival.

## Características

- **Modos**: Partida 1v1 (2 min + prórroga a gol de oro), Freeplay (reinicio/lanzamiento de bola y cámara lenta), Garaje y Ajustes.
- **IA escalable**: de **Bronce** (torpe, no vuela) a **Leyenda** (aéreos, air roll, flip resets, ataque desde el techo). Usa predicción de trayectorias y un árbol de comportamiento.
- **Progresión**: XP, subida de rango (Bronce → Leyenda) y desbloqueo de 4 coches.
- **Garaje**: visualizador del coche rotando, 4 modelos y colores neón.
- **Motor**: físicas con sub-stepping (anti-tunneling), colisiones Circle-Circle y Circle-OBB, momentum conservado.
- **Gráficos**: neón con bloom (`shadowBlur`), sombras proyectadas, estelas, sistema de partículas con *object pooling*, cámara con shake y zoom dinámico.
- **UI**: glassmorphism, transiciones, pantalla de carga y diseño responsivo con *safe-areas*.

## Arquitectura del código (dentro de `index.html`)

1. Utilidades matemáticas y `Vector2`
2. Progresión, coches, audio sintetizado (WebAudio) y partículas
3. Entrada táctil/teclado y cámara
4. Arena (geometría y colisiones) y pelota
5. Coche (física, estados y mecánicas avanzadas)
6. IA escalable (`BotAI`)
7. Renderizado (Canvas 2D)
8. Núcleo del juego (estado de partida y bucle de física)
9. Gestor de interfaz (pantallas, HUD, garaje, ajustes)
10. Arranque y bucle principal
