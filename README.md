# Resolution Toggle

Resolution Toggle is a tiny Windows tool for gamers who bounce between a normal desktop resolution and a custom gaming resolution.

It is built for setups that use custom or stretched resolutions from NVIDIA, AMD, Intel, Windows display settings, or CRU. Instead of digging through Windows display settings before and after a game, you install it once and use one desktop icon:

- first launch: choose your normal/native resolution and your custom gaming resolution
- next launch: switch to the custom resolution
- next launch after that: switch back to native

It always uses the highest refresh rate Windows exposes for the resolution it switches to.

## Why Use It?

Some games feel better or perform better at a custom resolution, especially competitive titles where players use stretched modes or lower resolutions.

Resolution Toggle is meant for the "pure display scaling" style of setup: if Windows and your GPU driver expose the custom resolution as a real display mode, the app switches the primary display to that mode directly. That can let the desktop resolution and active display signal match, instead of only scaling inside the game.

Resolution Toggle does not create custom resolutions. Your custom gaming resolution must already exist in Windows or your GPU driver settings.

## Install

1. Download `resolution-toggle-v1.0.0.exe` from the latest GitHub release.
2. Double-click it.
3. Use the `Toggle Resolution` icon added to your desktop.

The installer extracts itself automatically. There is no unzip prompt and no folder to pick.

## First Launch

The first time you open `Toggle Resolution`, it asks for:

- your normal/native resolution
- your custom gaming resolution
- whether the custom resolution should use fullscreen stretch or black bars/centered mode

Pick the resolutions, confirm, then close the setup message. Launch `Toggle Resolution` again to switch.

## Daily Use

Double-click `Toggle Resolution` on your desktop:

- if you are on native, it switches to the custom gaming resolution
- if you are on the custom resolution, it switches back to native

Only the primary display is changed.

## Stretch Or Black Bars

Resolution Toggle asks Windows for fullscreen stretch or centered/black bars when switching.

Some GPU drivers ignore that request and only use the scaling option set in the driver control panel. If that happens, use the driver settings shown by the app:

- NVIDIA App: System > Displays > Display scaling
- NVIDIA Control Panel: Display > Adjust desktop size and position
- AMD Software: Gaming > Display > Scaling Mode

For pure display scaling, make sure the custom resolution is exposed as a real display mode before using the toggle.

## Custom Resolutions

Your custom resolution must already be available to Windows. You can create it with your GPU settings or a tool like CRU.

If you just added or edited a CRU/custom mode and Windows behaves weirdly, rebooting or restarting the display driver once can help Windows pick up the new mode. Resolution Toggle does not restart the display driver every time you toggle.

## Change Settings

Open Start > Resolution Toggle > Change Settings.

You can also rerun the installer if you want to reinstall or repair the setup.

## Uninstall

Use either:

- Windows Settings > Apps > Installed apps > Resolution Toggle > Uninstall
- Start > Resolution Toggle > Uninstall Resolution Toggle

Uninstall removes the desktop icon, Start menu folder, Windows uninstall entry, saved settings, and installed files.

## Notes

- No admin rights are required.
- Installed files live in `%LOCALAPPDATA%\ResolutionToggle`.
- The desktop icon is named `Toggle Resolution`.
- The app uses built-in Windows PowerShell, so you do not need to install PowerShell 7.
