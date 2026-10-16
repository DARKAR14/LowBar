# LowBar: prueba XAML para Windows 11

Validado visualmente por el usuario en Windows 11 26H2, build 26300.9550,
con dos pantallas y estilo Transparente, el 16 de octubre de 2026.

## Uso

Ejecuta `LowBar.exe` de la carpeta `preview`, manteniendo `ExplorerTAP.dll`
y `Assets` al lado. El menú del icono junto al reloj permite cambiar el
estilo, restaurar Normal, actualizar la barra y salir. Si quieres que esta
versión se abra al iniciar sesión, activa «Abrir al iniciar» desde ese menú.
No muevas la carpeta después de activar esa opción.

La configuración queda en `data/settings.ini`, junto al ejecutable. Los
registros están en `%TEMP%\LowBar\lowbar.log`. Las actualizaciones del
repositorio original están desactivadas en esta compilación para evitar que
reemplacen el arreglo. No se ha cambiado la instalación anterior.

## Qué cambia

En Windows 11 build 22621 o posterior, el fondo se modifica mediante el
servicio XAML de ExplorerTAP, en vez de aplicar solo un atributo Win32 al
contenedor de la barra. Los errores de conexión ahora se muestran al usuario.
La barra se restaura al salir y el servicio también vigila la muerte del proceso.
El reinicio de Explorer se atiende con el mensaje TaskbarCreated.

Transparente usa SolidColor con alfa cero; no crea un efecto de desenfoque.
Opaco también usa color sólido. Desenfoque y Acrílico sí usan efectos del
compositor y pueden consumir más GPU. No hay bucle de repintado ni temporizador
periódico para imponer el estilo.

## Validación y límites

- Compilación Windows x64 y pruebas Go de la interfaz COM y los cinco estilos.
- Conexión real a Explorer y aplicación a dos barras; transparencia confirmada
  por el usuario en ambas pantallas.
- Los otros estilos tienen pruebas de parámetros, pero requieren comprobación
  visual. No se promete compatibilidad con todas las compilaciones de Windows.
- La enumeración XAML puede tardar al conectar pantallas; usa «Actualizar barra
  de tareas» si una barra recién creada conserva su fondo original.
- No se ha demostrado una reducción de GPU frente a TranslucentTB ni medido
  sistemáticamente el coste agregado de LowBar, Explorer y dwm.exe.
- Cierra otros personalizadores antes de usar esta versión.

## Compilar

Con Go 1.23 o posterior en PATH, ejecuta `scripts/build-xaml-preview.ps1`.
El script descarga el paquete oficial fijado de ExplorerTAP, comprueba SHA256,
ejecuta las pruebas y crea `dist/xaml-preview`. Consulta `THIRD_PARTY.md` antes
de distribuir una compilación.
