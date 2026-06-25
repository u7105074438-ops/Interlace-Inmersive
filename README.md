# Roquet Redemption by Areces

Juego de fútbol arcade 2D con coches cohete para **móvil**, inspirado en **Rocket League Sideswipe**.
Todo el juego (motor, físicas, IA, render y UI) vive en un único archivo: **`index.html`**.
No requiere build ni dependencias: ábrelo en cualquier navegador moderno (móvil o escritorio).

> El juego está pensado en **horizontal**. En móvil, gíralo a apaisado (hay un aviso de rotación).

## Cómo jugar

Abre `index.html` directamente, o sírvelo localmente:

```bash
python3 -m http.server 8080
# luego visita http://localhost:8080
```

## Controles

| Acción | Móvil | Teclado |
| --- | --- | --- |
| Mover / Pitch aéreo | Joystick virtual (izquierda) | Flechas / WASD |
| Saltar / Flip | Botón verde | Espacio / K |
| Turbo | Botón naranja | Shift / L |
| Air Roll | Botón violeta | J / Alt |
| Drift / roll | Botón cian | Z / Ctrl |
| Habilidad especial | Botón magenta (si está equipada) | — |
| Pausa | Botón superior derecho | Esc |

- **Doble salto direccional = Flip** (diagonales, backflips...).
- Mantén **Turbo en el aire** y apunta el morro a la bola para volar.
- Modo zurdo, tamaño de controles y zoom configurables en **Ajustes**.

## Mecánicas avanzadas (emergen de la física, no son animaciones)

- **Air Roll**: rotación continua 360° en el aire.
- **Flip Reset**: toca la bola con las ruedas en el aire para recuperar el flip.
- **Pinch**: aprisiona la bola contra un muro a alta velocidad → disparo explosivo.
- **Musty Flick**: golpea la bola con el techo durante un backflip para elevarla.
- **Stall**: salto + air roll en el aire para cancelar tu momentum.
- **Demoliciones**: a velocidad supersónica destruyes al rival.

## Progresión y rangos (clave)

- **10 divisiones**: Bronce I → Leyenda. Tu rango lo marca el **MMR**.
- **Ganas → subes; pierdes → bajas** (puedes descender de división). Ya no es trivial subir.
- **Te enfrentas SIEMPRE a bots de tu división** (no se elige el nivel del bot). A mayor rango, IA más dura.

## Modos

- **Clasificatoria 1v1** (2 min + prórroga a gol de oro) con intro VS animada.
- **Entreno Libre** (reinicio/lanzamiento de bola, cámara lenta, reposición).
- **Entrenamiento** con drills (tiro a puerta, aéreos, control de rebote, práctica libre).

## Garaje y cosmética

Configurable por categorías, todo desbloqueable por **rango**, **misiones** o **monedas**:

- **Chasis**, **Color** (incluye prisma animado), **Calca**, **Llama/Turbo**, **Estela**,
  **Festejo de gol**, **Ruedas**, **Adorno** (topper) y **Habilidad especial**.
- Rarezas: Común → Raro → Épico → Legendario → **Mítico**.
- Los mejores (míticos) son exclusivos del **rango Leyenda** o de misiones durísimas
  (p. ej. *marcar 30 goles en una partida de Leyenda*).

## Habilidades especiales (de misiones/rango)

Sobrecarga (turbo infinito), Escudo (inmune a demoliciones), Triple Salto (pasiva),
Onda de Choque, Imán, Escarcha (ralentiza al rival) y Meteoro (dispara la bola a portería).

## Misiones y logros

- **Diarias** (rotan cada día), **Carrera** y **Leyenda** (muy difíciles, recompensan los mejores cosméticos).
- **Logros** acumulativos con recompensa en monedas.

## Rendimiento (móvil)

- Timestep **fijo** con **sub-stepping** (anti-tunneling) y *clamp* de delta.
- `devicePixelRatio` limitado por calidad; `shadowBlur` usado con moderación.
- **Object pooling** de partículas con presupuesto ajustable.
- Calidad **auto** según el dispositivo; opciones de calidad/partículas/vibración en Ajustes.

## Arquitectura del código (dentro de `index.html`)

1. Utilidades matemáticas, `Vector2`, easing, RNG, color
2. Persistencia (`localStorage`)
3. Progresión: rangos (10 divisiones), XP, MMR
4. Base de datos de cosméticos (9 categorías) + expansión de contenido
5. Misiones, logros
6. Motor de audio sintetizado (WebAudio)
7. Sistema de partículas con *object pooling*
8. Entrada táctil (multitouch) + teclado
9. Cámara (shake por trauma, zoom dinámico, slow-mo)
10. Arena (geometría, colisiones) y pelota
11. Coche (física + mecánicas avanzadas + habilidades)
12. Resolución de colisiones (OBB bola-coche, coche-coche)
13. IA escalable (`BotAI`: predicción + árbol de comportamiento)
14. Renderizado (Canvas 2D, chasis paramétrico, luces, sombras, trails)
15. Núcleo del juego (modos, partida, bucle de física)
16. Gestor de interfaz (pantallas, HUD, garaje, misiones, carrera, ajustes)
17. Arranque, carga cinematográfica y bucle principal
