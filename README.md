# THE WORKER

**THE WORKER** es un juego de sigilo social y estrategia en 2D (vista cenital 3/4) ambientado en la
sede de **Stellar Sell**, una multinacional del calzado. Empiezas como empleado de correo en la
oficina 3B, tercera planta. La empresa quiere que trabajes; tu objetivo real es llegar a consejero
delegado **sin trabajar** y después quedarte con la compañía.

Para conseguirlo tienes 50 puestos que escalar, 166 salas repartidas en un rascacielos y una fábrica,
y unas 150 personas con personalidad propia a las que vigilar, sobornar, manipular, incriminar o
quitar de en medio. Nada está guionizado: los compañeros te ven, sacan conclusiones, cotillean,
Seguridad investiga y la policía puede acabar interviniendo. Con el sueldo honrado no llega: la
sátira del juego es que el sistema empuja a delinquir.

El diseño completo está en `docs/THE_WORKER_MANUAL_MAESTRO.md` (en español). El proyecto de Godot
está en la carpeta `the_worker/`.

---

## Cómo jugar

### Opción 1 — Windows (lo más fácil)
1. Descomprime `the_worker/export/TheWorker-windows.zip` (unos 40 MB).
2. Haz doble clic en `TheWorker.exe`. No necesita instalación.
   Si Windows muestra "Windows protegió su PC", pulsa *Más información → Ejecutar de todas formas*
   (el ejecutable no está firmado digitalmente).

> La carpeta `export/` no se sube al repositorio (es un resultado generado). Si no la tienes,
> genérala con las instrucciones de "Crear los ejecutables" más abajo.

### Opción 2 — Linux
Ejecuta `the_worker/export/linux/TheWorker.x86_64` (dale permiso de ejecución si hace falta:
`chmod +x TheWorker.x86_64`).

### Opción 3 — Abrir el proyecto en Godot
1. Descarga **Godot 4.7** (versión estándar, no la .NET) desde godotengine.org.
2. Abre Godot, pulsa *Importar* y elige el archivo `the_worker/project.godot`.
3. La primera vez tarda un poco en importar los recursos.
4. Pulsa **F5** (o el botón ▶ arriba a la derecha) para jugar.

---

## Controles

### PC (teclado y ratón)
| Acción | Tecla |
|---|---|
| Moverse | W A S D o flechas |
| Correr (esprint) | Doble pulsación de una dirección (o doble clic) |
| Andar con sigilo | Mayús (Shift) |
| Agacharse / esconderse | Ctrl |
| Interactuar (puertas, mesas, personas, objetos) | E |
| Mapa del edificio | Tab |
| Ordenador (Stellar OS) | C |
| Móvil | M |
| Inventario | I |
| Saltar tiempo (esperar) / dormir en casa de noche | T |
| Confirmar | Intro |
| Menú de pausa (guardar, ajustes, ascensos) | Esc |

### Android (pantalla táctil)
- **Stick izquierdo flotante**: toca y arrastra en la mitad izquierda para moverte.
  Doble toque y mantener = correr.
- **Botón grande abajo a la derecha**: acción contextual (interactuar con lo que tengas delante).
- **Botones de sigilo y agacharse** junto al botón contextual.
- **Barra inferior deslizable**: mapa, ordenador, móvil e inventario.

---

## Idiomas
El juego está en **inglés** (idioma base) y **español**. Cámbialo en
**Ajustes → Idioma** desde el menú principal o el menú de pausa. En los mismos ajustes están el
tamaño de texto, el alto contraste, el modo daltónico, los subtítulos, el volumen, la dificultad y la velocidad del reloj.

---

## Qué está hecho y qué falta (respecto al manual)

**Implementado**
- El edificio completo (166 salas, 21 plantas + sótanos, fábrica, calle y el piso del jugador),
  con ascensores, escaleras, torniquetes, tarjetas y horario de cierre.
- Las 50 ocupaciones con ascensos (y degradaciones), sueldos, tareas diarias y el ordenador
  Stellar OS (correo, personal, portal de inversión/mercado, cuaderno).
- Unas 150 personas simuladas: rasgos, rutinas, percepción, creencias, rumores, grafo social,
  sobornos, chantaje, investigaciones de Seguridad, interrogatorios y policía.
- Economía de la empresa, mercado, inversores, ideas (robo y presentación en la reunión Aurora),
  huelgas, final de partida y epílogos.
- Primer día guiado (vídeo de bienvenida, RR. HH., primeras tareas), guardado automático al
  dormir y "Continuar" desde el menú.
- Interfaz en inglés y español, controles táctiles para Android, audio con subtítulos.
- 67 baterías de pruebas automáticas (miles de comprobaciones).

**Huecos conocidos (honestos)**
- Algunas interacciones de oficina y seguridad funcionan en versión reducida porque dependen de
  piezas que aún no existen (lista detallada en `the_worker/docs_integration_todo.md`):
  - El documento oficial falsificado se puede fabricar pero todavía no tiene ningún uso.
  - Desde la sala de servidores no se pueden borrar tus registros de tarjeta ni los rastros del
    asistente A.S.S.I.S.T. (el juego te lo dice).
  - La sala de monitores no está vigilada permanentemente por dos guardias como pide el manual.
  - El inventario mensual de material de oficina (§22.9) no existe.
  - Parte del material de la fábrica (piel, suelas, prototipos) no se puede vender: falta un
    perista o ruta de robo en fábrica.
  - Algunos sonidos (cafetera, cuadro eléctrico, compactadora) reutilizan otros efectos.
- El minuto de apagón se amplió de 5 a 25 minutos de juego (el "5 min" del manual resultaba
  imposible de jugar); es una decisión consciente.
- La versión Android está configurada pero **no se ha generado** el `.aab`: falta crear una
  clave de firma (keystore) e instalar la plantilla de compilación Android. Está anotado como
  TODO en `the_worker/export_presets.cfg`.
- No se ha probado en un móvil real ni en Windows real (el `.exe` se generó y comprobó
  desde Linux; la versión Linux se verificó arrancando hasta el menú principal).

---

## Para programadores: pruebas y exportación

Todo se ejecuta desde la carpeta `the_worker/` con Godot 4.7.2 en la ruta (`godot`).

- Todas las pruebas: `tools/run_all_tests.sh` (tarda varios minutos; muestra
  `PASSED: N  FAILED: 0`).
- Una prueba: `tools/run_test.sh test_save_load`
- Validar datos y textos: `python3 tools/check_data.py` y `python3 tools/check_locale.py`
- Capturas automáticas: `tools/screenshot.sh <carpeta> boot`

**Crear los ejecutables** (necesita las plantillas de exportación 4.7.2 instaladas):
```
godot --headless --path . --export-release "Windows Desktop" export/windows/TheWorker.exe
godot --headless --path . --export-release "Linux" export/linux/TheWorker.x86_64
```
