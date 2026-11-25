# LowBar: prueba XAML para Windows 11

Validado visualmente por el usuario en Windows 11 26H2, build 26300.9550,
con dos pantallas y estilo Transparente, el 16 de octubre de 2026.
Tras Windows 11 build 26300.10075, ExplorerTAP 2026.2 dejó de aplicar
los estilos aunque la llamada COM devolvía éxito. La prueba local con
ExplorerTAP 2026.4 volvió a mostrar la barra transparente el 25 de noviembre
de 2026. La versión 2026.4 incluye la corrección de detección del árbol XAML.

## Uso

Ejecuta `LowBar.exe` de la carpeta `preview`, manteniendo `ExplorerTAP.dll`
y `Assets` al lado. El menú del icono junto al reloj permite cambiar el
estilo, restaurar Normal, actualizar la barra y salir. Si quieres que esta
versión se abra al iniciar sesión, activa «Abrir al iniciar» desde ese menú.
No muevas la carpeta después de activar esa opción.

La configuración queda en `data/settings.ini`, junto al ejecutable. Los
registros están en `%TEMP%\LowBar\lowbar.log`. A partir de v0.1.6, la
comprobación automática consulta las releases publicadas de este fork una vez
al día. Muestra un aviso, instala la versión nueva y reinicia LowBar para
volver a aplicar el estilo. El menú permite comprobar manualmente o desactivar
las actualizaciones. Los cambios de código sin una release no se instalan.

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
- La compilación `xamlpreview` excluye el actualizador oficial desactivado y
  sus dependencias de red/ZIP del proceso residente; usa un proceso temporal
  para comprobar releases. En una comparación local, la memoria privada
  bajó de 46,2 MB (v0.1.4) a 13,8–13,9 MB (v0.1.5); la memoria residente puede
  variar con el tiempo y según Windows.
- El 25 de noviembre de 2026, la copia local v0.1.7-preview usó aproximadamente
  18 MB de memoria residente y 15 MB de memoria privada en reposo. El
  comprobador de releases se ejecuta aparte y termina al finalizar; un único
  temporizador comprueba como máximo una vez al día. No hay un límite absoluto
  garantizado de memoria ante fallos del proceso o del sistema.
- El mutex de instancia única usa el error devuelto directamente por Win32;
  abrir LowBar otra vez no deja un segundo proceso residente.
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
Al preparar la próxima release, pasa `-Version 0.1.8-win11` (o un número mayor)
para que la versión del ejecutable coincida con el tag `v0.1.8-win11`; una
release solo se detecta si su número es mayor que el instalado.
