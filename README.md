# Resolution Toggle

Install a desktop shortcut that toggles the primary display between two resolutions.

## Install

Download and run the self-extracting installer from the latest GitHub release.

When installing from the source files, double-click `Install.cmd`.

The installer:

- launches `Install-ResolutionToggle.ps1`
- detects the primary display and lists available modes
- prompts for the secondary/stretch resolution
- shows `1920x1440` as a suggestion only, not a detected mode
- prompts for the default/native resolution
- guesses the default/native resolution from the detected primary-display modes
- installs files under `%LOCALAPPDATA%\ResolutionToggle`
- creates a desktop shortcut named `Toggle Resolution`
- uses the included `ToggleResolution.ico` for the shortcut

The shortcut toggles the primary display between the two configured resolutions.

## Refresh Rate

The toggle script selects the highest available refresh rate automatically at click time for the target resolution.

## Custom Resolutions

Custom/stretch resolutions must already be exposed by Windows and your GPU settings before installing. If a resolution is not listed during install, create it first in NVIDIA, AMD, Intel, or Windows display settings, then rerun `Install.cmd`.

## Reconfigure

Rerun `Install.cmd` anytime to choose different stretch/default resolutions.

## Uninstall

Double-click `Uninstall.cmd`.

The uninstaller removes the installed files and both the current and legacy desktop shortcut names.

## Notes

- No admin rights are required.
- The shortcut toggles only the primary display.
- If virtual super-resolution features expose modes above the panel's true native resolution, the default/native guess may be higher than native. Type the real native resolution manually when prompted.
