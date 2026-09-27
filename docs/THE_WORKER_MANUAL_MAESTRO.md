# THE WORKER
# DOCUMENTO MAESTRO DE CONSTRUCCIÓN

**Especificación de diseño · Especificación técnica · Biblia de contenido · Manual de obra**

Versión 2.0 — 25 de julio de 2026

---

## Naturaleza y uso de este documento

Este documento es la especificación completa y autosuficiente del videojuego **THE WORKER**. Contiene todo lo necesario para construirlo desde cero sin acceso a ninguna conversación, decisión o contexto previo. No existe información fuera de estas páginas.

Está redactado para ser consumido por dos lectores distintos:

**Para el sistema de IA que construye el juego.** Cada paso del manual de obra (Parte X) indica qué secciones consultar antes de escribir código. La Parte VII define las interfaces exactas de cada sistema: sus funciones públicas, sus señales y sus responsabilidades. Respetar esas firmas es lo que garantiza que una pieza construida en el paso 30 encaje con otra construida en el paso 12. La Parte IX contiene el esquema completo de cada archivo de datos.

**Para el responsable del proyecto.** La Parte X incluye, en cada paso, el prompt literal a utilizar, los archivos que deben resultar y el criterio de verificación concreto: qué debe ocurrir al ejecutar el juego para considerar el paso terminado.

### Índice general

| Parte | Contenido | Consultar |
|---|---|---|
| **0** | Resumen ejecutivo | Una vez, al inicio |
| **I** | Visión: concepto, premisa, tono, bucle | Una vez, al inicio |
| **II** | El mundo: edificio y estructura de ocupaciones | Al construir mundo o progresión |
| **III** | La simulación: cerebro social y cerebro económico | Al construir IA o economía |
| **IV** | La jugabilidad: trabajo, crimen, riesgo, interfaz | Al construir mecánicas |
| **V** | Producción: dirección de arte y sonido | Al construir presentación |
| **VI** | Balance y publicación | Al ajustar números o publicar |
| **VII** | **Especificación técnica de sistemas** | **Antes de escribir cualquier código** |
| **VIII** | **Biblia de contenido**: datos de salas, ocupaciones y personajes | Al escribir archivos de datos |
| **IX** | **Esquemas de datos**: los 16 archivos JSON especificados | Al escribir archivos de datos |
| **X** | **Manual de obra**: los 47 pasos con prompts | **En cada sesión de trabajo** |
| **XI** | Apéndices: verificación, diagnóstico, glosario | Como referencia |

### Convenciones del documento

- **[C]** marca una decisión cerrada y no negociable.
- **[P]** marca una propuesta técnica que admite ajuste durante la construcción.
- Los identificadores de datos aparecen `así`.
- Las referencias cruzadas usan la numeración de sección (ej. *ver 7.4*).

---

# 0. RESUMEN EJECUTIVO

**THE WORKER** es un juego de sigilo social y estrategia en dos dimensiones con vista cenital 3/4, ambientado íntegramente en la sede corporativa de **Stellar Sell**, una multinacional del calzado.

El jugador acaba de graduarse y es contratado como trabajador de correo electrónico en el conjunto de oficinas 3B, tercera planta. El objetivo que la empresa le asigna es hacer su trabajo. **El objetivo real del jugador es alcanzar el puesto de consejero delegado sin trabajar y, después, apropiarse de la compañía.**

Para lograrlo dispone de cincuenta ocupaciones que escalar, ciento sesenta y seis espacios que recorrer y aproximadamente ciento cincuenta personas a las que vigilar, sobornar, manipular, incriminar o eliminar. Cada una de esas personas posee personalidad propia expresada en seis rasgos numéricos, rutina diaria, memoria de lo que presencia y un registro persistente de agravios y favores. Los rumores se propagan por un grafo social durante los momentos de socialización. Las investigaciones registran físicamente las salas del edificio. La cotización bursátil reacciona a los escándalos. Y la partida termina de forma definitiva si el jugador es descubierto.

### Los tres pilares del diseño

**Primero: un mundo que razona.** No existe guion. Un compañero percibe al jugador durante medio segundo junto a una caja fuerte y genera una creencia de baja certeza. La comenta durante el almuerzo. El rumor se amplifica. Seguridad abre una investigación. El jugador soborna al investigador, pero un auditor honesto localiza la grabación que no se borró. Ninguna parte de esa secuencia está escrita: emerge de la interacción entre sistemas.

**Segundo: la progresión es el mundo.** Ascender de ocupación equivale literalmente a ascender por el edificio. Cada promoción concede acceso a más salas, más capital para sobornos y más información sobre las personas, pero también incrementa la vigilancia y hace el trabajo real más difícil de simular.

**Tercero: la aritmética obliga a delinquir.** El salario inicial es de treinta euros diarios y el coste de vida asciende a veintidós. El soborno más económico del juego cuesta doscientos diez euros. El salario honesto nunca financia el ascenso; esa es la tesis satírica del juego y está demostrada numéricamente en la sección 16.4.

### Datos de producto

| Concepto | Valor |
|---|---|
| Duración de una partida completa | ~21,6 horas |
| Finales | 9, con dos variantes cada uno de los siete de victoria |
| Modo de fracaso | Permadeath puro: reinicio en un mundo nuevo |
| Motor | Godot 4 |
| Plataformas | PC (Steam) y Android (Google Play) |
| Precio propuesto | 14,99 € / 6,99 € |
| Volumen estimado de código | 60.000–100.000 líneas de GDScript más datos |

---

# PARTE I — VISIÓN

## 1. Ficha técnica

| Campo | Especificación |
|---|---|
| **Título** | THE WORKER **[C]** |
| **Género** | Sátira corporativa / Sigilo social / Simulación inmersiva 2D |
| **Motor** | Godot 4, última versión estable disponible al iniciar la construcción **[C]** |
| **Perspectiva** | Cenital 3/4 durante el juego; corte vertical de la torre para mapa y transiciones **[P]** |
| **Modo** | Un jugador |
| **Idioma base** | Inglés. Español como localización posterior **[C]** |
| **Plataformas** | PC / Steam mediante exportación nativa a `.exe` (requisito innegociable) y Android / Google Play mediante `.aab` **[C]** |
| **Duración objetivo** | 21,6 horas por partida completa; alta rejugabilidad derivada de los nueve finales |
| **Modelo de lanzamiento** | Único y completo. Sin demostración, sin acceso anticipado, sin versión web **[C]** |
| **Precio** | 14,99 $/€ en Steam con descuento del 15% la primera semana; 6,99 $/€ en Google Play **[P]** |
| **Clasificación prevista** | PEGI 16 / ESRB Teen–Mature |

### 1.1 Terminología

La precisión terminológica es relevante porque dos conceptos del juego resultan fácilmente confundibles: la arquitectura del edificio y la progresión del jugador son sistemas independientes.

| Término | Definición |
|---|---|
| **Planta** | Nivel físico del edificio. Existen veinte plantas sobre rasante y tres sótanos. **Las plantas no son niveles de juego ni estructura de progresión.** |
| **Ocupación** | Puesto de trabajo del jugador. Existen cincuenta. Constituyen la estructura de progresión real. |
| **Rango** | Peldaño numérico de la escalera de ocupaciones, de R0 a R33. Varios rangos contienen dos ocupaciones alternativas. |
| **Escalón** | Agrupación jerárquica de rangos. Existen ocho, correspondientes a los ocho niveles de acreditación. |
| **Ala** | Subdivisión horizontal de una planta: A, B o C. El personal subalterno emplea la forma «el 3B»; la dirección emplea «la A10». La diferencia de jerga es intencionada. |
| **Acreditación** | Nivel de tarjeta de acceso, de N0 a N7. Determina qué salas puede abrir el jugador legítimamente. |
| **Creencia** | Unidad de información que un personaje no jugador almacena sobre el mundo. Puede ser verdadera o falsa, y posee un grado de certeza variable. Es la unidad atómica del sistema de inteligencia. |
| **Arquetipo** | Conjunto predefinido de valores para los seis rasgos de personalidad. Existen doce. |
| **Fundamentales** | Los valores económicos reales de la compañía. |
| **Reportados** | Los valores económicos que el jugador comunica al mercado. La diferencia entre ambos constituye su margen de falsificación. |
| **Expediente de personal** | Ficha consultable de cada personaje. Su nivel de detalle depende de la ocupación del jugador. |
| **Flagrancia** | Estado en el que un personaje ha identificado al jugador con certeza plena cometiendo un acto indebido. |
| **Banda de planta** | Agrupación de plantas que comparte paleta cromática y ambiente sonoro. Existen cinco. |
| **Jornada** | Un día completo de juego, incluyendo oficina, tarde y noche. Equivale a diez o doce minutos de tiempo real. |

## 2. Premisa y condición de victoria

### 2.1 Premisa **[C]**

El juego abre con una secuencia animada: la graduación universitaria del protagonista y su elección de primer empleo en Stellar Sell. Tras cruzar los torniquetes recibe una sesión breve de bienvenida y se le asigna una mesa en el conjunto de oficinas 3B.

Esa mesa contiene tres elementos que constituyen la totalidad de sus recursos iniciales: un **ordenador**, un juego de **llaves** y una **estampa**.

### 2.2 La condición de victoria, en dos fases **[C]**

**Fase primera: el cargo.** Ascender por las cincuenta ocupaciones hasta ocupar el despacho de la planta veinte.

**Fase segunda: la propiedad.** Ostentar el cargo de consejero delegado no confiere la titularidad de la compañía. Los documentos de propiedad se encuentran en la caja fuerte del despacho del consejero delegado. Obtenerlos y formalizarlos ante la notaría interna de la planta nueve es lo que transfiere la propiedad.

Un jugador puede completar la primera fase y perder la partida sin haber comprendido que existía una segunda. Esta inversión constituye el clímax del diseño narrativo.

### 2.3 Lema **[P]**

> *Work hard. Or don't.*

## 3. Tono y estrategia narrativa

### 3.1 Registro cómico **[C]**

El registro es la sátira corporativa. Reuniones que no producen decisiones, terminología vacía de contenido, jefes ridículos, cultura del empleado del mes, carteles motivacionales omnipresentes. Los métodos del jugador son inherentemente cómicos: emplear la herramienta de inteligencia artificial corporativa para simular su propio trabajo, insertar su rostro en una campaña publicitaria, sellar una autorización falsa con la estampa de su escritorio.

La comedia negra está presente pero **nunca se representa gráficamente**. La eliminación de un compañero se resuelve mediante encuadre, elipsis y sonido. Esta decisión no es únicamente estética: sostiene la clasificación por edades PEGI 16, que resulta relevante para la distribución en Google Play.

### 3.2 Narrativa emergente **[C]**

El texto narrativo escrito se limita a la secuencia de apertura y a los epílogos. No existe trama, no existen giros guionizados, el protagonista carece de pasado.

La narrativa real del juego son las secuencias que cada jugador produce al interactuar con los sistemas: a quién hundió, cómo ocultó un cuerpo, qué soborno fracasó, quién lo delató y por qué motivo. Estas secuencias constituyen el producto real del juego y son distintas en cada partida.

Los nueve epílogos no relatan una historia: **evalúan el estilo de juego** y el estado en que el jugador dejó la compañía.

### 3.3 Referentes de diseño

| Referente | Elemento adoptado |
|---|---|
| RimWorld, Dwarf Fortress | Sistemas simples cuya interacción genera narrativa no guionizada |
| Hitman (entregas modernas) | El escenario como mecanismo de relojería: rutinas, ventanas de oportunidad, disfraces |
| Sistema Némesis (Shadow of Mordor) | Persistencia de la relación individual entre el jugador y cada personaje |
| Papers, Please | Conversión de la burocracia en tensión jugable |
| Invisible Inc. | Sigilo con información completa y decisiones de alto coste |

## 4. Estructura del bucle de juego **[C]**

### 4.1 Jornada laboral (8:00 – 19:00)

Fichaje en los torniquetes → mantenimiento de la apariencia de productividad → operaciones encubiertas → evitación de testigos → cumplimiento de los deberes mínimos del cargo antes del cierre.

### 4.2 Tarde y noche

Salida del edificio → desplazamiento al domicilio → adquisición de alimentos y vestuario con capital propio → cena → descanso, momento en que el juego guarda la partida → desayuno antes del turno siguiente.

### 4.3 Noche avanzada (opcional)

Seguimiento de un trabajador hasta su domicilio con fines de robo, saqueo o eliminación. Requiere no ser identificado y escapar antes de la llegada de la policía. Exige el uso de pasamontañas, adquirido previamente.

### 4.4 Condiciones de fracaso

| Condición | Consecuencia |
|---|---|
| Capital insuficiente para alimentarse | Muerte por inanición. Fin de partida. |
| Incumplimiento reiterado de deberes | Expulsión. Fin de partida. |
| Investigación concluyente | Expulsión. Fin de partida. |
| Eliminación de un personaje ante testigos | Expulsión inmediata. Fin de partida. |
| Soborno rechazado con denuncia | Expulsión inmediata. Fin de partida. |
| Fracaso estando en el rango R0 | Expulsión definitiva. Fin de partida. |

---

# PARTE II — EL MUNDO

## 5. El edificio: Stellar Sell HQ **[C]**

### 5.1 Estructura general

El escenario principal es una torre de **veinte plantas sobre rasante, tres sótanos, una nave fabril anexa conectada por la planta baja y el sótano primero, y una azotea practicable**. Un conjunto de localizaciones urbanas completa el mundo.

La jerarquía corporativa asciende con la altura del edificio. Esta correspondencia es el principio organizador del juego: **ascender de ocupación equivale literalmente a ascender por el edificio**.

**Total: 166 espacios jugables.** El catálogo es ampliable: incorporar una sala consiste en añadir un registro de datos, no en escribir código.

### 5.2 Sistema de acreditaciones

Ocho niveles de tarjeta de acceso, correspondientes uno a uno con los ocho escalones de ocupación.

| Nivel | Escalón | Rangos | Zonas que abre |
|---|---|---|---|
| **N0** | Público | — | Recepción, cafetería, tienda insignia, baños de planta baja |
| **N1** | 1 Base | R0–R5 | Ala propia (3B), zonas comunes de plantas 1 a 4, office de planta |
| **N2** | 2 Junior | R6–R9 | Plantas 1 a 5 completas, archivo activo, fotocopiadoras |
| **N3** | 3 Senior | R10–R14 | Plantas 6 a 9, zonas comunes de la fábrica |
| **N4** | 4 Jefe de equipo / 5 Dirección de bloque | R15–R22 | Plantas 10 a 12, salas de reuniones grandes, fábrica completa |
| **N5** | 6 Dirección de área | R23–R27 | Plantas 13 a 15, sótanos completos |
| **N6** | 7 Alta directiva | R28–R31 | Plantas 16 a 19, comedor ejecutivo, archivo confidencial |
| **N7** | 8 La cúspide | R32–R33 | Planta 20, azotea, acceso total |

**Accesos especiales por ocupación.** Independientes del nivel de acreditación y determinados por el puesto concreto:

| Ocupación | Acceso especial |
|---|---|
| Auxiliar y Director de mantenimiento | Sótanos completos y red de conductos de ventilación, con acreditación N2 |
| Vigilante y Jefe de vigilantes | Llaves de prácticamente todo el edificio, con la restricción de no permanecer en despachos |
| Auxiliar de limpieza | Todas las salas de su zona fuera del horario laboral, mediante el carrito con llaves |
| Repartidor de correo interno | Justificación para transitar las plantas 1 a 9 sin generar sospecha |
| Asistente y Director de RRHH | Expedientes completos de la totalidad de la plantilla |
| Director de Seguridad | Todas las grabaciones de videovigilancia |
| Director de IT | Registros digitales y comunicaciones internas |

Este mecanismo convierte determinadas ocupaciones de escalón bajo en **llaves estratégicas** y constituye la razón mecánica por la que rechazar una promoción puede ser una decisión óptima.

### 5.3 Entradas ilegítimas

| Método | Requisito | Rastro que deja |
|---|---|---|
| Tarjeta robada | Sustraerla a un empleado de acreditación superior | El registro de acceso muestra el nombre del titular, no el tuyo. Si él tiene coartada, apuntará a ti. |
| Tarjeta clonada | Acceso a IT o al taller de reparación | Ninguno inmediato. Detectable en auditoría de sistemas. |
| Llaves físicas del escritorio inicial | Ninguno: se poseen desde el principio | Ninguno. Abren un subconjunto limitado de puertas antiguas. |
| Uniforme robado | Acceso al vestuario correspondiente en S1 | La cámara registra el uniforme, no la identidad. |
| Autorización falsa | Poseer la estampa; ser Director del bloque C10 la hace verosímil | Documento físico con tu sello. Definitivo si se verifica. |
| Conductos de ventilación | Acceso de mantenimiento o entrada por un baño | Ninguno: no existen cámaras ni lectores. |
| Azotea y cornisas | Acreditación N7 o entrada por el cuarto de máquinas | Cámara únicamente en la puerta de acceso. |

### 5.4 Rutas alternativas: la red del ladrón

| Ruta | Recorrido | Velocidad | Cámaras | Particularidad |
|---|---|---|---|---|
| **Conductos de ventilación** | Baños, archivos, salas técnicas, algunos despachos | Muy lenta | No | Ruidosos si se transitan a velocidad alta |
| **Escaleras de servicio** | Toda la torre, S3 a P20 | Media | No | Poco vigiladas; coincidir con alguien genera sospecha |
| **Montacargas** | Fábrica ↔ sótanos ↔ muelle de carga | Media | No | Único medio para desplazar cajas grandes o cuerpos |
| **Ascensores principales** | Toda la torre | Rápida | **Sí** | Lector de tarjeta por planta: registro permanente |
| **Escaleras principales** | Toda la torre | Media | Sí | Muy transitadas en las franjas de entrada y salida |
| **Azotea y cornisas** | P19 ↔ P20 | Lenta | Solo puerta | Vía de acceso al despacho del consejero delegado |
| **Muelle de basuras** | S1 → exterior | — | No | Extracción definitiva de objetos del edificio |

### 5.5 Videovigilancia y puntos ciegos

**Salas con cámara:** recepción, control de torniquetes, pasillos principales de todas las plantas, ascensores, la totalidad de las plantas 13 a 20, almacén de producto terminado, caja de planta 5, archivo confidencial del consejo, garaje (rampa de entrada), y la puerta de la azotea.

**Puntos ciegos:** baños de todas las plantas, escaleras de servicio, red de conductos, sótanos S2 y S3 completos, vestuarios, azotea salvo su puerta, offices y cocinitas de planta, cuartos de limpieza, y —irónicamente— el interior de la propia sala de monitores.

**Cadena de custodia de las grabaciones.** Todas las cámaras alimentan la sala de monitores de la planta baja. Las grabaciones constituyen **registros permanentes** que no decaen con el tiempo y solo desaparecen mediante borrado activo desde esa sala. Quien controla la sala de monitores controla la versión oficial de los hechos.

### 5.6 Franjas horarias

| Franja | Horario | Estado del edificio | Oportunidad principal |
|---|---|---|---|
| **Llegada** | 8:00–9:00 | Torniquetes congestionados | Acceder tras otro empleado; mezclarse en la multitud |
| **Trabajo mañana** | 9:00–13:00 | Ocupación máxima, cada uno en su puesto | Vigilar objetivos; operar en zonas estructuralmente vacías |
| **Comida** | 13:00–14:00 | **Cafetería saturada, oficinas desiertas** | **La ventana óptima para el robo** |
| **Trabajo tarde** | 14:00–18:00 | Ocupación normal, vigilancia estándar | Las reuniones programadas vacían despachos concretos |
| **Salida** | 18:00–19:00 | Éxodo generalizado | Ocultarse para permanecer en el edificio |
| **Nocturno** | 19:00+ | Solo personal de cierre y limpieza | Saqueo nocturno, con sospecha máxima automática |

### 5.7 Las cinco bandas de planta

Agrupaciones que comparten paleta cromática, ambiente sonoro y densidad de ocupación. Su función es mecánica además de estética: **el jugador percibe su ascenso social antes de leer ninguna cifra**.

| Banda | Plantas | Densidad de ocupación | Nivel de ruido ambiente |
|---|---|---|---|
| `the_guts` — Las tripas | S3, S2, S1 | Muy baja | Alto (maquinaria) |
| `the_pit` — La fosa | PB a P5, fábrica | **Muy alta** | Alto (actividad humana) |
| `the_specialists` — Los especialistas | P6 a P12 | Media | Medio |
| `the_power` — El poder | P13 a P17 | Baja | Bajo |
| `the_throne` — El trono | P18 a P20, azotea | **Mínima** | **Silencio** |

La correlación es deliberada: el espacio disponible por persona y el silencio son, en este juego, la representación material del privilegio.

*El catálogo completo de los 166 espacios, con datos constructivos, se encuentra en la sección 21.*

## 6. Estructura de ocupaciones

### 6.1 La escalera de rangos

La progresión se articula en **treinta y cuatro rangos, de R0 a R33**, distribuidos en ocho escalones. Varios rangos contienen **dos ocupaciones alternativas** entre las que el jugador elige, lo que produce bifurcaciones estratégicas. El total es de **cincuenta ocupaciones nominadas**.

| Propiedad | Especificación |
|---|---|
| Rango inicial | R1 — Trabajador de emails del 3B |
| Rango de castigo | R0 — Becario eterno. No se comienza en él: se desciende a él. Fracasar en R0 supone expulsión definitiva. |
| Promociones en una partida típica | Aproximadamente treinta |
| Saltos múltiples | Permitidos. Una operación de gran calibre puede saltar dos o tres rangos. |
| Descensos | Permitidos por fracaso público, acusación creíble, cifras que afloran o degradación por resultados de mercado. |
| Movimientos laterales | Permitidos hacia el mismo rango o inferior. Es el mecanismo para adquirir deliberadamente un puesto-llave y regresar después. |

### 6.2 La regla de la silla libre

Toda promoción exige la concurrencia de **tres condiciones simultáneas**:

1. **Reputación** igual o superior al mínimo del rango objetivo.
2. **Mérito reciente**: una idea presentada, un éxito visible, un rescate heroico o una recomendación adquirida mediante soborno.
3. **Vacante**: el puesto debe estar libre. El jugador puede generar la vacante mediante expulsión, incriminación o eliminación, o convencer a la dirección de crear el puesto si su reputación es excepcional.

La tercera condición es la que vincula todos los sistemas del juego a la progresión. **Brillar no siempre basta: en ocasiones es necesario vaciar la silla superior.**

### 6.3 Reposición automática de vacantes

Cuando una silla queda libre, el sistema la rellena de forma automática:

1. Promociona al personaje del rango inferior con la mayor puntuación combinada de **mérito y ambición**, habitualmente un arquetipo Climber.
2. Si ningún candidato cualifica, Recursos Humanos incorpora un Rookie a la base y toda la cadena asciende un peldaño.
3. El personaje que asciende por causa del jugador registra un **favor**; el que queda sin la silla registra un **agravio**. Ambos son permanentes.

La consecuencia es que la compañía nunca queda parcialmente vacía y el propio mundo genera los futuros aliados y enemigos del jugador.

### 6.4 Trato social por escalón

| Escalón | Comportamiento del entorno |
|---|---|
| 1 | Te ignoran, te envían a por café, te adelantan en la cola de la cafetería. |
| 2–3 | Existes. Algunos te saludan por tu nombre. |
| 4 | Tus antiguos iguales te adulan; los superiores te tratan como mobiliario. |
| 5 | Secretaría propia; tratamiento formal; los periodistas aprenden tu nombre. |
| 6 | Silencio al entrar; favores ofrecidos sin solicitarlos; temor. |
| 7 | Adulación de frente; hostilidad por la espalda; prensa e inversores permanentemente atentos. |
| 8 | **Nadie te dice la verdad. Nunca.** Y esa es la debilidad terminal del cargo. |

Este comportamiento no está guionizado: emerge de que el rango del jugador entra como variable en la función de utilidad de cada personaje (*ver 7.5*).

### 6.5 Curva económica y trampa salarial

| Concepto | Valor |
|---|---|
| Coste de vida base | 20–25 € diarios |
| Salario del rango inicial | 30 € diarios |
| Margen disponible en R1 | **8 € diarios** |
| Soborno más económico del juego | 210 € |
| Días de ahorro honesto necesarios | **26** |
| Días robando material de oficina | **5** |

A partir del escalón 5 los **gastos de estatus** (traje ejecutivo, comidas de representación, vehículo) consumen el incremento salarial. El jugador triplica sus ingresos y conserva un margen equivalente. *Cuanto más alto se asciende, más caro resulta parecer que se pertenece.*

*El catálogo completo de las cincuenta ocupaciones, con todos sus atributos, se encuentra en la sección 22.*

---

# PARTE III — LA SIMULACIÓN

## 7. El cerebro social

> Este sistema es el componente más complejo del juego. En un diseño con múltiples vías de victoria, ninguna reacción del mundo puede estar guionizada: el entorno debe responder de forma verosímil a cualquier estrategia.

### 7.1 Principio de diseño

La sensación de inteligencia no procede de un sistema centralizado que lo decide todo, sino de **la interacción entre varios sistemas simples correctamente calibrados**. Las capas se apoyan secuencialmente: percepción → creencias → decisión → memoria → propagación → escalada.

**No se emplea ningún modelo de lenguaje en tiempo de ejecución.** El juego se distribuye y funciona de forma autónoma, sin conexión a servicios externos. La inteligencia se implementa mediante algoritmos clásicos: máquinas de estados finitos, inteligencia artificial por utilidad, grafos de creencias y simulación económica determinista con componente estocástico. Todo ello es ejecutable en Godot y en hardware móvil.

### 7.2 La capa de creencias

Ningún personaje posee conocimiento omnisciente del mundo. Cada uno almacena un conjunto de creencias con la siguiente estructura:

```
Belief {
    id: String
    holder: String          # quién sostiene la creencia
    subject: String         # sobre quién versa
    fact: String            # qué afirma
    evidence_strength: float
    source: String          # "direct" | "rumor" | "record"
    certainty: float        # 0.0 – 1.0
    location: String
    timestamp: int          # jornada de creación
    is_record: bool         # si es permanente
}
```

| Origen | Certeza inicial | Comportamiento |
|---|---|---|
| **Percepción directa completa** | 0,90 | Decae lentamente |
| **Percepción parcial** | 0,35 | Decae con rapidez; acumulable |
| **Transmisión oral** | Certeza del emisor × 0,75 | Puede amplificarse hasta ×1,15 al propagarse |
| **Registro documental** | 1,00 | **No decae. Requiere destrucción activa.** |

**Cálculo de la sospecha del jugador.** La sospecha no es una variable arbitraria: es el agregado ponderado de las creencias existentes sobre el jugador.

```
Sospecha = Σ (certeza_creencia × credibilidad_portador × peso_tipo) 
           normalizado a 0–100
```

donde `credibilidad_portador` deriva de la reputación del personaje que sostiene la creencia. Esta formulación tiene dos consecuencias de diseño importantes: la sospecha resulta **explicable** (el jugador puede consultar en el panel de depuración qué creencias la componen) y **manipulable** (borrar una grabación, silenciar a un testigo o elevar la propia reputación la reducen por vías distintas).

### 7.3 Percepción

**Percepción visual.** Cada personaje posee un cono de visión definido por ángulo, distancia y orientación. Los valores base residen en `balance.json` y se modulan por el rasgo de Perspicacia del personaje y por la Sospecha actual del jugador.

La detección es **progresiva**. Permanecer dentro del cono llena un contador; abandonarlo lo vacía a menor velocidad. Los modificadores son:

| Factor | Efecto sobre la velocidad de llenado |
|---|---|
| Distancia | Inversamente proporcional |
| Jugador agachado | ×0,5 |
| Jugador inmóvil | ×0,7 |
| Jugador esprintando | ×1,8 |
| Perspicacia del personaje | +0,01 por punto |
| Sospecha del jugador | +0,005 por punto |
| Obstrucción parcial (mobiliario bajo) | ×0,4 |

**Tres umbrales:**

| Umbral | Valor | Consecuencia |
|---|---|---|
| Percepción parcial | 0,45 | Genera creencia de certeza 0,35. **Sin confrontación.** |
| Identificación completa | 1,00 | Si el jugador realiza un acto indebido, se declara **flagrancia**. Si no, no ocurre nada: verte trabajar es normal. |
| Pérdida de contacto | < 0,10 | El contador se reinicia. |

**Percepción auditiva.** Los ruidos se modelan como eventos con posición y radio. Un personaje dentro del radio orienta su atención hacia el origen e investiga si su Perspicacia lo justifica.

| Acción | Radio |
|---|---|
| Caminar sigiloso | 1,0 |
| Caminar normal | 3,5 |
| Esprintar | 9,0 |
| Abrir un cajón | 4,0 |
| Romper algo | 12,0 |

**Máscaras acústicas.** Determinadas salas poseen un nivel de ruido ambiente elevado que reduce el radio efectivo de los ruidos del jugador al 15%: call center, cuarto de calderas, línea de ensamblaje y fotocopiadoras. En esas salas el jugador recibe un indicador discreto de que su actividad no resulta audible.

### 7.4 Personalidad: los seis rasgos

Cada personaje se define mediante seis valores enteros en el rango 0–100.

| Rasgo | Sistemas que gobierna |
|---|---|
| **Ambición** | Frecuencia de generación de ideas propias; competencia por vacantes; probabilidad de sabotear al jugador |
| **Lealtad** | Probabilidad de denuncia frente a encubrimiento; resistencia al soborno |
| **Codicia** | Término principal de la fórmula de soborno |
| **Valentía** | Comportamiento al presenciar un delito: denunciar, negociar o silenciar por temor |
| **Perspicacia** | Amplitud y alcance del cono de visión; velocidad de detección; certeza de las creencias generadas |
| **Sociabilidad** | Volumen y velocidad de propagación de rumores |

### 7.5 Decisión por utilidad

Cada personaje evalúa periódicamente su repertorio de acciones y ejecuta la de mayor puntuación. El repertorio base es:

`trabajar` · `cotillear` · `denunciar en seguridad` · `confrontar al jugador` · `aceptar soborno` · `rechazar soborno` · `generar idea propia` · `descansar` · `huir` · `chantajear al jugador` · `sabotear a un rival`

La puntuación de cada acción es una combinación lineal ponderada de:

```
Utilidad(acción) = Σ (peso_rasgo × valor_rasgo)
                 + Σ (peso_creencia × certeza_creencia_relevante)
                 + peso_ánimo × ánimo_actual
                 + peso_relación × valor_ledger_hacia_jugador
                 + peso_rango × rango_del_jugador
                 + peso_sospecha × sospecha_del_jugador
                 + peso_reputación × reputación_del_jugador
```

**El trato diferencial por rango emerge de esta fórmula sin necesidad de guion.** Ante un jugador de rango bajo, la acción «denunciar sin temor» recibe puntuación elevada porque el término `peso_rango × rango_jugador` es despreciable. Ante un directivo, la misma acción se penaliza y «callar por temor» asciende. El sistema es idéntico; el comportamiento resulta opuesto.

La reevaluación se dispara **por eventos**, nunca en bucle continuo por fotograma.

### 7.6 Memoria, olvido y registro

| Tipo de información | Comportamiento temporal |
|---|---|
| Creencia ordinaria | Pierde 0,08 de certeza por jornada. Se olvida al descender de 0,10. |
| Creencia reforzada | Cada refuerzo restablece la certeza y reinicia el decaimiento. |
| **Registro** | **No decae jamás.** Solo desaparece mediante destrucción activa. |

**Elementos que constituyen registro:** un cuerpo hallado, una expulsión firmada, una grabación archivada, un acta del consejo, un asiento contable, un registro de acceso por tarjeta, un documento con sello.

La consecuencia de diseño es directa: **los delitos menores se diluyen con el paso del tiempo; los mayores dejan rastro permanente que el jugador debe gestionar activamente**. De aquí nace la tensión estratégica de decidir la escala de cada operación.

### 7.7 Grafo social y propagación de rumores

Los personajes están conectados mediante un grafo dirigido con siete tipos de arista.

| Tipo de vínculo | Fuerza | Comportamiento de propagación |
|---|---|---|
| **Departamento** | 0,3–0,5 | Numerosas aristas; propagación amplia y lenta |
| **Amistad** | 0,6–0,8 | Propagación rápida con mínima pérdida de certeza |
| **Pareja** | 0,9–1,0 | Propagación total. **Si es clandestina, constituye material de chantaje.** |
| **Rivalidad** | 0,5–0,7 | Propaga exclusivamente información negativa, y la amplifica |
| **Deuda** | Dirigida | Suprime temporalmente la acción de denuncia hacia el acreedor |
| **Jerarquía** | Dirigida ascendente | Toda información relevante asciende al superior |
| **Parentesco corporativo** | Especial | Acusar al beneficiario de un enchufe familiar se vuelve contra el acusador |

**Momentos de propagación.** Las creencias solo saltan entre personajes durante los momentos de socialización:

| Corrillo | Horario | Ubicación | Amplificación |
|---|---|---|---|
| **Clan de la cafetería** | 13:00–14:00 | Cafetería (PB) | **Máxima del juego** |
| Corrillo del futbolín | Ratos muertos | Sala de descanso (P4) | Media |
| **Corrillo de fumadores** | Cada 2 horas | Exterior, puerta principal | Alta, y **sin cámaras: aquí se dicen las verdades** |
| Grupo de chat del 3B | Permanente | Digital | Baja, pero **continua incluso de noche y legible por IT** |
| Pareja de contabilidad | Variable | P5 | Nula hacia fuera, hasta que se descubre |

El grafo explica mecánicamente por qué **aislar a una víctima** —reasignando su puesto como jefe de ala— reduce el número de testigos efectivos: menos aristas implican menos propagación.

### 7.8 Personajes con agenda propia

Los personajes con Ambición elevada persiguen sus propios objetivos de progresión. La compañía está poblada de competidores, no de decorado.

| Comportamiento | Implicación para el jugador |
|---|---|
| **Generan ideas propias** | Fuente de material robable… y también amenaza: pueden robar la del jugador |
| **Compiten por la misma vacante** | La regla de la silla libre se les aplica igualmente. Si el jugador no actúa, asciende el rival. |
| **Incriminan y sabotean** | Emplean los mismos sistemas que el jugador, contra él |
| **Acumulan mérito** | Su mérito compite con el del jugador en la evaluación de vacantes |

### 7.9 El registro de relaciones

Cada personaje mantiene un registro individual sobre el jugador:

```
Ledger {
    affection: int       # -100 a +100
    fear: int            # 0 a 100
    debt: int            # positivo: te debe; negativo: le debes
    grievances: Array    # [{ tipo, gravedad, jornada }]
    favours: Array       # [{ tipo, magnitud, jornada }]
}
```

| Contenido | Efectos |
|---|---|
| **Agravios** (expulsión, hundir a un amigo, robar una idea, incriminar, arrebatar un ascenso) | Reducen afección; aceleran la denuncia; propagan mala fama; alían al personaje con rivales del jugador; **incrementan el precio de sobornarlo** |
| **Favores** (promoción, encubrimiento, pago, evitar un despido) | Producen coartadas, avisos preventivos y silencios; **reducen el precio del soborno** |
| **Temor elevado** | Produce obediencia y silencio, pero impulsa al personaje a buscar protección entre los enemigos del jugador |

**Los agravios no decaen.** Persisten durante toda la partida. Una operación imprudente en la jornada tercera puede provocar la derrota en la jornada cuarenta.

### 7.10 Reputación y sospecha como moduladores globales

Los dos medidores no son barras de dificultad independientes: son **variables de entrada de todos los demás sistemas**.

**Efectos de reputación elevada:**

| Sistema afectado | Modificación |
|---|---|
| Creencias | Las creencias negativas sobre el jugador nacen con certeza reducida |
| Creencias | El decaimiento de la sospecha se acelera |
| Promociones | Desbloquea rangos superiores |
| Utilidad de los personajes | «Denunciar» se penaliza; «hacer un favor» se premia |
| Flagrancia | El personaje que descubre al jugador duda más antes de actuar |
| Interrogatorio | La respuesta «negar» resulta eficaz contra pruebas débiles |
| Notaría | El notario firma sin verificación |

**Efectos de sospecha elevada:**

| Sistema afectado | Modificación |
|---|---|
| Percepción | Incrementa la perspicacia efectiva de los personajes cercanos |
| Seguridad | Eleva el nivel de alerta global: más rondas, más grabaciones revisadas |
| Investigaciones | **Reduce el umbral de apertura de casos** |
| Sobornos | Encarece el precio y reduce la probabilidad de aceptación |
| Interrogatorio | Los desmentidos del jugador se descuentan |
| Audio | **El hilo musical corporativo se degrada progresivamente** (*ver 14.9*) |

**El cruce determinante.** Una acción idéntica produce consecuencias distintas según el estado de los medidores. Acceder a un despacho ajeno y ser visto, con reputación alta y sospecha baja, se resuelve con una explicación verosímil. La misma imagen con sospecha alta abre una investigación. **La inteligencia del mundo se calibra según la identidad que el jugador proyecta.**

### 7.11 La capa compartida de noticias

El componente que integra el cerebro social y el económico. Ambos consumen **una única capa de noticias y sentimiento**.

| Evento | Efecto social | Efecto económico |
|---|---|---|
| Cuerpo hallado | Investigación grave; sospecha máxima | Factor de riesgo al alza; caída de la cotización |
| Fraude aflorado | Investigación; pérdida de reputación | Reducción del múltiplo; pérdida de confianza inversora |
| Huelga | Descontento generalizado | Producción detenida; noticia negativa |
| Patrón de información privilegiada detectado | Investigación de máxima gravedad | Escándalo bursátil |

**Enterrar una noticia beneficia simultáneamente a ambos sistemas.** La manipulación de prensa no constituye un subsistema aislado: es la palanca que opera sobre los dos cerebros a la vez. Esta es la razón por la que el puesto de Director de Comunicación resulta desproporcionadamente valioso.

### 7.12 Dificultad emergente

La dificultad no se implementa como un multiplicador creciente. Emerge de tres fuentes estructurales:

**Primera: deberes progresivamente incumplibles.** El trabajo real que el jugador no sabe realizar exige trampas cada vez mayores (*ver 10.3*).

**Segunda: incremento de observadores.** Periodistas a partir del escalón 5, inversores a partir del 7, y en el escalón 8 el propio consejero delegado vigilando personalmente a su segundo.

**Tercera: proporcionalidad entre delito y evidencia.** Vaciar sillas de escalón alto requiere operaciones de mayor calibre, que generan más registros permanentes y abren investigaciones más severas.

### 7.13 Ejemplo de cadena emergente

La siguiente secuencia ilustra el funcionamiento integrado del sistema. Ninguna parte está guionizada.

> **Jornada 12, 13:42.** El jugador fuerza el cajón de Claudia Reeves para copiar un archivo. Debbie Foyle pasa por el pasillo y lo percibe durante medio segundo a ocho metros de distancia, parcialmente obstruida por un tabique. El contador de detección alcanza 0,51: **percepción parcial**. Se genera una creencia de certeza 0,35: *«Vi al jugador junto a la mesa de Claudia»*.
>
> **Jornada 12, 13:55.** Franja de comida. Debbie, con Sociabilidad 96, se sienta con George Penn. La creencia se propaga por una arista de departamento con fuerza 0,4. George la recibe con certeza 0,26, pero su Perspicacia elevada la interpreta en clave desfavorable.
>
> **Jornada 13, 09:15.** George, arquetipo Snitch con Lealtad 85, evalúa sus acciones. «Denunciar en seguridad» puntúa alto: su lealtad es elevada, el rango del jugador es bajo y ya posee una creencia previa de una semana atrás. Acude a la planta 15.
>
> **Jornada 13, 09:30.** Security agrega las dos creencias. El peso total alcanza 3,2, superando el umbral de apertura de 3,0. **Se abre una investigación.**
>
> **Jornada 14.** El jugador soborna al investigador por 12.000 euros. Probabilidad calculada: 0,71. Éxito. El caso se archiva y queda **frío**.
>
> **Jornada 31.** Rose Miller asciende a Auditora Jefe. Su rutina incluye la revisión de expedientes archivados. Encuentra que la grabación del pasillo de la planta 3 correspondiente a la jornada 12 **nunca se borró**: es un registro permanente. **El caso resucita** con una pieza de peso 4,5.
>
> **Jornada 31.** El jugador es ahora Director Financiero. Un escándalo en este momento no supone descenso: supone investigación con resultado terminal.

Cada subsistema del cerebro social existe para que secuencias de esta naturaleza ocurran de forma autónoma ante cualquier estrategia del jugador.

---

## 8. El elenco y el sistema de sobornos

### 8.1 Los doce arquetipos

Un arquetipo es un conjunto predefinido de valores para los seis rasgos. Cada personaje concreto recibe además una **variación aleatoria de ±15 puntos en cada rasgo**, acotada al intervalo 0–100. La consecuencia de diseño es que el jugador no puede memorizar tablas: debe aprender a interpretar el comportamiento observable.

| Identificador | Denominación | Amb | Leal | Cod | Val | Per | Soc | Función en el diseño |
|---|---|---|---|---|---|---|---|---|
| `climber` | The Climber | 90 | 30 | 60 | 60 | 70 | 60 | Competidor directo. Genera ideas y disputa vacantes. |
| `snitch` | The Snitch | 50 | 85 | 20 | 45 | 85 | 70 | Detecta y denuncia con rapidez. Prácticamente insobornable. |
| `bribable` | The Bribable | 55 | 20 | 90 | 35 | 50 | 55 | Aliado condicional mientras exista pago. |
| `company_man` | The Company Man | 35 | 95 | 10 | 70 | 65 | 40 | No se compra. Requiere evitación o expulsión. |
| `oblivious` | The Oblivious | 25 | 50 | 40 | 30 | 15 | 45 | Permite operar en su presencia. |
| `gossip` | The Gossip | 40 | 45 | 45 | 40 | 70 | 95 | Vector de propagación. Utilizable para inyectar rumores dirigidos. |
| `burnout` | The Burnout | 10 | 15 | 55 | 25 | 40 | 30 | El soborno más económico del juego. No denuncia. |
| `old_hand` | The Old Hand | 15 | 60 | 30 | 75 | 90 | 50 | Detecta con facilidad pero no siempre actúa. Aliado valioso. |
| `rookie` | The Rookie | 60 | 70 | 30 | 30 | 30 | 35 | Sin aristas sociales: sus rumores no propagan. Chivo expiatorio óptimo. |
| `hardliner` | The Hardliner | 50 | 70 | 25 | 90 | 60 | 40 | Denuncia sin vacilación. Cono de visión ampliado. |
| `coward` | The Coward | 45 | 50 | 60 | 10 | 60 | 50 | Presencia todo y silencia por temor. Chantajea posteriormente. |
| `incorruptible` | The Incorruptible | 30 | 90 | 5 | 80 | 80 | 45 | **Probabilidad de soborno nula por definición.** |

**Justificación del arquetipo insobornable.** Su existencia es deliberada y estructural. Si el capital resolviera cualquier situación, el juego se rompería en el momento en que el jugador acumulara fondos suficientes. Contra un personaje insobornable las únicas vías son el sigilo, la incriminación, la expulsión mediante procedimiento administrativo o la eliminación. Ser descubierto por uno de ellos constituye la situación de mayor riesgo del juego.

### 8.2 La fórmula de sobornos

**Paso primero: cálculo del precio justo.**

```
precio_justo = salario_diario_del_personaje × multiplicador_del_favor
```

| Favor solicitado | Multiplicador | Ejemplo de coste |
|---|---|---|
| Mirar hacia otro lado una vez | ×3 | Vigilante (70 €) → 210 € |
| Prestar un acceso, uniforme o llave | ×8 | Mantenimiento (56 €) → 448 € |
| Elogiarte ante un superior | ×15 | Jefe de equipo (120 €) → 1.800 € |
| **Silenciar algo recién presenciado** | **×20** | Compañero (30 €) → 600 € · Director (300 €) → 6.000 € |
| Mentir en un interrogatorio | ×40 | Director (300 €) → 12.000 € |
| Enterrar o cerrar una investigación | ×100 | Auditor Jefe (520 €) → 52.000 € |
| Votar a favor en el consejo | ×250 | Consejero (800 €) → 200.000 € |

**Paso segundo: cálculo de la probabilidad de aceptación.**

```
P = 0,10
  + 0,40 × (codicia / 100)
  + 0,20 × ratio_oferta
  + 0,10 × ((afección + deuda) / 100)
  + 0,10 × (reputación_jugador / 100)
  − 0,30 × (sospecha_jugador / 100)
  − 0,15 × (valentía / 100)
  − 0,20 × (lealtad / 100)
  ± 0,10 × modificador_de_rango

donde ratio_oferta = mín(oferta ÷ precio_justo, 2,0) ÷ 2,0
      modificador_de_rango = +0,10 si el jugador es superior jerárquico directo
                             −0,10 si el personaje es superior del jugador
                              0,00 en cualquier otro caso

P se acota finalmente al intervalo [0,00 , 0,95]
```

**Regla de excepción absoluta.** Si `codicia < 20` y `lealtad > 80`, entonces `P = 0` con independencia de cualquier otro factor. El juego no comunica esta condición mediante interfaz: el jugador debe inferirla del comportamiento observable del personaje y, a partir de la acreditación N5, del precio estimado que muestra el expediente.

**Paso tercero: resolución del rechazo.** Si el soborno fracasa, el resultado se determina por los rasgos del personaje:

| Condición | Resultado | Consecuencia |
|---|---|---|
| `valentía > 60` o `lealtad > 70` | **Denuncia** | **Expulsión inmediata. Fin de partida.** |
| `valentía < 30` | **Silencio con memoria** | No denuncia, pero genera creencia de certeza 0,9 y adquiere material de chantaje sobre el jugador |
| `codicia > 70` y oferta ≥ 0,7 × precio justo | **Contraoferta** | Solicita entre 1,3 y 1,8 veces el precio justo. El jugador puede reintentar. |
| Resto de casos | **Rechazo neutro** | Incremento de sospecha sin denuncia |

**Ofertas insuficientes.** Una oferta inferior al 50% del precio justo reduce la probabilidad a un tercio de su valor calculado e incrementa la sospecha aunque no se produzca denuncia. La negociación tiene coste.

**Canales de soborno.**

| Canal | Ventaja | Inconveniente |
|---|---|---|
| **Chat del móvil** | Sin testigos presenciales | **Genera registro digital permanente** legible por el Director de IT |
| **Llamada telefónica** | Sin registro escrito | Requiere privacidad física: si alguien está cerca, escucha |
| **En persona** | Sin registro de ningún tipo | Posibilidad de testigos y de cámaras |
| **Inmediato en flagrancia** | Resuelve la situación al instante | Multiplicador ×20, el más caro a pie de calle |

### 8.3 Los personajes nominados

Veintitrés personajes se definen manualmente por ocupar posiciones estructuralmente relevantes. El resto de la plantilla se genera por procedimiento (*ver 23.3*). Las fichas completas con valores numéricos se encuentran en la sección 23.

**Ala 3B — el entorno inicial del jugador**

| Personaje | Arquetipo | Función en el diseño |
|---|---|---|
| **Debbie Foyle** | `gossip` | Vector de propagación. Inyectarle un rumor lo distribuye por todo el edificio. Amenaza simétrica: también propaga lo del jugador. |
| **George Penn** | `snitch` | Amenaza permanente en el entorno inmediato. Obsesionado con el reconocimiento: regalarle un mérito lo neutraliza temporalmente. |
| **Nate Brackley** | `oblivious` | Perspicacia 15. Permite operar en su presencia. Enseña al jugador que los rasgos importan. |
| **Claudia Reeves** | `climber` | Primer competidor. Genera ideas de calidad alta. El jugador debe robarle o resignarse a perder la vacante. |
| **Old Ray Cudmore** | `old_hand` | Treinta y un años de antigüedad sin ascender. Perspicacia 90. Si el jugador se gana su respeto, revela accesos y rutinas del edificio. |
| **Sonia Vail** | `rookie` | Incorporada el mismo día que el jugador. Sin aristas sociales: chivo expiatorio óptimo, o única aliada sincera. |

**Mandos intermedios y puestos-llave**

| Personaje | Puesto | Arquetipo | Función |
|---|---|---|---|
| **Bernard Lasker** | Jefe del ala 3B (R15) | `hardliner` | Patrulla el ala. Debilidad explotable: solo evalúa las cifras del ala. Si el ala rinde, ignora el resto. |
| **Amelia Cole** | RRHH → Directora (R23) | `incorruptible` | Primer muro insobornable que el jugador encuentra. Custodia los expedientes completos. |
| **Tom Iverson** | Vigilante de día | `bribable` | Codicia 90. El seguro económico del jugador durante los primeros escalones. |
| **Ludmila Petrova** | Vigilante de noche | `hardliner` con Perspicacia 80 | Obstáculo principal del saqueo nocturno. Insobornable en la práctica. |
| **Connie Marks** | Limpieza veterana | `old_hand` | Acceso a todas las salas fuera de horario. Perspicacia 90. **Presencia todo y nadie la observa.** |
| **Frank Rudd** | Mantenimiento | `burnout` | Codicia 55, Lealtad 15. Presta el uniforme de trabajo por una cantidad irrisoria. |
| **Ernie Vaughn** | Capataz de fábrica (R15) | `climber` | Competidor por la vacante R15 y candidato idóneo para la incriminación en el robo de producto. |

**Dirección**

| Personaje | Puesto | Arquetipo | Función |
|---|---|---|---|
| **Diana Sedgwick** | Marketing A10 (R19) | `climber` | Demuestra la mecánica del autoelogio. La aplica contra el jugador si compiten. |
| **Iggy Robbins** | Coordinación A10 (R19) | `bribable` atípico | **No acepta dinero: acepta favores.** Mantiene contabilidad de lo que se le debe. |
| **Rose Miller** | Auditoría → Auditora Jefe (R29) | `incorruptible` | **Antagonista estructural de toda la partida.** Perspicacia 80, Lealtad 90. Su silla es el objetivo del rango R29. |
| **Alvin Pyne** | Director de IT (R24) | `coward` | Valentía 10. Observa los rastros digitales del jugador y silencia por temor. Protegerlo lo convierte en aliado permanente. |
| **Bree Nash** | Comunicación (R25) | `bribable` de precio alto | Única vía de enterrar noticias antes de alcanzar el puesto. Costosa e imprescindible. |
| **Maurice Sandbell** | CFO (R28) | `climber` | Realiza operaciones con información privilegiada por cuenta propia. Descubrirlo lo somete al jugador. |
| **Lorna Vickers** | Relación con Inversores (R29) | `gossip` con Sociabilidad 95 | Su red de contactos entre inversores tiene más valor que el capital. |
| **Preston Vaile III** | Vice-CEO (R32) | `hardliner` + `climber` | Aliado táctico contra Voss y enemigo garantizado después. Compite por la misma silla final. |
| **Harlan Voss** | **CEO (R33)** | Único: Per 95, Leal 0 | Veintidós años en el cargo. **Debilidad estructural: nadie le comunica información veraz.** Por eso resulta manipulable. |
| **Pearl Osgood** | Secretaría del CEO | `company_man` puro | El obstáculo real de la planta 20. Conoce la combinación de la caja fuerte. |

## 9. El cerebro económico

### 9.1 Principio de diseño

La simulación bursátil debe cumplir dos condiciones aparentemente contradictorias. Primera: ser **consecuencia verificable de lo que ocurre en el edificio**, de modo que el robo de producto se refleje en los márgenes y la expulsión de personal cualificado degrade la calidad. Segunda: ser **impredecible**, para que el jugador no pueda resolverla mediante una fórmula y exista riesgo real hasta el final de la partida.

La resolución de esa tensión es la arquitectura de cuatro fuerzas de la sección 9.3.

### 9.2 Fundamentales y reportados

**Los fundamentales** son los valores reales de la compañía, recalculados una vez por jornada.

| Componente | Fórmula de cálculo | Sistemas que lo alimentan |
|---|---|---|
| **Ingresos** | `unidades × precio_medio × fuerza_de_marca` | Calidad de producto (diseño, P7), eficacia de marketing (P6, A10), fuerza comercial (P11) |
| **Costes** | Suma de materiales, nóminas, gastos legales, **pérdidas por robo** y costes de escándalo | Eficiencia de fábrica, robos del jugador, investigaciones abiertas, demandas |
| **Beneficio** | `ingresos − costes` | — |
| **Expectativa de crecimiento** | Tendencia de los cuatro últimos trimestres más productos en desarrollo | Departamento de diseño, lanzamientos |
| **Factor de riesgo** | Suma ponderada de investigaciones abiertas, prensa negativa, huelgas y rotación de directivos | Security, NewsFeed, Company |

**Los reportados** son los valores que la compañía comunica al mercado. A partir de determinados cargos —Director del bloque B10, CFO, consejero delegado— el jugador decide el grado de coincidencia entre ambos conjuntos.

**La mecha de auditoría.** Toda divergencia entre fundamentales y reportados enciende un temporizador. Su duración es inversamente proporcional a la magnitud de la falsificación:

```
semanas_hasta_auditoría = 8 − (6 × magnitud_de_la_divergencia)
acotado al intervalo [2, 8]
```

Al expirar, la auditoría interna detecta la discrepancia con probabilidad proporcional a la perspicacia del Auditor Jefe en ese momento. Si el jugador ocupa ese puesto, la probabilidad es nula.

### 9.3 La fórmula del precio de la acción

**Valor intrínseco:**

```
múltiplo = múltiplo_base 
         + (0,8 × expectativa_de_crecimiento) 
         − (1,2 × factor_de_riesgo)

V = (beneficio_anual_esperado × múltiplo) ÷ número_de_acciones
```

**Evolución diaria:**

```
P(t+1) = P(t)
       + α × (V − P(t))          # gravedad hacia el valor real
       + β × sentimiento          # noticias y ánimo inversor
       + γ × momentum             # tendencia reciente amplificada
       + ruido                    # componente estocástico

donde  α = 0,05    β = 0,30    γ = 0,15
       ruido ∈ [−0,03, +0,03] × P(t)
       momentum = media de la variación de los cinco últimos días
```

**Interpretación de cada fuerza:**

| Fuerza | Velocidad | Función en el diseño |
|---|---|---|
| **Gravedad (α)** | Lenta, acumulativa | La verdad de la compañía acaba imponiéndose. Impide que la manipulación sea permanente. |
| **Sentimiento (β)** | Rápida, volátil | Punto de aplicación de la manipulación de prensa. La palanca del jugador. |
| **Momentum (γ)** | Amplificadora | Genera burbujas y pánicos. Convierte una noticia menor en un movimiento severo. |
| **Ruido** | Aleatoria | Impide la predicción perfecta. Garantiza riesgo residual permanente. |

**Consecuencia de diseño, y tesis del sistema: la manipulación compra tiempo, no inmunidad.** El jugador puede elevar la cotización mediante una noticia fabricada, pero si los fundamentales están deteriorados, la gravedad revierte el efecto y el cierre trimestral lo alcanza.

### 9.4 Calendario económico

| Periodicidad | Evento | Consecuencia para el jugador |
|---|---|---|
| **Diaria** | La acción cotiza | Oportunidad de operar; el rastro se acumula |
| **Semanal** | Informes internos de ventas, producción e incidencias | **Primera señal visible de los robos** |
| **Mensual** | Cierre contable | **Afloran los fraudes**: nóminas fantasma, facturas infladas, descuadres de inventario |
| **Trimestral** | Presentación de resultados en la planta 16 | El evento de mayor riesgo del escalón 7 |
| **Anual** | Junta del consejo, dividendos, revisión de cargos altos | Evaluación global del desempeño |

**Regla dura:** dos trimestres consecutivos con resultados por debajo del objetivo, en cualquier cargo de rango R28 o superior, producen degradación o expulsión.

### 9.5 La presentación trimestral de resultados

El evento se resuelve en tres fases, y las tres admiten manipulación.

**Fase primera: preparación.** El jugador consulta los fundamentales reales y decide los valores reportados. Inflar mejora la reacción inmediata a cambio de encender la mecha de auditoría descrita en 9.2.

**Fase segunda: la presentación.** Los inversores presentes formulan preguntas. El resultado se calcula así:

```
calidad_presentación = 0,4 × preparación
                     + 0,3 × (reputación / 100)
                     + 0,3 × proporción_de_aliados_en_sala

donde preparación ∈ {0,0 sin preparar
                     0,5 usando A.S.S.I.S.T.
                     0,8 con informe robado al COO
                     1,0 con trabajo real completo}
```

Un inversor sobornado que formula una pregunta favorable incrementa `proporción_de_aliados_en_sala`. El diseño satírico es explícito: **la calidad de la presentación pesa el sesenta por ciento y las cifras reales el cuarenta**.

**Fase tercera: reacción.** Cada inversor actualiza su confianza según su estrategia. El agregado ponderado por capital modifica el sentimiento de mercado.

### 9.6 Los inversores como agentes

Cinco estrategias, seis inversores nominados. Cada uno posee capital, estrategia, nivel de confianza en el jugador (0–100), venalidad y los seis rasgos estándar de personalidad.

| Estrategia | Función de decisión | Vector de manipulación |
|---|---|---|
| **Valor** | Evalúa exclusivamente fundamentales. Ignora el sentimiento. | **Inmune al marketing.** Solo la contabilidad falsificada lo engaña, y únicamente hasta la auditoría. |
| **Momentum** | Sigue y amplifica la tendencia reciente. | Un titular bien colocado lo desplaza en horas. |
| **Cazador de información** | Prioriza la anticipación sobre el análisis. | Se compra con soplos. Cada soplo constituye una prueba. |
| **Activista** | Persigue cambios en la dirección. | Se le puede dirigir contra un rival. También puede dirigirse contra el jugador. |
| **Pasivo institucional** | Compra sostenido, reacción mínima. | Solo responde a desastres. Su venta señala colapso. |

| Inversor | Estrategia | Capital | Confianza inicial | Venalidad |
|---|---|---|---|---|
| **Howard Grange** | Valor | Muy alto | 50 | Ninguna |
| **Tania Brekke** | Momentum | Alto | 50 | Soborno de precio alto |
| **Victor Sallow** | Cazador | Medio | 40 | Soborno económico; paga por soplos |
| **Margaret Ash** | Activista | Alto | 45 | Insobornable; chantajeable |
| **Neil Deming** | Pasivo institucional | Muy alto | 60 | Ninguna |
| **Bobby Kerr** | Momentum minorista | Bajo | 30 | Soborno muy económico; alcance desproporcionado |

### 9.7 Confianza inversora agregada

```
confianza_agregada = Σ (confianza_i × capital_i) ÷ Σ capital_i
```

**Este valor constituye el deber real de todo cargo de rango R28 o superior.** El objetivo trimestral se define en `market.json` y su incumplimiento reiterado activa la presión del consejo.

| Factor | Efecto sobre la confianza |
|---|---|
| Resultados por encima de lo esperado | +8 a +15 por inversor |
| Prensa favorable | +3 a +6 |
| Contacto personal en el lounge | +5 (coste: gasto de representación) |
| Soplo privilegiado | +12 al inversor cazador |
| Resultados por debajo de lo esperado | −10 a −20 |
| Escándalo público | −15 a −30 |
| **Falsificación descubierta** | **−25 a −40 y pérdida permanente de credibilidad** |

### 9.8 Operaciones con información privilegiada

A partir del rango R25 el jugador conoce las noticias con una antelación de uno a tres días. Operar en consecuencia produce el rendimiento más elevado del juego.

**Detección.** Cada operación acumula un punto de patrón:

```
probabilidad_detección = 0,05 × número_de_operaciones
                       + 0,10 × (volumen_medio ÷ volumen_umbral)
                       + 0,20 × (sospecha_jugador / 100)
                       + 0,30 × (perspicacia_auditor_jefe / 100)
```

Al superar el umbral definido en `market.json` se abre una investigación de gravedad máxima que además **constituye noticia pública**, con lo que incrementa la sospecha y deprime la cotización simultáneamente.

**Contramedidas disponibles:** operar mediante terceros sobornados —que pasan a ser testigos con registro—, reducir el volumen por operación, espaciar temporalmente las operaciones, enterrar la noticia mediante el Director de Comunicación, u ocupar personalmente el puesto de Auditor Jefe.

### 9.9 Palancas económicas por cargo

| Cargo | Variable que controla | Magnitud del efecto |
|---|---|---|
| Creativo de marketing | Fuerza de marca | Baja |
| Director de Marketing A10 | Fuerza de marca | Media |
| Diseñador de zapatos | Calidad de producto | Media |
| Director del bloque B10 | Cifras de venta reportadas | Media, con mecha de dos semanas |
| Capataz de fábrica | Eficiencia y pérdidas | Media |
| Director de Fábrica | Costes de producción | Alta |
| **Director de Comunicación** | **Sentimiento de mercado** | **Alta, y afecta a ambos cerebros** |
| **CFO** | **Valores reportados** | **Muy alta, con mecha de auditoría** |
| Director de Relación con Inversores | Confianza inversora directa | Alta |
| **Auditor Jefe** | Apertura y cierre de investigaciones | **Muy alta** |
| Inversionista / consejo | Votos y dividendos | Alta |
| Consejero delegado | Estrategia global | Total |

### 9.10 La ironía estructural

El sistema económico penaliza la corrupción del jugador de una forma que solo se manifiesta al final de la partida.

| Acción del jugador | Efecto inmediato | Efecto acumulado |
|---|---|---|
| Robo de producto | Ingreso personal | Incremento del componente «pérdidas» de los costes |
| Expulsión de personal cualificado | Vacante disponible | **Reducción de la calidad de producto y de la generación de ideas** |
| Eliminación de un personaje | Silencio garantizado | Reducción del talento disponible; incremento del factor de riesgo |
| Escándalo no enterrado | Sospecha | Reducción permanente del múltiplo de valoración |

**El resultado es que la compañía que el jugador hereda al firmar los documentos de propiedad vale exactamente lo que él dejó de ella.** Puede coronarse propietario de una empresa solvente o de una estructura vaciada. La victoria no cambia; cambia su contenido. El epílogo lo refleja explícitamente (*ver 12.9*).

### 9.11 Cartera personal del jugador

| Rango | Capacidad |
|---|---|
| R25 | Compra y venta de acciones desde el ordenador |
| R28 | Acceso a información privilegiada |
| **R30** | **Cambio de bando: adquisición de un paquete accionarial por ~250.000 € y percepción de dividendos en lugar de salario** |

El paquete accionarial concede **derecho de voto en el consejo**, lo que acelera el acceso a los rangos finales y puede frenar la propia expulsión del jugador. El riesgo simétrico es que deteriorar la compañía deteriora su patrimonio personal.

### 9.12 Eventos de mercado

Catálogo ajustable mediante datos. Cada evento define efecto en fundamentales, efecto en sentimiento, duración y probabilidad de aparición.

| Evento | Efecto |
|---|---|
| Cambio de tendencia en calzado | Ingresos ±15% durante dos trimestres |
| Encarecimiento del cuero | Costes +8% hasta cambio de proveedor |
| Lanzamiento de un competidor | Expectativa −10%; sentimiento negativo |
| Demanda judicial de un cliente | Costes legales y factor de riesgo al alza |
| Viralización en redes | Sentimiento muy positivo durante dos semanas |
| Recesión general | Múltiplo del sector −20% durante varios trimestres |
| Personaje público calzando la marca | Fuerza de marca al alza |
| Huelga | Producción detenida; riesgo al alza; noticia negativa |

---

# PARTE IV — LA JUGABILIDAD

## 10. El trabajo: los deberes como sistema jugable

> El juego se define por la premisa de simular productividad. Esta sección especifica en qué consiste materialmente trabajar, porque constituye el suelo sobre el que se apoyan todos los demás sistemas.

### 10.1 Principio de diseño

La sátira solo funciona si **cumplir los deberes honestamente resulta tedioso y consume tiempo de reloj**. Cada minuto dedicado al trabajo es un minuto no disponible para operaciones encubiertas.

Existe un límite: tedioso, no insufrible. Ningún deber individual debe requerir más de tres minutos de tiempo real de interacción activa.

**La tensión estructural de cada jornada.** El jugador dispone de once horas de oficina. Los deberes consumen entre el veinte y el sesenta por ciento según el rango. El resto constituye su tiempo operativo. **Falsificar el trabajo no es una opción entre varias: es el mecanismo que financia el tiempo necesario para todo lo demás.**

### 10.2 Los cinco tipos de deber

| Tipo | Mecánica | Ocupaciones que lo emplean | Automatizable |
|---|---|---|---|
| **Volumen** | Interfaz repetitiva de interacción: responder correos, sacar fotocopias, atender llamadas. Consume tiempo proporcional a la cantidad. | Escalones 1 y 2 | Sí, mediante A.S.S.I.S.T. o delegación |
| **Cuota** | Producir o vender un número de unidades. **Los robos del jugador reducen su propia cuota disponible.** | Fábrica y ventas | Parcialmente |
| **Entrega** | Producir un documento: informe, campaña, diseño, cierre contable. **Requiere material de origen.** | Escalón 3 en adelante | Sí, con material robado o IA |
| **Ronda** | Recorrer una secuencia de puntos del edificio. **Constituye justificación para estar donde no corresponde.** | Puestos-llave | No |
| **Presentación** | Escena con público. La reputación se expone ante testigos. | Escalones 5 a 8 | Parcialmente |

### 10.3 Escala de viabilidad honesta

| Escalón | Viabilidad | Consecuencia práctica |
|---|---|---|
| **1–2** | **Plenamente viable.** Solo consume tiempo. | Un jugador honesto sobrevive indefinidamente y no asciende nunca. |
| **3–4** | **Viable pero consume la jornada completa.** | Aquí se produce la primera elección real: trabajar o progresar. |
| **5–6** | **No viable sin material robado o asistencia artificial.** | El informe mensual del Director General de planta es el primer muro estructural. |
| **7–8** | **Inviable en términos absolutos.** | Requiere que terceros produzcan el trabajo: robo de informes al COO, delegación forzada, compra de contenido. |

Esta escala es la **fuente primaria de la dificultad emergente**. El juego no incrementa un multiplicador: hace que el cumplimiento honesto se vuelva progresivamente imposible.

### 10.4 A.S.S.I.S.T.: la herramienta de inteligencia artificial corporativa

*Automated Stellar Support and Information Synthesis Tool.* El acrónimo es intencionado.

| Resultado | Probabilidad | Efecto mecánico |
|---|---|---|
| **Aceptable** | 60% | El deber se cumple. Sin consecuencias. |
| **Excelente** | 25% | El deber se cumple y otorga mérito menor. |
| **Fallo evidente** | 15% | Terminología incoherente, datos inventados. **Un personaje con Perspicacia superior a 60 lo detecta:** pérdida de reputación y anotación en el expediente. |

**Coste oculto.** Cada uso genera un registro digital consultable por el Director de IT. El uso reiterado produce un patrón que un personaje mencionará en el momento menos oportuno. El diseño replica la dinámica real que satiriza: la herramienta que ahorra trabajo es también la que deja constancia de que no se trabajó.

### 10.5 Delegación

Disponible a partir del escalón 4, cuando el jugador tiene subordinados.

| Propiedad | Especificación |
|---|---|
| Coste temporal | Consume el tiempo del subordinado, no el del jugador |
| Coste en relación | Incrementa el agravio del subordinado en proporción a la frecuencia |
| Riesgo | Si el subordinado ejecuta mal, la responsabilidad recae en el jugador |
| Calidad del resultado | Proporcional a la competencia del subordinado: delegar en un `burnout` produce fallo con alta probabilidad |

**Nota de diseño.** Al delegar, el jugador se convierte funcionalmente en el tipo de superior que lo explotaba en el escalón 1. El juego no lo comenta mediante texto. La mecánica es el comentario.

### 10.6 Coste temporal de los deberes

| Deber | Ocupación | Tiempo de juego | Con A.S.S.I.S.T. |
|---|---|---|---|
| Ocho correos | R1 | 45 min | 5 min |
| Cuota de fotocopias | R2 | 60 min | No aplicable |
| Archivo de pedidos | R2 | 50 min | No aplicable |
| Atención de llamadas | R3 | 90 min | No aplicable |
| Cuota de línea de fábrica | R3 | 120 min | No aplicable |
| Reparto de correo interno | R4 | 90 min | No aplicable |
| Registro de facturas | R5 | 60 min | 15 min |
| Procesamiento de nóminas | R6 | 75 min | 20 min |
| Zona de limpieza | R7 | 150 min | No aplicable |
| Ronda de vigilante | R10 | 90 min por ronda | No aplicable |
| Piezas de campaña | R11 | 120 min | 30 min |
| Cierre contable mensual | R13 | 180 min | 45 min |
| **Informe mensual de área** | **R22** | **240 min** | **90 min, con riesgo de fallo evidente** |
| Métricas de bloque | R19 | 150 min | 40 min |
| **Resultados trimestrales** | **R28** | **300 min más preparación** | **Inviable en solitario** |
| Cierre de seguridad | R24 | 30 min | No aplicable, y obliga a ser el último |

## 11. El crimen: sistemas de apropiación y manipulación

### 11.1 Las ideas como objeto de juego

Una idea es una entidad con estado propio y ciclo de vida.

```
Idea {
    id: String
    owner: String           # personaje que la generó
    quality: int            # 20–100
    department: String
    freshness: int          # jornadas restantes antes de caducar
    known_by: Array         # personajes que saben de su existencia
    presented: bool
}
```

**Generación.** Los personajes con Ambición media o alta generan ideas periódicamente:

```
probabilidad_diaria = 0,12 + (0,004 × ambición)
calidad = 20 + aleatorio(0, 80) modulado por el departamento
frescura = aleatorio(3, 10) jornadas
```

**Señalización.** El evento es perceptible para el jugador mediante dos canales simultáneos: un indicador visual sobre el personaje y un cambio de comportamiento observable —agitación, desplazamiento hacia su ordenador para anotarla, o desplazamiento hacia otro personaje para comunicarla.

**Las cinco vías de adquisición.**

| Vía | Requisito | Rastro que deja | Riesgo relativo |
|---|---|---|---|
| **Escucha** | Proximidad en el momento en que la comunica a un tercero | El propietario sabe que estabas presente | Bajo |
| **Copia de archivo** | Acceso a su ordenador en su ausencia | Registro digital consultable por IT | Medio |
| **Herencia** | El propietario desaparece antes de presentarla | Ninguno respecto a la idea; el que corresponda a su desaparición | Máximo |
| **Compra** | Soborno con el favor específico de cesión y silencio | Ninguno documental, pero **el propietario conserva conocimiento completo** | Bajo, coste alto |
| **Cesión voluntaria** | Personaje con deuda elevada hacia el jugador | Ninguno | Nulo |

**Caducidad.** La frescura decrece cada jornada. Si el propietario la presenta antes que el jugador, pierde todo valor. **Vigilar a un personaje no es un ejercicio de paciencia: es una carrera contra su propia agenda.**

### 11.2 La escena de presentación: sala Aurora

Las ideas se presentan en reuniones programadas semanalmente en la sala Aurora de la planta 12, visibles en el calendario del jugador y en el organigrama corporativo.

**Cálculo del mérito obtenido:**

```
mérito = calidad_idea 
       × factor_presentación 
       × (0,7 + 0,3 × reputación / 100)

factor_presentación ∈ {0,6 sin preparación
                       0,8 con A.S.S.I.S.T.
                       1,0 con preparación real}
```

**El choque de credibilidad.** Si el propietario original está vivo y presente en la sala, puede acusar públicamente al jugador. La resolución es un contraste de credibilidad:

```
credibilidad_acusador = reputación_acusador
                      + 20 × número_de_personajes_con_creencia_"la_idea_era_suya"

credibilidad_jugador  = reputación_jugador
                      + 15 × número_de_aliados_presentes
                      − 0,5 × sospecha_jugador
```

| Resultado | Condición | Consecuencia |
|---|---|---|
| **Victoria del jugador** | Diferencia superior a 20 puntos a su favor | La idea le pertenece. **El acusador queda como usurpador: su reputación desciende 15 puntos.** |
| **Empate** | Diferencia inferior a 20 puntos | Nadie obtiene mérito. Ambos incrementan sospecha en 10 puntos. |
| **Derrota del jugador** | Diferencia superior a 20 puntos en contra | La idea revierte al propietario. **Reputación del jugador −20 y creación de una creencia de certeza 0,85: «este roba ideas»**, que se propaga por el grafo. |

Esta mecánica es la que justifica la existencia de cinco vías de adquisición en lugar de una. Presentar la idea de un personaje que sigue sentado en la sala exige haber preparado previamente el terreno —cultivando aliados, degradando su reputación— o haber garantizado su ausencia.

### 11.3 Inventario y contrabando

**Capacidad: ocho posiciones.** El jugador no puede transportar simultáneamente todo lo que sustrae.

| Categoría | Ejemplos | Consecuencia en un registro corporal |
|---|---|---|
| **Ordinario** | Llaves, estampa, teléfono, alimentos, tarjeta propia | Ninguna |
| **Comprometedor** | Producto robado, documentos ajenos, tarjeta de otro empleado, uniforme sustraído, pasamontañas, documentos de propiedad | **Evidencia definitiva de peso 10. El caso se cierra en contra del jugador.** |

**Ubicaciones de ocultación:**

| Ubicación | Seguridad | Inconveniente |
|---|---|---|
| Escritorio propio (3B) | Muy baja | Primera ubicación que registra cualquier investigación |
| Taquilla de vestuario | Media | Requiere acceso al vestuario correspondiente |
| **Archivo muerto (S2)** | **Alta** | Una investigación que registre sótanos lo localiza en fase 2 |
| Conductos de ventilación | Alta | Recuperación lenta e incómoda |
| Cuartos de limpieza | Media | Connie Marks accede a ellos diariamente |
| **Muelle de basuras (S1)** | **Absoluta** | **Irreversible: el objeto sale del juego** |

**Registro corporal.** Security puede registrar al jugador si su sospecha supera un umbral o si existe una investigación abierta que lo incluya en la lista corta. Transportar material comprometedor con sospecha elevada es la causa de derrota más evitable del juego.

### 11.4 Disfraces y gestión de identidad

Tres uniformes disponibles en los vestuarios del sótano primero: seguridad, limpieza y mantenimiento.

| Distancia de observación | Efecto del uniforme |
|---|---|
| **Superior a 6 metros** | El personaje clasifica al jugador por el uniforme. Un limpiador a las 20:00 es funcionalmente invisible. |
| **Inferior a 3 metros** | **Los personajes que conocen al jugador lo reconocen.** El disfraz no engaña a sus once compañeros de ala ni a ningún personaje con Perspicacia superior a 70. |
| **Cámaras** | Registran el uniforme, no la identidad. **Salvo que una investigación cruce el registro de acceso con el cuadrante de turnos**, procedimiento que sí ejecuta en fase 2. |

**Coherencia contextual.** El uniforme se evalúa contra la hora y la ubicación. Un limpiador en la planta 16 a las 14:00 genera más sospecha que el propio jugador sin disfraz. El uniforme funciona exclusivamente en su franja y su zona.

**Nota de diseño.** El uniforme de limpieza es el objeto de mayor valor táctico del juego durante los tres primeros escalones. Su utilidad supera la de cualquier promoción de ese tramo, lo que refuerza mecánicamente el sentido de los movimientos laterales.

### 11.5 Los compradores

Los compradores visitan la sala de demostraciones de la planta 11 según un calendario. Son personajes con rasgos propios, no interfaces de menú.

| Operación | Beneficio para el jugador | Riesgo |
|---|---|---|
| **Venta honesta** | Comisión legal reducida | Ninguno |
| **Sobreprecio** | Diferencia íntegra al bolsillo | El comprador puede reclamar semanas después; contabilidad lo detecta |
| **Venta fantasma** | Importe completo | Alto: el inventario no cuadrará en el cierre mensual |
| **Descuento con mordida** | Pago directo del comprador | Medio, y el comprador adquiere material de chantaje |

La resolución depende de los rasgos del comprador: uno con Perspicacia elevada detecta el sobreprecio en el acto; uno con Codicia elevada acepta la mordida sin objeción.

### 11.6 Robo en fábrica: las tres escalas

| Escala | Volumen | Requisitos | Ingreso aproximado | Rastro |
|---|---|---|---|---|
| **Bolsillo** | 1–2 pares | Estar dentro de la nave (R3+) | 40–80 € | Prácticamente ninguno |
| **Caja** | 10–20 pares | Carrito o acceso al montacargas (R8+) | 400–900 € | Detectable en el inventario semanal |
| **Palé** | 200–400 pares | Capataz o Director de Fábrica (R15+) más transportista cómplice | 8.000–18.000 € | **Visible en los márgenes de la compañía. El CFO lo detecta.** |

**El inventario semanal como mecanismo de consecuencia retardada.** Los robos no se detectan en el momento: afloran en el recuento posterior. Este retardo convierte el robo en una decisión estratégica con horizonte temporal, no en un botón de generación de capital.

**Incriminación.** Los albaranes del almacén se pueden falsificar para que el descuadre apunte al superior directo. Su expulsión libera la vacante, pero la sospecha sobre el jugador se incrementa porque también tenía acceso.

### 11.7 Descontento laboral y huelgas

El descontento es un valor global de 0 a 100 que agrega el estado de ánimo de los personajes de escalones 1 a 3.

| Factor | Efecto sobre el descontento |
|---|---|
| Despido percibido como injusto | +5 por caso |
| Cuota de producción por encima de lo razonable | +2 por jornada |
| Manipulación de nóminas descubierta | +10 |
| Condiciones de fábrica degradadas | +3 por jornada |
| Concesión salarial | −15 (coste económico directo) |
| Despido del causante del malestar | −10 |

Buena parte de esos factores los provoca el propio jugador cuando ocupa cargos de dirección.

**Acciones disponibles:**

| Acción | Requisito | Resultado |
|---|---|---|
| **Agitar** | Conversar con personajes descontentos; plantar rumores contra la dirección | Acelera el incremento del descontento |
| **Apaciguar** | Concesiones económicas o despido del causante | Reduce el descontento |
| **Liderar la huelga** | Descontento superior a 70 | Reputación muy alta entre escalones 1–3; muy baja ante dirección |
| **Traicionarla** | Haberla convocado y no comparecer, deteniéndola | **Reputación ante dirección muy alta: el jugador figura como quien salvó la compañía.** Reputación permanentemente destruida entre los escalones bajos. |

Durante una huelga activa: producción detenida, factor de riesgo al alza, noticia negativa publicada, cotización a la baja. Es un evento que opera sobre ambos cerebros simultáneamente.

### 11.8 La secuencia final: apropiación de la compañía

> Constituye el clímax del juego y la única secuencia con estructura de misión definida. La decisión es deliberada: tras veinte horas de sistemas abiertos, el desenlace requiere forma.

**Fase primera: revelación del objetivo.** Únicamente desde el puesto de Director Legal (R26) o superior el jugador descubre qué documentos transfieren la propiedad y qué procedimiento los valida. Con anterioridad, el segundo objetivo permanece oculto: el jugador sabe que quiere apropiarse de la compañía pero no cómo.

**Fase segunda: obtención de la combinación.** La caja fuerte del despacho requiere una combinación que solo conoce Harlan Voss. Tres vías:

| Vía | Procedimiento | Riesgo |
|---|---|---|
| **Pearl Osgood** | La secretaria la conoce. Arquetipo `company_man` con Lealtad 95: el soborno es inviable. Requiere chantaje —material obtenido de su expediente en RRHH— o un favor de magnitud extraordinaria. | Si el intento fracasa, informa directamente a Voss, que activa vigilancia personal sobre el jugador |
| **Archivos de Voss** | Está anotada en su despacho o su ordenador privado. Requiere permanencia prolongada en la sala. | Es el espacio con mayor densidad de vigilancia del edificio |
| **Procedimiento físico** | Como Director de Seguridad o de Mantenimiento existen medios materiales de apertura. | Ruidoso, lento y evidente: garantiza investigación posterior |

**Fase tercera: la ventana temporal.** Voss ocupa el despacho de 10:00 a 17:00 con interrupciones por reuniones. El jugador puede consultar su agenda desde el organigrama, o provocar reuniones prolongadas si ocupa el puesto de Coordinador de reuniones. Existen tres accesos: la puerta principal, la terraza de la azotea y el conducto del cuarto de máquinas.

**Fase cuarta: custodia de los documentos.** Los documentos son un objeto **comprometedor**. Transportarlos con sospecha elevada equivale a perder la partida en el siguiente registro. El jugador puede ocultarlos y regresar posteriormente.

**Fase quinta: la notaría.** El paso que la mayoría de jugadores no anticipa. **Los documentos carecen de validez sin formalización.** La notaría interna de la planta 9 requiere:

- Que el jugador ostente el cargo de consejero delegado, **o** presente una autorización que lo acredite —falsificable con la estampa si su reputación es suficiente.
- Un notario dispuesto a firmar. Es un personaje con rasgos propios: con reputación elevada firma sin verificación; con sospecha elevada solicita comprobación, lo que abre un plazo de tres jornadas durante el cual el jugador es máximamente vulnerable.

**Fase sexta: resolución.** Formalizada la transferencia, se evalúa el estado del tracking y de la compañía, y se dispara el epílogo correspondiente.

## 12. Riesgo y consecuencias

### 12.1 Los tres niveles de peligro

| Nivel | Naturaleza | Escala temporal | Sección |
|---|---|---|---|
| **1. Detección** | Un personaje identifica al jugador en el momento | Segundos | 12.2 |
| **2. Investigación** | El sistema construye un caso acumulando evidencia | Jornadas o semanas | 12.3–12.6 |
| **3. Resolución terminal** | El caso concluye, o se agota la supervivencia | Fin de partida | 12.7 |

Los niveles se alimentan secuencialmente. Resolver correctamente una detección no elimina el rastro: únicamente evita el problema inmediato.

### 12.2 Flagrancia: las dos salidas

**Distinción fundamental del sistema.**

| Estado | Condición | Consecuencia |
|---|---|---|
| **Percepción parcial** | Contador de detección entre 0,45 y 1,00 | Creencia de certeza 0,35. **Sin confrontación.** Constituye aproximadamente el noventa por ciento de las detecciones del juego. |
| **Flagrancia** | Contador en 1,00 **y** el jugador ejecutando un acto indebido | Certeza plena. Se activa la ventana de decisión. |

**Función del esprint.** Correr sirve para **impedir que la identificación se complete**, rompiendo la línea de visión antes de alcanzar el umbral. Una vez declarada la flagrancia, huir no elimina la creencia: el personaje conoce la identidad del jugador y su ubicación habitual.

**Opción primera: soborno inmediato.**

Aplica la fórmula de 8.2 con multiplicador ×20.

| Resultado | Consecuencia |
|---|---|
| **Aceptación** | No se produce denuncia. **La creencia se conserva íntegra y el personaje adquiere material de chantaje sobre el jugador.** Comprar silencio no es comprar olvido. |
| **Rechazo con denuncia** | Expulsión inmediata. Fin de partida. |
| **Rechazo silencioso** | Creencia de certeza 0,9 y capacidad de chantaje futuro |
| **Contraoferta** | Nuevo precio entre 1,3 y 1,8 veces el original |
| **Capital insuficiente** | La opción aparece deshabilitada |

**Opción segunda: eliminación.**

| Condición | Estado de la opción |
|---|---|
| Ningún otro personaje con línea de visión | Disponible |
| **Existencia de testigos** | **Deshabilitada y marcada visualmente en rojo.** El diseño impide que el jugador pierda la partida por un error de interfaz. |

Consecuencias de la eliminación: se genera un objeto cuerpo que requiere ocultación, con su cadena de evidencia asociada —manchas, registro horario de acceso, último contacto conocido, y el hueco que el personaje deja en las rutinas del edificio. Se abre una investigación de gravedad máxima en el momento en que su ausencia se detecta, habitualmente en la jornada siguiente.

**Inacción: la tercera consecuencia.** Si el jugador no elige en el plazo establecido, el personaje actúa según su arquetipo mediante la función de utilidad:

| Arquetipo | Acción resultante | Efecto |
|---|---|---|
| `hardliner`, `snitch`, `incorruptible` | Acude a Security | Sospecha +20 y probable apertura de investigación |
| `company_man` | Informa a su superior directo | Sospecha +10 y anotación en expediente |
| `gossip` | Lo comenta en la franja de comida | Propagación amplificada por el grafo |
| `coward` | Silencia y conserva la información | Chantaje posterior: solicitará capital, promoción o un favor |
| `burnout`, `oblivious` | Probabilidad significativa de desinterés | Ninguna consecuencia |

**La inacción es una decisión legítima y en ocasiones óptima.** Si el personaje que descubre al jugador es un `burnout`, invertir capital en sobornarlo constituye un desperdicio.

**Reasignación de las herramientas iniciales.** Las llaves cumplen su función literal: abrir puertas. La estampa es el instrumento de falsificación documental —autorizaciones, permisos de acceso, formularios de expulsión, y la autorización de la notaría en la secuencia final.

### 12.3 Las investigaciones: cinco fases

Una investigación es un agente con estado propio que progresa por fases. El jugador puede intervenir en todas.

**Fase 1 — Incidente.** Un evento supera el umbral de apertura de 3,0 puntos de evidencia.

| Disparador | Peso inicial |
|---|---|
| Desaparición de objeto de valor | 2,5 |
| Descuadre de inventario | 2,0 |
| Cuerpo hallado | 12,0 |
| Fraude aflorado en cierre mensual | 4,0 |
| Denuncia de un testigo directo | 4,0 |
| Patrón de información privilegiada | 6,0 |

*Palanca del jugador:* impedir que se produzca el incidente. Inventario compensado, cuerpo correctamente oculto, fraude de magnitud reducida.

**Fase 2 — Recogida de evidencia.** Duración de dos a diez jornadas según gravedad. El investigador ejecuta tres procedimientos:

1. **Interrogatorio de testigos:** consulta el grafo de creencias y recopila toda creencia relacionada con el incidente.
2. **Revisión de grabaciones:** examina las cámaras de las zonas relevantes en la franja horaria correspondiente.
3. **Registro físico de salas:** recorre las ubicaciones por orden de probabilidad. **Es la fase en la que aflora un cuerpo mal oculto o un objeto escondido en el archivo muerto.**

*Palancas del jugador:* borrar grabaciones antes de la revisión, trasladar el objeto o el cuerpo, sobornar al testigo principal, construir una coartada con un aliado del registro de relaciones.

**Fase 3 — Lista corta.** Se ordenan de uno a tres sospechosos según el peso de evidencia acumulado:

```
peso_sospechoso = Σ (peso_pieza × certeza_pieza)
                + 2,0 si tenía acceso a la ubicación
                + 1,5 si obtuvo beneficio del hecho
                + 3,5 si fue el último en salir del edificio
```

*Palancas del jugador:* incriminar a otro personaje —plantando el objeto en su taquilla, falsificando su registro de acceso o dirigiendo un rumor—, obtener declaraciones favorables de aliados, o beneficiarse de una reputación elevada que reduzca el peso inicial de su nombre.

**Fase 4 — Interrogatorio.** Si el jugador encabeza la lista corta, se ejecuta la escena de 12.5.

**Fase 5 — Veredicto.**

| Resultado | Condición | Consecuencia |
|---|---|---|
| **Archivo sin culpable** | Peso máximo inferior a 7,0 | El caso queda **frío**, no cerrado (*ver 12.6*) |
| **Culpabilidad de otro** | Otro sospechoso supera 7,0 | Expulsión de ese personaje. Si era inocente, agravio permanente y hostilidad de sus aliados. |
| **Culpabilidad del jugador, grado leve** | Peso entre 7,0 y 10,0 | Descenso de rango, pérdida de acreditación, sospecha máxima durante varias semanas |
| **Culpabilidad del jugador, grado grave** | Peso superior a 10,0 | **Fin de partida** |

### 12.4 Tabla de pesos de evidencia

| Pieza | Peso | Permanencia | Método de destrucción |
|---|---|---|---|
| Testigo directo | 4,0 | Decae lentamente | Soborno, chantaje, expulsión, eliminación |
| Testigo parcial | 0,8 | Decae en días | Se olvida por sí solo |
| **Grabación de cámara** | **4,5** | **Permanente** | Borrado en la sala de monitores |
| Registro de acceso por tarjeta | 2,5 | Permanente | Emplear rutas sin lector o tarjeta ajena |
| **Objeto comprometedor en posesión** | **10,0** | Inmediata | Deshacerse de él antes del registro |
| Rastro contable | 3,0 | Permanente, con retardo | Falsear asientos o cerrar la auditoría |
| Rumor sin fuente identificada | 0,3 | Decae | Contrarrumor o intervención de Comunicación |
| **Cuerpo hallado** | **12,0** | **Permanente** | No existe destrucción |
| Documento falsificado verificado | 5,0 | Permanente | Ninguna |

**Modulación por sospecha.** La sospecha global del jugador reduce el umbral de todas las fases en `0,03 × sospecha`. Con sospecha 80, el umbral de apertura desciende de 3,0 a 0,6: prácticamente cualquier incidente abre caso.

### 12.5 La escena de interrogatorio

Se desarrolla en la sala de la planta 15. El investigador —por defecto Rose Miller, o quien ocupe Auditoría o Seguridad— presenta las piezas de evidencia de forma secuencial. El jugador responde a cada una.

| Respuesta | Requisito | Efecto |
|---|---|---|
| **Negar** | Ninguno | Elimina la pieza si `reputación > 60` y `peso_pieza < 2,0`. En caso contrario, incrementa la sospecha. |
| **Explicar** | Coartada real o adquirida | Elimina la pieza. Si la coartada se verifica y resulta falsa, el peso se duplica. |
| **Acusar a otro** | Ninguno | Traslada la pieza al acusado. **Genera agravio permanente y hostilidad de sus aliados.** |
| **Silencio** | Ninguno | No incrementa el peso, pero eleva la sospecha en 5 puntos por uso |
| **Solicitar asistencia legal** | Contacto en el bufete de la planta 9 | **Congela el caso tres jornadas**, tiempo utilizable para destruir evidencia |

**Condición de éxito:** reducir el peso total del caso por debajo de 7,0.

**Detalle de tono.** Con reputación superior a 85, el interrogatorio se abre con una disculpa del investigador por la molestia. Con sospecha superior a 70, se abre con la puerta cerrándose de golpe. Es el mismo sistema con distinta presentación, y comunica al jugador su posición social sin necesidad de interfaz.

### 12.6 Casos fríos

Un caso archivado conserva íntegra su evidencia como registro permanente. Puede reactivarse por tres vías:

| Disparador | Probabilidad |
|---|---|
| Aparición de una pieza nueva | Determinista: si aparece, revive |
| Un testigo silencioso cambia de posición | Proporcional al agravio acumulado desde el archivo |
| **Cambio de ocupante en Auditoría** | 40% de revisión de expedientes archivados |

**Consecuencia de diseño: el juego posee memoria de largo alcance.** Un delito de la jornada quinta puede resolver la partida en la jornada cuarenta, cuando el jugador ocupa un cargo en el que un escándalo no produce descenso sino expulsión. Es también la justificación mecánica del valor del puesto de Auditor Jefe: es el único desde el que los casos fríos se cierran de forma definitiva.

### 12.7 Permadeath

**Especificación.** Al producirse cualquier condición terminal, la partida concluye de forma irreversible. No existe reanimación, no existe carga de un estado anterior. El jugador regresa a la secuencia de graduación e inicia un personaje nuevo en el rango R1, sin capital, sin rango y sin contactos.

**Estado del mundo en la partida siguiente: variante A — mundo limpio.** La nueva partida se desarrolla en una instancia completamente nueva de Stellar Sell. Todos los personajes regresan a su posición original, todas las vacantes se restauran, la compañía recupera su estado inicial y nada de la partida anterior persiste.

**Justificación de la variante elegida.** Tres razones: pureza estratégica, ya que cada partida constituye un problema limpio que permite ensayar estrategias distintas desde una posición idéntica; máxima dureza, coherente con el resto del diseño; y simplicidad técnica, al no requerir persistencia del estado del mundo entre partidas.

**Elementos persistentes:** exclusivamente la configuración del jugador y la galería de finales desbloqueados, que constituyen metainformación del jugador y no del personaje.

**Guardado.** Al dormir, en un único archivo que se sobrescribe. No existe la posibilidad de guardar y cargar para deshacer decisiones. La totalidad de la tensión del juego depende de la irreversibilidad.

### 12.8 El sistema de seguimiento invisible

Cinco contadores que el juego incrementa sin comunicarlo al jugador.

| Eje | Incrementos | Interpretación |
|---|---|---|
| **SANGRE** | +10 por eliminación · +5 por cuerpo ocultado · +3 por violencia sin muerte | Coste humano del ascenso |
| **ORO** | +1 por cada 1.000 € en sobornos · +1 por cada 2.000 € robados · +5 por fraude ejecutado | Grado de compra del camino |
| **SEDA** | +8 por idea robada · +5 por incriminación exitosa · +3 por rumor plantado · +5 por documento falsificado | Grado de manipulación no detectada |
| **SUDOR** | +2 por deber cumplido honestamente · +10 por informe real · +5 por presentación preparada | **El eje irónico** |
| **RUINA** | +1 por cada punto de pérdidas · +5 por talento expulsado · +10 por escándalo no enterrado | Estado en que se deja la compañía |

Los cuatro primeros determinan el estilo dominante. **RUINA es independiente** y modifica el epílogo de cualquier final de victoria.

### 12.9 Los nueve finales

**Condición de victoria plena:** ostentar el cargo R33, poseer los documentos de propiedad y haberlos formalizado en la notaría.

**Finales de victoria plena (cinco), según eje dominante:**

| Final | Eje | Contenido del epílogo |
|---|---|---|
| **THE BUTCHER** | Sangre | La compañía le pertenece y la plantilla le teme. El epílogo enumera nominalmente a quienes «se marcharon» durante su ascenso y detalla cómo la prensa nunca estableció la conexión. |
| **THE BUYER** | Oro | Todo el mundo le debe algo o le ha vendido algo. Es propietario y simultáneamente rehén de su propia red de comprados: el epílogo cuestiona quién ejerce el poder real cuando todos cobran del mismo pagador. |
| **THE GHOST** | Seda | Nadie sabe cómo llegó. El epílogo es una secuencia de todos los que asumieron la responsabilidad en su lugar, ninguno de los cuales sabe que existe un responsable distinto. |
| **THE WORKER** | Sudor | **El final que da título al juego.** Hizo tantas trampas y trabajó tanto que resulta ser competente. Se propuso ascender sin trabajar y terminó siendo el empleado más productivo de Stellar Sell. |
| **THE FULL SUITE** | Híbrido | Empleó todos los recursos disponibles. El epílogo lo retrata como el consejero delegado ideal según el manual corporativo, y esa es la totalidad del chiste. |

**Finales de victoria parcial (dos):**

| Final | Condición | Contenido |
|---|---|---|
| **THE FIGUREHEAD** | Cargo sin documentos | Ocupa la silla pero la compañía pertenece a otros. Percibe una fortuna y no posee nada: exactamente el trabajo que pretendía evitar, con mejor despacho. |
| **THE OWNER IN EXILE** | Documentos sin cargo | Obtuvo los papeles pero cayó antes de coronarse. Es propietario legal de una compañía en la que no puede entrar. Deberá litigar, y litigar es trabajar. |

**Finales de derrota (dos):**

| Final | Condición | Contenido |
|---|---|---|
| **THE FILE** | Investigación concluyente | El epílogo es el informe final de la investigación, redactado por quien lo capturó, con la totalidad de las pruebas ordenadas cronológicamente. **La derrota narrada por el adversario.** |
| **THE GAP** | Inanición o fracaso en R0 | No fue descubierto: simplemente no llegó. El epílogo es su propio hueco en el organigrama, cubierto la semana siguiente por otro recién graduado. **La compañía no registró su paso.** |

**Modificador de ruina.** Los siete finales de victoria poseen dos versiones según el valor final del eje RUINA: *imperio*, si la compañía conserva valor, o *cascarón*, si fue vaciada. No altera la victoria; altera su contenido.

## 13. Interfaz y experiencia de usuario

> **Principio rector: la interfaz es diegética.** Todo elemento que el jugador consulta existe dentro de la ficción como software corporativo deficiente. El HUD, por contraste, es mínimo: el protagonista de la pantalla es el edificio.

### 13.1 El HUD

| Posición | Elemento | Comportamiento |
|---|---|---|
| Superior izquierda | Reloj y jornada | Permanente. Es la información más consultada del juego. |
| Superior derecha | Capital disponible | Permanente |
| Inferior izquierda | Rango actual y barra doble de Reputación y Sospecha | Permanente. Reputación en azul, Sospecha en rojo. |
| Inferior derecha | Deberes de la jornada | Plegable. Los cumplidos se tachan. |
| Centro inferior | Indicación contextual de acción | Solo aparece cuando existe una acción disponible |

### 13.2 El indicador de detección

El elemento más importante de la interfaz. Sobre cada personaje con línea de visión hacia el jugador aparece un indicador que refleja el estado del contador de detección.

| Estado | Representación | Significado |
|---|---|---|
| Sin contacto | Ausente | El personaje no percibe al jugador |
| **En progreso** | Círculo parcialmente lleno, amarillo, con muesca creciente | **Existe margen para huir u ocultarse.** Romper la línea de visión lo vacía. |
| **Percepción parcial** | Círculo completo, naranja | Se ha generado una creencia de baja certeza. Sin confrontación. |
| **Flagrancia** | Círculo completo con signo de exclamación, rojo | Ventana de decisión activa |

**Requisito de accesibilidad:** los cuatro estados se distinguen por forma además de por color.

**Indicadores complementarios:** halo rojo en el perímetro de la pantalla cuando el jugador se encuentra en una zona que su acreditación no cubre; icono de cámara cuando está dentro del campo de una.

### 13.3 StellarOS: el ordenador

Interfaz a pantalla completa que emula un sistema operativo corporativo obsoleto. **La calidad del equipo mejora con el rango:** el terminal de R1 tarda en arrancar y muestra publicidad interna; el de R33 responde de inmediato. La progresión de esa mejora es un elemento humorístico deliberado y debe resultar perceptible.

| Aplicación | Función | Disponible desde |
|---|---|---|
| **MAIL** | Correspondencia corporativa absurda. Responder constituye el deber de volumen de los rangos base. | R1 |
| **NOTEBOOK** | Cuaderno de estrategia: notas libres del jugador más registro automático de objetivos marcados, favores pendientes y casos abiertos. Es la memoria externa del jugador en una partida de veinte horas. | R1 |
| **PERSONNEL** | Expedientes de personal, con el nivel de detalle que permita la acreditación. | R1 |
| **A.S.S.I.S.T.** | Generación automática de trabajo con resultado aleatorio y rastro digital. | R1 |
| **PORTAL** | Organigrama completo con la ocupación de cada silla y **la identificación de las vacantes**. Es donde el jugador localiza el hueco que debe ocupar, o generar. | R1 |
| **FILES** | Archivos propios y, según rango o intrusión, ajenos. | R1 |
| **MARKET** | Cotización, calendario de resultados, inversores con su nivel de confianza, cartera personal. | R25 |

### 13.4 El expediente de personal

Escala de detalle según acreditación. La información constituye una recompensa de progresión equiparable al acceso a salas.

| Acreditación | Contenido visible |
|---|---|
| **N1** | Nombre, fotografía, puesto, planta y ala. Equivale al organigrama público. |
| **N2** | Añade rutina aproximada por franjas y una descripción cualitativa del carácter en lenguaje natural. |
| **N3** | Añade los seis rasgos representados como barras y los vínculos sociales principales. |
| **N4** | Añade la debilidad explotable identificada y el historial de relación con el jugador. |
| **N5** | Añade valores numéricos exactos, expediente disciplinario y **precio estimado de soborno**. |
| **N6–N7** | Añade secretos personales, domicilio —lo que habilita las operaciones nocturnas— y **el registro de relaciones del personaje hacia otros personajes**: el mapa completo de la política interna. |

**Vías de acceso anticipado:** intrusión en Recursos Humanos concede el expediente completo de un personaje concreto con independencia del rango; ocupar un puesto en RRHH concede acceso permanente; el Director de IT accede a comunicaciones privadas; el chantaje sobre un personaje revela su expediente íntegro.

**Funciones de la aplicación:** búsqueda por nombre, filtrado por planta, arquetipo, rango o categoría funcional —«sobornables», «peligrosos», «deudores»—, ordenación por cualquier rasgo visible, marcado de objetivos con reflejo en mapa y HUD, comparación simultánea de dos personajes, y anotaciones del jugador vinculadas al cuaderno.

**Acción de estudio.** Consume entre quince y treinta minutos de tiempo de juego y proporciona una predicción del comportamiento del personaje ante una acción concreta. El tiempo es el recurso más escaso del juego: estudiar exhaustivamente a ciento cincuenta personas es imposible, lo que fuerza la priorización.

### 13.5 El teléfono móvil

Se presenta como superposición, no como pantalla completa: **el jugador permanece expuesto mientras lo utiliza**, y hacerlo en presencia de un superior genera sospecha.

| Pestaña | Función | Coste |
|---|---|---|
| **CONTACTOS** | Los números disponibles. Se obtienen trabajando en proximidad, mediante favores, desde RRHH o por compra. **Un directivo no responde a un jugador de rango muy inferior.** | — |
| **CHAT** | Comunicación escrita. **Genera registro digital permanente** consultable por el Director de IT. | Riesgo documental |
| **LLAMADA** | Comunicación oral sin registro escrito. **Requiere privacidad física.** Los baños y las escaleras de servicio son los únicos espacios seguros. | Riesgo de escucha |

**Interfaz de soborno:** selección de contacto, selección de favor, y ajuste de la cantidad mediante control deslizante. Con acreditación N5 o superior se muestra el precio estimado; por debajo, el jugador opera sin información.

### 13.6 El mapa

Representación en **corte vertical del edificio**, mostrando simultáneamente las veinte plantas, los tres sótanos y la nave anexa. Constituye la imagen identificativa del juego.

| Elemento | Representación |
|---|---|
| Acceso permitido | Verde |
| Acceso mediante método alternativo | Ámbar |
| Acceso vetado | Rojo |
| Personajes conocidos | Punto, solo si su rutina está desbloqueada |
| Objetivos marcados | Punto destacado |

**Capas activables:** cámaras, rutas alternativas, ocupación por franja horaria.

**Zoom a planta:** plano detallado con distribución de salas y alas.

**Nota de tono:** el mapa se presenta como el plano de evacuación de incendios de la compañía. El jugador lo emplea para el propósito inverso.

### 13.7 Controles

**PC:**

| Entrada | Acción |
|---|---|
| WASD | Desplazamiento en ocho direcciones |
| Doble pulsación de dirección o doble clic | Esprint |
| Shift mantenido | Desplazamiento sigiloso |
| Ctrl | Agacharse |
| E | Interactuar |
| Tab | Mapa |
| C | Ordenador (solo en el escritorio propio) |
| M | Teléfono móvil |
| F1 | Panel de depuración durante el desarrollo |

**Android:**

| Entrada | Acción |
|---|---|
| Stick virtual izquierdo | Desplazamiento |
| Doble toque en el stick | Esprint |
| Botón contextual grande, inferior derecha | Acción disponible; el icono cambia según contexto |
| Barra inferior deslizable | Acceso a mapa, ordenador y móvil |
| Toque sobre un personaje | Ficha rápida según nivel de acreditación |

**Requisito común:** ninguna acción irreversible se ejecuta con una sola pulsación. Todas requieren confirmación explícita.

### 13.8 El tutorial

Se desarrolla en la sala de formación de la planta 1 y no supera los diez minutos. Es saltable en partidas posteriores.

**Primera parte: el vídeo corporativo.** Una grabación de bienvenida presentada por un Harlan Voss quince años más joven, saturada de terminología vacía. Mientras se reproduce, el jugador aprende a desplazarse por la sala. **El vídeo es el tutorial de movimiento y en ningún momento se declara como tal.**

**Segunda parte: el recorrido al puesto.** Un empleado de Recursos Humanos acompaña al jugador y le explica, sin advertirlo, todo lo necesario para delinquir: la ubicación de su tarjeta, la función de las llaves, el procedimiento de fichaje, la enumeración de las zonas restringidas —que constituye la lista de objetivos— y el horario de comida.

**Tercera parte: la primera jornada.** Tres tareas encadenadas que enseñan el bucle completo: enviar tres correos, observar a Claudia Reeves generando una idea, y ocultarse al paso de Bernard Lasker. **El juego no instruye al jugador para que robe: le demuestra que puede.**

### 13.9 La secuencia de apertura

Aproximadamente noventa segundos, sin diálogo hablado —únicamente texto y sonido, lo que reduce el coste de producción y simplifica la localización.

**Primer movimiento: la graduación.** Birrete al aire. Se despliega un abanico de ofertas de empleo, todas atenuadas salvo una: Stellar Sell. El jugador la elige. Es la única elección de la secuencia, y es falsa: no existe alternativa.

**Segundo movimiento: el traslado.** Autobús, calle, y la torre emergiendo entre la neblina hasta ocupar la pantalla completa. El personaje eleva la mirada: veinte plantas de jerarquía sobre su cabeza.

**Tercer movimiento: el acceso.** Cruza los torniquetes. Título y lema.

### 13.10 Accesibilidad

| Requisito | Especificación |
|---|---|
| Tamaño de texto | Ajustable en tres niveles. Crítico en la versión móvil. |
| Contraste | Modo de alto contraste para los indicadores de detección |
| Daltonismo | Todos los estados críticos se distinguen por forma además de color |
| Velocidad temporal | El ritmo del reloj es ajustable independientemente de la dificultad |
| **Subtitulado sonoro** | **Todo sonido con función informativa dispone de subtítulo descriptivo.** Requisito crítico: en este juego el audio transporta información de sigilo. |

---

# PARTE V — DIRECCIÓN DE ARTE Y SONIDO

## 14. Especificación visual y sonora

> **Principio rector: el arte y el sonido cumplen función informativa, no decorativa.** Con ciento sesenta y seis espacios y ciento cincuenta personajes, el jugador debe poder determinar de un vistazo dónde se encuentra, con quién y en qué grado de riesgo. Cada decisión estética de esta sección tiene una justificación mecánica.

### 14.1 Perspectiva

**Durante el juego: cenital 3/4.** Cámara elevada con inclinación moderada.

| Razón | Justificación mecánica |
|---|---|
| Legibilidad de los conos de visión | Es la única perspectiva en la que el jugador percibe con exactitud el campo visual de cada personaje. Sin ella, el sigilo no resulta equitativo. |
| Movimiento bidimensional | Las salas se convierten en espacios que se recorren y rodean, no en corredores lineales. Necesario con ciento sesenta y seis espacios. |
| Visibilidad de rostro y hombros | La inclinación permite expresión facial y, sobre todo, que la silueta comunique el rango. |

**Fuera del juego: corte vertical de la torre.** El mapa, las transiciones de ascensor, la pantalla de promoción y el organigrama emplean una sección del edificio con las veinte plantas apiladas. Comunica de forma inmediata el principio organizador del juego.

### 14.2 Dirección de arte

**Estilo: vectorial plano con contorno.** Formas limpias, colores planos, contornos definidos, sombras simples.

| Justificación | Detalle |
|---|---|
| **Escalabilidad de producción** | Permite composición modular de ciento cincuenta personajes y ciento sesenta y seis salas |
| **Legibilidad** | Las formas planas con contorno se distinguen sin esfuerzo en cenital y en pantalla reducida |
| **Independencia de resolución** | Nitidez equivalente en 4K y en pantalla móvil sin duplicar recursos |
| **Viabilidad de producción** | **Una proporción sustancial del arte se genera por código**, lo que elimina la dependencia de recursos externos concretos |
| **Coherencia con el registro** | Permite que la comedia negra se lea como absurdo y no como violencia explícita |

**Regla operativa: silueta antes que detalle.** Cualquier elemento que no se reconozca por su contorno a tamaño reducido debe rediseñarse.

### 14.3 Paletas por banda de planta

| Banda | Plantas | Paleta | Iluminación | Efecto buscado |
|---|---|---|---|---|
| `the_guts` | S3–S1 | Grises sucios, óxido, verde de señalización de emergencia | Focos aislados, grandes zonas en penumbra | Abandono; espacios que nadie inspecciona |
| `the_pit` | PB–P5, fábrica | **Gris fluorescente y verde enfermizo.** Moqueta con manchas, plástico beige | Tubos fluorescentes con parpadeo intermitente | Anonimato y fatiga. **El punto de partida del jugador.** |
| `the_specialists` | P6–P12 | Azules corporativos, blancos limpios, acentos de marca | Iluminación uniforme y suficiente | Actividad y competencia |
| `the_power` | P13–P17 | Maderas cálidas, moqueta de calidad, azul marino, latón | Iluminación indirecta | Silencio y capital. Alfombras que absorben el sonido de los pasos. |
| `the_throne` | P18–P20, azotea | Oro atenuado, mármol, cristal, cuero negro | Luz natural abundante desde ventanales | Altitud, y la evidencia de que aquí nadie trabaja |

**Refuerzos satíricos integrados en la paleta:**

| Elemento | Comportamiento por banda |
|---|---|
| Densidad de ocupación | Desciende monótonamente al ascender. **El espacio por persona es la representación material del privilegio.** |
| Nivel de ruido ambiente | Desciende en paralelo |
| Plantas ornamentales | De plástico en las bandas bajas; naturales en las altas |
| Carteles motivacionales | Frecuencia máxima en `the_pit`, nula en `the_throne` |

**Excepción de contraste: la nave fabril.** Naranjas de maquinaria, chispas, partículas en suspensión. Es el único espacio del juego donde se produce algo material, y debe resultar visualmente evidente.

### 14.4 Composición modular de personajes

Cada personaje se ensambla en tiempo de carga a partir de capas seleccionadas por datos.

| Capa | Variantes | Determina |
|---|---|---|
| Constitución | 6 | Altura y anchura |
| Cabeza y rasgos | 20 | Estructura facial, edad aparente |
| Cabello y vello facial | 25 | Personalidad y edad |
| Tono de piel | 8 | Diversidad de plantilla |
| **Vestuario por rango** | 8 | **El rango resulta visible sin interfaz** |
| Accesorios | 15 | Gafas, tarjeta colgada, taza, carpeta, auriculares, carrito |
| Paleta de vestuario | 12 | Variación individual dentro del uniforme de clase |

El espacio combinatorio excede las cuatrocientas mil combinaciones. Los personajes nominados emplean combinaciones reservadas más un accesorio identificativo único.

### 14.5 La silueta como indicador de rango

El escalón de cualquier personaje debe ser determinable a distancia sin recurrir a la interfaz.

| Escalón | Silueta | Elementos |
|---|---|---|
| **1–2** | Encorvada, ropa amplia sin estructura, desplazamiento rápido y contraído | Transporta objetos: cajas, documentos |
| **3** | Erguida, vestuario ajustado, desplazamiento normal | Transporta una carpeta |
| **4** | Hombros marcados, **manos libres**, desplazamiento con pausas de observación | No transporta nada: esa es la señal |
| **5–6** | Traje con hombreras, silueta angular, zancada amplia | Frecuentemente acompañado por un subordinado |
| **7–8** | **Ocupa más volumen visual que cualquier otro personaje.** Silueta ancha y estática | Los demás personajes se apartan de su trayectoria |

Harlan Voss posee la silueta de mayor volumen del juego.

**Consecuencia jugable:** al entrar en una sala el jugador determina de inmediato si se encuentra entre iguales o entre superiores, y por tanto su nivel de exposición.

### 14.6 Tics visuales por arquetipo

Cada arquetipo posee un comportamiento observable que permite identificarlo antes de consultar su expediente.

| Arquetipo | Tic visual |
|---|---|
| `gossip` | Se inclina hacia su interlocutor al hablar |
| `snitch` | Comprueba los laterales antes de iniciar conversación |
| `oblivious` | Auriculares permanentes; no gira la cabeza |
| `old_hand` | Desplazamiento lento; **dirige la mirada directamente hacia cualquier anomalía** |
| `burnout` | Se apoya en las paredes durante las pausas |
| `hardliner` | Cono de visión ampliado que barre lentamente su zona |
| `coward` | Retrocede medio paso al ser abordado |
| `climber` | Desplazamiento acelerado hacia despachos de superiores |
| `incorruptible` | Postura estática y frontal; no evita la mirada |

**El jugador aprende a interpretar personalidades sin abrir el expediente.** La aplicación de personal confirma lo que ya había inferido, lo que convierte la observación en una habilidad real.

### 14.7 Catálogo de animaciones

**Del jugador**, por orden de frecuencia de uso: caminar · esprintar · desplazamiento sigiloso · agachado · sentarse y teclear · abrir cajón e inspeccionar · sustraer, con animación rápida y postura culpable · ocultarse · **arrastrar un cuerpo**, con animación lenta y de esfuerzo · consultar el móvil · **el gesto del soborno**, un apretón de manos con transferencia · ser descubierto, con congelación postural · fichar en el torniquete.

**De los personajes:** el repertorio base de desplazamiento, más animaciones de reposo con personalidad —consultar el reloj, bostezar, conversar en corrillo, teclear con intensidad, **consultar el móvil furtivamente**, que es la señal del escaqueo— y animaciones de reacción: sobresalto, sospecha, señalar, desplazarse a Security.

**Ambientales:** fotocopiadora en funcionamiento, línea de ensamblaje, puertas de ascensor, cámaras en rotación, máquina de café.

**Nota de producción:** animación limitada de ocho a doce fotogramas por ciclo con poses clave definidas, no interpolación fotograma a fotograma. Es el estándar en animación de estilo cartoon, reduce el coste de producción y **mejora la legibilidad**.

### 14.8 Composición modular de salas

Cada banda de planta dispone de un kit de construcción:

| Categoría | Contenido |
|---|---|
| Estructura | Suelos, paredes, puertas —ordinaria, con lector, de servicio—, ventanas, techos con luminarias |
| Mobiliario | Cubículos, escritorios de despacho, archivadores, estanterías, sofás, maquinaria, palés, taquillas |
| Elementos de detalle | Tazas, plantas, **carteles motivacionales**, papeleras, extintores, relojes de pared |
| Interactivos | Marcados con un realce discreto: cajones, ordenadores, cámaras, escondites |

Cada sala se define exclusivamente en datos. **Incorporar una sala nueva no requiere producción de arte adicional.**

### 14.9 Música: el hilo musical corporativo

**La banda sonora principal es diegética:** procede de los altavoces del edificio. Música ambiental de ascensor con saxofón sintetizado, alegre y anodina. Suena de forma continua porque la compañía considera que incrementa la productividad.

**Y responde al nivel de sospecha del jugador:**

| Sospecha | Comportamiento del hilo musical |
|---|---|
| 0–25 | Reproducción normal: alegre y molesta |
| 26–50 | Reducción leve del tempo. Alguna nota desafinada ocasional. |
| 51–75 | **Comportamiento de cinta deteriorada:** tempo irregular, oscilación de tono, silencios anómalos |
| 76–100 | Práctica atonalidad. La melodía permanece reconocible pero deformada. **Cesa por completo de forma intermitente.** |

**El edificio vigila al jugador mediante música.** El canal auditivo comunica el nivel de riesgo antes de que el jugador consulte la barra correspondiente. Es información diegética, satírica y económica en términos de producción.

**Otras piezas:** un arreglo del hilo musical por banda de planta, más orquestal en las superiores y más comprimido en las inferiores · **la nave fabril carece de hilo musical**: solo el ritmo de la maquinaria, que ya constituye música industrial · el exterior nocturno emplea silencio y ambiente urbano, cuyo contraste incrementa la sensación opresiva al regresar · el menú principal y los epílogos son las únicas piezas no diegéticas, y la de los epílogos varía según el eje dominante.

### 14.10 Efectos de sonido como canal de información

En un juego de sigilo el sonido no es ambiente: es un canal de datos con tres categorías funcionales.

**Categoría primera: sonidos del jugador, que lo delatan.**

| Acción | Radio audible | Nota |
|---|---|---|
| Desplazamiento sigiloso | 1,0 | Prácticamente inaudible |
| Desplazamiento normal | 3,5 | — |
| Esprint | 9,0 | Alerta a toda la sala |
| Abrir cajón | 4,0 | Sonido distintivo e inconfundible |
| Forzar cerradura | 6,0 | Prolongado |
| Romper un objeto | 12,0 | Alerta la planta completa |
| Lector de tarjeta | 2,0 | Además genera registro |

**Categoría segunda: sonidos de los personajes, que advierten al jugador.** Pasos aproximándose con posicionamiento estéreo direccional, conversaciones audibles a través de tabiques, chirrido de silla al incorporarse alguien, radios de vigilante, campanilla de llegada del ascensor. **Aprender a escuchar constituye una habilidad real del jugador.**

**Categoría tercera: máscaras acústicas.** Call center, cuarto de calderas, línea de ensamblaje y fotocopiadoras reducen el radio efectivo de los ruidos del jugador al quince por ciento. El juego lo comunica mediante un indicador discreto.

**Señales especiales:** el momento de flagrancia posee sonido propio —un golpe seco con interrupción del hilo musical durante un segundo—; la alarma de seguridad varía por planta; **el móvil vibra al recibir un mensaje**, lo que puede ocurrir en el momento más inoportuno si el jugador no lo ha silenciado.

### 14.11 Estrategia de recursos

**Requisito: recursos exclusivamente de licencia CC0, con verificación individual de licencia. No se emplean recursos generados por inteligencia artificial.**

| Capa | Origen | Proporción estimada |
|---|---|---|
| **Generación por código** | Primitivas de dibujo de Godot y shaders. Suelos, paredes, mobiliario simple, siluetas, efectos, interfaz. | **La mayor parte** |
| Kits CC0 | Kenney.nl, OpenGameArt, itch.io filtrando por licencia | Complemento |
| Sonido | freesound.org filtrando por CC0 | Efectos |
| Música | Composición propia con instrumentación sintética sencilla | **Debe sonar económica: es parte del chiste** |
| Tipografía | Google Fonts, licencia OFL | — |

**Consideración de producción.** Ningún catálogo de recursos libres cubre un juego de esta especificidad. La capa de generación por código es lo que hace viable el proyecto, y por ese motivo el estilo vectorial plano no constituye una preferencia estética sino **la decisión de producción que determina la factibilidad**.

---

# PARTE VI — BALANCE Y PUBLICACIÓN

## 15. Balance global

### 15.1 Escala temporal

| Unidad | Equivalencia | Contenido |
|---|---|---|
| **Jornada** | 10–12 minutos reales | Oficina (8–10 min) más tarde y noche (2 min) |
| Semana laboral | 5 jornadas ≈ 1 hora | Cierre con informes internos |
| Mes | 20 jornadas ≈ 4 horas | **Cierre contable: afloran los fraudes** |
| Trimestre | 25 jornadas ≈ 5 horas | **Presentación de resultados** |
| **Partida completa** | **~110 jornadas ≈ 21,6 horas** | Treinta y tres promociones |

Un jugador que alcance el rango R28 experimenta cuatro o cinco trimestres completos, lo que proporciona recorrido suficiente para que la degradación por resultados sea una amenaza real y no teórica.

**El reloj no se detiene** salvo en menús de configuración. En el ordenador su velocidad se reduce al cuarenta por ciento, pero no se pausa: consultar expedientes tiene coste temporal.

### 15.2 Ritmo de progresión

| Escalón | Promociones | Tiempo por promoción | Acumulado |
|---|---|---|---|
| 1 — Base | 5 | ~18 min | 1,5 h |
| 2 — Junior | 4 | ~25 min | 3,2 h |
| 3 — Senior | 5 | ~35 min | 6,1 h |
| 4 — Jefe de equipo | 4 | ~40 min | 8,8 h |
| 5 — Dirección de bloque | 4 | ~45 min | 11,8 h |
| 6 — Dirección de área | 5 | ~50 min | 16,0 h |
| 7 — Alta directiva | 4 | ~55 min | 19,7 h |
| 8 — La cúspide | 2 | ~60 min | **21,6 h** |

**Justificación del ritmo.** El escalón 1 es deliberadamente rápido: el jugador experimenta los sistemas, percibe progresión y se compromete con la partida. A partir del escalón 3 el tiempo por promoción se incrementa, no porque exista más trabajo sino porque **la regla de la silla libre se convierte en el cuello de botella**: la limitación deja de ser el mérito y pasa a ser la disponibilidad de vacante.

Los saltos múltiples permiten a un jugador experto reducir sustancialmente la duración. Una partida óptima puede aproximarse a las quince horas; una imprudente puede superar las treinta.

### 15.3 Curva de tensión

| Fase | Duración | Estado emocional buscado |
|---|---|---|
| **Luna de miel** | 1–3 jornadas tras cada promoción | Sospecha baja, despacho nuevo, salas por explorar. **Respiro y recompensa.** |
| **Preparación** | 3–6 jornadas | Observación, estudio de expedientes, planificación. Tensión baja con actividad mental alta. |
| **Ejecución** | 1–2 jornadas | Tensión máxima |
| **Consecuencias** | 2–8 jornadas | Investigación, propagación de rumores, auditoría. Tensión sostenida. |
| **Resolución** | 1–2 jornadas | El caso se cierra, se enfría, o el jugador cae |

**Regla de diseño obligatoria:** el sistema no debe encadenar dos investigaciones activas contra el jugador sin un intervalo mínimo de tres jornadas, salvo que el propio jugador las provoque. El parámetro reside en `investigations.json`.

### 15.4 Economía: la demostración de la tesis

**Gastos fijos diarios:**

| Concepto | Importe |
|---|---|
| Desayuno | 4–6 € |
| Cena | 8–12 € |
| Alquiler prorrateado | 6–8 € |
| **Total base** | **20–25 €** |
| Gastos de estatus, escalón 5 | +40 € |
| Gastos de estatus, escalón 6 | +60 € |
| Gastos de estatus, escalón 7 | +90 € |
| Gastos de estatus, escalón 8 | +120 € |

**Balance por escalón:**

| Escalón | Salario diario | Margen honesto | Ingreso ilícito típico | Coste operativo habitual |
|---|---|---|---|---|
| 1 | 30–42 € | **+5 a +17 €** | 20–50 € | Sobornos de 150–400 € |
| 2 | 48–62 € | +23 a +37 € | 60–150 € | Sobornos de 300–900 € |
| 3 | 70–88 € | +45 a +63 € | 200–500 € | Sobornos de 800–3.000 € |
| 4 | 110–135 € | +45 a +70 € | 500–1.500 € | Sobornos de 2.000–8.000 € |
| 5 | 170–220 € | +50 a +100 € | 1.000–3.000 € | 5.000–15.000 € |
| 6 | 280–360 € | +100 a +180 € | 3.000–10.000 € | 15.000–40.000 € |
| 7 | 480–550 € | +200 a +300 € | 10.000–60.000 € | 40.000–150.000 € |
| 8 | 1.200–2.500 € | +900 a +2.200 € | Sin límite teórico | Variable |

**La demostración numérica:**

> En el rango R1 el jugador percibe 30 € diarios y gasta 22 €. Su margen es de **8 € por jornada**.
>
> El soborno más económico del juego —solicitar a Tom Iverson, con salario de 70 €, que mire hacia otro lado, con multiplicador ×3— cuesta **210 €**.
>
> Ahorrando exclusivamente el margen honesto: **veintiséis jornadas de trabajo** para un único favor menor.
>
> Sustrayendo y revendiendo material de oficina, con un rendimiento aproximado de 35 € diarios: **cinco jornadas**.
>
> **El juego no solicita al jugador que delinca. La aritmética lo hace en su lugar.**

**El contrapeso del estatus.** A partir del escalón 5 los gastos de representación consumen el incremento salarial. El jugador triplica sus ingresos y conserva un margen prácticamente equivalente. La sátira se implementa como hoja de cálculo.

### 15.5 Sumideros de capital

Tres mecanismos garantizan que el capital nunca resulte excedente:

| Sumidero | Importe | Naturaleza |
|---|---|---|
| **Soborno de emergencia** | ×20 del salario del testigo. En el escalón 6, ser descubierto por un director cuesta ~6.000 € | **Imprevisible.** El jugador no puede presupuestarlo. |
| **Cierre de investigación** | 15.000–50.000 € | Mecanismo de emergencia. Salva la partida y agota la reserva. |
| **Adquisición del paquete accionarial en R30** | ~250.000 € | Absorbe la totalidad del capital acumulado en la partida. |

### 15.6 Comodidades de uso

| Función | Especificación |
|---|---|
| **Salto temporal** | Permite avanzar a una franja concreta, **exclusivamente si el jugador se encuentra en ubicación segura y sin observadores** |
| Marcado de objetivos | Desde el expediente de personal, con reflejo en mapa y HUD |
| Resumen de jornada | Al dormir: ingresos, gastos, variación de medidores, deberes incumplidos |
| **Aviso de deber pendiente** | Una hora antes del cierre. *No perdonar el incumplimiento es duro; no advertirlo sería injusto.* |
| Registro automático en el cuaderno | Los eventos relevantes se anotan sin intervención del jugador |

### 15.7 Presets de dificultad

Tres configuraciones que operan exclusivamente sobre `balance.json`.

| Preset | Decaimiento de sospecha | Precio de sobornos | Margen en deberes |
|---|---|---|---|
| **Interno** | ×1,4 | ×0,75 | ×1,5 |
| **Estándar** | ×1,0 | ×1,00 | ×1,0 |
| **Auditoría** | ×0,6 | ×1,25 | ×0,7 |

**Elementos invariables en cualquier preset:** el permadeath y las reglas terminales —eliminación ante testigos, soborno denunciado, investigación concluyente. **La dureza estructural constituye el juego y no es configurable.**

## 16. Publicación

### 16.1 Requisitos de sistema

| | Mínimos | Recomendados |
|---|---|---|
| **PC** | Windows 10 · procesador de doble núcleo a 2,4 GHz · 4 GB de RAM · gráfica con soporte Vulkan u OpenGL 3.3 · 2 GB de disco | Windows 10 u 11 · cuatro núcleos · 8 GB de RAM · gráfica dedicada · unidad de estado sólido |
| **Android** | Versión 8.0 · 3 GB de RAM | Versión 11 o superior · 6 GB de RAM |

**Observación técnica:** un juego bidimensional en Godot 4 posee requisitos gráficos reducidos. El factor limitante no es el renderizado sino **la simulación de aproximadamente ciento cincuenta agentes**, motivo por el cual el sistema de nivel de detalle y el número configurable de agentes forman parte de los requisitos y no de las opciones accesorias.

### 16.2 Clasificación por edades

**Clasificación prevista: PEGI 16 / ESRB Teen–Mature.**

| Factor | Efecto sobre la clasificación |
|---|---|
| Violencia contra personajes humanos | Eleva la clasificación |
| Criminalidad como mecánica central recompensada | Eleva la clasificación |
| Ausencia de contenido sexual | Neutro |
| Ausencia de sustancias | Neutro |

**Decisiones de diseño que sostienen la clasificación 16 frente a 18:** las eliminaciones se resuelven sin representación gráfica mediante elipsis, encuadre y sonido; no se representa sangre en términos realistas; el registro satírico enmarca el conjunto como comedia negra.

**Consideraciones operativas.** Google Play exige un cuestionario de contenido cuya respuesta debe ser veraz: una declaración inexacta puede motivar la retirada de la aplicación. Steam requiere el marcado de contenido para adultos, sin que ello afecte a la visibilidad. Las clasificaciones formales tienen coste; para un desarrollo independiente el sistema automatizado IARC que emplean las tiendas digitales resulta suficiente y es gratuito.

### 16.3 Precio y modelo de distribución

| Plataforma | Precio | Justificación |
|---|---|---|
| **Steam** | 14,99 $/€ con descuento del 15% la primera semana | Rango habitual de un título independiente bidimensional con más de veinte horas de contenido y sistemas profundos. Por debajo de 10 el precio señala un producto menor; por encima de 20 un estudio desconocido no lo sostiene. El descuento de lanzamiento impulsa el pico inicial de ventas, que es el indicador que evalúa el algoritmo de la plataforma. |
| **Google Play** | 6,99 $/€, modelo premium | Sin publicidad y sin compras integradas. Un juego cuyo tema es la corrupción con microtransacciones constituiría una contradicción temática. |

**Modelo de lanzamiento: único y completo.** Sin demostración, sin acceso anticipado, sin versión web.

### 16.4 La página de tienda

El activo comercial de mayor relevancia. Debe publicarse **entre tres y seis meses antes del lanzamiento** para acumular lista de deseados.

**Descripción breve:**

> *You were hired to work. You have other plans. Climb 50 corporate ranks — by stealing ideas, buying silence, and never doing your job.*

**Estructura de la descripción extensa:**

1. El planteamiento invertido: el objetivo no es desempeñar bien el puesto, es no trabajar nunca y apropiarse de la compañía.
2. Los sistemas enunciados como fantasías del jugador: robar la idea de un compañero y presentarla, comprar el silencio de un vigilante, falsificar una autorización con el sello del escritorio, ascender ocupando la silla que se acaba de vaciar.
3. La simulación: ciento cincuenta trabajadores con personalidad, memoria y agravios persistentes; rumores que se propagan durante el almuerzo; investigaciones que registran físicamente los sótanos.
4. La torre: veinte plantas, ciento sesenta y seis espacios, y un principio —ascender de puesto es ascender por el edificio.
5. La advertencia: permadeath. Ser descubierto termina la partida.

**Etiquetas:** Stealth · Immersive Sim · Simulation · Dark Humor · Strategy · Singleplayer · 2D · Indie · Crime · Management · Permadeath · Satire.

**Imagen de cabecera:** la torre en corte vertical con una figura de tamaño reducido ascendiendo por su interior. Debe resultar legible a tamaño de miniatura, que es la condición determinante.

### 16.5 Material audiovisual

**Ocho capturas, cada una comunicando un sistema distinto:**

1. El ala 3B con los conos de visión activos y el indicador de detección parcialmente lleno.
2. El expediente de personal abierto mostrando los rasgos de un personaje.
3. El momento de flagrancia con las dos opciones en pantalla.
4. El mapa en corte de la torre completa.
5. La sala de monitores con las grabaciones.
6. La planta 20, para exhibir el contraste cromático frente a la planta 1.
7. La pantalla de mercado con la cotización descendiendo.
8. Un cuerpo siendo trasladado al archivo muerto, con encuadre cómico y sin representación gráfica.

**Tráiler de setenta y cinco a noventa segundos, compuesto exclusivamente por material de juego:**

| Tiempo | Contenido |
|---|---|
| 0–8 s | Un cubículo. Voz corporativa: *«Welcome to Stellar Sell».* El personaje teclea. Corte. |
| 8–25 s | El planteamiento en texto: *«Your job: send emails»* / *«Your plan: own the company»* |
| 25–55 s | Montaje acelerado: vigilar a un compañero, robar la idea, el soborno, la grabación borrada, el cuerpo trasladado, la promoción, la planta cambiando de paleta al ascender |
| 55–70 s | La tensión: una investigación, el interrogatorio, el hilo musical desafinando |
| 70–85 s | La torre en corte ascendiendo hasta la planta 20. Título, lema, fecha, logotipo de la plataforma |

### 16.6 Cronograma

| Hito | Momento |
|---|---|
| Inicio de la construcción | Mes 0 |
| **Publicación de la página de tienda** | Cuando el escalón 1 sea jugable de principio a fin |
| Publicación de avances periódicos | Durante toda la construcción. La lista de deseados crece con la constancia, no con un anuncio único. |
| **Prueba de juego cerrada con participantes externos** | Dos meses antes de la finalización |
| Tráiler definitivo, página pulida, versión de prensa | Un mes antes |
| Lanzamiento | Martes o miércoles. Evitando semanas de rebajas de la plataforma y ventanas de grandes lanzamientos. |
| Atención intensiva y parcheado | Primeras cuatro semanas. **El primer mes determina la trayectoria comercial del título.** |

### 16.7 Análisis de riesgos

| Riesgo | Evaluación | Mitigación |
|---|---|---|
| **Descubribilidad** | El riesgo de mayor magnitud. La mayoría de títulos independientes venden poco no por deficiencia de calidad sino por ausencia de visibilidad. | Página publicada con antelación de meses y avances constantes. **La lista de deseados acumulada es el único factor que activa el algoritmo el día del lanzamiento.** |
| **Alcance** | Ciento sesenta y seis espacios, cincuenta ocupaciones y ciento cincuenta personajes constituyen un volumen elevado de contenido. | Arquitectura orientada a datos: el contenido son registros, no código. Construcción incremental de una pieza por sesión. |
| **Curva de aprendizaje** | Una simulación con dos cerebros puede resultar abrumadora en los primeros veinte minutos. | Escalón 1 de ritmo acelerado, tutorial diegético, y expediente de personal escalado: la complejidad se administra progresivamente con las promociones. |
| **Rechazo al permadeath** | Perder dieciocho horas de partida provoca abandono en un segmento del público. | Constituye identidad del diseño. El preset Interno atenúa los parámetros sin modificar las reglas. |
| **Rendimiento en Android** | Ciento cincuenta agentes en hardware modesto. | Nivel de detalle en tres niveles y número configurable de agentes. **Verificación desde las primeras fases, no al final.** |
| **Deficiencia de diversión** | El riesgo menos mencionado: los sistemas pueden ser sólidos sobre el papel y resultar tediosos al jugarlos. | **La prueba con participantes externos es indispensable.** El equipo de desarrollo carece de la distancia necesaria para evaluarlo. |

**Expectativa realista.** El éxito comercial de un primer título independiente es improbable con independencia de su calidad. Lo que sí resulta garantizado si el proyecto se completa es un juego terminado, publicado y de propiedad íntegra, más la adquisición de la competencia necesaria para construir el siguiente, que estadísticamente es el que funciona.

---

# PARTE VII — ESPECIFICACIÓN TÉCNICA DE SISTEMAS

> **Esta parte debe consultarse antes de escribir cualquier línea de código.** Define la arquitectura, las interfaces públicas de cada sistema y las convenciones obligatorias. Respetar las firmas aquí especificadas es lo que garantiza que una pieza construida en el paso treinta encaje con otra construida en el paso doce sin necesidad de refactorización.

## 17. Arquitectura general

### 17.1 Los tres principios estructurales

**Primero: separación estricta entre contenido y lógica.** El código constituye la maquinaria; los datos, el contenido. Las cincuenta ocupaciones, los ciento sesenta y seis espacios, los ciento cincuenta personajes, los precios, los umbrales y la totalidad del texto residen en archivos de datos independientes bajo `data/`. La consecuencia operativa es que ajustar el balance del juego no requiere modificar código.

**Segundo: desacoplamiento total mediante bus de eventos.** Ningún sistema global invoca directamente a otro. Toda comunicación se produce mediante emisión de señales al `EventBus` y suscripción a las mismas. La consecuencia es que cualquier sistema puede reescribirse o desactivarse sin que los demás dejen de funcionar.

**Tercero: propiedad exclusiva del dato.** Cada variable de estado tiene un único sistema propietario autorizado a modificarla. Los demás la consultan mediante la interfaz pública. La consecuencia es que ante un comportamiento anómalo el origen es determinable sin ambigüedad.

**Corolario operativo:** si una función requiere conocer a más de dos sistemas para cumplir su cometido, su diseño es incorrecto y debe rehacerse, no parchearse.

### 17.2 Estructura de directorios

```
the_worker/
├── project.godot                  Configuración y registro de autoloads
├── export_presets.cfg             Perfiles de exportación Windows y Android
│
├── data/                          CONTENIDO — dieciséis archivos JSON
│   ├── balance.json               Todos los parámetros numéricos ajustables
│   ├── occupations.json           Las 50 ocupaciones
│   ├── archetypes.json            Los 12 arquetipos
│   ├── npcs_named.json            Los 23 personajes nominados
│   ├── npcs_generation.json       Reglas de generación procedural
│   ├── social_graph.json          Tipos de vínculo y corrillos
│   ├── bribes.json                Multiplicadores de favor
│   ├── ideas.json                 Plantillas de idea por departamento
│   ├── duties.json                Definición de deberes por ocupación
│   ├── investors.json             Los 6 inversores
│   ├── market.json                Parámetros de simulación bursátil
│   ├── market_events.json         Catálogo de eventos de mercado
│   ├── investigations.json        Umbrales y pesos de evidencia
│   ├── endings.json               Condiciones de los 9 finales
│   ├── art_bands.json             Paletas y ambientes por banda
│   └── rooms/                     Un archivo por planta
│       ├── s3.json  s2.json  s1.json  pb.json  factory.json
│       ├── p01.json … p20.json
│       └── exterior.json
│
├── src/
│   ├── autoload/                  Los 14 sistemas globales
│   ├── core/                      Clases de datos tipadas
│   ├── simulation/                Los cerebros: percepción, utilidad, investigación, mercado
│   ├── entities/                  Player, NPC, objetos interactivos
│   ├── world/                     RoomBuilder, FloorStreamer, navegación
│   ├── ui/                        HUD, StellarOS, móvil, mapa
│   └── util/                      Validador, funciones auxiliares
│
├── scenes/
│   ├── world/                     Escena principal, plantillas de sala
│   ├── ui/                        Una escena por pantalla
│   └── cinematics/                Apertura y epílogos
│
├── assets/
│   ├── art/  audio/  fonts/
│
├── locale/
│   └── strings.csv                Texto en inglés más columnas de localización
│
└── tests/                         Escenarios de validación headless
```

### 17.3 Convenciones de código obligatorias

| Elemento | Convención | Ejemplo |
|---|---|---|
| Archivos y directorios | `snake_case` | `belief_net.gd` |
| Clases | `PascalCase` con `class_name` declarado | `class_name BeliefNet` |
| Nodos de escena | `PascalCase` | `DetectionIndicator` |
| Variables y funciones | `snake_case` | `func compute_utility()` |
| Constantes | `MAYÚSCULAS_CON_GUIÓN` | `const MAX_SUSPICION := 100` |
| Miembros privados | Prefijo de guión bajo | `func _recalculate_beliefs()` |
| Señales | Tiempo pasado | `signal investigation_opened` |
| Identificadores de datos | `snake_case` | `"email_worker_3b"` |
| Claves de localización | `PREFIJO_MAYÚSCULAS` | `UI_BRIBE_CONFIRM` |

**Requisitos adicionales:**

- **Tipado estático obligatorio.** Toda variable, parámetro y valor de retorno declara su tipo.
- **Longitud máxima de función: cuarenta líneas.** Si se excede, se descompone.
- **Prohibición de valores literales.** Todo parámetro numérico ajustable reside en `balance.json`.
- **Cabecera documental obligatoria** de tres líneas en cada archivo: función del archivo, estado del que es propietario, señales a las que se suscribe.

Ejemplo de cabecera:

```gdscript
# belief_net.gd — Almacena y gestiona todas las creencias del mundo.
# PROPIETARIO DE: el conjunto de creencias, su decaimiento, y el cálculo de sospecha.
# ESCUCHA: player_seen_partially, player_caught_redhanded, day_advanced, rumor_spread
```

## 18. El bus de eventos

### 18.1 Justificación

Considérese el caso de la apertura de una investigación. Sin bus de eventos, `Security` debería invocar a `Market` para incrementar el factor de riesgo, a `NewsFeed` para generar la noticia, a `Tracking` para registrar el evento y a `AudioDirector` para degradar el hilo musical. Cuatro sistemas quedarían acoplados de forma permanente y cualquier modificación en uno afectaría a los demás.

Con bus de eventos, `Security` emite una única señal. Cada sistema interesado se suscribe de forma independiente. **Ninguno de ellos conoce la existencia de `Security`.** Añadir un consumidor nuevo no requiere modificar el emisor.

### 18.2 Catálogo completo de señales

```gdscript
extends Node
# event_bus.gd — Tablón central de comunicación entre sistemas.
# PROPIETARIO DE: nada. Únicamente declara y distribuye señales.
# ESCUCHA: nada.

# ─── PERCEPCIÓN Y SIGILO ───────────────────────────────────────
signal player_seen_partially(npc_id: String, certainty: float, location: String)
signal player_caught_redhanded(npc_id: String, crime_type: String, witnesses: int)
signal player_lost_from_sight(npc_id: String)
signal noise_emitted(position: Vector2, radius: float, source: String)
signal camera_recorded_player(camera_id: String, room_id: String, day: int)
signal card_reader_logged(reader_id: String, card_owner: String, day: int, hour: int)

# ─── CREENCIAS Y SOCIAL ────────────────────────────────────────
signal belief_created(belief_id: String, holder: String, subject: String, certainty: float)
signal belief_decayed(belief_id: String, new_certainty: float)
signal belief_forgotten(belief_id: String)
signal record_created(record_id: String, record_type: String, weight: float)
signal record_destroyed(record_id: String, method: String)
signal rumor_spread(from_npc: String, to_npc: String, belief_id: String)
signal suspicion_changed(old_value: float, new_value: float)
signal reputation_changed(old_value: float, new_value: float)

# ─── SOBORNOS Y RELACIONES ─────────────────────────────────────
signal bribe_offered(npc_id: String, amount: int, favour_type: String)
signal bribe_result(npc_id: String, accepted: bool, outcome: String)
signal grievance_added(npc_id: String, grievance_type: String, severity: int)
signal favour_added(npc_id: String, favour_type: String, magnitude: int)
signal blackmail_initiated(npc_id: String, target: String, leverage: String)

# ─── IDEAS Y TRABAJO ───────────────────────────────────────────
signal idea_generated(idea_id: String, owner: String, quality: int, department: String)
signal idea_acquired(idea_id: String, method: String)
signal idea_expired(idea_id: String)
signal idea_presented(idea_id: String, presenter: String, merit_gained: int)
signal idea_contested(idea_id: String, accuser: String, result: String)
signal duty_assigned(duty_id: String, duty_type: String, deadline_hour: int)
signal duty_completed(duty_id: String, quality: float, method: String)
signal duty_failed(duty_id: String, consequence: String)
signal assist_used(task_type: String, result_quality: String)

# ─── PROGRESIÓN ────────────────────────────────────────────────
signal occupation_changed(old_id: String, new_id: String, reason: String)
signal seat_vacated(occupation_id: String, previous_holder: String, cause: String)
signal seat_filled(occupation_id: String, new_holder: String)
signal promotion_available(occupation_ids: Array)
signal promotion_declined(occupation_id: String)
signal merit_gained(source: String, amount: int)
signal clearance_changed(old_level: int, new_level: int)

# ─── SEGURIDAD E INVESTIGACIÓN ─────────────────────────────────
signal alert_level_changed(old_level: int, new_level: int)
signal investigation_opened(case_id: String, incident_type: String, severity: int)
signal investigation_phase_advanced(case_id: String, new_phase: int)
signal evidence_added(case_id: String, evidence_type: String, weight: float, points_to: String)
signal suspect_list_formed(case_id: String, suspects: Array)
signal interrogation_started(case_id: String, interrogator: String)
signal investigation_resolved(case_id: String, verdict: String, culprit: String)
signal case_went_cold(case_id: String)
signal case_revived(case_id: String, trigger: String)
signal body_discovered(body_id: String, room_id: String)
signal police_dispatched(target_location: String, response_time: float)

# ─── ECONOMÍA Y NOTICIAS ───────────────────────────────────────
signal news_published(headline_id: String, sentiment_delta: float, is_scandal: bool)
signal news_buried(headline_id: String, by_whom: String)
signal fundamentals_updated(revenue: float, costs: float, risk: float)
signal quarter_reported(real_figures: Dictionary, reported_figures: Dictionary)
signal audit_fuse_lit(discrepancy: float, weeks_until_check: int)
signal audit_triggered(discrepancy_found: bool)
signal stock_price_updated(price: float, delta_percent: float)
signal investor_confidence_changed(investor_id: String, old_value: int, new_value: int)
signal insider_pattern_detected(operations_count: int)

# ─── MUNDO Y TIEMPO ────────────────────────────────────────────
signal day_advanced(day_number: int)
signal time_band_changed(old_band: String, new_band: String)
signal week_closed(week_number: int)
signal month_closed(month_number: int)
signal quarter_closed(quarter_number: int)
signal room_entered(room_id: String, by_player: bool)
signal room_exited(room_id: String, by_player: bool)
signal floor_changed(old_floor: int, new_floor: int)
signal strike_discontent_changed(old_value: int, new_value: int)
signal strike_started()
signal strike_resolved(resolution: String)

# ─── FIN DE PARTIDA ────────────────────────────────────────────
signal ownership_documents_obtained()
signal ownership_notarised()
signal game_over(cause: String, ending_id: String, tracking_snapshot: Dictionary)
```

### 18.3 Regla de nomenclatura de señales

**Toda señal se declara en tiempo pasado.** Una señal informa de un hecho consumado; nunca emite una orden. `player_seen_partially` es correcto; `see_player` sería incorrecto.

Esta convención es lo que impide que el bus degenere en un mecanismo de invocación indirecta. Si un sistema necesita solicitar una acción a otro, la arquitectura está mal planteada.

### 18.4 Depuración

El bus incorpora un mecanismo de registro condicional:

```gdscript
const DEBUG_SIGNALS := false

func _log(signal_name: String, args: Array) -> void:
    if DEBUG_SIGNALS:
        print("[BUS] %s → %s" % [signal_name, str(args)])
```

Activarlo permite observar el flujo completo de razonamiento del juego en la consola, lo que resulta indispensable para diagnosticar comportamientos emergentes inesperados.

## 19. Interfaces de los sistemas globales

> Las firmas siguientes son de cumplimiento obligatorio. Un sistema construido en un paso posterior asumirá su existencia exacta.

### 19.1 `Database`

**Propietario de:** la totalidad de los datos estáticos cargados desde `data/`. Acceso de solo lectura tras el arranque.

```gdscript
class_name DatabaseSystem extends Node

# Carga y validación al arrancar
func load_all() -> bool
func get_load_errors() -> Array[String]

# Acceso a ocupaciones
func get_occupation(id: String) -> OccupationData
func get_occupations_by_rank(rank: int) -> Array[OccupationData]
func get_occupations_by_tier(tier: int) -> Array[OccupationData]
func get_all_occupations() -> Array[OccupationData]

# Acceso a salas
func get_room(id: String) -> RoomData
func get_rooms_by_floor(floor: int) -> Array[RoomData]
func get_rooms_by_clearance(max_clearance: int) -> Array[RoomData]
func get_all_rooms() -> Array[RoomData]

# Acceso a personajes y arquetipos
func get_archetype(id: String) -> ArchetypeData
func get_named_npc(id: String) -> NPCData
func get_all_named_npcs() -> Array[NPCData]
func get_generation_rules(department: String) -> Dictionary

# Acceso a inversores, deberes e ideas
func get_investor(id: String) -> InvestorData
func get_all_investors() -> Array[InvestorData]
func get_duty_definition(duty_type: String) -> Dictionary
func get_idea_template(department: String) -> Dictionary

# Acceso al balance mediante ruta con puntos
func get_balance(path: String) -> Variant       # "percepcion.cono_angulo_base"
func get_balance_int(path: String) -> int
func get_balance_float(path: String) -> float
func get_difficulty_modifier(key: String) -> float
```

### 19.2 `GameClock`

**Propietario de:** hora, jornada, semana, mes, trimestre, franja horaria activa.

```gdscript
class_name GameClockSystem extends Node

# Consulta de estado
func get_hour() -> int
func get_minute() -> int
func get_day() -> int
func get_week() -> int
func get_month() -> int
func get_quarter() -> int
func get_current_band() -> String     # "arrival" | "work_morning" | "lunch" |
                                      # "work_afternoon" | "exit" | "night"
func get_time_string() -> String       # "13:42"
func is_working_hours() -> bool

# Control
func pause() -> void
func resume() -> void
func set_speed_multiplier(mult: float) -> void   # 0.4 dentro del ordenador
func advance_to_band(band: String) -> bool       # Falla si hay observadores
func advance_to_next_day() -> void               # Al dormir

# Utilidad
func hours_until_closing() -> float
func days_since(day: int) -> int
```

**Emite:** `time_band_changed`, `day_advanced`, `week_closed`, `month_closed`, `quarter_closed`.

### 19.3 `PlayerState`

**Propietario de:** ocupación, capital, reputación, inventario, deberes de la jornada, ejes de seguimiento.

**No es propietario de la sospecha:** ese valor lo calcula `BeliefNet` y `PlayerState` únicamente lo almacena en caché.

```gdscript
class_name PlayerStateSystem extends Node

# Ocupación
func get_occupation() -> OccupationData
func get_rank() -> int
func get_tier() -> int
func get_clearance() -> int
func set_occupation(id: String, reason: String) -> void
func get_personnel_file_level() -> int

# Capital
func get_money() -> int
func add_money(amount: int, source: String) -> void
func spend_money(amount: int, reason: String) -> bool   # false si es insuficiente
func can_afford(amount: int) -> bool
func get_daily_expenses() -> int

# Medidores
func get_reputation() -> float
func modify_reputation(delta: float, reason: String) -> void
func get_suspicion() -> float                            # cacheado desde BeliefNet
func _set_suspicion_from_beliefnet(value: float) -> void # solo BeliefNet invoca

# Inventario
func get_inventory() -> Array[ItemData]
func add_item(item_id: String) -> bool                   # false si está lleno
func remove_item(item_id: String) -> bool
func has_item(item_id: String) -> bool
func has_hot_items() -> bool
func get_hot_item_count() -> int
func get_free_slots() -> int

# Deberes
func get_todays_duties() -> Array[Dictionary]
func complete_duty(duty_id: String, quality: float, method: String) -> void
func fail_duty(duty_id: String) -> void
func get_pending_duties() -> Array[Dictionary]
func get_consecutive_failures() -> int

# Seguimiento
func add_tracking(axis: String, amount: int) -> void     # "blood"|"gold"|"silk"|"sweat"|"ruin"
func get_tracking(axis: String) -> int
func get_dominant_axis() -> String

# Persistencia
func save_state() -> Dictionary
func load_state(data: Dictionary) -> void
```

### 19.4 `BeliefNet`

**Propietario de:** todas las creencias del mundo, su decaimiento, los registros permanentes, y el cálculo de la sospecha.

```gdscript
class_name BeliefNetSystem extends Node

# Creación
func create_belief(holder: String, subject: String, fact: String,
                   certainty: float, source: String, location: String) -> String
func create_record(record_type: String, subject: String,
                   weight: float, location: String) -> String

# Consulta
func get_beliefs_about(subject: String) -> Array[Belief]
func get_beliefs_held_by(holder: String) -> Array[Belief]
func get_belief(id: String) -> Belief
func get_records_about(subject: String) -> Array[Belief]
func count_credible_beliefs_about(subject: String, min_certainty: float) -> int

# Modificación
func reinforce_belief(id: String, additional_certainty: float) -> void
func destroy_record(id: String, method: String) -> bool
func transfer_belief(id: String, to_holder: String, degradation: float) -> String

# Sospecha
func calculate_player_suspicion() -> float
func get_suspicion_breakdown() -> Array[Dictionary]     # para el panel de depuración

# Mantenimiento
func apply_daily_decay() -> void                        # invocado por day_advanced

# Persistencia
func save_state() -> Dictionary
func load_state(data: Dictionary) -> void
```

### 19.5 `NPCDirector`

**Propietario de:** el estado completo de los personajes, sus rutinas, su ánimo, su registro de relaciones y su nivel de detalle de simulación.

```gdscript
class_name NPCDirectorSystem extends Node

# Población
func generate_population() -> void
func get_npc(id: String) -> NPCRuntime
func get_all_npcs() -> Array[NPCRuntime]
func get_npcs_in_room(room_id: String) -> Array[NPCRuntime]
func get_npcs_by_archetype(archetype: String) -> Array[NPCRuntime]
func get_npc_by_occupation(occupation_id: String) -> NPCRuntime

# Rasgos
func get_trait(npc_id: String, trait_name: String) -> int
func get_all_traits(npc_id: String) -> Dictionary
func get_effective_perception(npc_id: String) -> int     # modulado por sospecha

# Registro de relaciones
func get_ledger(npc_id: String) -> Dictionary
func add_grievance(npc_id: String, type: String, severity: int) -> void
func add_favour(npc_id: String, type: String, magnitude: int) -> void
func get_affection(npc_id: String) -> int
func get_fear(npc_id: String) -> int
func get_debt(npc_id: String) -> int

# Rutinas y ubicación
func get_current_location(npc_id: String) -> String
func get_scheduled_location(npc_id: String, band: String) -> String
func override_routine(npc_id: String, band: String, location: String) -> void
func is_slacker(npc_id: String) -> bool

# Estado vital
func remove_npc(npc_id: String, cause: String) -> void   # expulsión o eliminación
func is_alive(npc_id: String) -> bool

# Nivel de detalle
func set_lod(npc_id: String, level: int) -> void         # 0 completo, 1 medio, 2 estadístico
func get_lod(npc_id: String) -> int
func force_full_lod(npc_id: String, reason: String) -> void

# Persistencia
func save_state() -> Dictionary
func load_state(data: Dictionary) -> void
```

### 19.6 `SocialGraph`

**Propietario de:** los vínculos entre personajes y la propagación de creencias.

```gdscript
class_name SocialGraphSystem extends Node

func build_initial_graph() -> void
func add_link(from_npc: String, to_npc: String, link_type: String, strength: float) -> void
func remove_link(from_npc: String, to_npc: String) -> void
func get_links(npc_id: String) -> Array[Dictionary]
func get_link_strength(from_npc: String, to_npc: String) -> float
func get_neighbours(npc_id: String, min_strength: float) -> Array[String]

func propagate_at_gathering(gathering_id: String) -> int  # devuelve nº de propagaciones
func inject_rumour(target_npc: String, fact: String, certainty: float) -> String
func kill_rumour(belief_fact: String) -> int              # Director de Comunicación

func get_gathering_participants(gathering_id: String) -> Array[String]
func is_isolated(npc_id: String) -> bool

func save_state() -> Dictionary
func load_state(data: Dictionary) -> void
```

### 19.7 `Security`

**Propietario de:** nivel de alerta, cámaras, investigaciones activas y casos fríos.

```gdscript
class_name SecuritySystem extends Node

# Alerta
func get_alert_level() -> int                            # 0 a 5
func recalculate_alert_level() -> void

# Cámaras y registros
func register_camera_footage(room_id: String, day: int, hour: int) -> String
func delete_footage(footage_id: String) -> bool          # solo desde sala de monitores
func get_footage_for_room(room_id: String, day: int) -> Array[String]

# Investigaciones
func open_investigation(incident_type: String, severity: int, location: String) -> String
func get_investigation(case_id: String) -> Investigation
func get_active_investigations() -> Array[Investigation]
func get_cold_cases() -> Array[Investigation]
func add_evidence(case_id: String, evidence_type: String, weight: float, points_to: String) -> void
func advance_phase(case_id: String) -> void
func resolve_investigation(case_id: String, verdict: String, culprit: String) -> void
func revive_cold_case(case_id: String, trigger: String) -> void
func close_case_permanently(case_id: String) -> bool     # solo Auditor Jefe

# Consulta de riesgo
func get_case_weight_against(subject: String, case_id: String) -> float
func is_player_in_shortlist(case_id: String) -> bool
func can_search_player() -> bool

func save_state() -> Dictionary
func load_state(data: Dictionary) -> void
```

### 19.8 `Company`

**Propietario de:** ocupación de las sillas, fundamentales, valores reportados, y la lógica de promoción.

```gdscript
class_name CompanySystem extends Node

# Sillas
func get_seat_holder(occupation_id: String) -> String     # "" si está vacante
func is_seat_vacant(occupation_id: String) -> bool
func get_vacant_seats() -> Array[String]
func vacate_seat(occupation_id: String, cause: String) -> void
func fill_seat(occupation_id: String, npc_id: String) -> void
func auto_fill_vacancies() -> void

# Promoción del jugador
func can_player_promote_to(occupation_id: String) -> Dictionary
    # devuelve { allowed: bool, missing: Array[String] }
    # missing puede contener "reputation", "merit", "vacancy"
func get_available_promotions() -> Array[String]
func promote_player(occupation_id: String) -> bool
func demote_player(reason: String) -> void
func register_merit(source: String, amount: int) -> void
func get_recent_merit() -> int

# Fundamentales
func get_fundamentals() -> Dictionary
    # { revenue, costs, profit, growth_expectation, risk_factor }
func get_reported_figures() -> Dictionary
func set_reported_figures(figures: Dictionary) -> void    # solo cargos autorizados
func recalculate_fundamentals() -> void
func add_theft_loss(amount: float) -> void
func modify_product_quality(delta: float) -> void
func modify_brand_strength(delta: float) -> void

# Descontento
func get_discontent() -> int
func modify_discontent(delta: int, cause: String) -> void

func save_state() -> Dictionary
func load_state(data: Dictionary) -> void
```

### 19.9 `Market`

**Propietario de:** cotización, histórico, inversores, confianza agregada, cartera del jugador.

```gdscript
class_name MarketSystem extends Node

# Cotización
func get_price() -> float
func get_intrinsic_value() -> float
func get_price_history(days: int) -> Array[float]
func get_momentum() -> float
func get_sentiment() -> float
func tick_hourly() -> void

# Inversores
func get_investor_confidence(investor_id: String) -> int
func modify_investor_confidence(investor_id: String, delta: int, reason: String) -> void
func get_aggregate_confidence() -> float
func get_quarterly_target() -> float
func is_meeting_target() -> bool

# Presentación de resultados
func conduct_quarterly_presentation(preparation: float, allies_present: int) -> Dictionary
    # devuelve { quality: float, confidence_changes: Dictionary, sentiment_delta: float }

# Cartera del jugador
func get_player_shares() -> int
func buy_shares(quantity: int) -> bool
func sell_shares(quantity: int) -> bool
func get_portfolio_value() -> float
func get_dividend_income() -> int
func get_board_votes() -> int

# Información privilegiada
func register_insider_operation(volume: int) -> void
func get_insider_pattern_score() -> float
func get_upcoming_news(days_ahead: int) -> Array[String]  # solo R25+

func save_state() -> Dictionary
func load_state(data: Dictionary) -> void
```

### 19.10 `NewsFeed`

**Propietario de:** la capa compartida de noticias y sentimiento.

```gdscript
class_name NewsFeedSystem extends Node

func publish(headline_id: String, sentiment_delta: float, is_scandal: bool) -> String
func bury(news_id: String, by_whom: String) -> bool      # Director de Comunicación
func fabricate(target: String, headline_id: String) -> String
func get_active_news() -> Array[Dictionary]
func get_sentiment_contribution() -> float
func get_scandal_count(days: int) -> int
func apply_daily_decay() -> void

func save_state() -> Dictionary
func load_state(data: Dictionary) -> void
```

### 19.11 `IdeaPool`

**Propietario de:** las ideas vivas del mundo.

```gdscript
class_name IdeaPoolSystem extends Node

func generate_for_npc(npc_id: String) -> String
func get_idea(idea_id: String) -> Idea
func get_ideas_by_owner(npc_id: String) -> Array[Idea]
func get_available_ideas() -> Array[Idea]
func get_unclaimed_ideas() -> Array[Idea]                # de personajes eliminados

func acquire(idea_id: String, method: String) -> bool
func present(idea_id: String) -> Dictionary
    # devuelve { merit: int, contested: bool, contest_result: String }
func contest(idea_id: String, accuser: String) -> String
func expire_stale_ideas() -> int

func save_state() -> Dictionary
func load_state(data: Dictionary) -> void
```

### 19.12 `Tracking`

**Propietario de:** los cinco ejes y la evaluación de finales.

```gdscript
class_name TrackingSystem extends Node

func add(axis: String, amount: int, source: String) -> void
func get_axis(axis: String) -> int
func get_all_axes() -> Dictionary
func get_dominant_axis() -> String
func is_hybrid() -> bool
func get_ruin_tier() -> String                           # "empire" | "husk"
func evaluate_ending() -> String                         # devuelve ending_id
func get_snapshot() -> Dictionary

func save_state() -> Dictionary
func load_state(data: Dictionary) -> void
```

### 19.13 `SaveSystem`

**Propietario de:** los dos archivos de persistencia.

```gdscript
class_name SaveSystemNode extends Node

const RUN_PATH := "user://run.json"
const PROFILE_PATH := "user://profile.json"
const SAVE_VERSION := 1

func save_run() -> bool                                  # escritura atómica
func load_run() -> bool
func delete_run() -> void                                # al perder la partida
func run_exists() -> bool

func save_profile() -> bool
func load_profile() -> bool
func unlock_ending(ending_id: String) -> void
func get_unlocked_endings() -> Array[String]
func get_setting(key: String) -> Variant
func set_setting(key: String, value: Variant) -> void
```

**Procedimiento de escritura atómica obligatorio:** escribir en `user://run.json.tmp`, verificar la integridad del archivo, y renombrar sobre el destino. Un corte de energía a mitad del proceso no debe corromper la partida.

## 20. Rendimiento y nivel de detalle

### 20.1 Los tres niveles de simulación

| Nivel | Población | Sistemas activos | Frecuencia de actualización |
|---|---|---|---|
| **0 — Completo** | Sala del jugador y adyacentes, máximo 20 | Cono de visión, percepción auditiva, utilidad completa, animación, creencias detalladas | Cada fotograma |
| **1 — Medio** | Misma planta, máximo 40 | Desplazamiento por rutina, decisiones simplificadas | Cada 0,5 segundos |
| **2 — Estadístico** | Resto de la población, ~100 | Posición inferida del horario, probabilidad de participación en rumores | Cada 5 segundos |

### 20.2 Reglas de asignación

- **Los personajes implicados en una trama activa ascienden siempre a nivel 0**, con independencia de su ubicación. Trama activa incluye: figurar en una lista corta de investigación, estar marcado como objetivo, mantener deuda con el jugador, o poseer una idea que el jugador esté vigilando. Esta regla evita que un elemento narrativamente relevante se degrade por lejanía.
- **La actualización se produce por eventos, no por sondeo continuo.** Las creencias se recalculan al recibir una señal.
- **El mercado se recalcula una vez por hora de juego**, nunca por fotograma.
- **El número máximo de agentes es configurable** desde las opciones para hardware modesto.

### 20.3 Objetivos de rendimiento

| Plataforma | Objetivo |
|---|---|
| PC de gama media | 60 fotogramas por segundo sostenidos |
| Android de gama media | 30 fotogramas por segundo estables |

## 21. Validación mediante ejecución sin ventana

Godot admite ejecución sin interfaz gráfica, lo que permite validar sistemas a velocidad máxima. **Ningún sistema se considera terminado sin su escenario de validación en estado satisfactorio.**

Invocación: `godot --headless --script tests/nombre_del_test.gd`

| Escenario | Verifica |
|---|---|
| `test_event_bus` | Todas las señales existen y son emisibles y recibibles |
| `test_validate` | Un dato malformado produce el error especificado; uno correcto se carga |
| `test_data_integrity` | 50 ocupaciones sin identificadores duplicados, 166 salas, 12 arquetipos, rangos R0 a R33 completos, referencias cruzadas válidas |
| `test_game_clock` | Una jornada completa emite todas las franjas en orden y `day_advanced` una sola vez |
| `test_player_state` | Capital, inventario con distinción de material comprometedor, deberes, ejes de seguimiento |
| `test_perception` | Un personaje a media distancia genera creencia de certeza baja, no alta |
| `test_noise` | Las máscaras acústicas reducen el radio efectivo al valor especificado |
| `test_beliefs` | Decaimiento tras N jornadas; los registros no decaen; la sospecha se calcula correctamente |
| `test_rumor` | Una creencia inyectada a un `gossip` alcanza cinco personajes tras la franja de comida |
| `test_utility_ai` | El mismo personaje actúa de forma opuesta ante rango bajo y rango alto del jugador |
| `test_bribe` | Probabilidad nula con `incorruptible`; probabilidad alta con `burnout`; el registro de relaciones modifica el precio |
| `test_caught` | Ser descubierto por cada uno de los doce arquetipos produce la reacción documentada |
| `test_idea_presentation` | Los tres resultados del choque de credibilidad se producen según la fórmula |
| `test_promotion` | La regla de la silla libre exige las tres condiciones; la reposición automática funciona |
| `test_investigation` | Las cinco fases se recorren; un cuerpo mal ocultado aflora en fase 2 |
| `test_cold_case` | Un caso archivado revive al cambiar el ocupante de Auditoría |
| `test_market` | Un trimestre con escándalo deprime la cotización; sin escándalo, no |
| `test_endings` | Cada uno de los nueve finales se dispara con su combinación de ejes |
| `test_save_load` | Guardar y cargar reproduce el estado exacto de todos los sistemas |

---

# PARTE VIII — BIBLIA DE CONTENIDO

> Los datos de esta parte se transcriben directamente a archivos JSON según los esquemas de la Parte IX. Las columnas *Dim* (dimensiones en unidades de rejilla), *Cám* (presencia de cámaras) y *Ocupación* (número de personajes por franja) son datos constructivos necesarios para instanciar cada sala.

## 22. Catálogo de espacios

**Clave de la columna Ocupación:** los cuatro valores corresponden a las franjas *trabajo · comida · tarde · noche*.

### 22.1 Sótano 3 — Las tripas
*Banda `the_guts` · Kit `technical` · Ambiente `machinery_hum` · Ruido ambiente 0,8*

| id | Nombre | Acred. | Dim | Cám | Ocupación | Conecta con | Oportunidad | Riesgo |
|---|---|---|---|---|---|---|---|---|
| `boiler_room` | Cuarto de calderas | N5, mantenimiento | 12×10 | No | 0·0·0·0 | `service_tunnel`, `service_stairs` | **Máscara acústica total.** Ningún ruido es audible desde fuera | Temperatura: permanencia limitada a 20 min |
| `electrical_room` | Sala eléctrica | N5, mantenimiento | 8×8 | No | 0·0·0·0 | `service_stairs` | **Corte de energía por plantas: desactiva cámaras 5 min** | Todo apagón genera investigación automática |
| `maintenance_store` | Almacén de mantenimiento | N2 + mantenimiento | 10×8 | No | 1·0·1·0 | `service_tunnel`, `service_stairs` | **Uniforme de mantenimiento**, herramientas de forzado | Frank Rudd transita con frecuencia |
| `service_tunnel` | Túnel de servicio | N5, mantenimiento | 30×4 | No | 0·0·0·0 | `boiler_room`, `maintenance_store`, `factory_dye_lab` | Acceso a la nave fabril sin cruzar planta baja | Recorrido largo: exposición temporal prolongada |
| `forgotten_corridor` | El pasillo que nadie limpia | N5 | 16×3 | No | 0·0·0·0 | `service_stairs` | **Escondite de fiabilidad máxima. Ninguna investigación lo registra.** | Localización no evidente en la primera partida |

### 22.2 Sótano 2 — La memoria
*Banda `the_guts` · Kit `archive` · Ambiente `ventilation_drone` · Ruido 0,3*

| id | Nombre | Acred. | Dim | Cám | Ocupación | Conecta con | Oportunidad | Riesgo |
|---|---|---|---|---|---|---|---|---|
| `dead_archive` | Archivo muerto | N5, limpieza | 24×18 | No | 0·0·0·0 | `service_stairs`, `freight_elevator` | **Ocultación de objetos y cuerpos. El escondite de mayor capacidad.** Documentos históricos comprometedores | Una investigación de gravedad alta registra sótanos en fase 2 |
| `server_room` | Sala de servidores | N5, IT | 12×12 | No | 0·0·0·0 | `service_stairs` | **Borrado de registros digitales** | Frío; el acceso queda registrado en el propio servidor |
| `backup_room` | Cuarto de copias de seguridad | N5, IT | 8×8 | No | 0·0·0·0 | `server_room` | Las copias restauran lo borrado: **destruirlas también es necesario** | La ausencia de copias se detecta en auditoría de sistemas |
| `old_confidential_cage` | Jaula de archivo confidencial antiguo | N6 | 10×6 | No | 0·0·0·0 | `dead_archive` | Secretos corporativos de décadas anteriores | Candado antiguo: forzarlo emite ruido de radio 6 |

### 22.3 Sótano 1 — Logística baja
*Banda `the_guts` · Kit `logistics` · Ambiente `distant_traffic` · Ruido 0,4*

| id | Nombre | Acred. | Dim | Cám | Ocupación | Conecta con | Oportunidad | Riesgo |
|---|---|---|---|---|---|---|---|---|
| `garage` | Garaje y aparcamiento | N4 | 30×24 | Sí, rampa | 2·0·2·0 | `main_elevator_1`, `service_stairs`, exterior | Sabotaje de vehículos de directivos; ocultación; **escucha de conversaciones privadas** | Cámara en la rampa de entrada |
| `maintenance_workshop` | Taller de mantenimiento | N2 + mantenimiento | 12×10 | No | 2·1·2·0 | `service_stairs`, `freight_elevator` | Herramientas de forzado y corte | — |
| `security_locker_room` | Vestuario de seguridad | N3 + vigilante | 10×8 | No | 1·2·1·2 | `service_stairs` | **Uniforme de vigilante** | Ser visto sustrayéndolo constituye evidencia definitiva |
| `cleaning_locker_room` | Vestuario de limpieza | N2, limpieza | 10×8 | No | 0·1·0·4 | `service_stairs` | **Uniforme de limpieza y carrito con llaves maestras** | Connie Marks accede varias veces al día |
| `general_warehouse` | Almacén general | N2 | 20×16 | No | 1·0·1·0 | `freight_elevator`, `loading_dock` | Material de valor revendible | Inventario mensual |
| `trash_dock` | Muelle de basuras | N1 | 12×10 | No | 0·0·1·0 | `general_warehouse`, exterior | **Extracción definitiva de objetos del juego** | Irreversible: lo depositado no se recupera |
| `freight_elevator_room` | Cuarto del montacargas | N3 | 8×8 | No | 0·0·0·0 | `freight_elevator` | **Transporte de cajas grandes y cuerpos** | Lento y con emisión de ruido de radio 8 |

### 22.4 Planta baja — La fachada
*Banda `the_pit` · Kit `lobby` · Ambiente `lobby_murmur` · Ruido 0,5*

| id | Nombre | Acred. | Dim | Cám | Ocupación | Conecta con | Oportunidad | Riesgo |
|---|---|---|---|---|---|---|---|---|
| `main_reception` | Recepción principal | N0 | 20×14 | **Sí** | 3·2·3·1 | exterior, `turnstiles` | Observación de llegadas y visitas | Recepcionista con Perspicacia 70 |
| `turnstiles` | Control de torniquetes | N0 | 10×8 | **Sí** | 2·1·2·1 | `main_reception`, ascensores, escaleras | **Acceso tras otro empleado en franja de llegada** | Registro de fichaje permanente |
| `monitor_room` | **Sala de monitores de seguridad** | N5 + vigilante | 10×8 | No, interior | 2·1·2·2 | `turnstiles` | **Borrado de grabaciones.** Visión de todo el edificio | Ocupación permanente por dos vigilantes |
| `cafeteria` | Cafetería | N0 | 30×22 | No | 4·**45**·4·0 | `turnstiles`, `cafeteria_kitchen` | **El amplificador de rumores de mayor alcance del juego** | Máxima densidad de observadores en franja de comida |
| `cafeteria_kitchen` | Cocina de la cafetería | N1 | 14×10 | No | 5·6·3·0 | `cafeteria`, `trash_dock` | **Sustracción de alimentos: elimina el gasto de manutención** | Personal de cocina presente |
| `flagship_store` | Tienda insignia | N0 | 18×14 | **Sí** | 3·2·3·0 | `main_reception`, exterior | Colocación de producto sustraído; consulta de precios reales | Cámara y dependientes |
| `visitor_lounge` | Sala de espera de visitas | N0 | 12×10 | Sí | 1·0·2·0 | `main_reception` | **Escucha de compradores antes de su reunión** | — |
| `mail_office` | Oficina de paquetería y correo | N1 | 12×10 | No | 2·1·2·0 | `turnstiles`, `freight_elevator` | **Interceptación de correspondencia interna** | El repartidor detecta ausencias |
| `infirmary` | Enfermería | N0 | 10×8 | No | 1·1·1·0 | `main_reception` | Recuperación sin dejar registro; suministros médicos | — |
| `ground_toilets` | Baños de planta baja | N0 | 8×6 | No | 0·1·0·0 | `main_reception` | **Punto ciego. Espacio seguro para llamadas.** | — |

### 22.5 Nave fabril
*Banda `factory` · Kit `industrial` · Ambiente `assembly_line` · Ruido 0,9*

| id | Nombre | Acred. | Dim | Cám | Ocupación | Conecta con | Oportunidad | Riesgo |
|---|---|---|---|---|---|---|---|---|
| `assembly_line` | Línea de ensamblaje | N3 | 40×20 | Sí | 18·6·18·0 | `mold_room`, `quality_control`, `factory_break_room` | **Máscara acústica.** Maquinaria que apagar en el cierre | Densidad alta de operarios |
| `mold_room` | Sala de moldes y hormas | N3 | 16×12 | No | 4·1·4·0 | `assembly_line`, `materials_store` | **Sabotaje de moldes: degrada la calidad del producto** | Detectable en control de calidad |
| `materials_store` | Almacén de materiales | N3 | 20×16 | No | 2·0·2·0 | `mold_room`, `loading_dock` | Cuero y suelas revendibles | Inventario semanal |
| `quality_control` | Control de calidad | N3 | 14×10 | No | 3·1·3·0 | `assembly_line`, `finished_goods` | **Emisión de informes de defecto que hunden al capataz** | Los informes llevan la firma del emisor |
| `finished_goods` | **Almacén de producto terminado** | N3 / N4 completo | 24×20 | Sí, puerta | 3·1·3·0 | `quality_control`, `loading_dock`, `freight_elevator` | **Robo en tres escalas: bolsillo, caja y palé** | **Inventario semanal: los robos afloran con retardo** |
| `loading_dock` | Muelle de carga | N4 | 20×16 | Sí | 4·2·4·1 | `finished_goods`, `general_warehouse`, exterior | **Extracción de palés con transportista cómplice** | Albaranes rastreables |
| `foreman_office` | Oficina del capataz | N4 | 10×8 | No | 1·0·1·0 | `assembly_line` | Albaranes falsificables; ordenador de Ernie Vaughn | Ernie entra con frecuencia irregular |
| `factory_break_room` | Sala de descanso de fábrica | N3 | 12×10 | No | 2·12·2·0 | `assembly_line` | **Corrillo de operarios: información y medición del descontento** | — |
| `factory_dye_lab` | Laboratorio de tintes y pegamentos | N3 | 14×12 | No | 2·0·2·0 | `mold_room`, `service_tunnel` | Químicos; **sabotajes con apariencia de accidente** | Manipulación errónea genera evidencia física |

### 22.6 Planta 1 — Personas y papeles
*Banda `the_pit` · Kit `office_admin` · Ambiente `office_hum` · Ruido 0,2*

| id | Nombre | Acred. | Dim | Cám | Ocupación | Conecta con | Oportunidad | Riesgo |
|---|---|---|---|---|---|---|---|---|
| `hr_office` | **Recursos Humanos** | N2 + RRHH | 16×12 | No | 4·1·4·0 | `corridors_low`, `p1_toilets` (conducto) | **Expedientes completos de toda la plantilla: rutinas, secretos, domicilios.** Formularios de expulsión en blanco | Amelia Cole permanece en la sala casi todo el horario |
| `training_room` | Sala de formación | N1 | 14×12 | No | 0·0·2·0 | `corridors_low` | *Ubicación del tutorial* | — |
| `payroll_office` | Administración de nóminas | N2 | 12×10 | No | 3·1·3·0 | `corridors_low` | **Manipulación salarial; creación de empleados fantasma** | Auditoría detecta acumulación |
| `main_copyroom` | Fotocopiadora central | N2 | 10×8 | No | 1·1·1·0 | `corridors_low` | **Visibilidad de todo documento copiado.** Máscara acústica leve | — |
| `p1_toilets` | Baños planta 1 | N1 | 8×6 | No | 0·1·0·0 | `corridors_low`, `vent_network` | **Punto ciego con acceso a conducto hacia RRHH** | — |

### 22.7 Planta 2 — La voz al cliente
*Banda `the_pit` · Kit `callcenter` · Ambiente `call_center_noise` · Ruido **0,95***

| id | Nombre | Acred. | Dim | Cám | Ocupación | Conecta con | Oportunidad | Riesgo |
|---|---|---|---|---|---|---|---|---|
| `call_center` | Call center | N1 | 30×24 | No | 38·8·38·0 | `corridors_low` | **Máscara acústica permanente de mayor intensidad del edificio.** Quejas utilizables contra departamentos | Treinta y ocho observadores potenciales |
| `complaints_office` | Oficina de reclamaciones | N2 | 12×10 | No | 3·1·3·0 | `call_center` | Reclamaciones que desacreditan a otros departamentos | — |
| `orders_archive` | Archivo activo de pedidos | N2 | 14×12 | No | 2·0·2·0 | `corridors_low` | **Extravío deliberado de pedidos de rivales** | Los pedidos perdidos se auditan mensualmente |
| `p2_toilets` | Baños planta 2 | N1 | 8×6 | No | 0·1·0·0 | `corridors_low`, `vent_network` | Punto ciego | — |

### 22.8 Planta 3 — El entorno inicial
*Banda `the_pit` · Kit `open_office` · Ambiente `office_hum` · Ruido 0,2*

| id | Nombre | Acred. | Dim | Cám | Ocupación | Conecta con | Oportunidad | Riesgo |
|---|---|---|---|---|---|---|---|---|
| `wing_3a` | Ala 3A | N1 | 20×14 | No, pasillo sí | 12·2·12·0 | `corridors_low` | Segundo grupo de personajes observables | — |
| `wing_3b` | **Ala 3B — puesto inicial** | N1 | 20×14 | No, pasillo sí | 12·2·12·0 | `corridors_low`, `p3_pantry` | **Escritorio propio: llaves, estampa, ordenador.** Vigilancia próxima de once compañeros | **Once observadores permanentes a menos de tres metros** |
| `wing_3c` | Ala 3C | N1 | 20×14 | No | 11·2·11·0 | `corridors_low` | Tercer grupo de personajes | — |
| `p3_meeting_small` | Sala de reuniones pequeña | N1 | 10×8 | No | 0·0·4·0 | `corridors_low` | **Desocupada la mayor parte del horario** | — |
| `p3_pantry` | Office de planta | N1 | 8×8 | No | 1·2·1·0 | `wing_3b` | **Nevera comunal: sustracción de alimentos.** Punto ciego | Tránsito frecuente para café |
| `p3_copyroom` | Fotocopiadora planta 3 | N1 | 6×6 | No | 0·0·1·0 | `corridors_low` | Copias excedentes | — |
| `p3_toilets` | Baños planta 3 | N1 | 8×6 | No | 0·1·0·0 | `corridors_low`, `vent_network` | Punto ciego | — |

### 22.9 Planta 4 — Administración
*Banda `the_pit` · Kit `open_office` · Ambiente `office_hum` · Ruido 0,2*

| id | Nombre | Acred. | Dim | Cám | Ocupación | Conecta con | Oportunidad | Riesgo |
|---|---|---|---|---|---|---|---|---|
| `wing_4a` | Ala 4A, ventas internas | N1 | 20×14 | No | 12·2·12·0 | `corridors_low` | Personajes con ideas de rama comercial | — |
| `wing_4b` | Ala 4B, facturación | N1 | 20×14 | No | 11·2·11·0 | `corridors_low` | **Facturas inflables en pequeñas cuantías** | Contabilidad revisa mensualmente |
| `wing_4c` | Ala 4C, soporte administrativo | N1 | 18×14 | No | 10·2·10·0 | `corridors_low` | — | — |
| `foosball_room` | Sala de descanso con futbolín | N1 | 12×10 | No | 3·6·4·0 | `corridors_low` | **Corrillo permanente: información de coste reducido** | — |
| `office_supplies` | Almacén de material de oficina | N2 | 12×10 | No | 1·0·1·0 | `corridors_low` | **Sustracción y reventa: ~35 € diarios** | Inventario mensual |
| `p4_toilets` | Baños planta 4 | N1 | 8×6 | No | 0·1·0·0 | `corridors_low`, `vent_network` | Punto ciego | — |

### 22.10 Planta 5 — Contabilidad y auditoría
*Banda `the_pit` · Kit `office_formal` · Ambiente `quiet_office` · Ruido 0,15*

| id | Nombre | Acred. | Dim | Cám | Ocupación | Conecta con | Oportunidad | Riesgo |
|---|---|---|---|---|---|---|---|---|
| `accounting` | Contabilidad general | N2 | 20×16 | No | 10·2·10·0 | `corridors_low` | **Falsificación de asientos; detección de fraudes ajenos utilizables como chantaje** | Contables con Perspicacia media-alta |
| `internal_audit` | **Auditoría interna** | N2 | 14×12 | No | 5·1·5·0 | `corridors_low` | **Visibilidad de las investigaciones en curso antes de recibir notificación** | **Territorio de Rose Miller** |
| `floor_safe` | Caja de planta | N4 | 6×6 | **Sí** | 0·0·0·0 | `accounting` | **Efectivo disponible** | Cámara y registro de apertura |
| `chief_accountant_office` | Despacho del jefe de contabilidad | N3 | 10×8 | No | 1·0·1·0 | `accounting` | Ordenador con acceso a los libros | — |
| `p5_toilets` | Baños planta 5 | N1 | 8×6 | No | 0·1·0·0 | `corridors_low`, `vent_network` | Punto ciego | — |

### 22.11 Plantas 6 a 9 — Los especialistas
*Banda `the_specialists` · Ambiente `quiet_office` · Ruido 0,2*

**Planta 6 — Marketing** *(Kit `creative`)*

| id | Nombre | Acred. | Dim | Ocupación | Oportunidad | Riesgo |
|---|---|---|---|---|---|---|
| `campaign_room` | Sala de campañas | N3 | 18×14 | 8·2·8·0 | **Autoelogio: inserción del nombre y rostro propios en campañas** | El fracaso de una campaña con rostro propio es público |
| `product_photo_studio` | Estudio de fotografía de producto | N3 | 16×12 | 3·1·3·0 | Material de campaña sustraíble | — |
| `social_media_office` | Oficina de redes sociales | N3 | 12×10 | 4·1·4·0 | Modificación del sentimiento público a escala reducida | — |
| `graphic_design` | Diseño gráfico | N3 | 14×12 | 5·1·5·0 | **Falsificación de documentos con apariencia oficial** | — |
| `p6_toilets` | Baños planta 6 | N3 | 8×6 | 0·1·0·0 | Punto ciego con conducto | — |

**Planta 7 — Diseño de producto** *(Kit `creative`)*

| id | Nombre | Acred. | Dim | Ocupación | Oportunidad | Riesgo |
|---|---|---|---|---|---|---|
| `shoe_design_studio` | Estudio de diseño | N3 | 20×16 | 9·2·9·0 | **Fuente principal de ideas de calidad alta del juego** | Diseñadores con Ambición elevada: competidores |
| `prototype_workshop` | Taller de prototipos | N3 | 16×12 | 4·1·4·0 | Prototipos físicos sustraíbles | — |
| `exotic_materials` | Sala de materiales exóticos | N3 | 12×10 | 1·0·1·0 | Materiales de valor elevado | Inventario estricto |
| `walk_test_runway` | Pasarela de pruebas | N3 | 24×8 | 2·0·3·0 | *Comedia:* observación de directivos en situación ridícula | — |
| `historic_designs_archive` | **Archivo de diseños históricos** | N3 | 14×12 | 0·0·1·0 | **Diseños de tres décadas atrás presentables como propios** | Old Ray Cudmore recuerda esos diseños |
| `p7_toilets` | Baños planta 7 | N3 | 8×6 | 0·1·0·0 | Punto ciego con conducto | — |

**Planta 8 — Tecnología** *(Kit `technical_office`)*

| id | Nombre | Acred. | Dim | Ocupación | Oportunidad | Riesgo |
|---|---|---|---|---|---|---|
| `systems_office` | Oficina de sistemas | N3 | 16×14 | 7·2·7·0 | **Accesos y visibilidad de rastros digitales** | Alvin Pyne observa toda actividad |
| `repair_workshop` | Taller de reparación | N3 | 14×12 | 3·1·3·0 | **Los ordenadores ajenos pasan por aquí: instalación de accesos** | — |
| `equipment_store` | Almacén de equipos | N3 | 12×10 | 1·0·1·0 | Equipamiento superior sin justificación | Inventario |
| `it_chief_office` | Despacho del jefe de IT | N4 | 10×8 | 1·0·1·0 | Credenciales de administrador | — |
| `p8_toilets` | Baños planta 8 | N3 | 8×6 | 0·1·0·0 | Punto ciego con conducto | — |

**Planta 9 — Asesoría jurídica** *(Kit `office_formal`)*

| id | Nombre | Acred. | Dim | Ocupación | Oportunidad | Riesgo |
|---|---|---|---|---|---|---|
| `legal_firm` | Bufete interno | N3 | 18×14 | 6·2·6·0 | Contratos, demandas, **documentación comprometedora** | — |
| `notary` | **Notaría interna** | N3 | 10×8 | 1·0·1·0 | **Formalización de los documentos de propiedad: el paso final del juego** | El notario exige verificación si la sospecha es elevada |
| `legal_archive` | Archivo legal | N3 | 14×12 | 1·0·1·0 | Precedentes y contratos históricos | — |
| `legal_director_office` | Despacho del director legal | N5 | 12×10 | 1·0·1·0 | **Revelación de qué documentos transfieren la propiedad** | — |
| `p9_toilets` | Baños planta 9 | N3 | 8×6 | 0·1·0·0 | Punto ciego con conducto | — |

### 22.12 Plantas 10 a 12 — Dirección de bloques
*Banda `the_specialists` · Kit `management` · Ambiente `executive_quiet` · Ruido 0,1*

**Planta 10 — Dirección de bloques**

| id | Nombre | Acred. | Dim | Cám | Ocupación | Oportunidad |
|---|---|---|---|---|---|---|
| `a10_general_office` | Despacho de Dirección General A10 | N4 | 14×12 | Sí | 1·0·1·0 | Ordenador del Director General de planta |
| `a10_marketing_office` | Despacho de Marketing A10 | N4 | 12×10 | Sí | 1·0·1·0 | *Puesto de Diana Sedgwick* |
| `a10_coordination_office` | Despacho de Coordinación A10 | N4 | 12×10 | Sí | 1·0·1·0 | *Puesto de Iggy Robbins* |
| `block_coordination_room` | Sala de coordinación de bloques | N4 | 16×12 | Sí | 0·0·6·0 | Planificación de la planta completa |
| `p10_secretariat` | Secretaría de planta | N4 | 10×8 | Sí | 2·1·2·0 | **Agendas completas de los directivos de la planta** |
| `p10_toilets` | Baños planta 10 | N4 | 8×6 | No | 0·1·0·0 | Punto ciego |

**Planta 11 — Grandes cuentas**

| id | Nombre | Acred. | Dim | Cám | Ocupación | Oportunidad |
|---|---|---|---|---|---|---|
| `buyer_demo_room` | **Sala de demostraciones a compradores** | N4 | 20×16 | Sí | 4·1·6·0 | **Engaño a compradores: sobreprecio, venta fantasma, mordida** |
| `senior_sales_offices` | Despachos de comerciales senior | N4 | 18×14 | Sí | 6·2·6·0 | Contactos y estructura de comisiones |
| `sales_contracts_room` | Sala de contratos de venta | N4 | 12×10 | Sí | 2·0·2·0 | Contratos falsificables |
| `vip_client_archive` | Archivo de clientes VIP | N4 | 12×10 | Sí | 1·0·1·0 | **Relación de compradores con sus debilidades documentadas** |
| `p11_exec_pantry` | Office ejecutivo | N4 | 8×8 | No | 1·3·1·0 | Escucha de comerciales |
| `p11_toilets` | Baños planta 11 | N4 | 8×6 | No | 0·1·0·0 | Punto ciego |

**Planta 12 — Salas de reunión**

| id | Nombre | Acred. | Dim | Cám | Ocupación | Oportunidad |
|---|---|---|---|---|---|---|
| `aurora_room` | **Sala de reuniones Aurora** | N4 | 24×18 | Sí | 0·0·14·0 | **Presentación de ideas: la escena social decisiva del juego** |
| `meeting_12a` | Sala mediana 12A | N4 | 12×10 | Sí | 0·0·6·0 | Las reuniones vacían despachos |
| `meeting_12b` | Sala mediana 12B | N4 | 12×10 | Sí | 0·0·6·0 | Las reuniones vacían despachos |
| `video_conference` | Sala de videoconferencias | N4 | 14×10 | Sí | 0·0·4·0 | Escucha de reuniones con contrapartes externas |
| `p12_toilets` | Baños planta 12 | N4 | 8×6 | No | 0·1·0·0 | Punto ciego |

### 22.13 Plantas 13 a 17 — El poder
*Banda `the_power` · Kit `executive` · Ambiente `executive_quiet` · Ruido 0,05 · **Cámaras en todos los pasillos***

**Planta 13 — Finanzas**

| id | Nombre | Acred. | Dim | Cám | Ocupación | Oportunidad |
|---|---|---|---|---|---|---|
| `investment_room` | Sala de inversiones | N5 | 16×14 | Sí | 5·1·5·0 | Visibilidad anticipada de movimientos |
| `cfo_office` | Oficina del CFO | N5 | 14×12 | Sí | 1·0·1·0 | **Contraste entre fundamentales reales y valores reportados** |
| `market_data_room` | Sala de datos de mercado | N5 | 14×12 | Sí | 3·1·3·0 | Cotización en tiempo real |
| `treasury` | Tesorería | N5 | 12×10 | Sí | 2·0·2·0 | **Movimiento de capital de cuantía elevada** |
| `p13_toilets` | Baños planta 13 | N5 | 8×6 | No | 0·1·0·0 | Punto ciego |

**Planta 14 — Comunicación**

| id | Nombre | Acred. | Dim | Cám | Ocupación | Oportunidad |
|---|---|---|---|---|---|---|
| `press_room` | Sala de prensa | N5 | 16×14 | Sí | 4·1·4·0 | **Los periodistas vigilan al jugador desde aquí a partir del escalón 5** |
| `public_relations` | Relaciones públicas | N5 | 14×12 | Sí | 5·1·5·0 | **Supresión de noticias y fabricación de escándalos ajenos** |
| `recording_studio` | Estudio de grabación corporativo | N5 | 14×12 | No | 2·0·2·0 | Material grabado comprometedor |
| `comms_director_office` | Despacho del director de comunicación | N5 | 12×10 | Sí | 1·0·1·0 | *Puesto de Bree Nash* |
| `p14_toilets` | Baños planta 14 | N5 | 8×6 | No | 0·1·0·0 | Punto ciego |

**Planta 15 — Seguridad corporativa**

| id | Nombre | Acred. | Dim | Cám | Ocupación | Oportunidad |
|---|---|---|---|---|---|---|
| `security_director_office` | Despacho del Director de Seguridad | N5 | 12×10 | Sí | 1·0·1·0 | **Punto de convergencia de todas las grabaciones** |
| `alarm_central` | Central de alarmas | N5 | 10×8 | Sí | 2·1·2·1 | Desactivación selectiva de alarmas por zona |
| `guard_lockers` | Sala de taquillas de vigilantes | N3 + vigilante | 12×10 | No | 2·3·2·3 | Uniformes, llaves, cuadrante de turnos |
| `interrogation_room` | **Sala de interrogatorios** | N5 | 8×8 | Sí | 0·0·0·0 | *Destino del jugador si encabeza una lista corta* |
| `incident_archive` | Archivo de incidencias | N5 | 12×10 | No | 1·0·1·0 | **Historial completo de incidentes: los casos fríos residen aquí** |
| `p15_toilets` | Baños planta 15 | N5 | 8×6 | No | 0·1·0·0 | Punto ciego |

**Planta 16 — Inversores** *(Kit `executive_lux`)*

| id | Nombre | Acred. | Dim | Cám | Ocupación | Oportunidad |
|---|---|---|---|---|---|---|
| `investor_lounge` | Lounge de inversores | N6 | 20×16 | Sí | 4·2·6·0 | **Trato personal con los seis inversores** |
| `trading_room` | Sala de bolsa | N6 | 16×14 | Sí | 4·1·4·0 | Operación directa en el mercado |
| `investor_offices` | Despachos de inversionistas | N6 | 18×14 | Sí | 3·1·3·0 | Estrategias y secretos individuales |
| `results_room` | **Sala de presentación de resultados** | N6 | 22×16 | Sí | 0·0·0·0 | **El evento trimestral de mayor riesgo** |
| `p16_toilets` | Baños planta 16 | N6 | 8×6 | No | 0·1·0·0 | Punto ciego |

**Planta 17 — Alta directiva** *(Kit `executive_lux`)*

| id | Nombre | Acred. | Dim | Cám | Ocupación | Oportunidad |
|---|---|---|---|---|---|---|
| `area_director_offices_a` | Despachos de directores de área, ala A | N6 | 16×12 | Sí | 3·0·3·0 | — |
| `area_director_offices_b` | Despachos de directores de área, ala B | N6 | 16×12 | Sí | 3·0·3·0 | — |
| `area_director_offices_c` | Despachos de directores de área, ala C | N6 | 16×12 | Sí | 2·0·2·0 | — |
| `exec_secretariats` | Secretarías | N6 | 12×10 | Sí | 4·1·4·0 | **Agendas de la alta directiva** |
| `exec_dining` | Comedor ejecutivo | N6 | 18×14 | No | 0·8·0·0 | **Manutención de lujo sin coste; conversaciones de alto nivel** |
| `p17_toilets` | Baños planta 17 | N6 | 8×6 | No | 0·1·0·0 | Punto ciego |

### 22.14 Plantas 18 a 20 — El trono
*Banda `the_throne` · Ambiente `silence` · Ruido 0,0 · **Cámaras en todos los pasillos***

**Planta 18 — El consejo** *(Kit `boardroom`)*

| id | Nombre | Acred. | Dim | Cám | Ocupación | Oportunidad |
|---|---|---|---|---|---|---|
| `board_antechamber` | Antesala del consejo | N6 | 12×10 | Sí | 1·0·2·0 | Escucha previa a las sesiones |
| `boardroom` | Sala del consejo de administración | N6 | 24×18 | Sí | 0·0·0·0 | **Votaciones sobre promociones y expulsiones** |
| `board_confidential_archive` | **Archivo confidencial del consejo** | N6 | 12×10 | Sí | 0·0·0·0 | **Los secretos corporativos de máximo nivel** |
| `board_secretary_office` | Despacho del secretario del consejo | N6 | 10×8 | Sí | 1·0·1·0 | **Las actas: su falsificación es el instrumento de mayor alcance** |
| `p18_toilets` | Baños planta 18 | N6 | 8×6 | No | 0·1·0·0 | Punto ciego |

**Planta 19 — Antesala de la cúspide** *(Kit `boardroom`)*

| id | Nombre | Acred. | Dim | Cám | Ocupación | Oportunidad |
|---|---|---|---|---|---|---|
| `vice_ceo_office` | Despacho del vice-CEO | N6 | 16×14 | Sí | 1·0·1·0 | *Puesto de Preston Vaile III* |
| `crisis_room` | Sala de crisis | N6 | 16×12 | Sí | 0·0·0·0 | Se activa ante escándalo |
| `exec_gym` | Gimnasio ejecutivo | N6 | 18×14 | No | 1·2·2·0 | **Directivos desprevenidos y sin vigilancia** |
| `exec_spa` | Spa ejecutivo | N6 | 14×12 | No | 0·2·1·0 | **Conversaciones de máxima confidencialidad** |
| `exec_secretariat` | Secretaría ejecutiva | N6 | 10×8 | Sí | 2·0·2·0 | Agenda de Harlan Voss |
| `p19_toilets` | Baños planta 19 | N6 | 8×6 | No | 0·1·0·0 | Punto ciego |

**Planta 20 y azotea — El trono** *(Kit `ceo`)*

| id | Nombre | Acred. | Dim | Cám | Ocupación | Oportunidad |
|---|---|---|---|---|---|---|
| `ceo_secretariat` | Secretaría del consejero delegado | N7 | 12×10 | Sí | 1·1·1·0 | **Pearl Osgood: el obstáculo real de la planta** |
| `ceo_office` | **Despacho del consejero delegado** | N7 | 20×16 | Pasillo sí, interior no | 1·0·1·0 | **La caja fuerte con los documentos de propiedad** |
| `ceo_private_room` | Sala privada | N7 | 10×8 | No | 0·1·0·0 | Secretos personales de Voss |
| `ceo_boardroom` | Sala de juntas del consejero delegado | N7 | 16×12 | Sí | 0·0·2·0 | — |
| `rooftop_terrace` | Terraza y helipuerto | N7 | 24×20 | Solo puerta | 0·0·1·0 | **Acceso alternativo al despacho** |
| `rooftop_machine_room` | Cuarto de máquinas de azotea | N5, mantenimiento | 10×8 | No | 0·0·0·0 | **Conducto con salida al despacho del consejero delegado** |

### 22.15 Espacios transversales

| id | Nombre | Acred. | Cám | Notas |
|---|---|---|---|---|
| `main_elevator_1` | Ascensor principal 1 | Variable | **Sí** | Lector de tarjeta por planta: registro permanente |
| `main_elevator_2` | Ascensor principal 2 | Variable | **Sí** | Idéntico |
| `main_stairs` | Escaleras principales | N1 | Sí | Muy transitadas en franjas de entrada y salida |
| `service_stairs` | **Escaleras de servicio** | N1 | **No** | S3 a P20. Coincidir con otro personaje genera sospecha |
| `vent_network` | **Red de conductos** | Mantenimiento | **No** | Desplazamiento lento; ruidoso a velocidad alta |
| `freight_elevator` | Montacargas | N3 | No | Único medio para cajas grandes y cuerpos |
| `cleaning_closet_low` | Cuarto de limpieza, plantas 1–5 | N1 | No | **Escondite** |
| `cleaning_closet_mid` | Cuarto de limpieza, plantas 6–12 | N3 | No | **Escondite** |
| `cleaning_closet_high` | Cuarto de limpieza, plantas 13–17 | N5 | No | **Escondite** |
| `cleaning_closet_top` | Cuarto de limpieza, plantas 18–20 | N6 | No | **Escondite** |
| `corridors_low` | Pasillos, plantas 1–12 | Variable | **Sí** | Patrullados por vigilantes |
| `corridors_high` | Pasillos, plantas 13–20 | Variable | **Sí** | Patrullaje intensificado |

### 22.16 Exterior
*Banda `exterior` · Kit `city` · Ambiente `street_ambient`*

| id | Nombre | Dim | Oportunidad | Riesgo |
|---|---|---|---|---|
| `player_flat` | Domicilio del jugador | 14×12 | **Descanso, que guarda la partida; manutención; ocultación de objetos** | — |
| `supermarket` | Supermercado | 16×12 | Adquisición de alimentos | Coste diario obligatorio |
| `clothes_shop` | Tienda de ropa | 12×10 | **Pasamontañas y trajes ejecutivos** | Precio elevado |
| `street` | Calle entre domicilio y oficina | 40×8 | Rutas, paradas, **corrillo de fumadores** | Testigos ocasionales |
| `alleys` | Callejones | 20×6 | **Evasión policial** | Sin salida si se produce cerco |
| `npc_house_humble` | Vivienda de personaje, piso modesto | 12×10 | Robo y saqueo | Vecindario próximo |
| `npc_house_semi` | Vivienda de personaje, adosado | 16×12 | Botín superior | Idéntico |
| `npc_house_mansion` | Vivienda de personaje, residencia de directivo | 24×18 | **Máximo botín del exterior** | Alarma y seguridad privada |
| `transport_stop` | Parada de transporte | 8×6 | Seguimiento discreto | — |
| `police_station` | Comisaría | 16×12 | *Origen de la respuesta policial* | **Tiempo de respuesta computado** |

**Recuento por sección:** S3 (5) + S2 (4) + S1 (7) + PB (10) + Fábrica (9) + P1 (5) + P2 (4) + P3 (7) + P4 (6) + P5 (5) + P6 (5) + P7 (6) + P8 (5) + P9 (5) + P10 (6) + P11 (6) + P12 (5) + P13 (5) + P14 (5) + P15 (6) + P16 (5) + P17 (6) + P18 (5) + P19 (6) + P20 (6) + Transversales (12) + Exterior (10) = **166 espacios**.

---

## 23. Catálogo de ocupaciones

**Clave de columnas:** *R* rango · *E* escalón · *N* acreditación · *€* salario diario · *PF* nivel de expediente de personal · *Deber* tipo y cantidad · *Coste* tiempo de juego del deber.

### 23.1 Escalón 1 — Base

| # | id | Denominación | R | N | € | PF | Deber | Coste | Oportunidad exclusiva | Riesgo exclusivo | Promociona a |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `eternal_intern` | Becario eterno | 0 | 1 | 5 en vales | 1 | Recados sin especificar | Variable | **Invisibilidad social: ningún personaje registra su presencia** | Fracasar supone expulsión definitiva | R1 |
| 2 | `email_worker_3b` | **Trabajador de emails del 3B** | 1 | 1 | 30 | 1 | Volumen: 8 correos | 45 min | Vigilancia próxima de once compañeros; aprendizaje de rutinas sin expectativas sobre él | Once observadores permanentes a tres metros | R2 (`order_filer`, `copy_operator`) · salto a R4 |
| 3 | `order_filer` | Archivador de pedidos | 2 | 1 | 34 | 1 | Volumen: 40 pedidos | 50 min | **Extravío deliberado de pedidos de rivales**; conocimiento del flujo documental | El extravío se audita mensualmente | R3 |
| 4 | `copy_operator` | Operario de fotocopias | 2 | 1 | 32 | 1 | Volumen: 200 copias | 60 min | **Visibilidad de todo documento reproducido: información temprana de coste nulo** | Ninguno significativo | R3 |
| 5 | `call_operator` | Teleoperador de atención al cliente | 3 | 1 | 38 | 1 | Volumen: 25 llamadas | 90 min | Máscara acústica permanente; quejas utilizables contra departamentos | Deber de duración elevada | R4 |
| 6 | `line_operator` | Operario de línea de fábrica | 3 | 1 | 36 | 1 | Cuota: 120 unidades | 120 min | **Acceso a la nave fabril antes de la acreditación N3**; primer robo de producto | Deber de máxima duración del escalón | R4 |
| 7 | `mail_courier` | **Repartidor de correo interno** *(puesto-llave)* | 4 | 1 | 40 | 1 | Ronda: 9 plantas | 90 min | **Justificación para transitar las plantas 1 a 9 sin generar sospecha.** Interceptación de correspondencia | Si falta contenido de un sobre, el reparto lo hizo él | R5 |
| 8 | `billing_clerk` | Auxiliar administrativo de facturación | 5 | 1 | 42 | 1 | Volumen: 30 facturas | 60 min | **Inflación de facturas en cuantías de 2 a 3 €, acumulativas** | Contabilidad revisa mensualmente | R6 (`payroll_clerk`, `warehouse_assistant`) |

### 23.2 Escalón 2 — Junior

| # | id | Denominación | R | N | € | PF | Deber | Coste | Oportunidad exclusiva | Riesgo exclusivo | Promociona a |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 9 | `payroll_clerk` | Administrativo de nóminas | 6 | 2 | 50 | 2 | Volumen: nóminas | 75 min | **Incremento del salario propio en 40–60 € mensuales sin detección inmediata** | La acumulación se detecta en auditoría | R7 |
| 10 | `warehouse_assistant` | Ayudante de almacén de oficina | 6 | 2 | 48 | 2 | Cuota: inventario | 60 min | **Sustracción y reventa de material: ~35 € diarios** | Inventario mensual | R7 |
| 11 | `junior_sales` | Junior de ventas internas | 7 | 2 | 55 | 2 | Cuota: 5 ventas | 90 min | **Primeros compradores engañables: sobreprecio con apropiación del margen** | Reclamaciones con retardo de semanas | R8 |
| 12 | `cleaner` | **Auxiliar de limpieza** *(puesto-llave)* | 7 | 2 | 52 | 2 | Ronda: zona completa antes de las 21:00 | 150 min | **Acceso a la totalidad de su zona fuera de horario con llaves maestras. Invisibilidad social del personal de limpieza** | Si falta algo en su zona, la lista de sospechosos es de dos nombres | R8 · lateral inverso a R8–R9 |
| 13 | `junior_accountant` | Junior de contabilidad | 8 | 2 | 58 | 2 | Volumen: cajas menores | 70 min | **Localización exacta del capital de la compañía**; acceso justificado a la planta 5 | Contables perspicaces en la sala | R9 |
| 14 | `maintenance_aide` | **Auxiliar de mantenimiento** *(puesto-llave)* | 8 | 2 | 56 | 2 | Ronda: partes de avería | 100 min | **Acceso legítimo a sótanos y conductos. Uniforme como disfraz. Capacidad de averiar deliberadamente una cámara o cerradura y ser convocado a repararla** | Los partes falsos se auditan | R9 · lateral inverso |
| 15 | `hr_assistant` | Asistente de RRHH | 9 | 2 | 62 | 2 | Volumen: expedientes | 80 min | **Acceso permanente a expedientes: chantajes tempranos, rutinas y domicilios de toda la plantilla** | Amelia Cole supervisa | R10 (`senior_sales`, `security_guard`) |

### 23.3 Escalón 3 — Senior

| # | id | Denominación | R | N | € | PF | Deber | Coste | Oportunidad exclusiva | Riesgo exclusivo | Promociona a |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 16 | `senior_sales` | Senior de ventas | 10 | 3 | 75 + comisión | 3 | Cuota: 12 ventas | 120 min | Comisiones legítimas apreciables; engaño a compradores de volumen medio | Objetivos de venta exigentes | R11 |
| 17 | `security_guard` | **Vigilante de seguridad** *(puesto-llave)* | 10 | 3 | 70 | 3 | Ronda por franjas más cierre: **salir el último, cerrar y apagar la maquinaria** | 90 min por ronda | **Saqueo nocturno de la totalidad del edificio.** Llaves de casi todo. Conocimiento memorizado de cámaras y puntos ciegos | **Olvidar cualquier tarea de cierre supone expulsión.** Sospecha máxima automática si desaparece algo | R17 (salto doble natural) · lateral a R11–R12 |
| 18 | `marketing_creative` | Creativo de marketing | 11 | 3 | 78 | 3 | Entrega: piezas de campaña | 120 min | **Autoelogio: inserción del nombre y rostro propios en campañas.** Reputación pasiva | El fracaso de una campaña propia es público | R12 |
| 19 | `junior_shoe_designer` | Diseñador junior de zapatos | 11 | 3 | 76 | 3 | Entrega: bocetos semanales | 110 min | **Apropiación de diseños del archivo histórico de treinta años atrás** | Old Ray Cudmore recuerda esos diseños | R12 |
| 20 | `it_technician` | Técnico de IT | 12 | 3 | 82 | 3 | Volumen: tickets | 90 min | **Manipulación legítima de ordenadores ajenos: accesos, copias, sabotaje sin intrusión** | Todo acceso queda registrado | R13 |
| 21 | `paralegal` | Paralegal del bufete interno | 12 | 3 | 80 | 3 | Entrega: contratos | 100 min | **Aprendizaje de falsificación documental con validez aparente**; acceso a demandas comprometedoras | El bufete revisa por duplicado | R13 |
| 22 | `senior_accountant` | Contable senior | 13 | 3 | 88 | 3 | Entrega: cierre mensual | 180 min | **Falsificación de asientos. Detección de fraudes ajenos utilizables como chantaje sobre superiores** | El cierre mensual es auditado | R14 |
| 23 | `quality_analyst` | Analista de reclamaciones y calidad | 14 | 3 | 85 | 3 | Entrega: informes de calidad | 120 min | **Emisión de informes de defecto que provocan la expulsión del capataz o del Director de Fábrica** | Los informes llevan firma; un informe falso verificado es evidencia | R15 (`wing_3b_chief`, `factory_foreman`) |

### 23.4 Escalón 4 — Jefe de equipo

| # | id | Denominación | R | N | € | PF | Deber | Coste | Oportunidad exclusiva | Riesgo exclusivo | Promociona a |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 24 | `wing_3b_chief` | Jefe del ala 3B | 15 | 4 | 110 | 4 | Cuota: rendimiento del ala | 90 min | **Asignación de tareas y puestos: determina quién está dónde y cuándo. Permite desplazar testigos y aislar objetivos** | El rendimiento del ala se evalúa mensualmente | R16 |
| 25 | `factory_foreman` | Capataz de fábrica | 15 | 4 | 115 | 4 | Cuota: producción e inventario | 120 min | **Robo de producto a escala de palé. Albaranes falsificables. Incriminación del Director de Fábrica** | El descuadre de inventario apunta primero al capataz | R16 |
| 26 | `purchasing_chief` | Jefe de compras | 16 | 4 | 125 | 4 | Entrega: proveedores | 100 min | **Recepción de sobornos de proveedores: primera fuente de ingreso pasivo. Selección deliberada de proveedor deficiente como sabotaje** | Los contratos son auditables | R17 |
| 27 | `it_team_lead` | Jefe de equipo de IT | 16 | 4 | 120 | 4 | Cuota: disponibilidad de sistemas | 90 min | **Credenciales de administrador parciales: lectura de correo ajeno, borrado de registros menores** | Los borrados dejan metarregistro | R17 |
| 28 | `payroll_manager` | Responsable de nóminas | 17 | 4 | 135 | 4 | Entrega: nómina completa | 120 min | **Creación de empleados ficticios con abono a cuenta propia** | Auditoría interna lo detecta si se prolonga meses | R18 |
| 29 | `guard_chief` | Jefe de vigilantes | 17 | 4 | 130 | 4 | Entrega: cuadrante de turnos | 80 min | **Determinación de qué zonas quedan sin vigilancia cada noche.** Acceso rotatorio a la sala de monitores | **Si ocurre un incidente en la zona desatendida, el cuadrante lleva su firma** | R18 |
| 30 | `meeting_coordinator` | Coordinador de reuniones y agendas | 18 | 4 | 128 | 4 | Volumen: agendas | 90 min | **Conocimiento de la ubicación de cada directivo en cada franja. Capacidad de provocar reuniones prolongadas para desalojar un despacho** | — | R19 (`a10_marketing_director`, `a10_coordination_director`) |

### 23.5 Escalón 5 — Dirección de bloque

| # | id | Denominación | R | N | € | PF | Deber | Coste | Oportunidad exclusiva | Riesgo exclusivo | Promociona a |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 31 | `a10_marketing_director` | **Director de Marketing del bloque A10** | 19 | 4+ | 170 | 5 | Entrega: métricas mensuales | 150 min | **Autoelogio a escala industrial: campañas completas con imagen propia. Reputación pasiva diaria. Presupuesto parcialmente desviable** | **Los periodistas de la planta 14 inician seguimiento.** Dos meses deficientes suponen descenso a R15–R16 | R20 |
| 32 | `a10_coordination_director` | **Director de Coordinación del bloque A10** | 19 | 4+ | 170 | 5 | Entrega: flujo operativo | 150 min | **Control del flujo del bloque: generación de cuellos de botella para rivales, favores cuantificables, reasignación de equipos** | El flujo deficiente se atribuye directamente | R20 |
| 33 | `b10_director` | Director del bloque B10, ventas internas | 20 | 4+ | 185 | 5 | Cuota: cifras del bloque | 150 min | **Inflación de cifras con reputación inmediata** | **La discrepancia aflora en aproximadamente dos semanas** | R21 |
| 34 | `c10_director` | Director del bloque C10, administración | 21 | 4+ | 195 | 5 | Entrega: papeleo del bloque | 140 min | **Firma y estampa con validez administrativa: autorizaciones falsas con apariencia legítima** | Un documento verificado y falso es evidencia de peso 5 | R22 |
| 35 | `floor10_general_director` | Director General de la planta 10 | 22 | 4+ | 220 | 5 | **Entrega: informe mensual de área** | **240 min** | **Primer cargo con secretaría propia.** Ensayo de las competencias de dirección | **El primer deber estructuralmente incumplible: exige robo de ideas o asistencia artificial** | R23 (`hr_director`, `factory_director`) |

### 23.6 Escalón 6 — Dirección de área

| # | id | Denominación | R | N | € | PF | Deber | Coste | Oportunidad exclusiva | Riesgo exclusivo | Promociona a |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 36 | `hr_director` | Director de RRHH | 23 | 5 | 280 | 5 | Entrega: rotación y contratación | 150 min | **Expulsión administrativa de cualquier personaje de escalón 4 o inferior mediante procedimiento formal.** Temor generalizado | **Cada despido injusto genera un enemigo externo susceptible de acudir a la prensa** | R24 |
| 37 | `factory_director` | Director de Fábrica | 23 | 5 | 290 | 5 | Cuota: producción total | 160 min | **Desvío de palés completos. Contratación de transportistas cómplices** | **Las huelgas se dirigen contra este cargo** | R24 |
| 38 | `security_director` | **Director de Seguridad** | 24 | 5 | 300 | 5 | **Cierre: último en salir, cerrar, apagar maquinaria** | 30 min | **La totalidad de las grabaciones pasa por este cargo: borrado del rastro propio, investigación selectiva de terceros** | **Olvidar el cierre supone expulsión. Si desaparece algo, fue el último presente** | R25 |
| 39 | `it_director` | Director de IT | 24 | 5 | 295 | 5 | Cuota: disponibilidad global | 140 min | **Lectura de toda comunicación interna. Fabricación de evidencia digital indistinguible de la auténtica** | Un subordinado honesto puede detectar el uso de credenciales | R25 |
| 40 | `comms_director` | Director de Comunicación y Prensa | 25 | 5 | 320 | 5 | Entrega: imagen pública | 140 min | **Supresión de noticias propias y fabricación de escándalos ajenos. La palanca que opera sobre ambos cerebros** | La prensa suprimida puede reaparecer por vía externa | R26 |
| 41 | `legal_director` | **Director Legal** | 26 | 5 | 340 | 5 | Entrega: blindaje jurídico | 150 min | **Revelación de qué documentos transfieren la propiedad de la compañía y qué procedimiento los valida** | El bufete registra las consultas | R27 |
| 42 | `deputy_cfo` | Director Financiero adjunto | 27 | 5 | 360 | 5 | Entrega: tesorería | 160 min | **Movimiento de capital de gran cuantía. Introducción práctica al mercado** | Tesorería se concilia semanalmente | R28 (`cfo`, `coo`) |

### 23.7 Escalón 7 — Alta directiva

| # | id | Denominación | R | N | € | PF | Deber | Coste | Oportunidad exclusiva | Riesgo exclusivo | Promociona a |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 43 | `cfo` | **Director Financiero** | 28 | 6 | 550 | 6 | **Entrega: resultados trimestrales y objetivo bursátil** | **300 min** | **Información privilegiada: el rendimiento económico más elevado del juego. Maquillaje de las cuentas reportadas** | **Dos trimestres deficientes suponen degradación. Un escándalo contable no produce descenso sino investigación terminal** | R30 · R32 |
| 44 | `coo` | Director de Operaciones | 28 | 6 | 540 | 6 | Entrega: operación completa | 280 min | **Robo de ideas a escala industrial: el edificio completo remite informes susceptibles de firma propia** | Responsabilidad sobre fábrica, logística y ventas simultáneamente | R30 · R32 |
| 45 | `investor_relations` | Director de Relación con Inversores | 29 | 6 | 500 | 6 | Entrega: confianza inversora | 200 min | **Los inversores determinan las promociones desde este cargo: soborno, chantaje o generación de rendimiento** | La confianza es medible y su caída es pública | R31 |
| 46 | `chief_auditor` | **Auditor Jefe** | 29 | 6 | 520 | 6 | Entrega: cierre de expedientes de fraude | 220 min | **Cierre definitivo de las investigaciones propias, incluidos los casos fríos históricos. Apertura de investigaciones contra rivales** | **Si un subordinado honesto localiza algo, el escándalo es doble por encubrimiento** | R31 |
| 47 | `board_investor` | Inversionista y miembro del consejo | 30 | 6 | Dividendos ~800 | 6 | Entrega: voto en consejo | 120 min | **Cambio de condición: adquisición de paquete accionarial con la totalidad del capital acumulado y derecho de voto** | **El patrimonio propio queda expuesto al deterioro de la compañía** | R32 |
| 48 | `board_secretary` | Secretario del consejo | 31 | 6 | 480 | 6 | Entrega: actas del consejo | 150 min | **Conocimiento anticipado de toda decisión. Falsificación de acta: el instrumento de mayor alcance del juego** | Un acta falsificada verificada ante notaría es evidencia terminal | R32 |

### 23.8 Escalón 8 — La cúspide

| # | id | Denominación | R | N | € | PF | Deber | Coste | Oportunidad exclusiva | Riesgo exclusivo |
|---|---|---|---|---|---|---|---|---|---|---|
| 49 | `vice_ceo` | Vice-CEO | 32 | 7 | 1.200 | 7 | **Entrega: ausencia de fallos en la compañía completa** | 300 min | Acceso a las plantas 19 y 20. **Preparación de la caída de Voss por cualquiera de las vías disponibles** | **Deber estructuralmente incumplible. Por primera vez un personaje vigila al jugador de forma personal y deliberada** |
| 50 | `ceo` | **Consejero delegado de Stellar Sell** | 33 | 7 | 2.500 + bonus | 7 | Entrega: consejo trimestral, objetivo bursátil, gestión de crisis | Variable | **Acceso a la caja fuerte con los documentos de propiedad: el objetivo final** | **El vice-CEO aspira al cargo. El consejo puede destituir. Y nadie comunica información veraz al ocupante** |

## 24. Catálogo de personajes

### 24.1 Los doce arquetipos con valores base

| id | Denominación | Ambición | Lealtad | Codicia | Valentía | Perspicacia | Sociabilidad |
|---|---|---|---|---|---|---|---|
| `climber` | The Climber | 90 | 30 | 60 | 60 | 70 | 60 |
| `snitch` | The Snitch | 50 | 85 | 20 | 45 | 85 | 70 |
| `bribable` | The Bribable | 55 | 20 | 90 | 35 | 50 | 55 |
| `company_man` | The Company Man | 35 | 95 | 10 | 70 | 65 | 40 |
| `oblivious` | The Oblivious | 25 | 50 | 40 | 30 | 15 | 45 |
| `gossip` | The Gossip | 40 | 45 | 45 | 40 | 70 | 95 |
| `burnout` | The Burnout | 10 | 15 | 55 | 25 | 40 | 30 |
| `old_hand` | The Old Hand | 15 | 60 | 30 | 75 | 90 | 50 |
| `rookie` | The Rookie | 60 | 70 | 30 | 30 | 30 | 35 |
| `hardliner` | The Hardliner | 50 | 70 | 25 | 90 | 60 | 40 |
| `coward` | The Coward | 45 | 50 | 60 | 10 | 60 | 50 |
| `incorruptible` | The Incorruptible | 30 | 90 | 5 | 80 | 80 | 45 |

**Variación individual:** cada personaje generado recibe ±15 en cada rasgo, con acotación al intervalo 0–100.

### 24.2 Los veintitrés personajes nominados con valores definitivos

| id | Nombre | Ocupación | Arquetipo | Amb | Leal | Cod | Val | Per | Soc | Debilidad explotable | Riesgo que representa |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `npc_debbie_foyle` | Debbie Foyle | `order_filer` | `gossip` | 42 | 40 | 48 | 38 | 72 | **96** | Suministrarle información: distribuye lo que se le proporcione | **Distribuye también lo que observe del jugador** |
| `npc_george_penn` | George Penn | `email_worker_3b` | `snitch` | 55 | 88 | 18 | 48 | 84 | 68 | Concederle un mérito genera favor en su registro | Acude a Security ante cualquier anomalía |
| `npc_nate_brackley` | Nate Brackley | `email_worker_3b` | `oblivious` | 22 | 48 | 42 | 28 | **12** | 40 | Innecesaria: no percibe nada | Prácticamente ninguno |
| `npc_claudia_reeves` | Claudia Reeves | `email_worker_3b` | `climber` | **94** | 28 | 58 | 62 | 74 | 58 | Su ambición: presenta ideas con urgencia | **Primer competidor. Genera ideas de calidad 60–90** |
| `npc_ray_cudmore` | Old Ray Cudmore | `order_filer` | `old_hand` | 12 | 62 | 28 | 78 | **92** | 48 | El respeto sostenido: revela accesos y rutinas del edificio | Detecta cualquier anomalía de inmediato |
| `npc_sonia_vail` | Sonia Vail | `email_worker_3b` | `rookie` | 58 | 72 | 32 | 28 | 32 | 30 | Su aislamiento social: sus afirmaciones no propagan | Puede convertirse en aliada o en acusadora |
| `npc_bernard_lasker` | Bernard Lasker | `wing_3b_chief` | `hardliner` | 52 | 72 | 22 | **92** | 58 | 38 | **Solo evalúa las cifras del ala: si el ala rinde, ignora el resto** | Patrulla el ala con frecuencia alta |
| `npc_amelia_cole` | Amelia Cole | `hr_assistant` → `hr_director` | `incorruptible` | 32 | **94** | 8 | 78 | 76 | 42 | **Ninguna. Probabilidad de soborno nula** | Custodia los expedientes completos |
| `npc_tom_iverson` | Tom Iverson | `security_guard` | `bribable` | 50 | 18 | **92** | 32 | 48 | 52 | Capital, en cuantías reducidas | Ninguno mientras se le pague |
| `npc_ludmila_petrova` | Ludmila Petrova | `security_guard` (nocturno) | `hardliner` | 48 | 74 | 20 | **94** | **82** | 36 | **Ninguna asequible** | **Obstáculo principal del saqueo nocturno** |
| `npc_connie_marks` | Connie Marks | `cleaner` | `old_hand` | 14 | 58 | 34 | 72 | **90** | 54 | Trato considerado sostenido | **Presencia toda actividad fuera de horario sin ser observada** |
| `npc_frank_rudd` | Frank Rudd | `maintenance_aide` | `burnout` | 8 | 14 | 58 | 22 | 38 | 28 | Cantidad irrisoria: cede el uniforme | Ninguno |
| `npc_ernie_vaughn` | Ernie Vaughn | `factory_foreman` | `climber` | **88** | 32 | 64 | 58 | 66 | 56 | Su ambición | Competidor por R15; candidato a incriminación |
| `npc_diana_sedgwick` | Diana Sedgwick | `a10_marketing_director` | `climber` | **92** | 26 | 62 | 56 | 68 | 72 | **El halago directo** | Aplica el autoelogio contra el jugador |
| `npc_iggy_robbins` | Iggy Robbins | `a10_coordination_director` | `bribable` | 58 | 24 | 78 | 40 | 62 | 60 | **Favores, no capital.** Mantiene contabilidad de la deuda | Reclama el cobro en el momento más inoportuno |
| `npc_rose_miller` | **Rose Miller** | `internal_audit` → `chief_auditor` | `incorruptible` | 34 | **92** | 4 | 82 | **84** | 44 | **Ninguna** | **Antagonista estructural de la partida completa** |
| `npc_alvin_pyne` | Alvin Pyne | `it_director` | `coward` | 44 | 52 | 62 | **8** | 64 | 48 | **Protección: se convierte en aliado permanente** | Silencia por temor, pero conserva la información |
| `npc_bree_nash` | Bree Nash | `comms_director` | `bribable` | 62 | 34 | 84 | 44 | 70 | 66 | Capital, en cuantía elevada | Conoce todo lo que ha enterrado |
| `npc_maurice_sandbell` | Maurice Sandbell | `cfo` | `climber` | **90** | 22 | 76 | 54 | 72 | 50 | **Opera con información privilegiada por cuenta propia: descubrirlo lo somete** | Competidor directo en el escalón 7 |
| `npc_lorna_vickers` | Lorna Vickers | `investor_relations` | `gossip` | 56 | 42 | 58 | 46 | 68 | **94** | Su red de contactos entre inversores | Distribuye información en el círculo de inversores |
| `npc_preston_vaile` | Preston Vaile III | `vice_ceo` | `hardliner` | **88** | 42 | 48 | **88** | 74 | 52 | **Su hostilidad hacia Voss: aliado táctico** | **Aspira a la misma silla final** |
| `npc_harlan_voss` | **Harlan Voss** | `ceo` | *(único)* | 78 | **0** | 68 | 82 | **95** | 58 | **Nadie le comunica información veraz: es manipulable mediante intermediarios** | Perspicacia máxima del juego |
| `npc_pearl_osgood` | Pearl Osgood | `ceo_secretariat` | `company_man` | 28 | **96** | 6 | 74 | 78 | 46 | **Chantaje derivado de su expediente, o favor de magnitud extraordinaria** | **Conoce la combinación de la caja fuerte. Si el intento fracasa, informa a Voss** |

### 24.3 Generación de la plantilla restante

**Distribución por departamento:**

| Departamento | Población | Bolsa de arquetipos |
|---|---|---|
| Fábrica | 25 | `burnout` 30% · `hardliner` 20% · `oblivious` 15% · `gossip` 10% · `climber` 10% · `coward` 10% · `old_hand` 5% |
| Plantas base 1–5 | 45 | `oblivious` 20% · `gossip` 15% · `rookie` 15% · `snitch` 12% · `climber` 12% · `burnout` 10% · `coward` 10% · `company_man` 6% |
| Especializadas 6–9 | 30 | `climber` 25% · `company_man` 15% · `gossip` 12% · `coward` 12% · `snitch` 10% · `old_hand` 10% · `bribable` 10% · `oblivious` 6% |
| *Auditoría y Legal (subconjunto)* | *8* | `incorruptible` 35% · `company_man` 30% · `snitch` 20% · `hardliner` 15% |
| *Ventas y Marketing (subconjunto)* | *12* | `climber` 40% · `bribable` 20% · `gossip` 20% · `coward` 10% · `burnout` 10% |
| Dirección de bloques 10–12 | 20 | `climber` 35% · `hardliner` 20% · `bribable` 20% · `company_man` 15% · `coward` 10% |
| Plantas altas 13–20 | 20 | `climber` 30% · `hardliner` 25% · `company_man` 20% · `incorruptible` 15% · `bribable` 10% |
| Exterior | 10 | `oblivious` 40% · `gossip` 30% · `hardliner` 20% *(agentes de policía)* · `burnout` 10% |

**Procedimiento de generación:**

1. Asignar nombre desde un banco de nombres ingleses, sin repetición de combinación nombre-apellido.
2. Sortear arquetipo según la bolsa del departamento asignado.
3. Calcular cada rasgo como valor base del arquetipo más una desviación aleatoria en el intervalo [−15, +15], acotado a [0, 100].
4. Asignar plantilla de rutina según el escalón de su ocupación.
5. Generar vínculos iniciales: entre dos y cinco aristas de departamento, entre cero y dos de amistad, entre cero y una de rivalidad.
6. Asignar el indicador `slacker` al quince por ciento de los personajes de escalones 1 a 3.
7. Generar semilla de retrato para la composición modular de su apariencia.

### 24.4 Los seis inversores

| id | Nombre | Estrategia | Capital | Confianza inicial | Venalidad | Reacciona a |
|---|---|---|---|---|---|---|
| `inv_howard_grange` | Howard Grange | Valor | Muy alto | 50 | **Ninguna** | Exclusivamente fundamentales. Examina las notas al pie de los informes |
| `inv_tania_brekke` | Tania Brekke | Momentum | Alto | 50 | Soborno de precio alto | Titulares de prensa. Reacciona en horas |
| `inv_victor_sallow` | Victor Sallow | Cazador de información | Medio | 40 | Soborno económico; paga por soplos | Información anticipada. **Cada soplo constituye evidencia** |
| `inv_margaret_ash` | Margaret Ash | Activista | Alto | 45 | Insobornable; chantajeable | Cambios en la dirección. **Puede dirigirse contra un rival o contra el jugador** |
| `inv_neil_deming` | Neil Deming | Pasivo institucional | Muy alto | 60 | **Ninguna** | Únicamente desastres. **Su venta señala colapso** |
| `inv_bobby_kerr` | Bobby Kerr | Momentum minorista | Bajo | 30 | Soborno muy económico | Redes sociales. **Alcance desproporcionado e incontrolable** |

### 24.5 Plantillas de rutina diaria

| Escalón | Llegada | Trabajo mañana | Comida | Trabajo tarde | Salida | Noche |
|---|---|---|---|---|---|---|
| 1–2 | Torniquetes 8:15–8:45 | Puesto asignado | Cafetería | Puesto asignado | Salida 18:00–18:30 | Ausente |
| 3 | Torniquetes 8:30–9:00 | Puesto más una o dos reuniones | Cafetería | Puesto más visitas a otras plantas | Salida 18:00–18:45 | Ausente |
| 4 | Torniquetes 8:00–8:30 | Patrulla de zona, asignación de tareas | Cafetería o comedor | Reuniones cortas, control de presencia | Salida 18:30–19:00 | Ausente |
| 5–6 | Torniquetes 8:30–9:30 | Despacho | Comedor ejecutivo P17 | **Reuniones prolongadas en P12: el despacho queda vacío** | Salida 18:00–20:00 | Ausente |
| 7–8 | Irregular | Agenda densa: consejo, prensa, inversores | Comedor ejecutivo | Agenda irregular | Irregular | **Viajes: ausencias de jornadas completas** |
| Vigilante diurno | 7:00 | Rondas cada 90 min | Relevo | Rondas | 19:00 | Ausente |
| Vigilante nocturno | 19:00 | — | — | — | — | **Rondas cada 90 min hasta las 7:00** |
| Limpieza | 17:00 | — | — | Preparación | — | **Zonas asignadas de 18:00 a 22:00** |

**Modificadores comunes a todas las plantillas:** desplazamiento al baño en momento aleatorio · pausa de café a las 10:30 y 16:00 · corrillo de fumadores cada dos horas en el exterior · desplazamiento a fotocopiadora según necesidad · y el **escaqueo**, que afecta a los personajes marcados como `slacker`: se ausentan de su puesto en momentos impredecibles, y descubrirlos proporciona material de chantaje sin coste.

---

# PARTE IX — ESQUEMAS DE DATOS

> Los dieciséis archivos de `data/` especificados. Cada esquema incluye un registro completo de ejemplo. Toda clave marcada como obligatoria debe validarse al arrancar mediante las clases de `src/core/`.

## 25. `balance.json` — parámetros globales

Archivo de mayor relevancia operativa: **contiene la totalidad de los valores numéricos ajustables del juego**. Modificarlo no requiere tocar código.

```json
{
  "_version": 1,
  "_nota": "Todos los parámetros ajustables. Los presets de dificultad multiplican sobre estos valores base.",

  "economia": {
    "_nota": "Tesis del diseño: el salario honesto nunca financia el ascenso.",
    "desayuno_min": 4,
    "desayuno_max": 6,
    "cena_min": 8,
    "cena_max": 12,
    "alquiler_diario": 7,
    "dinero_inicial": 120,
    "estatus_por_escalon": { "5": 40, "6": 60, "7": 90, "8": 120 },
    "penalizacion_reputacion_sin_traje": 2.0,
    "precio_traje_ejecutivo": 1800,
    "precio_pasamontanas": 45,
    "precio_paquete_accionarial": 250000
  },

  "tiempo": {
    "minutos_reales_por_jornada": 11.0,
    "hora_inicio_jornada": 8,
    "hora_fin_jornada": 19,
    "velocidad_en_ordenador": 0.4,
    "jornadas_por_semana": 5,
    "jornadas_por_mes": 20,
    "jornadas_por_trimestre": 25,
    "aviso_deber_pendiente_horas_antes": 1
  },

  "percepcion": {
    "cono_angulo_base": 75.0,
    "cono_distancia_base": 8.0,
    "cono_angulo_hardliner": 100.0,
    "velocidad_llenado_base": 1.0,
    "velocidad_vaciado_base": 0.4,
    "mod_agachado": 0.5,
    "mod_inmovil": 0.7,
    "mod_esprint": 1.8,
    "mod_obstruccion_parcial": 0.4,
    "mod_perspicacia_por_punto": 0.01,
    "mod_sospecha_por_punto": 0.005,
    "umbral_parcial": 0.45,
    "umbral_flagrancia": 1.0,
    "umbral_perdida_contacto": 0.10,
    "distancia_reconocimiento_disfraz": 3.0,
    "distancia_clasificacion_uniforme": 6.0
  },

  "ruido": {
    "radio_sigiloso": 1.0,
    "radio_normal": 3.5,
    "radio_esprint": 9.0,
    "radio_cajon": 4.0,
    "radio_forzar_cerradura": 6.0,
    "radio_romper_objeto": 12.0,
    "radio_lector_tarjeta": 2.0,
    "radio_montacargas": 8.0,
    "reduccion_por_mascara": 0.15
  },

  "creencias": {
    "certeza_directa_completa": 0.90,
    "certeza_parcial": 0.35,
    "descuento_por_transmision": 0.75,
    "amplificacion_rumor_max": 1.15,
    "decaimiento_diario": 0.08,
    "umbral_olvido": 0.10,
    "mod_credibilidad_por_reputacion": 0.003,
    "mod_certeza_inicial_por_reputacion_jugador": -0.002
  },

  "sobornos": {
    "base": 0.10,
    "peso_codicia": 0.40,
    "peso_ratio_oferta": 0.20,
    "peso_afecto_deuda": 0.10,
    "peso_reputacion": 0.10,
    "peso_sospecha": -0.30,
    "peso_valentia": -0.15,
    "peso_lealtad": -0.20,
    "mod_rango_superior": 0.10,
    "mod_rango_inferior": -0.10,
    "probabilidad_maxima": 0.95,
    "insobornable_codicia_max": 20,
    "insobornable_lealtad_min": 80,
    "umbral_oferta_insultante": 0.5,
    "penalizacion_oferta_insultante": 0.33,
    "umbral_denuncia_valentia": 60,
    "umbral_denuncia_lealtad": 70,
    "umbral_silencio_valentia": 30,
    "umbral_contraoferta_codicia": 70,
    "factor_contraoferta_min": 1.3,
    "factor_contraoferta_max": 1.8
  },

  "investigaciones": {
    "umbral_apertura": 3.0,
    "umbral_lista_corta": 5.0,
    "umbral_condena_leve": 7.0,
    "umbral_condena_grave": 10.0,
    "dias_recogida_min": 2,
    "dias_recogida_max": 10,
    "mod_umbral_por_sospecha": -0.03,
    "jornadas_respiro_minimo": 3,
    "prob_revision_al_cambiar_auditor": 0.40,
    "dias_congelacion_por_abogado": 3,
    "pesos_evidencia": {
      "testigo_directo": 4.0,
      "testigo_parcial": 0.8,
      "grabacion_camara": 4.5,
      "registro_tarjeta": 2.5,
      "objeto_comprometedor": 10.0,
      "rastro_contable": 3.0,
      "rumor_sin_fuente": 0.3,
      "cuerpo_hallado": 12.0,
      "documento_falsificado": 5.0,
      "bonus_oportunidad": 2.0,
      "bonus_movil": 1.5,
      "bonus_ultimo_en_salir": 3.5
    }
  },

  "mercado": {
    "alpha_gravedad": 0.05,
    "beta_sentimiento": 0.30,
    "gamma_momentum": 0.15,
    "ruido_diario_max": 0.03,
    "precio_inicial": 42.50,
    "multiplo_base": 14.0,
    "mod_multiplo_crecimiento": 0.8,
    "mod_multiplo_riesgo": -1.2,
    "dias_momentum": 5,
    "mecha_auditoria_min_semanas": 2,
    "mecha_auditoria_max_semanas": 8,
    "trimestres_malos_para_degradar": 2,
    "umbral_patron_insider": 2.0,
    "peso_presentacion_calidad": 0.6,
    "peso_presentacion_cifras": 0.4
  },

  "ideas": {
    "prob_generacion_diaria_base": 0.12,
    "mod_prob_por_ambicion": 0.004,
    "frescura_min_jornadas": 3,
    "frescura_max_jornadas": 10,
    "calidad_min": 20,
    "calidad_max": 100,
    "factor_presentacion_sin_preparar": 0.6,
    "factor_presentacion_assist": 0.8,
    "factor_presentacion_real": 1.0,
    "umbral_diferencia_choque": 20,
    "penalizacion_reputacion_derrota_choque": -20,
    "penalizacion_reputacion_acusador_fallido": -15,
    "certeza_creencia_roba_ideas": 0.85
  },

  "deberes": {
    "assist_prob_aceptable": 0.60,
    "assist_prob_excelente": 0.25,
    "assist_prob_desastre": 0.15,
    "assist_umbral_deteccion_perspicacia": 60,
    "fallos_para_aviso": 1,
    "fallos_para_descenso": 3,
    "fallos_para_expulsion": 5,
    "penalizacion_reputacion_fallo": -8
  },

  "descontento": {
    "inicial": 20,
    "por_despido_injusto": 5,
    "por_cuota_excesiva_diaria": 2,
    "por_manipulacion_nominas": 10,
    "por_condiciones_fabrica": 3,
    "reduccion_por_concesion": -15,
    "reduccion_por_despedir_causante": -10,
    "umbral_huelga": 70
  },

  "seguimiento": {
    "sangre_por_eliminacion": 10,
    "sangre_por_cuerpo_ocultado": 5,
    "oro_por_mil_en_sobornos": 1,
    "oro_por_dos_mil_robados": 1,
    "oro_por_fraude": 5,
    "seda_por_idea_robada": 8,
    "seda_por_incriminacion": 5,
    "seda_por_rumor_plantado": 3,
    "seda_por_falsificacion": 5,
    "sudor_por_deber_honesto": 2,
    "sudor_por_informe_real": 10,
    "ruina_por_punto_perdidas": 1,
    "ruina_por_talento_expulsado": 5,
    "ruina_por_escandalo": 10,
    "umbral_ruina_cascaron": 150
  },

  "lod": {
    "radio_salas_completo": 1,
    "intervalo_medio_segundos": 0.5,
    "intervalo_estadistico_segundos": 5.0,
    "max_agentes_completo": 20,
    "max_agentes_medio": 40,
    "max_agentes_total": 150
  },

  "dificultad": {
    "interno":   { "decaimiento_sospecha": 1.4, "precio_soborno": 0.75, "margen_deberes": 1.5 },
    "estandar":  { "decaimiento_sospecha": 1.0, "precio_soborno": 1.00, "margen_deberes": 1.0 },
    "auditoria": { "decaimiento_sospecha": 0.6, "precio_soborno": 1.25, "margen_deberes": 0.7 }
  }
}
```

## 26. `occupations.json`

**Claves obligatorias:** `id`, `name_key`, `rank`, `tier`, `clearance`, `daily_wage`, `personnel_file_level`, `duties`, `promotes_to`.

```json
{
  "_version": 1,
  "occupations": [
    {
      "id": "email_worker_3b",
      "name_key": "OCC_EMAIL_WORKER",
      "rank": 1,
      "tier": 1,
      "clearance": 1,
      "daily_wage": 30,
      "office_room": "wing_3b",
      "desk_position": [4, 5],
      "computer_tier": 1,
      "personnel_file_level": 1,
      "duties": [
        {
          "id": "duty_emails_r1",
          "type": "volume",
          "subtype": "emails",
          "amount": 8,
          "time_cost_minutes": 45,
          "assist_time_cost_minutes": 5,
          "deadline_hour": 18,
          "fail_penalty": "warning"
        }
      ],
      "tools": ["keys_basic", "stamp"],
      "special_access": [],
      "opportunities": ["watch_colleagues_close", "learn_building_routines"],
      "risks": ["eleven_permanent_witnesses", "floor_chief_patrols"],
      "promotes_to": ["order_filer", "copy_operator"],
      "can_jump_to": ["mail_courier"],
      "demotes_to": ["eternal_intern"],
      "min_reputation": 0,
      "silhouette": "tier_1"
    }
  ]
}
```

## 27. `rooms/*.json`

Un archivo por planta. **Claves obligatorias:** `id`, `name_key`, `floor`, `clearance_required`, `art_band`, `kit`, `size`.

```json
{
  "_version": 1,
  "floor": 3,
  "rooms": [
    {
      "id": "wing_3b",
      "name_key": "ROOM_WING_3B",
      "floor": 3,
      "wing": "B",
      "clearance_required": 1,
      "special_access": [],
      "art_band": "the_pit",
      "kit": "open_office",
      "ambient_sound": "office_hum",
      "ambient_noise_level": 0.2,
      "has_cameras": false,
      "camera_positions": [],
      "size": [20, 14],
      "furniture": [
        { "type": "cubicle", "pos": [4, 2],  "rotation": 0, "owner": "npc_debbie_foyle" },
        { "type": "cubicle", "pos": [4, 5],  "rotation": 0, "owner": "player_start" },
        { "type": "cubicle", "pos": [4, 8],  "rotation": 0, "owner": "npc_george_penn" },
        { "type": "cubicle", "pos": [8, 2],  "rotation": 0, "owner": "npc_nate_brackley" },
        { "type": "cubicle", "pos": [8, 5],  "rotation": 0, "owner": "npc_claudia_reeves" },
        { "type": "cubicle", "pos": [8, 8],  "rotation": 0, "owner": "npc_sonia_vail" },
        { "type": "cubicle", "pos": [12, 2], "rotation": 0, "owner": "generated" },
        { "type": "cubicle", "pos": [12, 5], "rotation": 0, "owner": "generated" },
        { "type": "cubicle", "pos": [12, 8], "rotation": 0, "owner": "generated" },
        { "type": "cubicle", "pos": [16, 2], "rotation": 0, "owner": "generated" },
        { "type": "cubicle", "pos": [16, 5], "rotation": 0, "owner": "generated" },
        { "type": "cubicle", "pos": [16, 8], "rotation": 0, "owner": "generated" },
        { "type": "filing_cabinet", "pos": [1, 1],  "rotation": 90 },
        { "type": "printer",        "pos": [18, 3], "rotation": 180 },
        { "type": "motivational_poster", "pos": [10, 0], "rotation": 0 }
      ],
      "hiding_spots": [
        { "id": "hide_3b_desk",   "type": "under_desk",     "pos": [4, 5] },
        { "id": "hide_3b_closet", "type": "supply_closet",  "pos": [18, 12] }
      ],
      "interactables": [
        { "id": "player_desk", "type": "desk", "pos": [4, 5],
          "contains": ["keys_basic", "stamp"], "has_computer": true },
        { "id": "claudia_computer", "type": "npc_computer", "pos": [8, 5],
          "owner": "npc_claudia_reeves", "requires_absence": true }
      ],
      "illegitimate_entries": [],
      "connects_to": ["corridors_low", "p3_pantry"],
      "occupants_by_band": {
        "arrival": 8, "work_morning": 12, "lunch": 2,
        "work_afternoon": 12, "exit": 4, "night": 0
      }
    }
  ]
}
```

## 28. `archetypes.json`

```json
{
  "_version": 1,
  "variation_range": 15,
  "archetypes": [
    {
      "id": "gossip",
      "name_key": "ARCH_GOSSIP",
      "description_key": "ARCH_GOSSIP_DESC",
      "traits": {
        "ambition": 40, "loyalty": 45, "greed": 45,
        "courage": 40, "perception": 70, "sociability": 95
      },
      "visual_tic": "leans_toward_interlocutor",
      "caught_reaction": "spread_at_lunch",
      "propagation_bonus": 1.4
    }
  ]
}
```

## 29. `npcs_named.json`

```json
{
  "_version": 1,
  "npcs": [
    {
      "id": "npc_debbie_foyle",
      "name": "Debbie Foyle",
      "archetype": "gossip",
      "traits": {
        "ambition": 42, "loyalty": 40, "greed": 48,
        "courage": 38, "perception": 72, "sociability": 96
      },
      "occupation": "order_filer",
      "home_room": "wing_3b",
      "desk_position": [4, 2],
      "routine_template": "tier_1_2",
      "routine_overrides": [
        { "band": "work_morning", "time": "10:30", "action": "coffee",
          "location": "p3_pantry", "duration_minutes": 15 },
        { "band": "lunch", "time": "13:00", "action": "gossip",
          "location": "cafeteria", "duration_minutes": 60,
          "note": "Ocupa siempre la primera fila del comedor" }
      ],
      "initial_links": [
        { "to": "npc_george_penn",    "type": "department", "strength": 0.4 },
        { "to": "npc_sonia_vail",     "type": "friendship", "strength": 0.7 },
        { "to": "npc_claudia_reeves", "type": "rivalry",    "strength": 0.5 },
        { "to": "npc_nate_brackley",  "type": "department", "strength": 0.3 }
      ],
      "gatherings": ["cafeteria_clan", "chat_3b"],
      "weakness_key": "NPC_WEAK_FEED_GOSSIP",
      "danger_key": "NPC_DANGER_SPREADS_YOURS",
      "unique_accessory": "oversized_mug",
      "portrait_seed": 10472,
      "is_slacker": false
    }
  ]
}
```

## 30. `npcs_generation.json`

```json
{
  "_version": 1,
  "name_bank": {
    "first_names": ["Adam", "Brenda", "Carl", "Diane", "Edwin", "Fiona", "Gordon",
                    "Helen", "Ian", "Judith", "Kevin", "Laura", "Martin", "Nora",
                    "Oliver", "Patricia", "Quentin", "Rachel", "Simon", "Tessa"],
    "last_names": ["Ashby", "Bramwell", "Croft", "Dunmore", "Eastlake", "Fenwick",
                   "Garrow", "Halloway", "Inchcape", "Jardine", "Kettleby",
                   "Lockridge", "Marbury", "Northcott", "Overton", "Prescott",
                   "Quilter", "Rathbone", "Stanhope", "Thackeray"]
  },
  "departments": [
    {
      "id": "factory",
      "population": 25,
      "rooms": ["assembly_line", "mold_room", "materials_store",
                "quality_control", "finished_goods", "factory_break_room"],
      "archetype_bag": {
        "burnout": 0.30, "hardliner": 0.20, "oblivious": 0.15,
        "gossip": 0.10, "climber": 0.10, "coward": 0.10, "old_hand": 0.05
      },
      "tier_range": [1, 3]
    },
    {
      "id": "audit_legal",
      "population": 8,
      "rooms": ["internal_audit", "legal_firm", "legal_archive"],
      "archetype_bag": {
        "incorruptible": 0.35, "company_man": 0.30,
        "snitch": 0.20, "hardliner": 0.15
      },
      "tier_range": [2, 3]
    }
  ],
  "link_generation": {
    "department_links_min": 2,
    "department_links_max": 5,
    "friendship_links_min": 0,
    "friendship_links_max": 2,
    "rivalry_links_min": 0,
    "rivalry_links_max": 1,
    "secret_couple_probability": 0.03
  },
  "slacker_probability_tier_1_3": 0.15
}
```

## 31. `social_graph.json`

```json
{
  "_version": 1,
  "link_types": [
    { "id": "department", "strength_min": 0.3, "strength_max": 0.5,
      "propagates": "all", "degradation": 0.75, "directed": false },
    { "id": "friendship", "strength_min": 0.6, "strength_max": 0.8,
      "propagates": "all", "degradation": 0.90, "directed": false },
    { "id": "couple", "strength_min": 0.9, "strength_max": 1.0,
      "propagates": "all", "degradation": 0.98, "directed": false,
      "blackmail_material": true },
    { "id": "rivalry", "strength_min": 0.5, "strength_max": 0.7,
      "propagates": "negative_only", "degradation": 1.15, "directed": false },
    { "id": "debt", "strength_min": 0.5, "strength_max": 1.0,
      "propagates": "none", "suppresses_denunciation": true, "directed": true },
    { "id": "hierarchy", "strength_min": 0.6, "strength_max": 0.9,
      "propagates": "relevant_only", "degradation": 0.85, "directed": true },
    { "id": "nepotism", "strength_min": 0.8, "strength_max": 1.0,
      "propagates": "all", "accusation_backfires": true, "directed": false }
  ],
  "gatherings": [
    { "id": "cafeteria_clan", "room": "cafeteria", "band": "lunch",
      "amplification": 1.4, "max_participants": 45 },
    { "id": "foosball_circle", "room": "foosball_room", "band": "any",
      "amplification": 1.0, "max_participants": 6 },
    { "id": "smokers_circle", "room": "street", "interval_hours": 2,
      "amplification": 1.2, "max_participants": 8, "no_cameras": true },
    { "id": "chat_3b", "room": null, "band": "all_including_night",
      "amplification": 0.8, "readable_by_it": true },
    { "id": "accounting_couple", "room": "accounting", "band": "any",
      "amplification": 0.0, "is_secret": true }
  ]
}
```

## 32. Esquemas restantes

### 32.1 `bribes.json`

```json
{
  "_version": 1,
  "favours": [
    { "id": "look_away_once",       "multiplier": 3,   "name_key": "BRIBE_LOOK_AWAY" },
    { "id": "lend_access",          "multiplier": 8,   "name_key": "BRIBE_LEND_ACCESS" },
    { "id": "praise_to_superior",   "multiplier": 15,  "name_key": "BRIBE_PRAISE" },
    { "id": "silence_witnessed",    "multiplier": 20,  "name_key": "BRIBE_SILENCE" },
    { "id": "lie_in_interrogation", "multiplier": 40,  "name_key": "BRIBE_LIE" },
    { "id": "bury_investigation",   "multiplier": 100, "name_key": "BRIBE_BURY_CASE" },
    { "id": "vote_in_board",        "multiplier": 250, "name_key": "BRIBE_BOARD_VOTE" }
  ],
  "channels": [
    { "id": "mobile_chat", "leaves_digital_record": true,  "requires_privacy": false },
    { "id": "phone_call",  "leaves_digital_record": false, "requires_privacy": true },
    { "id": "in_person",   "leaves_digital_record": false, "requires_privacy": false,
      "witness_risk": true },
    { "id": "immediate",   "leaves_digital_record": false, "forced_favour": "silence_witnessed" }
  ]
}
```

### 32.2 `duties.json`

```json
{
  "_version": 1,
  "duty_types": [
    { "id": "volume",       "interface": "repetitive_click", "automatable": true,
      "delegatable": true },
    { "id": "quota",        "interface": "counter",          "automatable": false,
      "delegatable": true, "affected_by_theft": true },
    { "id": "delivery",     "interface": "document",         "automatable": true,
      "requires_material": true },
    { "id": "round",        "interface": "waypoints",        "automatable": false,
      "provides_alibi": true },
    { "id": "presentation", "interface": "scene",            "automatable": false,
      "public_reputation": true }
  ]
}
```

### 32.3 `ideas.json`

```json
{
  "_version": 1,
  "templates": [
    { "department": "design",    "quality_min": 50, "quality_max": 100,
      "text_keys": ["IDEA_DESIGN_1", "IDEA_DESIGN_2", "IDEA_DESIGN_3"] },
    { "department": "marketing", "quality_min": 35, "quality_max": 90,
      "text_keys": ["IDEA_MKT_1", "IDEA_MKT_2", "IDEA_MKT_3"] },
    { "department": "sales",     "quality_min": 30, "quality_max": 80,
      "text_keys": ["IDEA_SALES_1", "IDEA_SALES_2"] },
    { "department": "operations","quality_min": 25, "quality_max": 75,
      "text_keys": ["IDEA_OPS_1", "IDEA_OPS_2"] }
  ],
  "acquisition_methods": [
    { "id": "overhear",   "risk": "low",     "leaves_trace": "owner_knows_presence" },
    { "id": "steal_file", "risk": "medium",  "leaves_trace": "digital_record" },
    { "id": "inherit",    "risk": "maximum", "leaves_trace": "none_for_idea" },
    { "id": "purchase",   "risk": "low",     "leaves_trace": "owner_knows_all" },
    { "id": "gifted",     "risk": "none",    "leaves_trace": "none" }
  ]
}
```

### 32.4 `investors.json`

```json
{
  "_version": 1,
  "strategies": [
    { "id": "value",        "weight_fundamentals": 1.0, "weight_sentiment": 0.0 },
    { "id": "momentum",     "weight_fundamentals": 0.2, "weight_sentiment": 0.8 },
    { "id": "info_hunter",  "weight_fundamentals": 0.4, "weight_sentiment": 0.3,
      "weight_tips": 0.3 },
    { "id": "activist",     "weight_fundamentals": 0.5, "weight_management": 0.5 },
    { "id": "passive",      "weight_fundamentals": 0.7, "weight_sentiment": 0.1,
      "reaction_threshold": 0.25 }
  ],
  "investors": [
    {
      "id": "inv_howard_grange",
      "name": "Howard Grange",
      "strategy": "value",
      "capital": 4500000,
      "initial_confidence": 50,
      "bribable": false,
      "blackmailable": false,
      "traits": { "ambition": 40, "loyalty": 60, "greed": 30,
                  "courage": 70, "perception": 90, "sociability": 40 },
      "reacts_to": ["fundamentals", "audit_results"],
      "on_confidence_loss": "public_statement"
    }
  ]
}
```

### 32.5 `market.json`

Contiene los parámetros de simulación (duplicados desde `balance.json` para permitir ajuste independiente durante el desarrollo), el calendario trimestral y los objetivos por trimestre.

### 32.6 `market_events.json`

```json
{
  "_version": 1,
  "events": [
    {
      "id": "footwear_trend_shift",
      "name_key": "EVENT_TREND_SHIFT",
      "probability_per_quarter": 0.25,
      "duration_quarters": 2,
      "effects": { "revenue_multiplier": [0.85, 1.15] },
      "sentiment_delta": 0.0
    },
    {
      "id": "leather_price_rise",
      "name_key": "EVENT_LEATHER_RISE",
      "probability_per_quarter": 0.20,
      "duration_quarters": 1,
      "effects": { "costs_multiplier": 1.08 },
      "sentiment_delta": -0.05,
      "mitigable_by": "purchasing_chief"
    }
  ]
}
```

### 32.7 `investigations.json`

Contiene los umbrales por fase, los pesos de evidencia (duplicados desde `balance.json`), las duraciones de fase, el orden de registro de salas y las condiciones de reactivación de casos fríos.

### 32.8 `endings.json`

```json
{
  "_version": 1,
  "endings": [
    {
      "id": "the_worker",
      "name_key": "ENDING_THE_WORKER",
      "category": "full_victory",
      "conditions": {
        "rank": 33,
        "has_ownership_documents": true,
        "notarised": true,
        "dominant_axis": "sweat"
      },
      "epilogue_key": "EPILOGUE_THE_WORKER",
      "has_ruin_variants": true
    },
    {
      "id": "the_gap",
      "name_key": "ENDING_THE_GAP",
      "category": "defeat",
      "conditions": {
        "cause": ["starvation", "failed_at_r0"]
      },
      "epilogue_key": "EPILOGUE_THE_GAP",
      "has_ruin_variants": false
    }
  ]
}
```

### 32.9 `art_bands.json`

```json
{
  "_version": 1,
  "bands": [
    {
      "id": "the_pit",
      "name_key": "BAND_THE_PIT",
      "floors": [0, 1, 2, 3, 4, 5],
      "palette": {
        "floor": "#8a8f7d",
        "wall": "#b5b8a8",
        "accent": "#6d7a5c",
        "light": "#d9e0c4",
        "shadow": "#4a4f42"
      },
      "lighting": { "type": "fluorescent", "flicker": true, "intensity": 0.85 },
      "ambient_sound": "office_hum",
      "ambient_noise_level": 0.2,
      "plants_are_plastic": true,
      "motivational_poster_density": "high",
      "muzak_arrangement": "compressed"
    }
  ]
}
```

## 33. `locale/strings.csv`

Formato estándar de localización de Godot. La primera columna contiene la clave; las siguientes, un idioma cada una.

```csv
keys,en,es
UI_BRIBE_CONFIRM,"Offer %s to keep quiet?","¿Ofrecer %s por su silencio?"
UI_CAUGHT_TITLE,"You've been seen.","Te han visto."
UI_CAUGHT_BRIBE,"Offer money","Ofrecer dinero"
UI_CAUGHT_ELIMINATE,"Silence them permanently","Silenciarlo definitivamente"
UI_CAUGHT_NO_WITNESS_WARNING,"There are witnesses.","Hay testigos."
OCC_EMAIL_WORKER,"Email Worker, Wing 3B","Trabajador de emails del 3B"
OCC_CEO,"Chief Executive Officer","Consejero delegado"
ROOM_WING_3B,"Wing 3B","Ala 3B"
ROOM_DEAD_ARCHIVE,"Dead Archive","Archivo muerto"
ARCH_GOSSIP,"The Gossip","La cotilla"
ARCH_GOSSIP_DESC,"Talks to everyone. Remembers everything.","Habla con todos. Lo recuerda todo."
NPC_WEAK_FEED_GOSSIP,"Feed her a rumour and she'll spread it for you.","Suminístrale un rumor y lo difundirá."
IDEA_DESIGN_1,"A sole that adapts to the wearer's gait","Una suela que se adapta a la pisada"
EPILOGUE_THE_WORKER,"You set out to reach the top without working...","Te propusiste llegar arriba sin trabajar..."
```

**Regla de cumplimiento obligatorio:** ni el código ni los archivos de datos contienen texto literal destinado a mostrarse. Únicamente claves.

---

# PARTE X — MANUAL DE OBRA

> Los cuarenta y siete pasos de construcción. Cada paso especifica qué se construye, qué secciones del documento consultar, el prompt literal a emplear, y el criterio de verificación. **Ningún paso se inicia hasta que el anterior supere su verificación.**

## 34. Preparación del entorno

### 34.1 Software necesario

| Programa | Función | Observación |
|---|---|---|
| **Godot 4**, versión estable | Motor de desarrollo | Ejecutable único, sin instalación. Descarga desde el sitio oficial del motor. |
| **Claude Code** | Redacción del código | Requiere Node.js instalado previamente |
| Editor de texto | Inspección de archivos | Cualquiera resulta suficiente |

No se requiere Git, ni entorno de compilación, ni conocimientos de programación por parte del responsable del proyecto.

### 34.2 Creación del proyecto

Crear un directorio denominado `the_worker` en la ubicación deseada. **El paso 1 genera la totalidad de la estructura interna.** No es necesario crear nada más de forma manual.

### 34.3 Procedimiento de respaldo

Antes de cada sesión de trabajo:

1. Cerrar Godot.
2. Copiar el directorio `the_worker` completo.
3. Renombrar la copia con la fecha: `the_worker_2026-07-25`.

Este procedimiento requiere treinta segundos y sustituye por completo a un sistema de control de versiones para las necesidades de este proyecto. Si una sesión produce un estado defectuoso, se elimina el directorio de trabajo y se restaura la copia.

### 34.4 Procedimiento de verificación

Cuando un paso indique verificación mediante ejecución:

1. Abrir Godot y cargar el proyecto (`the_worker/project.godot`).
2. Pulsar **F5**.
3. Comprobar el criterio especificado en el paso.

Cuando un paso indique verificación sin ventana, ejecutar en la consola del sistema, situado en el directorio del proyecto:

```
godot --headless --script tests/nombre_del_test.gd
```

**Ante cualquier error:** copiar el texto completo del mensaje, sin resumir ni interpretar, y proporcionarlo al sistema de IA. Los mensajes de error de Godot identifican archivo y línea exactos.

### 34.5 Especificación de trabajo para el sistema de IA

Las siguientes condiciones aplican a la totalidad de los pasos y no requieren repetirse en cada prompt:

- **Entrega de archivos completos.** Cuando un archivo requiere modificación, se reescribe íntegramente. No se entregan fragmentos, diferencias ni instrucciones de edición parcial.
- **Separación entre datos y lógica.** Ningún valor de contenido o de balance se escribe dentro del código.
- **Comunicación exclusiva mediante `EventBus`.** Ningún sistema global invoca a otro de forma directa.
- **Tipado estático en la totalidad del código.**
- **Validación sin ventana antes de considerar terminada cualquier pieza.**
- **Respeto de las firmas especificadas en la Parte VII.** Un sistema construido en un paso posterior asumirá su existencia exacta.

### 34.6 Plantilla de prompt

Para cualquier paso, en caso de necesitar reformulación:

```
Estoy construyendo el videojuego THE WORKER en Godot 4.
Documento maestro adjunto: THE_WORKER_MANUAL_MAESTRO.md

Consulta las secciones [X] y [Y] del documento, y la Parte VII completa
antes de escribir código.

PASO [N]: [denominación del paso].

Requisitos de entrega:
- Archivos completos con su ruta exacta indicada.
- GDScript con tipado estático.
- Datos en data/, lógica en src/.
- Comunicación entre sistemas exclusivamente por EventBus.
- Respeta las firmas de la Parte VII.
- Incluye el test correspondiente en tests/.
- Concluye indicando qué debo observar al ejecutar para verificar el paso.
```

## 35. Fase A — Fundación técnica

### PASO 1 — Estructura del proyecto

**Construye:** `project.godot`, la jerarquía completa de directorios.
**Consultar:** 17.2, 17.3.

```
PASO 1: estructura del proyecto.

Crea:

1. project.godot configurado para Godot 4:
   - Resolución base 1920x1080
   - Modo de estiramiento canvas_items con aspecto expand
   - Orientación libre para compatibilidad con pantallas móviles alargadas
   - Nombre del proyecto: The Worker

2. La jerarquía completa de directorios de la sección 17.2, con un archivo
   marcador en cada directorio vacío para que Godot los conserve.

3. El registro de los 14 autoloads de la sección 19 en project.godot,
   COMENTADOS, con una nota indicando en qué paso se crea cada uno.

Concluye enumerando la totalidad de directorios y archivos que deben existir.
```

**Verificación:** el proyecto abre en Godot sin errores y la jerarquía de directorios aparece en el panel de sistema de archivos.

---

### PASO 2 — El bus de eventos

**Construye:** `src/autoload/event_bus.gd`.
**Consultar:** 18 completa.

```
PASO 2: el EventBus.

Crea src/autoload/event_bus.gd con la totalidad de las señales del catálogo de
la sección 18.2, con sus tipos exactos.

Requisitos:
- Es un autoload. Regístralo en project.godot.
- No contiene lógica: únicamente declara señales.
- Incluye la constante DEBUG_SIGNALS y la función _log de la sección 18.4.
- Cabecera documental de tres líneas según 17.3.

Incluye tests/test_event_bus.gd que verifique que todas las señales existen,
se pueden emitir y se pueden recibir mediante conexión.
```

**Verificación:** `godot --headless --script tests/test_event_bus.gd`

---

### PASO 3 — Validador y clases de datos

**Construye:** `src/util/validate.gd` y las clases de `src/core/`.
**Consultar:** 17.3, Parte IX completa.

```
PASO 3: validador y clases de datos tipadas.

1. src/util/validate.gd — clase con métodos estáticos:
   require_string, require_int, require_int_range, require_int_min,
   require_float, require_float_range, require_bool, require_array,
   require_dict, require_vector2, optional_string, optional_int,
   optional_float, optional_array, optional_dict

   Cada método recibe (dict, key, [límites], source: String). Ante fallo produce
   un error con este formato exacto:
   "ARCHIVO → entrada N → campo 'clave': PROBLEMA (esperado X, recibido Y)"

2. Las clases de datos en src/core/, todas con class_name, tipado estático y
   un método static from_dict(d: Dictionary, source: String):
   - OccupationData    (esquema en sección 26)
   - RoomData          (esquema en sección 27)
   - ArchetypeData     (esquema en sección 28)
   - NPCData           (esquema en sección 29)
   - InvestorData      (esquema en sección 32.4)
   - Belief            (estructura en sección 7.2)
   - Idea              (estructura en sección 11.1)
   - Investigation     (fases en sección 12.3)
   - ItemData          (categorías ordinario y comprometedor, sección 11.3)

Incluye tests/test_validate.gd que verifique que un dato malformado produce el
error con el formato especificado y que un dato correcto se carga.
```

**Verificación:** `godot --headless --script tests/test_validate.gd`

---

### PASO 4 — Base de datos y balance

**Construye:** `src/autoload/database.gd`, `data/balance.json`, `data/occupations.json`, `data/archetypes.json`.
**Consultar:** 19.1, 25, 26, 28, 23 completa, 24.1.

```
PASO 4: Database y los primeros archivos de datos.

1. data/balance.json con el contenido íntegro de la sección 25 del documento.

2. data/occupations.json con las CINCUENTA ocupaciones de la sección 23,
   siguiendo el esquema de la sección 26. Transcribe todos los atributos de las
   tablas: rango, escalón, acreditación, salario, nivel de expediente, deberes
   con su tipo y coste temporal, herramientas, accesos especiales, y las
   relaciones promotes_to, can_jump_to y demotes_to.

3. data/archetypes.json con los doce arquetipos de la sección 24.1,
   incluyendo tic visual y reacción ante flagrancia.

4. src/autoload/database.gd implementando la interfaz completa de la
   sección 19.1:
   - Carga y valida todos los archivos de data/ al arrancar
   - Detiene el arranque con mensaje explícito si algo falla
   - Expone acceso de solo lectura
   - get_balance acepta ruta con puntos: "percepcion.cono_angulo_base"
   - Ejecuta las comprobaciones cruzadas de la sección 17.1

Incluye tests/test_data_integrity.gd que verifique: cincuenta ocupaciones sin
identificadores duplicados, doce arquetipos, cobertura completa de los rangos
R0 a R33, y lectura correcta de balance.json.
```

**Verificación:** `godot --headless --script tests/test_data_integrity.gd` debe confirmar cincuenta ocupaciones y doce arquetipos.

---

### PASO 5 — El reloj

**Construye:** `src/autoload/game_clock.gd`.
**Consultar:** 5.6, 15.1, 19.2.

```
PASO 5: GameClock.

Crea src/autoload/game_clock.gd implementando la interfaz completa de la
sección 19.2.

Requisitos:
- Conversión de tiempo real a tiempo de juego según balance.json
  (una jornada equivale a once minutos reales).
- Las seis franjas de la sección 5.6 con sus horarios exactos.
- Emisión de time_band_changed, day_advanced, week_closed, month_closed
  y quarter_closed en los momentos correspondientes.
- set_speed_multiplier para el uso del ordenador (0,4). El tiempo se ralentiza
  pero NO se detiene.
- advance_to_band que falle si existen observadores (la comprobación real se
  implementa en el paso 10; por ahora deja el punto de extensión documentado).

Incluye tests/test_game_clock.gd: simula una jornada completa y verifica que se
emiten las seis franjas en orden correcto y que day_advanced se emite una única vez.
```

**Verificación:** `godot --headless --script tests/test_game_clock.gd`

---

### PASO 6 — Estado del jugador

**Construye:** `src/autoload/player_state.gd`.
**Consultar:** 19.3, 6, 11.3, 12.8.

```
PASO 6: PlayerState.

Crea src/autoload/player_state.gd implementando la interfaz completa de la
sección 19.3.

Consideraciones importantes:
- La sospecha NO se modifica desde aquí. Este sistema únicamente la almacena en
  caché. El método _set_suspicion_from_beliefnet es de uso exclusivo de BeliefNet
  (paso 13). Documéntalo explícitamente.
- El inventario tiene ocho posiciones y distingue objetos ordinarios de
  comprometedores según la sección 11.3.
- Los cinco ejes de seguimiento con los incrementos de la sección 12.8.
- Emisión de occupation_changed, duty_completed, duty_failed,
  reputation_changed y clearance_changed.
- Implementa save_state y load_state.

Incluye tests/test_player_state.gd: capital con caso de fondos insuficientes,
inventario con límite de capacidad y detección de objetos comprometedores,
deberes, y acumulación en los ejes.
```

**Verificación:** `godot --headless --script tests/test_player_state.gd`

---

### PASO 7 — Constructor de salas

**Construye:** `src/world/room_builder.gd`, `data/rooms/p03.json`, `data/art_bands.json`, `scenes/world/main.tscn`.
**Consultar:** 14.2, 14.3, 14.8, 22.8, 27, 32.9.

```
PASO 7: RoomBuilder y la primera sala.

1. data/art_bands.json con las cinco bandas de la sección 14.3, cada una con su
   paleta hexadecimal, tipo de iluminación, ambiente sonoro y nivel de ruido.
   Sigue el esquema de la sección 32.9.

2. data/rooms/p03.json con las SIETE salas de la planta 3 según la
   sección 22.8, empleando el esquema de la sección 27. Detalla wing_3b con
   precisión: doce cubículos en las posiciones del esquema, escondites,
   e interactuables.

3. src/world/room_builder.gd que:
   - Lea la definición JSON de una sala
   - Genere suelo, paredes y puertas POR CÓDIGO, con formas y colores planos
     según la sección 14.2. Sin recursos externos en esta fase.
   - Instancie el mobiliario en las posiciones especificadas
   - Aplique la paleta de la banda correspondiente
   - Registre puntos interactuables y escondites
   - Genere la geometría de colisión

4. scenes/world/main.tscn que construya wing_3b al iniciar.

Al ejecutar debo observar la sala 3B dibujada en vista cenital, con sus doce
cubículos, en la paleta gris-verdosa de la banda the_pit.
```

**Verificación:** ejecutar. Debe aparecer la sala dibujada desde arriba con sus cubículos y la paleta correcta.

---

### PASO 8 — El jugador

**Construye:** `src/entities/player.gd` y su escena.
**Consultar:** 13.7, 14.1, 14.5, 14.7.

```
PASO 8: el jugador.

Crea src/entities/player.gd y su escena correspondiente:

- Desplazamiento en ocho direcciones con WASD, perspectiva cenital 3/4.
- Tres velocidades con sus valores en balance.json: sigiloso (Shift),
  normal, y esprint (doble pulsación de dirección o doble clic).
- Agacharse con Ctrl: reduce velocidad, reduce detectabilidad, y permite
  ocultarse tras mobiliario bajo.
- Interacción con E sobre objetos próximos, con indicación contextual en pantalla.
- Cámara con seguimiento y desplazamiento hacia la dirección de mirada.
- El personaje se dibuja por código con la silueta de escalón 1 de la
  sección 14.5: encorvado, ropa amplia, transportando un objeto.
- Cada modo de desplazamiento emite noise_emitted con el radio correspondiente
  de balance.json.
- Animación limitada de ocho a doce fotogramas según la sección 14.7.

Al ejecutar debo poder desplazarme por la sala 3B con las tres velocidades y
comprobar en la consola que se emiten los eventos de ruido con radios distintos.
```

**Verificación:** ejecutar. Desplazarse con WASD, probar Shift, doble pulsación y Ctrl. Los radios de ruido deben diferir en consola.

## 36. Fase B — Percepción y sigilo

### PASO 9 — Personajes y rutinas

**Construye:** `src/autoload/npc_director.gd`, `src/entities/npc.gd`, `data/npcs_named.json`.
**Consultar:** 19.5, 24.2, 24.5, 29, 14.4.

```
PASO 9: NPCDirector y los primeros personajes.

1. data/npcs_named.json con los siete personajes del ala 3B según la
   sección 24.2 (Debbie Foyle, George Penn, Nate Brackley, Claudia Reeves,
   Old Ray Cudmore, Sonia Vail y Bernard Lasker), con sus valores numéricos
   exactos y sus vínculos iniciales. Emplea el esquema de la sección 29.

2. src/autoload/npc_director.gd implementando la interfaz de la sección 19.5.
   Por ahora sin el sistema de nivel de detalle: eso es el paso 40.

3. src/entities/npc.gd: un personaje que sigue su rutina diaria según las
   plantillas de la sección 24.5, reaccionando a time_band_changed.
   Se dibuja mediante el sistema modular de la sección 14.4 con la silueta
   de su escalón.

Al ejecutar deben aparecer los siete personajes en sus cubículos del 3B y
desplazarse a la cafetería cuando comience la franja de comida.
```

**Verificación:** ejecutar. Los personajes ocupan sus posiciones y se desplazan a las 13:00.

---

### PASO 10 — Percepción visual

**Construye:** `src/simulation/perception.gd`.
**Consultar:** 7.3, 13.2.

```
PASO 10: sistema de percepción visual.

Crea src/simulation/perception.gd:

- Cono de visión por personaje con ángulo, distancia y orientación. Valores base
  en balance.json, modulados por Perspicacia según la sección 7.3.
- Línea de visión real: paredes y mobiliario alto obstruyen.
- Detección PROGRESIVA con los modificadores exactos de la tabla de la
  sección 7.3: distancia, agachado, inmóvil, esprint, obstrucción parcial,
  perspicacia y sospecha del jugador.
- Los tres umbrales de la sección 7.3:
  * 0,45 percepción parcial → emite player_seen_partially con certeza 0,35
  * 1,00 identificación completa → emite player_caught_redhanded ÚNICAMENTE si
    el jugador está ejecutando un acto indebido. Si no lo está, no ocurre nada:
    ser visto trabajando es normal.
  * Por debajo de 0,10 el contador se reinicia y emite player_lost_from_sight
- El arquetipo hardliner emplea el ángulo ampliado y lo barre lentamente.

Dibuja los conos de forma semitransparente para permitir depuración visual.

Incluye tests/test_perception.gd: un personaje a distancia media genera creencia
de certeza baja, no alta.
```

**Verificación:** ejecutar. Los conos son visibles y el contador progresa al entrar en ellos.

---

### PASO 11 — Percepción auditiva

**Construye:** ampliación de `src/simulation/perception.gd`.
**Consultar:** 7.3, 14.10.

```
PASO 11: percepción auditiva y máscaras acústicas.

Amplía src/simulation/perception.gd:

- Los eventos noise_emitted se evalúan contra la posición de cada personaje.
- Un personaje dentro del radio orienta su atención hacia el origen e investiga
  si su Perspicacia supera el umbral de balance.json.
- MÁSCARAS ACÚSTICAS: las salas con ambient_noise_level elevado (call_center,
  boiler_room, assembly_line, main_copyroom) reducen el radio efectivo al 15%
  según balance.json.
- Indicación discreta en pantalla cuando el jugador se encuentra en una sala con
  máscara activa.

Incluye tests/test_noise.gd que verifique la reducción de radio en sala con máscara.
```

**Verificación:** ejecutar. Esprintar junto a un personaje provoca que se oriente; repetir en el call center no debe producir reacción.

---

### PASO 12 — Indicador de detección

**Construye:** `src/ui/detection_indicator.gd`, `src/ui/hud.gd`.
**Consultar:** 13.1, 13.2, 13.10.

```
PASO 12: el indicador de detección y el HUD.

1. src/ui/detection_indicator.gd según la sección 13.2:
   - Indicador sobre cada personaje con línea de visión hacia el jugador
   - Los cuatro estados exactos, distinguibles por FORMA además de color
     (requisito de accesibilidad, sección 13.10)
   - Halo rojo perimetral en zona sin acreditación suficiente
   - Icono de cámara dentro del campo de una

2. src/ui/hud.gd con los cinco elementos de la sección 13.1 en sus posiciones
   especificadas.

Ambos elementos deben resultar legibles a tamaño de pantalla móvil.
```

**Verificación:** ejecutar. Aproximarse a un personaje: el indicador progresa visiblemente.

---

### PASO 13 — La capa de creencias

**Construye:** `src/autoload/belief_net.gd`.
**Consultar:** 7.2, 7.6, 19.4.

```
PASO 13: BeliefNet.

Crea src/autoload/belief_net.gd implementando la interfaz completa de la
sección 19.4.

Requisitos:
- Estructura de creencia según la sección 7.2, con todos sus campos.
- Se suscribe a player_seen_partially y player_caught_redhanded para crear
  creencias con las certezas de la tabla de la sección 7.2.
- DECAIMIENTO: al recibir day_advanced, cada creencia pierde certeza según
  balance.json. Las que descienden del umbral se olvidan y emiten
  belief_forgotten.
- REGISTROS: las creencias con is_record verdadero NO decaen jamás. Solo
  desaparecen mediante destroy_record. Los tipos de registro son los de la
  sección 7.6.
- CÁLCULO DE SOSPECHA según la fórmula de la sección 7.2, ponderando por
  certeza y por credibilidad del portador. Actualiza PlayerState mediante
  _set_suspicion_from_beliefnet y emite suspicion_changed.
- get_suspicion_breakdown devuelve el desglose para el panel de depuración.

Incluye tests/test_beliefs.gd: creación, decaimiento tras N jornadas,
persistencia de registros, y corrección del cálculo de sospecha.
```

**Verificación:** `godot --headless --script tests/test_beliefs.gd`

---

### PASO 14 — Moduladores y panel de depuración

**Construye:** ampliaciones en varios sistemas, `src/ui/debug_panel.gd`.
**Consultar:** 7.10.

```
PASO 14: moduladores globales y panel de depuración.

1. Implementa los efectos de la sección 7.10, cada uno desde el sistema al que
   corresponde, sin acoplar sistemas:

   REPUTACIÓN elevada:
   - En BeliefNet: las creencias negativas nacen con certeza reducida
   - En BeliefNet: el decaimiento de sospecha se acelera

   SOSPECHA elevada:
   - En Perception: incrementa la perspicacia efectiva de los personajes próximos
   - Deja preparado el punto de extensión para el nivel de alerta (paso 27)

   Todos los coeficientes en balance.json.

2. src/ui/debug_panel.gd, activable con F1, mostrando en tiempo real:
   sospecha y su desglose, reputación, número de creencias vivas sobre el
   jugador, las tres de mayor peso con su portador, franja horaria actual,
   y el personaje seleccionado con sus seis rasgos.

Este panel será la herramienta principal de diagnóstico durante todo el desarrollo.
```

**Verificación:** ejecutar, pulsar F1. Dejarse observar: la sospecha debe incrementarse y el desglose debe reflejar la creencia generada.

## 37. Fase C — Sistemas sociales

### PASO 15 — Grafo social y rumores

**Construye:** `src/autoload/social_graph.gd`, `data/social_graph.json`.
**Consultar:** 7.7, 19.6, 31.

```
PASO 15: SocialGraph y propagación de rumores.

1. data/social_graph.json con los siete tipos de vínculo y los cinco corrillos
   de la sección 7.7, empleando el esquema de la sección 31.

2. src/autoload/social_graph.gd implementando la interfaz de la sección 19.6:
   - Grafo con los siete tipos de arista, cada uno con su comportamiento
     específico de propagación
   - PROPAGACIÓN en los momentos de socialización: al recibir time_band_changed
     con la franja de comida, ejecuta propagate_at_gathering para el corrillo
     de la cafetería
   - La certeza se degrada según el factor del tipo de vínculo, pero los rumores
     pueden AMPLIFICARSE hasta el factor máximo de balance.json
   - La rivalidad propaga exclusivamente información negativa
   - inject_rumour permite al jugador introducir información
   - kill_rumour para el Director de Comunicación

Incluye tests/test_rumor.gd: inyectar una creencia a Debbie Foyle y verificar
que alcanza cinco personajes tras la franja de comida.
```

**Verificación:** `godot --headless --script tests/test_rumor.gd`

---

### PASO 16 — Inteligencia por utilidad

**Construye:** `src/simulation/utility_ai.gd`.
**Consultar:** 7.5.

```
PASO 16: la inteligencia por utilidad.

Crea src/simulation/utility_ai.gd:

- El repertorio completo de acciones de la sección 7.5.
- La fórmula de puntuación de la sección 7.5, con todos sus términos.
  Los pesos residen en balance.json.
- Reevaluación POR EVENTOS, no en bucle por fotograma.

REQUISITO CRÍTICO de la sección 7.5: el trato diferencial por rango del jugador
debe EMERGER de la fórmula. No debe existir ninguna condición explícita del tipo
"si el rango es bajo entonces denunciar". El término peso_rango x rango_jugador
debe producir el comportamiento por sí solo.

Incluye tests/test_utility_ai.gd que verifique que el mismo personaje, ante la
misma creencia, elige acciones opuestas según si el rango del jugador es 1 o 28.
```

**Verificación:** el test debe demostrar comportamientos opuestos.

---

### PASO 17 — Registro de relaciones

**Construye:** ampliación de `src/autoload/npc_director.gd`.
**Consultar:** 7.9, 19.5.

```
PASO 17: el registro de relaciones.

Amplía NPCDirector con la estructura Ledger de la sección 7.9 por personaje.

Requisitos:
- Los cuatro campos más las listas de agravios y favores, con tipo, gravedad
  y jornada.
- Los efectos de la tabla de la sección 7.9: los agravios reducen afección,
  aceleran la denuncia y encarecen el soborno; los favores producen el efecto
  inverso.
- Los agravios NO decaen. Persisten toda la partida.
- Alimenta el registro suscribiéndote a las señales pertinentes del EventBus:
  seat_vacated, investigation_resolved, idea_acquired, bribe_result.
- Emite grievance_added y favour_added.

Amplía el panel de depuración para mostrar el registro del personaje seleccionado.
```

**Verificación:** ejecutar. El panel F1 debe mostrar el registro de un personaje seleccionado.

---

### PASO 18 — Sobornos

**Construye:** `src/simulation/bribery.gd`, `data/bribes.json`.
**Consultar:** 8.2, 32.1.

```
PASO 18: el sistema de sobornos.

1. data/bribes.json con los siete favores y los cuatro canales de la
   sección 8.2, empleando el esquema de la sección 32.1.

2. src/simulation/bribery.gd implementando la sección 8.2 con exactitud:
   - Cálculo del precio justo
   - La fórmula de probabilidad completa con todos sus términos, acotada
     al intervalo [0,00 , 0,95]
   - LA REGLA DE EXCEPCIÓN ABSOLUTA: si codicia menor que 20 y lealtad mayor
     que 80, la probabilidad es cero con independencia de cualquier otro factor.
     El juego NO comunica esta condición mediante interfaz.
   - La tabla completa de resolución del rechazo de la sección 8.2: denuncia,
     silencio con memoria, contraoferta y rechazo neutro, con sus condiciones
     exactas de rasgos.
   - Ofertas insuficientes según balance.json.
   - Los cuatro canales con sus consecuencias diferenciadas.

Incluye tests/test_bribe.gd: probabilidad cero con Rose Miller y con Amelia Cole;
probabilidad elevada con Frank Rudd; y verificación de que el registro de
relaciones modifica el precio en la dirección correcta.
```

**Verificación:** `godot --headless --script tests/test_bribe.gd`

---

### PASO 19 — Flagrancia

**Construye:** `src/simulation/caught_handler.gd`, `src/ui/caught_window.gd`.
**Consultar:** 12.2 completa.

```
PASO 19: el momento de flagrancia.

Implementa la sección 12.2 en su totalidad.

Al recibir player_caught_redhanded:
- Ralentización temporal y aparición de la ventana de decisión con dos opciones.

OPCIÓN 1, SOBORNO INMEDIATO: aplica bribery.gd con el favor
silence_witnessed (multiplicador 20). Los cuatro resultados de la tabla.
IMPORTANTE: si se acepta, el personaje NO denuncia pero CONSERVA la creencia
íntegra y adquiere material de chantaje. Registra ambos efectos.

OPCIÓN 2, ELIMINACIÓN: disponible únicamente si el parámetro witnesses es cero.
Con testigos, la opción aparece DESHABILITADA y marcada en rojo, no pulsable.
Es un requisito: el jugador no debe poder perder la partida por un error de
interfaz.

LA TERCERA CONSECUENCIA, que no es una opción del menú: transcurrido el plazo de
balance.json sin elección, el personaje actúa según su arquetipo, exactamente
como la tabla de la sección 12.2. Implementa las cinco reacciones diferenciadas.

Incluye tests/test_caught.gd: ser descubierto por cada uno de los doce
arquetipos y verificar que cada uno produce la reacción documentada.
```

**Verificación:** `godot --headless --script tests/test_caught.gd`

---

### PASO 20 — Expedientes de personal

**Construye:** `src/ui/stellar_os/personnel_app.gd`.
**Consultar:** 13.3, 13.4.

```
PASO 20: la aplicación de expedientes de personal.

Crea src/ui/stellar_os/personnel_app.gd según la sección 13.4:

- Ficha de cada personaje con el detalle ESCALADO POR ACREDITACIÓN, siguiendo
  exactamente la tabla de niveles N1 a N7.
- Las funciones completas: búsqueda, los filtros enumerados, ordenación por
  rasgo visible, marcado de objetivos, comparación de dos personajes,
  y anotaciones vinculadas al cuaderno.
- La acción de ESTUDIO: consume entre quince y treinta minutos de tiempo de
  juego mediante GameClock y devuelve una predicción del comportamiento del
  personaje ante una acción concreta.
- Las vías de acceso anticipado de la sección 13.4.

Estilo visual: interfaz corporativa obsoleta según la sección 14.8. El contraste
con el HUD del juego es deliberado.

Al ejecutar, sentado en el escritorio propio y con acreditación N1, debo ver
únicamente nombre, fotografía, puesto y planta de cada personaje.
```

**Verificación:** ejecutar, sentarse en el escritorio, abrir el ordenador con C, acceder a la aplicación. Con N1 solo deben aparecer los cuatro campos básicos.

## 38. Fase D — Progresión y trabajo

### PASO 21 — Sillas y promociones

**Construye:** `src/autoload/company.gd`.
**Consultar:** 6.2, 6.3, 19.8.

```
PASO 21: Company.

Crea src/autoload/company.gd implementando la interfaz de la sección 19.8.
Por ahora sin fundamentales económicos: eso es el paso 32.

Requisitos:
- Registro de qué personaje ocupa cada una de las cincuenta sillas.
- LA REGLA DE LA SILLA LIBRE de la sección 6.2: can_player_promote_to devuelve
  el diccionario con las condiciones que faltan, para que la interfaz pueda
  informar al jugador de qué le impide ascender.
- La reposición automática de la sección 6.3, incluida la generación del favor
  en quien asciende y del agravio en quien queda sin la silla.
- Promociones con elección de rama cuando el rango contiene dos ocupaciones.
- Posibilidad de RECHAZAR una promoción.
- Descensos y movimientos laterales.
- Registro de mérito reciente con caducidad.

Incluye tests/test_promotion.gd: verificar que las tres condiciones son
necesarias, que la reposición funciona en cadena, y que se generan favor y
agravio.
```

**Verificación:** `godot --headless --script tests/test_promotion.gd`

---

### PASO 22 — Deberes y la herramienta de IA

**Construye:** `src/simulation/duty_system.gd`, `data/duties.json`, `src/ui/stellar_os/mail_app.gd`, `src/ui/stellar_os/assist_app.gd`.
**Consultar:** 10 completa, 32.2.

```
PASO 22: el sistema de deberes.

1. data/duties.json con los cinco tipos de la sección 10.2 y sus propiedades,
   empleando el esquema de la sección 32.2.

2. src/simulation/duty_system.gd con los cinco tipos y sus mecánicas
   diferenciadas.

3. Implementa el primer deber jugable de tipo VOLUMEN: los ocho correos del
   rango R1, como aplicación MAIL de StellarOS. Correspondencia corporativa
   absurda; responder consume tiempo de juego real según la tabla de la
   sección 10.6.

4. A.S.S.I.S.T. según la sección 10.4: la lotería de resultados con sus tres
   probabilidades exactas, la detección del fallo evidente por personajes con
   Perspicacia superior al umbral, y el rastro digital acumulativo.

5. Consecuencias del incumplimiento según balance.json: aviso, descenso,
   expulsión.

El principio de diseño de la sección 10.1 debe cumplirse: cumplir honestamente
consume el tiempo que el jugador necesita para delinquir.
```

**Verificación:** ejecutar, abrir MAIL y responder correos. El reloj debe avanzar cuarenta y cinco minutos de juego.

---

### PASO 23 — Generación de ideas

**Construye:** `src/autoload/idea_pool.gd`, `data/ideas.json`.
**Consultar:** 11.1, 19.11, 32.3.

```
PASO 23: IdeaPool.

1. data/ideas.json con las plantillas por departamento y los cinco métodos de
   adquisición, según el esquema de la sección 32.3.

2. src/autoload/idea_pool.gd implementando la interfaz de la sección 19.11:
   - Generación según la fórmula de probabilidad de la sección 11.1
   - Estructura de idea completa con todos sus campos
   - SEÑALIZACIÓN de la sección 11.1: indicador visual sobre el personaje más
     cambio de comportamiento observable
   - CADUCIDAD: la frescura decrece cada jornada; si el propietario la presenta
     antes, la idea pierde todo valor
   - Las cinco vías de adquisición con sus rastros diferenciados

Al ejecutar, permaneciendo junto a Claudia Reeves durante varias jornadas, debe
aparecerle el indicador de idea y observarse su cambio de comportamiento.
```

**Verificación:** ejecutar y esperar junto a Claudia Reeves.

---

### PASO 24 — La sala Aurora

**Construye:** `src/simulation/idea_presentation.gd`, `src/ui/aurora_scene.gd`.
**Consultar:** 11.2 completa.

```
PASO 24: la escena de presentación de ideas.

Implementa la sección 11.2 íntegramente. Es la escena social decisiva del juego.

Requisitos:
- Reuniones programadas semanalmente en aurora_room, visibles en el calendario
  y en la aplicación PORTAL.
- La fórmula de mérito de la sección 11.2 con sus tres factores de presentación.
- EL CHOQUE DE CREDIBILIDAD: si el propietario está vivo y presente, puede
  acusar. Implementa las dos fórmulas de credibilidad y los tres resultados
  posibles con sus consecuencias numéricas exactas, incluida la creación de la
  creencia "roba ideas" con la certeza especificada.

Incluye tests/test_idea_presentation.gd que fuerce los tres resultados del
choque y verifique las consecuencias de cada uno.
```

**Verificación:** `godot --headless --script tests/test_idea_presentation.gd`

---

### PASO 25 — StellarOS completo

**Construye:** las siete aplicaciones de `src/ui/stellar_os/`.
**Consultar:** 13.3.

```
PASO 25: StellarOS completo.

Completa las siete aplicaciones de la tabla de la sección 13.3. MAIL, PERSONNEL
y A.S.S.I.S.T. ya existen de pasos anteriores.

Construye:
- NOTEBOOK: anotaciones libres del jugador más registro automático de objetivos
  marcados, favores pendientes y casos abiertos. Es la memoria externa del
  jugador en una partida de veinte horas.
- PORTAL: organigrama completo con el ocupante de cada silla y LA
  IDENTIFICACIÓN DE LAS VACANTES. Es donde el jugador localiza el hueco que
  debe ocupar o generar. Consulta Company.
- FILES: archivos propios y, según rango o intrusión, ajenos.
- MARKET: deja el marco preparado. Se completa en el paso 34.

El ordenador MEJORA CON EL RANGO según la sección 13.3: el terminal de R1 tarda
en arrancar y muestra publicidad interna; el de R33 responde de inmediato. La
progresión debe resultar perceptible: es un elemento humorístico deliberado.
```

**Verificación:** ejecutar. Las siete aplicaciones abren. PORTAL muestra las cincuenta sillas con su ocupación.

---

### PASO 26 — El teléfono móvil

**Construye:** `src/ui/mobile/`.
**Consultar:** 13.5.

```
PASO 26: el teléfono móvil.

Implementa la sección 13.5:

- Superposición, NO pantalla completa: el jugador permanece expuesto mientras lo
  utiliza. Usarlo ante un superior incrementa la sospecha.
- CONTACTOS: adquisición por proximidad laboral, favores, RRHH o compra.
  Un directivo no responde a un jugador de rango muy inferior.
- CHAT: genera REGISTRO DIGITAL consultable por el Director de IT.
- LLAMADA: sin registro escrito, pero requiere privacidad física. Si hay un
  personaje en el radio de escucha, oye la conversación.
- Interfaz de soborno: contacto, favor, y ajuste de cantidad por control
  deslizante. Con expediente de nivel N5 o superior se muestra el precio
  estimado.
```

**Verificación:** ejecutar, abrir el móvil con M en medio de la oficina. El indicador de detección debe seguir activo.

---

## 39. Fase E — Riesgo y consecuencias

### PASO 27 — Seguridad y vigilancia

**Construye:** `src/autoload/security.gd`, sistema de cámaras y lectores.
**Consultar:** 5.4, 5.5, 7.10, 19.7.

```
PASO 27: Security.

Crea src/autoload/security.gd implementando la parte de vigilancia de la
interfaz de la sección 19.7. Las investigaciones son el paso 28.

Requisitos:
- NIVEL DE ALERTA GLOBAL de cero a cinco, calculado a partir de la sospecha del
  jugador más los incidentes recientes. Emite alert_level_changed.
- Efectos del nivel de alerta: frecuencia de rondas de vigilantes, perspicacia
  efectiva de los vigilantes, y probabilidad de revisión de grabaciones.
- SISTEMA DE CÁMARAS: las salas con has_cameras registran al jugador si su
  acreditación no cubre la zona. Cada grabación es un REGISTRO PERMANENTE que
  no decae. Emite camera_recorded_player.
- REGISTROS DE ACCESO: cada puerta con lector genera constancia con
  identificador de tarjeta, jornada y hora. Emite card_reader_logged.
- delete_footage funciona exclusivamente desde monitor_room.
- can_search_player devuelve verdadero si la sospecha supera el umbral o si
  existe investigación abierta que incluya al jugador.

Conecta el efecto pendiente del paso 14: la sospecha elevada incrementa el
nivel de alerta.
```

**Verificación:** ejecutar. Acceder a una zona con cámara sin acreditación suficiente: el panel F1 debe mostrar el registro generado.

---

### PASO 28 — Investigaciones

**Construye:** `src/simulation/investigation.gd`, `data/investigations.json`.
**Consultar:** 12.3, 12.4, 19.7.

```
PASO 28: el motor de investigaciones.

1. data/investigations.json con los umbrales, los pesos de evidencia de la
   tabla de la sección 12.4, las duraciones de fase, y el orden de registro de
   salas.

2. src/simulation/investigation.gd implementando las CINCO FASES de la
   sección 12.3 con exactitud.

Detalles de cumplimiento obligatorio:
- FASE 1: los disparadores de la tabla con sus pesos iniciales. Umbral de
  apertura 3,0 modulado por la sospecha del jugador.
- FASE 2: los tres procedimientos secuenciales. El registro físico de salas
  recorre las ubicaciones por orden de probabilidad y ES DONDE AFLORA un cuerpo
  mal ocultado o un objeto escondido. Duración de dos a diez jornadas según
  gravedad.
- FASE 3: la fórmula completa de peso por sospechoso, incluidos los tres
  incrementos por oportunidad, móvil y ser el último en salir.
- FASE 4: transición a la escena de interrogatorio si el jugador encabeza.
- FASE 5: los cuatro veredictos con sus umbrales exactos.
- Las palancas del jugador en cada fase deben estar implementadas como puntos
  de entrada públicos.
- El intervalo mínimo de tres jornadas entre investigaciones de la sección 15.3.

Incluye tests/test_investigation.gd: recorrido completo de las cinco fases con
y sin interferencia, y verificación de que un cuerpo mal ocultado aflora en la
fase 2.
```

**Verificación:** `godot --headless --script tests/test_investigation.gd`

---

### PASO 29 — El interrogatorio

**Construye:** `src/ui/interrogation_scene.gd`.
**Consultar:** 12.5.

```
PASO 29: la escena de interrogatorio.

Implementa la sección 12.5 en la sala interrogation_room de la planta 15.

Requisitos:
- El investigador presenta las piezas de evidencia de forma SECUENCIAL, una a una.
- Las cinco respuestas de la tabla con sus condiciones y efectos exactos,
  incluida la duplicación del peso si una coartada falsa se verifica.
- Condición de éxito: reducir el peso total por debajo de 7,0.
- La solicitud de asistencia legal congela el caso tres jornadas.
- EL DETALLE DE TONO de la sección 12.5: con reputación superior a 85 la escena
  se abre con una disculpa del investigador; con sospecha superior a 70, con la
  puerta cerrándose de golpe. Es el mismo sistema con distinta presentación y
  comunica al jugador su posición social sin interfaz.
```

**Verificación:** provocar una investigación deliberadamente y dejarse acusar.

---

### PASO 30 — Casos fríos

**Construye:** ampliación de `src/autoload/security.gd`.
**Consultar:** 12.6.

```
PASO 30: casos fríos.

Implementa la sección 12.6.

Requisitos:
- Un caso archivado conserva íntegra su evidencia como registro permanente y
  pasa a estado frío. Emite case_went_cold.
- Los tres disparadores de reactivación de la tabla, con sus probabilidades:
  aparición de pieza nueva (determinista), cambio de posición de un testigo
  silencioso (proporcional al agravio acumulado), y cambio de ocupante en la
  silla de Auditoría (40% de probabilidad de revisión).
- close_case_permanently accesible únicamente desde la ocupación chief_auditor.
  Es la única vía de cierre definitivo.

Incluye tests/test_cold_case.gd: archivar un caso, cambiar el ocupante de
Auditoría, y verificar la reactivación.
```

**Verificación:** `godot --headless --script tests/test_cold_case.gd`

---

### PASO 31 — Seguimiento, finales y persistencia

**Construye:** `src/autoload/tracking.gd`, `src/autoload/save_system.gd`, `data/endings.json`.
**Consultar:** 12.7, 12.8, 12.9, 19.12, 19.13, 32.8.

```
PASO 31: seguimiento, finales y persistencia.

1. src/autoload/tracking.gd con los cinco ejes y los incrementos exactos de la
   tabla de la sección 12.8. Los cuatro primeros determinan el estilo dominante;
   RUINA es independiente y determina la variante.

2. data/endings.json con las condiciones de los nueve finales de la
   sección 12.9, empleando el esquema de la sección 32.8.

3. PERMADEATH VARIANTE A según la sección 12.7: al producirse cualquier
   condición terminal se borra user://run.json y la partida siguiente comienza
   en una instancia completamente nueva. Solo persiste user://profile.json.

4. src/autoload/save_system.gd implementando la interfaz de la sección 19.13.
   ESCRITURA ATÓMICA obligatoria: escribir en archivo temporal, verificar
   integridad, y renombrar sobre el destino. Cada autoload implementa save_state
   y load_state; SaveSystem únicamente los recorre sin conocer su contenido.

Incluye tests/test_endings.gd (los nueve finales se disparan con su combinación
de condiciones) y tests/test_save_load.gd (guardar y cargar reproduce el estado
exacto de todos los sistemas).
```

**Verificación:** ambos tests sin ventana.

## 40. Fase F — Economía

### PASO 32 — Fundamentales de la compañía

**Construye:** ampliación de `src/autoload/company.gd`.
**Consultar:** 9.2, 9.10, 19.8.

```
PASO 32: los fundamentales económicos.

Amplía Company con la parte económica de la interfaz de la sección 19.8.

Requisitos:
- Los cinco componentes de la tabla de la sección 9.2 con sus fórmulas de
  cálculo y los sistemas que los alimentan.
- Recálculo una vez por jornada al recibir day_advanced.
- La distinción entre fundamentales y valores reportados. set_reported_figures
  accesible únicamente desde los cargos autorizados: b10_director, cfo, ceo.
- LA MECHA DE AUDITORÍA de la sección 9.2: toda divergencia enciende un
  temporizador cuya duración es inversamente proporcional a la magnitud.
  Emite audit_fuse_lit y, al expirar, audit_triggered.
- LA IRONÍA ESTRUCTURAL de la sección 9.10: add_theft_loss incrementa costes;
  la expulsión de personal cualificado reduce la calidad de producto y la
  generación de ideas; los escándalos incrementan el factor de riesgo.
  Conecta estos efectos a las señales correspondientes del EventBus.
- El sistema de descontento de la sección 11.7 con los factores de su tabla.
```

**Verificación:** ejecutar, robar producto, y comprobar en el panel F1 que el componente de pérdidas se incrementa.

---

### PASO 33 — El mercado

**Construye:** `src/autoload/market.gd`, `data/market.json`.
**Consultar:** 9.3, 9.4, 19.9.

```
PASO 33: Market.

1. data/market.json con los parámetros de simulación, el calendario trimestral
   y los objetivos por trimestre.

2. src/autoload/market.gd implementando la parte de cotización de la interfaz
   de la sección 19.9:
   - Cálculo del valor intrínseco según la fórmula de la sección 9.3, con el
     múltiplo modulado por crecimiento y riesgo.
   - La fórmula de evolución diaria con sus cuatro fuerzas y sus coeficientes
     exactos de balance.json.
   - Recálculo UNA VEZ POR HORA DE JUEGO, nunca por fotograma.
   - Histórico de precios para el cálculo del momentum sobre cinco jornadas.
   - El calendario económico de la sección 9.4 con sus cinco periodicidades.

Incluye tests/test_market.gd: verificar que un trimestre con escándalo deprime
la cotización y uno sin escándalo no, y que la gravedad revierte una
manipulación de sentimiento en el plazo esperado.
```

**Verificación:** `godot --headless --script tests/test_market.gd`

---

### PASO 34 — Inversores y presentación de resultados

**Construye:** ampliación de `src/autoload/market.gd`, `data/investors.json`, `src/ui/stellar_os/market_app.gd`, `src/ui/results_presentation.gd`.
**Consultar:** 9.5, 9.6, 9.7, 9.11, 24.4, 32.4.

```
PASO 34: inversores, confianza y presentación trimestral.

1. data/investors.json con las cinco estrategias y los seis inversores de la
   sección 24.4, empleando el esquema de la sección 32.4.

2. Amplía Market con:
   - Los inversores como agentes con capital, estrategia, confianza y venalidad.
   - El agregado ponderado por capital de la sección 9.7.
   - La tabla de factores que modifican la confianza, con sus valores exactos.
   - La cartera personal del jugador según la sección 9.11, incluidos los
     derechos de voto derivados del paquete accionarial.

3. src/ui/results_presentation.gd con las TRES FASES de la sección 9.5:
   preparación con decisión de valores reportados, presentación con la fórmula
   de calidad y sus cuatro niveles de preparación, y reacción de cada inversor
   según su estrategia.

4. Completa la aplicación MARKET de StellarOS: cotización, calendario,
   inversores con su confianza, y cartera.
```

**Verificación:** ejecutar con rango R28 forzado y ejecutar una presentación trimestral.

---

### PASO 35 — Noticias e información privilegiada

**Construye:** `src/autoload/news_feed.gd`, `data/market_events.json`.
**Consultar:** 7.11, 9.8, 9.12, 19.10, 32.6.

```
PASO 35: NewsFeed y el bucle de información privilegiada.

1. data/market_events.json con el catálogo de la sección 9.12, empleando el
   esquema de la sección 32.6.

2. src/autoload/news_feed.gd implementando la interfaz de la sección 19.10.

REQUISITO CENTRAL, la capa compartida de la sección 7.11: cada noticia debe
producir SIMULTÁNEAMENTE un efecto de sospecha y un efecto de sentimiento de
mercado. Un escándalo incrementa la vigilancia sobre el jugador y deprime la
cotización con el mismo evento. Enterrar la noticia beneficia a ambos sistemas.

3. El bucle de información privilegiada de la sección 9.8:
   - get_upcoming_news accesible desde R25
   - Acumulación de puntos de patrón con la fórmula de detección
   - Al superar el umbral: investigación de gravedad máxima que ADEMÁS es noticia
   - Las contramedidas enumeradas como puntos de entrada
```

**Verificación:** ejecutar, provocar un escándalo, y comprobar que sospecha y cotización se ven afectadas por el mismo evento.

## 41. Fase G — Mundo completo

### PASO 36 — El mapa

**Construye:** `src/ui/map_view.gd`.
**Consultar:** 13.6, 14.1.

```
PASO 36: el mapa en corte vertical.

Implementa la sección 13.6:
- Representación en corte del edificio completo: veinte plantas, tres sótanos
  y la nave anexa. Es la imagen identificativa del juego.
- Codificación cromática de acceso según la tabla.
- Puntos de personaje únicamente para los conocidos con rutina desbloqueada,
  según el nivel de expediente.
- Las tres capas activables: cámaras, rutas alternativas, ocupación por franja.
- Zoom a planta con plano detallado.
- Los objetivos marcados desde el expediente aparecen destacados.
```

**Verificación:** ejecutar y pulsar Tab.

---

### PASO 37 — Inventario y contrabando

**Construye:** `src/simulation/inventory.gd`, ampliación de `src/ui/hud.gd`.
**Consultar:** 11.3.

```
PASO 37: inventario y contrabando.

Implementa la sección 11.3:
- Ocho posiciones. Las dos categorías de objeto con sus consecuencias
  diferenciadas en un registro corporal.
- Las seis ubicaciones de ocultación de la tabla, con sus niveles de seguridad
  e inconvenientes. El muelle de basuras extrae el objeto del juego de forma
  irreversible.
- Registro corporal por parte de Security cuando can_search_player devuelve
  verdadero. Portar material comprometedor produce evidencia de peso 10.
- Interfaz de inventario con distinción visual clara entre categorías.
```

**Verificación:** ejecutar, sustraer un objeto comprometedor, y provocar un registro con sospecha elevada.

---

### PASO 38 — Disfraces

**Construye:** `src/simulation/disguise.gd`.
**Consultar:** 11.4.

```
PASO 38: el sistema de disfraces.

Implementa la sección 11.4:
- Tres uniformes obtenibles en los vestuarios del sótano primero.
- El comportamiento por distancia de la tabla: clasificación por uniforme más
  allá de seis metros; reconocimiento personal por debajo de tres metros para
  quienes conocen al jugador o poseen Perspicacia superior a 70.
- Las cámaras registran el uniforme, no la identidad, SALVO que una
  investigación en fase 2 cruce el registro de acceso con el cuadrante de turnos.
- COHERENCIA CONTEXTUAL: el uniforme se evalúa contra hora y zona. Un uniforme
  fuera de su franja o su zona incrementa la sospecha en lugar de reducirla.
```

**Verificación:** ejecutar, obtener el uniforme de limpieza, y comprobar que a las 20:00 los personajes no reaccionan pero a las 14:00 sí.

---

### PASO 39 — Exterior y policía

**Construye:** `data/rooms/exterior.json`, `src/simulation/police.gd`, ciclo nocturno.
**Consultar:** 4.2, 4.3, 7.10, 22.16.

```
PASO 39: el mundo exterior.

1. data/rooms/exterior.json con las diez localizaciones de la sección 22.16.

2. El ciclo de tarde y noche de las secciones 4.2 y 4.3: salida del edificio,
   desplazamiento, adquisición de alimentos y vestuario, cena, descanso que
   guarda la partida, y desayuno.

3. src/simulation/police.gd:
   - La misma lógica de testigos y creencias del interior.
   - Un aviso consolidado despacha una unidad desde police_station con el
     tiempo de respuesta de balance.json. Emite police_dispatched.
   - EL PASAMONTAÑAS reduce la identificación: sin él el testigo reconoce al
     jugador y la creencia se vincula a su identidad, propagándose al edificio
     como registro; con él la creencia carece de sujeto determinado.
   - Los callejones permiten la evasión, pero producen cerco si se agotan.

4. El seguimiento de personajes hasta su domicilio, con las tres tipologías de
   vivienda y sus botines diferenciados.
```

**Verificación:** ejecutar, salir del edificio al terminar la jornada, adquirir alimentos y dormir. La partida debe guardarse.

---

### PASO 40 — Nivel de detalle y rendimiento

**Construye:** ampliación de `src/autoload/npc_director.gd`, `src/world/floor_streamer.gd`.
**Consultar:** 20 completa.

```
PASO 40: nivel de detalle y streaming de plantas.

1. Implementa los tres niveles de simulación de la sección 20.1 en NPCDirector,
   con sus poblaciones, sistemas activos y frecuencias exactas.

2. Las reglas de asignación de la sección 20.2, especialmente:
   LOS PERSONAJES IMPLICADOS EN UNA TRAMA ACTIVA ASCIENDEN SIEMPRE A NIVEL 0,
   con independencia de su ubicación. Trama activa incluye: figurar en lista
   corta, estar marcado como objetivo, mantener deuda con el jugador, o poseer
   una idea vigilada. Esta regla impide que un elemento narrativamente relevante
   se degrade por lejanía.

3. src/world/floor_streamer.gd: mantiene cargadas únicamente la planta actual y
   las adyacentes. Descarga y carga al usar ascensores o escaleras.

4. Opción de configuración para el número máximo de agentes.

Objetivo de rendimiento de la sección 20.3: sesenta fotogramas por segundo en
equipo de gama media.
```

**Verificación:** ejecutar con la población completa y observar el contador de fotogramas.

---

### PASO 41 — Fábrica, compradores y huelgas

**Construye:** `src/simulation/factory_theft.gd`, `src/simulation/buyers.gd`, `src/simulation/strike.gd`.
**Consultar:** 11.5, 11.6, 11.7.

```
PASO 41: fábrica, compradores y conflicto laboral.

1. El robo en fábrica según la sección 11.6: las tres escalas con sus requisitos,
   ingresos y rastros. EL INVENTARIO SEMANAL como mecanismo de consecuencia
   retardada: los robos afloran en el recuento posterior, no en el momento.
   La falsificación de albaranes para dirigir el descuadre al superior.

2. Los compradores según la sección 11.5: las cuatro operaciones con sus
   beneficios y riesgos. Los compradores son personajes con rasgos propios:
   uno perspicaz detecta el sobreprecio en el acto; uno codicioso acepta la
   mordida.

3. El sistema de huelgas según la sección 11.7: el medidor de descontento con
   sus factores, las cuatro acciones disponibles, y los efectos de una huelga
   activa sobre ambos cerebros simultáneamente.
```

**Verificación:** ejecutar, sustraer una caja de producto, y esperar al recuento semanal.

## 42. Fase H — Contenido masivo

> Los tres pasos siguientes se ejecutan de forma iterativa. Cada iteración es una sesión independiente.

### PASO 42 — Las 166 salas

**Iteraciones:** aproximadamente doce, una por agrupación de plantas.
**Consultar:** 22 completa, 27.

```
PASO 42.[N]: las salas de [agrupación].

Crea data/rooms/[archivo].json con las salas de la sección 22.[N] del documento,
empleando el esquema completo de la sección 27.

Para cada sala transcribe: identificador, clave de nombre, planta y ala,
acreditación requerida, accesos especiales, banda artística, kit, ambiente
sonoro y nivel de ruido, presencia y posición de cámaras, dimensiones,
mobiliario con posiciones, escondites, interactuables, entradas ilegítimas,
conexiones con otras salas, y ocupación por franja.

Las posiciones de mobiliario deben ser coherentes con las dimensiones
declaradas y dejar espacio transitable.

Verifica al terminar que el recuento acumulado de salas coincide con lo esperado.
```

**Orden recomendado de iteraciones:** planta baja y sótanos, nave fabril, plantas 1 y 2, planta 4, planta 5, plantas 6 y 7, plantas 8 y 9, plantas 10 y 11, plantas 12 y 13, plantas 14 y 15, plantas 16 y 17, plantas 18 a 20, transversales y exterior.

---

### PASO 43 — Las 50 ocupaciones completas

**Iteraciones:** ocho, una por escalón.
**Consultar:** 23 completa, 26.

```
PASO 43.[N]: las ocupaciones del escalón [N].

Amplía data/occupations.json con las ocupaciones del escalón [N] según la
sección 23.[N], empleando el esquema completo de la sección 26.

Para cada ocupación transcribe todos los atributos de la tabla, con especial
atención a:
- La definición completa de sus deberes: tipo, cantidad, coste temporal, coste
  con asistencia artificial, hora límite y penalización por incumplimiento.
- Las herramientas y accesos especiales.
- Las relaciones de promoción, salto y descenso.
- El nivel de expediente de personal que concede.

Verifica que las relaciones de promoción son coherentes: toda ocupación
referenciada en promotes_to debe existir.
```

---

### PASO 44 — La plantilla completa

**Iteraciones:** dos.
**Consultar:** 24.2, 24.3, 29, 30.

```
PASO 44.1: los personajes nominados.

Completa data/npcs_named.json con los VEINTITRÉS personajes de la sección 24.2,
con sus valores numéricos exactos, rutinas, vínculos iniciales, corrillos,
debilidad, riesgo, accesorio identificativo y semilla de retrato.
```

```
PASO 44.2: el generador de plantilla.

1. data/npcs_generation.json con el banco de nombres, las bolsas de arquetipos
   por departamento de la sección 24.3, y las reglas de generación de vínculos.

2. El procedimiento de generación de siete pasos de la sección 24.3, integrado
   en NPCDirector.generate_population.

Verifica al terminar que la población total asciende a aproximadamente ciento
cincuenta personajes, que ninguna combinación de nombre y apellido se repite,
y que la distribución de arquetipos por departamento se aproxima a las
probabilidades declaradas.
```

## 43. Fase I — Cierre

### PASO 45 — La secuencia final

**Construye:** `src/simulation/endgame.gd`.
**Consultar:** 11.8 completa.

```
PASO 45: la secuencia de apropiación.

Implementa la sección 11.8 en su totalidad. Es el clímax del juego y la única
secuencia con estructura de misión definida.

Las seis fases con sus requisitos exactos:
1. Revelación del objetivo únicamente desde legal_director o superior. Con
   anterioridad el segundo objetivo permanece oculto.
2. Las tres vías de obtención de la combinación, con sus riesgos diferenciados.
   Pearl Osgood informa a Voss si el intento fracasa.
3. La ventana temporal con los tres accesos al despacho.
4. Los documentos como objeto comprometedor.
5. LA NOTARÍA: los documentos carecen de validez sin formalización. Requiere
   ostentar el cargo o presentar autorización falsificada, más un notario
   dispuesto. Con reputación elevada firma sin verificación; con sospecha
   elevada solicita comprobación y abre un plazo de tres jornadas de máxima
   vulnerabilidad.
6. Evaluación del tracking y disparo del epílogo correspondiente.

Emite ownership_documents_obtained y ownership_notarised.
```

**Verificación:** ejecutar con rango R33 forzado y completar la secuencia.

---

### PASO 46 — Apertura, tutorial y epílogos

**Construye:** `scenes/cinematics/`, `src/ui/tutorial.gd`, `src/ui/endings_gallery.gd`.
**Consultar:** 12.9, 13.8, 13.9.

```
PASO 46: apertura, tutorial y epílogos.

1. La secuencia de apertura de la sección 13.9: noventa segundos, tres
   movimientos, sin diálogo hablado. Únicamente texto y sonido.

2. El tutorial de la sección 13.8 en la sala de formación: las tres partes,
   menos de diez minutos, saltable en partidas posteriores. El vídeo corporativo
   ES el tutorial de movimiento y no debe declararse como tal.

3. Los nueve epílogos de la sección 12.9, cada uno con su texto, más las
   variantes de ruina para los siete de victoria.

4. La galería de finales del menú principal, con siluetas para los no
   desbloqueados. Persiste en user://profile.json.
```

**Verificación:** iniciar partida nueva y completar el tutorial.

---

### PASO 47 — Arte, sonido y ajuste final

**Construye:** paletas, animaciones, audio.
**Consultar:** 14 completa, 15 completa.

```
PASO 47: presentación y ajuste final.

1. Aplicación de las cinco paletas de la sección 14.3 a todas las salas, con
   sus iluminaciones y los refuerzos satíricos: densidad de ocupación
   decreciente, ruido ambiente decreciente, plantas de plástico frente a
   naturales, densidad de carteles motivacionales.

2. El catálogo completo de animaciones de la sección 14.7, con animación
   limitada de ocho a doce fotogramas.

3. EL HILO MUSICAL CORPORATIVO de la sección 14.9 con sus cuatro estados de
   degradación según la sospecha. Es un elemento central del diseño: el edificio
   comunica al jugador su nivel de riesgo mediante el canal auditivo.

4. Los efectos de sonido de la sección 14.10 en sus tres categorías
   funcionales, con los radios de balance.json.

5. Ajuste final de balance.json según la Parte VI, y los tres presets de
   dificultad de la sección 15.7.

6. Los subtítulos descriptivos para todo sonido con función informativa
   (sección 13.10).
```

**Verificación:** partida completa desde el rango R1, verificando que la degradación musical acompaña al incremento de sospecha.

## 44. Dependencias entre sistemas

| Para construir | Es necesario haber construido |
|---|---|
| Cualquier sistema | EventBus y Database (pasos 2 y 4) |
| Percepción | Un personaje con rutina (paso 9) |
| Creencias | Percepción (paso 10) |
| Rumores | Creencias y grafo social (pasos 13 y 15) |
| Flagrancia | Percepción y sobornos (pasos 10 y 18) |
| Investigaciones | Creencias y Security (pasos 13 y 27) |
| Promociones | Company, deberes e ideas (pasos 21 a 24) |
| Mercado | Company con fundamentales (paso 32) |
| Secuencia final | Prácticamente todos los sistemas |
| Finales | Tracking y la totalidad de sistemas (paso 31) |

**Regla operativa:** ningún sistema se construye antes de que su escenario de validación pueda ejecutarse.

---

# PARTE XI — APÉNDICES

## 45. Lista de verificación por pieza

Antes de dar por terminado cualquier paso:

- [ ] Los archivos se han entregado completos, con su ruta exacta indicada.
- [ ] La totalidad del código emplea tipado estático.
- [ ] No existe ningún valor numérico ajustable escrito dentro del código.
- [ ] Ningún sistema global invoca a otro de forma directa.
- [ ] Ninguna función excede las cuarenta líneas.
- [ ] Cada archivo incluye su cabecera documental de tres líneas.
- [ ] Todo texto destinado a mostrarse emplea claves de localización.
- [ ] Las firmas empleadas coinciden con las especificadas en la Parte VII.
- [ ] El escenario de validación correspondiente existe y se supera.
- [ ] Se ha indicado el criterio de verificación por ejecución.

## 46. Diagnóstico de incidencias

| Situación | Procedimiento |
|---|---|
| **Error en rojo al ejecutar** | Copiar el mensaje completo, sin resumir. Indicar el paso en curso. |
| **Ausencia de respuesta o pantalla vacía** | Indicar que no se producen errores y describir lo observado. |
| **Comportamiento distinto del esperado** | Describir por separado el comportamiento esperado y el observado. Evitar valoraciones. |
| **Bloqueo del editor** | Cerrar, restaurar la copia de respaldo, e indicar que el paso bloqueaba el editor. |
| **Propuesta de modificación parcial** | Requerir la reescritura íntegra del archivo. |
| **Incoherencia con un paso anterior** | Indicar la sección de la Parte VII que define la interfaz correcta. |

## 47. Errores estructurales a evitar

> Este proyecto fracasó en un intento anterior con otro motor. Las causas fueron las siguientes.

| Causa del fracaso anterior | Medida preventiva en esta especificación |
|---|---|
| Aplicación sucesiva de parches sobre código defectuoso | Entrega de archivos completos, sin excepción |
| Instrucciones incrementales mutuamente contradictorias | Un paso completo por sesión, con verificación previa al siguiente |
| Invocación directa entre componentes hasta formar dependencias circulares | Comunicación exclusiva mediante bus de eventos |
| Contenido escrito dentro del código | Separación estricta entre `data/` y `src/` |
| Improvisación sin especificación previa | Esta especificación |
| Dependencia de un editor visual con archivos no versionables en texto | Godot con formato de texto plano en su totalidad |
| Construcción de sistemas sin capacidad de verificación | Escenario de validación obligatorio por sistema |
| Múltiples componentes modificando el mismo estado | Propiedad exclusiva del dato |
| Imposibilidad de revertir a un estado funcional | Copia del directorio con fecha antes de cada sesión |
| Ampliación del alcance durante la construcción | Alcance cerrado en esta especificación |

## 48. Localización de parámetros

| Para modificar | Archivo |
|---|---|
| El salario de una ocupación | `data/occupations.json` |
| El multiplicador de un favor | `data/bribes.json` |
| La velocidad de detección | `data/balance.json` → `percepcion` |
| El decaimiento de las creencias | `data/balance.json` → `creencias` |
| Los umbrales de investigación | `data/balance.json` → `investigaciones` |
| Los coeficientes del mercado | `data/balance.json` → `mercado` |
| Añadir una sala | `data/rooms/pXX.json` |
| Añadir un personaje | `data/npcs_named.json` |
| Un texto visible | `locale/strings.csv` |
| La dificultad | `data/balance.json` → `dificultad` |

## 49. Decisiones abiertas

Dos cuestiones menores sin resolver. No condicionan la construcción y pueden decidirse al alcanzar el paso correspondiente.

**Nombre del protagonista.** Si lo determina el jugador al iniciar la partida o si es fijo. *Recomendación: que lo determine el jugador, dado que refuerza la condición intercambiable del personaje, que es coherente con la premisa satírica.*

**Confirmación del lema.** *Work hard. Or don't.*

---

# CIERRE

Esta especificación contiene la totalidad de la información necesaria para construir THE WORKER:

- **Partes I a VI:** la especificación de diseño completa, desde la premisa hasta el plan de publicación.
- **Parte VII:** la especificación técnica, con las interfaces exactas de los catorce sistemas globales y el catálogo íntegro de señales.
- **Partes VIII y IX:** la biblia de contenido con los ciento sesenta y seis espacios, las cincuenta ocupaciones y los personajes con sus valores definitivos, más los dieciséis esquemas de datos.
- **Parte X:** el manual de obra con los cuarenta y siete pasos, cada uno con su prompt, sus dependencias y su criterio de verificación.
- **Parte XI:** los apéndices de verificación, diagnóstico y referencia.

**El punto de partida es el paso 1.** No existe información previa que consultar.

---

*THE WORKER — Documento Maestro de Construcción · Versión 2.0 · 25 de julio de 2026*
