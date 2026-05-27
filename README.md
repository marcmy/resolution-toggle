# Resolution Toggle

Resolution Toggle installs a desktop icon that switches your primary display between your normal resolution and a custom/stretch resolution.

## Install

1. Download `resolution-toggle-v1.0.0.exe` from the latest GitHub release.
2. Double-click it.
3. After install, use the `Toggle Resolution` icon on your desktop.

The installer does not ask for your resolutions. The first time you launch `Toggle Resolution`, it asks for:

- your normal/native resolution
- your custom/stretch resolution
- whether the custom resolution should stretch fullscreen or use black bars/centered mode

After you save, launch `Toggle Resolution` again to switch to the custom resolution. Launch it again to switch back.

Resolution Toggle always picks the highest refresh rate Windows exposes for the resolution it is switching to.

## Custom Resolutions

Your custom/stretch resolution must already exist in Windows or your GPU settings. If Windows does not expose that resolution, Resolution Toggle cannot switch to it.

## Change Settings

Open Start > Resolution Toggle > Change Settings.

## Uninstall

Use either:

- Windows Settings > Apps > Installed apps > Resolution Toggle > Uninstall
- Start > Resolution Toggle > Uninstall Resolution Toggle

Uninstall removes the desktop icon, Start menu folder, Windows uninstall entry, saved settings, and installed files.

## Notes

- No admin rights are required.
- The desktop icon toggles the primary display.
- Fullscreen stretch / black bars is requested through Windows when switching modes. If your GPU driver ignores that request, Resolution Toggle shows where to set it manually in NVIDIA or AMD settings.
