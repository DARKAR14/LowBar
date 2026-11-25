# LowBar para Windows 11 (fork comunitario)

Esta versión aplica el estilo de la barra de tareas XAML de Windows 11. El modo **Transparente** se probó en Windows 11 26H2 con dos pantallas. Admite Normal, Opaco, Transparente, Desenfoque y Acrílico. No utiliza un temporizador de repintado; Desenfoque y Acrílico usan efectos del compositor y pueden consumir más GPU.

## Instalación con un comando

Abre PowerShell en Windows 11 x64 (build 22621 o posterior) y ejecuta:

```powershell
irm https://raw.githubusercontent.com/DARKAR14/LowBar/main/install.ps1 | iex
```

El comando descarga la última release publicada de este fork, instala LowBar para el usuario actual y lo inicia. No requiere Go ni LLVM. El actualizador está preparado en el código local, pero la release pública v0.1.5 aún no lo incluye. Cuando se publique la primera release con esta función, quienes tengan v0.1.5 deberán repetir el comando una vez; a partir de entonces, LowBar comprobará nuevas releases diariamente, avisará y reiniciará la barra tras instalarlas.

Para activar el inicio con Windows, usa «Abrir al iniciar» en el menú del icono. Para volver al aspecto de Windows, elige «Normal» o «Salir».

El componente XAML procede de [TranslucentTB 2026.2](https://github.com/TranslucentTB/TranslucentTB/tree/2026.2), bajo GPL-3.0. Este es un fork comunitario y no una release oficial de LowBar. Consulta [licencias y fuente del componente](THIRD_PARTY.md), [validación y límites](docs/WINDOWS11-PREVIEW.md) y el [README original](docs/UPSTREAM-README.md).

## Desarrollo

Con Go 1.23+ en Windows, `scripts/build-xaml-preview.ps1` comprueba el SHA256 del componente descargado, ejecuta pruebas y crea `dist/LowBar.zip`. La release se publica mediante `.github/workflows/release-xaml.yml` al subir una etiqueta `v*-xaml` al fork.
