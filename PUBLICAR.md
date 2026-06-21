# Publicar "Roquet Redemption by Areces" en tiendas (guía paso a paso)

El juego es un único `index.html` + 3 archivos PWA (`manifest.webmanifest`, `sw.js`, `icon.svg`).
Ya está preparado como **PWA instalable a pantalla completa**. Aquí tienes 3 caminos:

- **A. Instalarlo como app (gratis, sin tienda, sin bordes de navegador)** — 2 minutos.
- **B. Google Play / Samsung con PWABuilder** — lo más fácil para tiendas. Play tiene cuota única de 25 $; Samsung es gratis.
- **C. Capacitor (APK autocontenido, sin servidor)** — 100% gratis, ideal para Samsung o instalar a mano.

> Datos de tu web ya desplegada: `https://googledocx-nine.vercel.app`
> Asegúrate de subir SIEMPRE estos 4 juntos en la misma carpeta: `index.html`, `manifest.webmanifest`, `sw.js`, `icon.svg`.

---

## A. Instalarlo como app (gratis, quita los bordes del navegador)

1. Sube los 4 archivos a tu web (Vercel). Comprueba que abren bien:
   - `https://googledocx-nine.vercel.app/manifest.webmanifest` (debe mostrar el JSON).
   - `https://googledocx-nine.vercel.app/sw.js` (debe mostrar el código).
   - `https://googledocx-nine.vercel.app/icon.svg` (debe mostrar el icono).
2. En el móvil, abre `https://googledocx-nine.vercel.app` en **Chrome** (no en el navegador de WhatsApp).
3. Menú **⋮ (arriba a la derecha) → "Instalar aplicación"** (o "Añadir a pantalla de inicio").
4. Acepta. Aparece un icono en tu pantalla de inicio.
5. Ábrelo desde ese icono: se ejecuta **a pantalla completa, sin barra de direcciones**, en horizontal y funciona sin conexión.

Esto ya resuelve "los bordes del navegador tapan el juego" sin tienda alguna.

---

## B. Subirlo a tiendas con PWABuilder (recomendado)

### B.0 Requisitos
- Tu web en HTTPS con los 4 archivos (Vercel ✔).
- Un PC con navegador.
- Para **Google Play**: cuenta de Google Play Console (**25 $ pago único**): https://play.google.com/console
- Para **Samsung**: cuenta de Samsung Seller Portal (**gratis**): https://seller.samsungapps.com

### B.1 Generar los paquetes (.aab y .apk)
1. Ve a **https://www.pwabuilder.com**.
2. Pega tu URL `https://googledocx-nine.vercel.app` y pulsa **Start**.
3. PWABuilder analiza la PWA (detecta el manifest y el service worker que añadí). Verás una puntuación; si falta algo menor, pulsa **"Fix"/"Edit your manifest"** y guarda.
4. Pulsa **"Package For Stores"**.
5. En la tarjeta **Android** pulsa **"Generate Package"**.
6. Opciones importantes que te pedirá:
   - **Package ID / Package name**: pon algo único tipo `app.vercel.googledocx_nine.twa` (solo minúsculas, números y puntos; sin guiones medios). Apunta este nombre.
   - **App name**: `Roquet Redemption by Areces`.
   - **Signing key**: elige **"Create new"** (que te genere una). **DESCARGA y GUARDA** el `.keystore` y la contraseña en lugar seguro: si la pierdes no podrás actualizar la app nunca más.
7. Pulsa **Download**. Obtienes un `.zip` con:
   - `app-release-signed.aab` (para subir a Google Play).
   - `app-release-signed.apk` (para Samsung o instalar a mano).
   - `assetlinks.json` (para verificar tu dominio — clave para que NO salga la barra de URL).
   - Instrucciones (`next-steps.md`).

### B.2 Verificar tu dominio (assetlinks.json) — para que se vea sin barra
1. Abre el `assetlinks.json` del zip. Lleva el SHA-256 de tu clave de firma.
2. Súbelo a tu web en la ruta **exacta**: `https://googledocx-nine.vercel.app/.well-known/assetlinks.json`
   - En tu proyecto, crea la carpeta `.well-known/` junto a `index.html` y mete dentro `assetlinks.json`, y re-despliega.
   - Comprueba que abre en el navegador esa URL y muestra el JSON.
3. Si usas **Play App Signing** (lo normal), después de subir la app a Play, ve a **Play Console → tu app → Integridad de la app (App integrity) → Firma de apps** y copia el **SHA-256** que muestra Google ahí. Pega ESE fingerprint en `assetlinks.json` y vuelve a subirlo. (Google re-firma tu app, por eso hay que usar su huella.)

### B.3 Publicar en Google Play
1. Entra en **https://play.google.com/console** y paga los **25 $** (una vez).
2. **Create app** → nombre `Roquet Redemption by Areces`, idioma, tipo **Game**, gratis.
3. Rellena el menú lateral (Play te marca lo obligatorio):
   - **Store listing**: descripción, capturas (mínimo 2; haz screenshots en horizontal), icono 512×512 (PWABuilder lo incluye; si no, exporta el `icon.svg` a PNG 512), gráfico de cabecera 1024×500.
   - **Privacy policy**: Play **exige una URL de política de privacidad**. Crea una página simple (puede ser otra URL en Vercel) que diga: *"Este juego no recopila ni envía datos personales; todo el progreso se guarda localmente en el dispositivo."* Pega esa URL.
   - **Data safety**: declara **"No data collected / No data shared"**.
   - **Content rating**: rellena el cuestionario IARC (gratis).
   - **Target audience**, **Ads** (declara "No ads" si no pones anuncios).
4. **Production → Create new release**:
   - Activa **Play App Signing** (recomendado, lo gestiona Google).
   - Sube el **`app-release-signed.aab`**.
   - Notas de la versión.
5. **Review release → Start rollout to Production**.
6. Revisión de Google: suele tardar de unas horas a varios días. Cuando esté aprobada, sale publicada.
7. Vuelve a B.2 paso 3 para fijar el `assetlinks.json` con la huella de Play App Signing (si no, saldrá una fina barra de URL arriba).

### B.4 Publicar en Samsung Galaxy Store (gratis)
1. Entra en **https://seller.samsungapps.com** y regístrate (gratis; te pueden pedir verificar identidad).
2. **Add New Application** → tipo **Game** → Android.
3. Sube el **`.apk`** (Samsung acepta APK; también AAB).
4. Rellena ficha (nombre, descripción, capturas, icono), país, precio **Free**, clasificación de edad.
5. Envía a revisión. Suele ser más rápido que Play.

---

## C. Capacitor — APK autocontenido (gratis, sin servidor)

Empaqueta el HTML DENTRO de la app (no necesita Vercel; va offline puro). Bueno para Samsung o instalar a mano (sideload). Requiere **Node.js** y **Android Studio** (gratis).

### C.1 Instalar herramientas
- Node.js LTS: https://nodejs.org
- Android Studio: https://developer.android.com/studio (incluye el JDK y el SDK).

### C.2 Crear el proyecto
```bash
mkdir roquet-app && cd roquet-app
npm init -y
npm install @capacitor/core @capacitor/android
npm install -D @capacitor/cli
npx cap init "Roquet Redemption" "com.areces.roquet" --web-dir=www
mkdir www
# Copia DENTRO de www/ tu index.html (y opcionalmente manifest.webmanifest, sw.js, icon.svg)
npx cap add android
npx cap copy
npx cap open android   # abre Android Studio
```

### C.3 Pantalla completa + horizontal (importante)
Edita `android/app/src/main/AndroidManifest.xml`, en la etiqueta `<activity ...>` añade:
```xml
android:screenOrientation="sensorLandscape"
```
Para inmersivo total (ocultar barras del sistema), añade en `android/app/src/main/res/values/styles.xml` un tema sin barra de acción, o instala el plugin:
```bash
npm install @capacitor-community/keep-awake   # opcional, evita que se apague la pantalla
```
y en `MainActivity.java` (onCreate) puedes activar modo inmersivo con:
```java
getWindow().getDecorView().setSystemUiVisibility(
  android.view.View.SYSTEM_UI_FLAG_FULLSCREEN
  | android.view.View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
  | android.view.View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
```

### C.4 Generar el APK / AAB firmado
En Android Studio: **Build → Generate Signed Bundle / APK**:
1. Elige **APK** (para Samsung / sideload) o **AAB** (para Play).
2. **Create new** keystore → guárdalo y apunta la contraseña (no la pierdas).
3. Variante **release** → Finish. El APK sale en `android/app/release/`.
4. Súbelo a Samsung Seller (gratis) o instálalo en tu móvil (activa "Instalar apps desconocidas").

---

## Resumen rápido
- **Sin tienda, sin bordes, ya**: opción **A** (instalar PWA).
- **A tiendas, fácil**: opción **B** (PWABuilder) → Samsung gratis; Play 25 $ una vez.
- **APK gratis sin servidor**: opción **C** (Capacitor).

Notas:
- Guarda SIEMPRE el **keystore** y su contraseña (sin él no puedes actualizar la app).
- Play exige **política de privacidad** (di que no recoges datos: es verdad, solo `localStorage`).
- El juego ya va a 60 FPS; en TWA usa Chrome y en Capacitor el WebView del sistema: fluido y a pantalla completa.
