# LowBar para Windows 11 (fork comunitario)

Esta versión aplica el estilo de la barra de tareas XAML de Windows 11. El modo **Transparente** se probó en Windows 11 26H2 con dos pantallas. Admite Normal, Opaco, Transparente, Desenfoque y Acrílico. No utiliza un temporizador de repintado; Desenfoque y Acrílico usan efectos del compositor y pueden consumir más GPU.

## Instalación con un comando

Abre PowerShell en Windows 11 x64 (build 22621 o posterior) y ejecuta:

```powershell
irm https://raw.githubusercontent.com/DARKAR14/LowBar/main/install.ps1 | iex
```

El comando descarga la última release publicada de este fork, instala LowBar para el usuario actual y lo inicia. No requiere Go ni LLVM. Las versiones que incluyen el actualizador comprueban nuevas releases diariamente, avisan, verifican el paquete y reinician LowBar tras instalarlo. La v0.1.5 anterior no puede actualizarse sola: quienes la tengan deben repetir este comando una vez después de publicarse la primera release con el actualizador. Los cambios de código sin una release publicada no se instalan.

Para activar el inicio con Windows, usa «Abrir al iniciar» en el menú del icono. Para volver al aspecto de Windows, elige «Normal» o «Salir».

El componente XAML procede de [TranslucentTB 2026.4](https://github.com/TranslucentTB/TranslucentTB/tree/2026.4), bajo GPL-3.0. Este es un fork comunitario y no una release oficial de LowBar. Consulta [licencias y fuente del componente](THIRD_PARTY.md), [validación y límites](docs/WINDOWS11-PREVIEW.md) y el [README original](docs/UPSTREAM-README.md).

## Desarrollo

Con Go 1.23+ en Windows, `scripts/build-xaml-preview.ps1 -Version 0.1.8-win11` comprueba el SHA256 del componente descargado, ejecuta pruebas y crea `dist/LowBar.zip`. La release se publica mediante `.github/workflows/release-xaml.yml` al subir una etiqueta `v*-win11` al fork. La versión del ejecutable se toma de esa etiqueta.
