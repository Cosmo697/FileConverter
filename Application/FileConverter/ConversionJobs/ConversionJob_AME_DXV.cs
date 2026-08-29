// <copyright file="ConversionJob_AME_DXV.cs" company="AAllard">License: http://www.gnu.org/licenses/gpl.html GPL version 3.</copyright>

namespace FileConverter.ConversionJobs
{
    using System;
    using System.Diagnostics;
    using System.IO;
    using System.Linq;
    using System.Threading;

    /// <summary>
    /// Encode Resolume DXV3 via Adobe Media Encoder watch folders (Resolume DXV plugin).
    /// Requires a one-time AME watch-folder setup (see Middleware/ame-watch/README.txt).
    /// </summary>
    public class ConversionJob_AME_DXV : ConversionJob
    {
        private static readonly object AmeGate = new object();

        public ConversionJob_AME_DXV()
            : base()
        {
        }

        public ConversionJob_AME_DXV(ConversionPreset conversionPreset, string inputFilePath)
            : base(conversionPreset, inputFilePath)
        {
        }

        protected override void Convert()
        {
            // Serialize AME watch-folder jobs; concurrent drops into the same folder are racey.
            lock (AmeGate)
            {
                this.ConvertLocked();
            }
        }

        private void ConvertLocked()
        {
            bool ameStartedByUs = false;
            try
            {
                this.ConvertLockedCore(out ameStartedByUs);
            }
            finally
            {
                // Only quit AME when this job launched it — leave a user-opened session alone.
                if (ameStartedByUs)
                {
                    this.UserState = "Closing Adobe Media Encoder";
                    StopAmeProcesses();
                }
            }
        }

        private void ConvertLockedCore(out bool ameStartedByUs)
        {
            ameStartedByUs = false;
            this.UserState = "Preparing DXV3 (Adobe Media Encoder)";
            this.Progress = 0.05f;

            string quality = this.ConversionPreset.GetSettingsValue<string>(ConversionPreset.ConversionSettingKeys.DxvQuality) ?? "NoAlpha";
            bool withAlpha = string.Equals(quality, "WithAlpha", StringComparison.OrdinalIgnoreCase);
            string watchKey = withAlpha ? "dxv-normal-withalpha" : "dxv-normal-noalpha";

            string watchRoot = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "FileConverter",
                "ame-watch");
            string inputDir = Path.Combine(watchRoot, watchKey, "input");
            string outputDir = Path.Combine(watchRoot, watchKey, "output");
            Directory.CreateDirectory(inputDir);
            Directory.CreateDirectory(outputDir);

            string pluginPath = @"C:\Program Files\Adobe\Common\Plug-ins\7.0\MediaCore\Resolume DXV\DXV3MediaCoreExport.prm";
            if (!File.Exists(pluginPath))
            {
                this.ConversionFailed(
                    "Resolume DXV3 Adobe plugin not found. Install Resolume Alley/Arena (DXV exporters), then reopen Adobe Media Encoder.");
                return;
            }

            string ameExe = FindAmeExecutable();
            if (string.IsNullOrEmpty(ameExe))
            {
                this.ConversionFailed(
                    "Adobe Media Encoder not found. Install AME (this machine uses D:\\Adobe\\Adobe Media Encoder 2026\\), create DXV3 watch folders, then retry.");
                return;
            }

            ameStartedByUs = EnsureAmeRunning(ameExe);
            if (ameStartedByUs)
            {
                Diagnostics.Debug.Log("Adobe Media Encoder was started by File Converter for this DXV job.");
            }

            string leaf = Path.GetFileName(this.InputFilePath);
            string staged = Path.Combine(inputDir, leaf);
            if (File.Exists(staged))
            {
                string baseName = Path.GetFileNameWithoutExtension(leaf);
                string ext = Path.GetExtension(leaf);
                int n = 1;
                do
                {
                    staged = Path.Combine(inputDir, $"{baseName}_{n:000}{ext}");
                    n++;
                }
                while (File.Exists(staged));
            }

            File.Copy(this.InputFilePath, staged, false);
            Diagnostics.Debug.Log($"AME watch staged: {staged}");
            this.UserState = "Waiting for Adobe Media Encoder (DXV3)";
            this.Progress = 0.15f;

            string baseLeaf = Path.GetFileNameWithoutExtension(leaf);
            DateTime deadline = DateTime.UtcNow.AddMinutes(45);
            string produced = null;

            while (DateTime.UtcNow < deadline)
            {
                if (this.CancelIsRequested)
                {
                    this.ConversionFailed("Cancelled.");
                    return;
                }

                FileInfo candidate = new DirectoryInfo(outputDir)
                    .EnumerateFiles("*", SearchOption.TopDirectoryOnly)
                    .Where(f =>
                        (f.Extension.Equals(".mov", StringComparison.OrdinalIgnoreCase)
                         || f.Extension.Equals(".dxv3", StringComparison.OrdinalIgnoreCase))
                        && f.Name.StartsWith(baseLeaf, StringComparison.OrdinalIgnoreCase)
                        && f.Length > 0)
                    .OrderByDescending(f => f.LastWriteTimeUtc)
                    .FirstOrDefault();

                if (candidate != null)
                {
                    long len1 = candidate.Length;
                    Thread.Sleep(2000);
                    candidate.Refresh();
                    long len2 = candidate.Length;
                    if (len1 == len2 && len2 > 0)
                    {
                        produced = candidate.FullName;
                        break;
                    }
                }

                this.Progress = Math.Min(0.9f, this.Progress + 0.01f);
                Thread.Sleep(3000);
            }

            if (string.IsNullOrEmpty(produced))
            {
                this.ConversionFailed(
                    "Timed out waiting for AME DXV3 output. Create AME watch folders for:\n" +
                    $"  input:  {inputDir}\n" +
                    $"  output: {outputDir}\n" +
                    "Format=DXV3, Normal Quality " + (withAlpha ? "With Alpha" : "No Alpha") +
                    ". See Middleware\\ame-watch\\README.txt.");
                return;
            }

            this.UserState = "Copying DXV3 result";
            this.Progress = 0.95f;
            File.Copy(produced, this.OutputFilePath, true);
            this.Progress = 1f;
            Diagnostics.Debug.Log($"DXV3 output: {this.OutputFilePath}");
        }

        private static string FindAmeExecutable()
        {
            // Prefer a live process path when AME is already open (Adobe often lives under D:\Adobe on this machine).
            try
            {
                Process process = Process.GetProcessesByName("Adobe Media Encoder").FirstOrDefault();
                if (process != null)
                {
                    try
                    {
                        string path = process.MainModule?.FileName;
                        if (!string.IsNullOrEmpty(path) && File.Exists(path))
                        {
                            return path;
                        }
                    }
                    catch (Exception exception)
                    {
                        Diagnostics.Debug.Log($"Could not read AME process path: {exception.Message}");
                    }
                }
            }
            catch (Exception exception)
            {
                Diagnostics.Debug.Log($"AME process lookup failed: {exception.Message}");
            }

            string[] guesses =
            {
                @"D:\Adobe\Adobe Media Encoder 2026\Adobe Media Encoder.exe",
                @"D:\Adobe\Adobe Media Encoder 2025\Adobe Media Encoder.exe",
                @"C:\Program Files\Adobe\Adobe Media Encoder 2026\Adobe Media Encoder.exe",
                @"C:\Program Files\Adobe\Adobe Media Encoder 2025\Adobe Media Encoder.exe",
            };

            foreach (string guess in guesses)
            {
                if (File.Exists(guess))
                {
                    return guess;
                }
            }

            return null;
        }

        /// <returns>True if this call launched AME (caller should quit it when the job ends).</returns>
        private static bool EnsureAmeRunning(string ameExe)
        {
            if (GetAmeProcesses().Length > 0)
            {
                return false;
            }

            Diagnostics.Debug.Log($"Starting Adobe Media Encoder: {ameExe}");
            Process.Start(new ProcessStartInfo(ameExe)
            {
                UseShellExecute = true,
            });

            DateTime readyDeadline = DateTime.UtcNow.AddSeconds(90);
            while (DateTime.UtcNow < readyDeadline)
            {
                if (GetAmeProcesses().Length > 0)
                {
                    // Give watch folders a moment to bind after the process appears.
                    Thread.Sleep(8000);
                    return true;
                }

                Thread.Sleep(500);
            }

            Diagnostics.Debug.Log("Adobe Media Encoder start timed out waiting for process.");
            return true; // still attempt quit later in case a late process appears
        }

        private static Process[] GetAmeProcesses()
        {
            try
            {
                return Process.GetProcessesByName("Adobe Media Encoder")
                    .Where(p =>
                    {
                        try
                        {
                            return !p.HasExited;
                        }
                        catch
                        {
                            return false;
                        }
                    })
                    .ToArray();
            }
            catch (Exception exception)
            {
                Diagnostics.Debug.Log($"AME process list failed: {exception.Message}");
                return Array.Empty<Process>();
            }
        }

        private static void StopAmeProcesses()
        {
            Process[] processes = GetAmeProcesses();
            if (processes.Length == 0)
            {
                return;
            }

            Diagnostics.Debug.Log($"Closing Adobe Media Encoder ({processes.Length} process(es)).");
            foreach (Process process in processes)
            {
                try
                {
                    if (process.HasExited)
                    {
                        continue;
                    }

                    // Prefer a graceful close so AME can flush watch-folder state.
                    process.CloseMainWindow();
                    if (!process.WaitForExit(20000))
                    {
                        Diagnostics.Debug.Log($"AME PID {process.Id} ignored CloseMainWindow; killing.");
                        process.Kill();
                        process.WaitForExit(5000);
                    }
                }
                catch (Exception exception)
                {
                    Diagnostics.Debug.Log($"Failed to close AME PID {process.Id}: {exception.Message}");
                    try
                    {
                        if (!process.HasExited)
                        {
                            process.Kill();
                        }
                    }
                    catch
                    {
                        // ignored
                    }
                }
                finally
                {
                    try
                    {
                        process.Dispose();
                    }
                    catch
                    {
                        // ignored
                    }
                }
            }
        }
    }
}
