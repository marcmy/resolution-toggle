[CmdletBinding()]
param(
    [string]$Version = "1.0.0"
)

$ErrorActionPreference = "Stop"

$RepoRoot = $PSScriptRoot
$DistDir = Join-Path $RepoRoot "dist"
$OutputName = "resolution-toggle-v$Version.exe"
$OutputPath = Join-Path $DistDir $OutputName
$BuildRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ResolutionToggleBuild-" + [guid]::NewGuid().ToString("N"))
$PayloadRoot = Join-Path $BuildRoot "payload"
$PayloadZip = Join-Path $BuildRoot "payload.zip"
$StubSource = Join-Path $BuildRoot "ResolutionToggleBootstrapper.cs"
$ManifestPath = Join-Path $BuildRoot "asInvoker.manifest"
$StubExe = Join-Path $BuildRoot "ResolutionToggleBootstrapper.exe"
$Marker = "RT_PAYLOAD_V1"

$Files = @(
    "Install.cmd",
    "Install-ResolutionToggle.ps1",
    "Toggle-Resolution.ps1",
    "Uninstall-ResolutionToggle.ps1",
    "Uninstall.cmd",
    "ToggleResolution.ico",
    "README.md",
    "LICENSE"
)

foreach ($file in $Files) {
    $path = Join-Path $RepoRoot $file
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required file missing: $file"
    }
}

$csc = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path -LiteralPath $csc -PathType Leaf)) {
    $csc = Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe"
}
if (-not (Test-Path -LiteralPath $csc -PathType Leaf)) {
    throw "Could not find the .NET Framework C# compiler."
}

$compressionAssembly = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\System.IO.Compression.FileSystem.dll"
if (-not (Test-Path -LiteralPath $compressionAssembly -PathType Leaf)) {
    $compressionAssembly = Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\System.IO.Compression.FileSystem.dll"
}
if (-not (Test-Path -LiteralPath $compressionAssembly -PathType Leaf)) {
    throw "Could not find System.IO.Compression.FileSystem.dll."
}

$stubSourceText = @"
using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Text;
using System.Windows.Forms;

internal static class ResolutionToggleBootstrapper
{
    private const string MarkerText = "$Marker";

    [STAThread]
    private static int Main()
    {
        string tempDir = null;

        try
        {
            string exePath = Process.GetCurrentProcess().MainModule.FileName;
            byte[] marker = Encoding.ASCII.GetBytes(MarkerText);
            byte[] markerBuffer = new byte[marker.Length];
            byte[] lengthBuffer = new byte[8];

            using (FileStream exe = File.OpenRead(exePath))
            {
                if (exe.Length < marker.Length + lengthBuffer.Length)
                {
                    throw new InvalidDataException("Installer payload is missing.");
                }

                exe.Seek(-marker.Length, SeekOrigin.End);
                ReadExactly(exe, markerBuffer, 0, markerBuffer.Length);
                for (int i = 0; i < marker.Length; i++)
                {
                    if (markerBuffer[i] != marker[i])
                    {
                        throw new InvalidDataException("Installer payload marker is missing.");
                    }
                }

                exe.Seek(-(marker.Length + lengthBuffer.Length), SeekOrigin.End);
                ReadExactly(exe, lengthBuffer, 0, lengthBuffer.Length);
                long payloadLength = BitConverter.ToInt64(lengthBuffer, 0);
                long payloadOffset = exe.Length - marker.Length - lengthBuffer.Length - payloadLength;
                if (payloadLength <= 0 || payloadOffset < 0)
                {
                    throw new InvalidDataException("Installer payload length is invalid.");
                }

                tempDir = Path.Combine(Path.GetTempPath(), "ResolutionToggleInstall-" + Guid.NewGuid().ToString("N"));
                Directory.CreateDirectory(tempDir);

                string zipPath = Path.Combine(tempDir, "payload.zip");
                exe.Seek(payloadOffset, SeekOrigin.Begin);
                using (FileStream zip = File.Create(zipPath))
                {
                    CopyBytes(exe, zip, payloadLength);
                }

                ZipFile.ExtractToDirectory(zipPath, tempDir);
                File.Delete(zipPath);
            }

            string installCmd = Path.Combine(tempDir, "Install.cmd");
            if (!File.Exists(installCmd))
            {
                throw new FileNotFoundException("Install.cmd was not found in the installer payload.");
            }

            ProcessStartInfo start = new ProcessStartInfo();
            start.FileName = Path.Combine(Environment.SystemDirectory, "cmd.exe");
            start.Arguments = "/c \"\"" + installCmd + "\"\"";
            start.WorkingDirectory = tempDir;
            start.UseShellExecute = false;
            start.CreateNoWindow = true;

            using (Process process = Process.Start(start))
            {
                process.WaitForExit();
                if (process.ExitCode != 0)
                {
                    return process.ExitCode;
                }
            }

            return 0;
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "Resolution Toggle Installer", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        finally
        {
            if (!String.IsNullOrEmpty(tempDir))
            {
                try
                {
                    Directory.Delete(tempDir, true);
                }
                catch
                {
                }
            }
        }
    }

    private static void ReadExactly(Stream input, byte[] buffer, int offset, int count)
    {
        while (count > 0)
        {
            int read = input.Read(buffer, offset, count);
            if (read <= 0)
            {
                throw new EndOfStreamException();
            }

            offset += read;
            count -= read;
        }
    }

    private static void CopyBytes(Stream input, Stream output, long bytes)
    {
        byte[] buffer = new byte[81920];
        while (bytes > 0)
        {
            int toRead = (int)Math.Min(buffer.Length, bytes);
            int read = input.Read(buffer, 0, toRead);
            if (read <= 0)
            {
                throw new EndOfStreamException();
            }

            output.Write(buffer, 0, read);
            bytes -= read;
        }
    }
}
"@

$manifest = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
    <security>
      <requestedPrivileges>
        <requestedExecutionLevel level="asInvoker" uiAccess="false" />
      </requestedPrivileges>
    </security>
  </trustInfo>
</assembly>
"@

function Add-FileBytes {
    param(
        [System.IO.Stream]$Output,
        [string]$Path
    )

    $inputStream = [System.IO.File]::OpenRead($Path)
    try {
        $inputStream.CopyTo($Output)
    } finally {
        $inputStream.Dispose()
    }
}

try {
    New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
    New-Item -ItemType Directory -Force -Path $PayloadRoot | Out-Null

    foreach ($file in $Files) {
        Copy-Item -LiteralPath (Join-Path $RepoRoot $file) -Destination $PayloadRoot -Force
    }

    Compress-Archive -Path (Join-Path $PayloadRoot "*") -DestinationPath $PayloadZip -Force
    Set-Content -LiteralPath $StubSource -Value $stubSourceText -Encoding UTF8
    Set-Content -LiteralPath $ManifestPath -Value $manifest -Encoding UTF8

    & $csc /nologo /target:winexe /optimize+ /platform:anycpu /win32manifest:$ManifestPath /reference:System.Windows.Forms.dll /reference:$compressionAssembly /out:$StubExe $StubSource
    if ($LASTEXITCODE -ne 0) {
        throw "C# bootstrapper build failed with exit code $LASTEXITCODE."
    }

    $payloadBytes = [System.IO.File]::ReadAllBytes($PayloadZip)
    $lengthBytes = [BitConverter]::GetBytes([int64]$payloadBytes.Length)
    $markerBytes = [System.Text.Encoding]::ASCII.GetBytes($Marker)

    $outputStream = [System.IO.File]::Create($OutputPath)
    try {
        Add-FileBytes -Output $outputStream -Path $StubExe
        $outputStream.Write($payloadBytes, 0, $payloadBytes.Length)
        $outputStream.Write($lengthBytes, 0, $lengthBytes.Length)
        $outputStream.Write($markerBytes, 0, $markerBytes.Length)
    } finally {
        $outputStream.Dispose()
    }

    Get-Item -LiteralPath $OutputPath
} finally {
    if (Test-Path -LiteralPath $BuildRoot) {
        Remove-Item -LiteralPath $BuildRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
