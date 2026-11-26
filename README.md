# plutonium-on-mac

Run [Plutonium](https://plutonium.pw) (Call of Duty: Black Ops, Black Ops II, World at War, and Modern Warfare 3) on Apple Silicon Macs using free and open-source software—no CrossOver license required.

## Architecture & Performance

This setup packages a patched Wine engine (built from CrossOver 26.3 source), [Sikarugir](https://github.com/Sikarugir-App/Sikarugir)'s wrapper template, DXVK on MoltenVK 1.4.2 (BO1, WaW, MW3), and [DXMT](https://github.com/3Shain/dxmt) v0.80 over Metal (BO2) into an isolated prefix inside the repo folder.

### x87 Acceleration (`x87sidecar`)

CoD's older engines do physics and effects in x87 floating-point math, which Rosetta 2 translates slowly. `launch.sh` enables `WINE_X87_SIDECAR=plutonium-bootstrapper-win32.exe` by default, and 32-bit Windows binaries are built with SSE math.

Back-to-back session benchmarks (M1 Pro):

| Workload | Without x87 sidecar | With x87 sidecar |
|---|---:|---:|
| BO2 Zombies (lowest second) | 37 FPS | **100 FPS** |
| BO1 Multiplayer (average) | 80 FPS | **112 FPS** |
| BO1 Campaign (average) | 72 FPS | **104 FPS** |
| BO1 Campaign (seconds < 60 FPS) | 134 | **2** |

### Built-in Runtime Optimizations

- **BO1 config tweaks (`TWEAKS=1` default):** `lib/games.sh` automatically disables `r_blur_allowed`, `r_distortion`, `sm_enable` (shadows), and the stock `com_maxfps` cap in `storage/t5/players/*.cfg`.
- **BO2 8x MSAA crash prevention:** Apple GPUs support at most 4x MSAA (8x crashes with `E_INVALIDARG`). `launch.sh` seeds `storage/t6/players/hardware_mp.chp` / `hardware_zm.chp` and clamps `r_aaSamples` above `4` down to `4`.
- **Frame pacing (`MAXFPS=<n>`):** Caps BO1 via `com_maxfps` and BO2 via `DXMT_CONFIG="d3d11.preferredMaxFrameRate=$MAXFPS;"`. On 120 Hz ProMotion displays, `MAXFPS=60` keeps each frame at an even 2 refreshes.
- **High-polling-rate mice:** `WINE_MOUSE_COALESCING` is off by default (`MOUSE_COALESCING=0`) so 500–1000 Hz mouse reports are not batched per display refresh.
- **Microsoft XAudio2 2.7:** When BO1 is present (`BO1_DIR` or Steam), `setup.sh` extracts `XAudio2_7.dll` from BO1's DirectX redistributables for proper xWMA audio decoding.

---

## Real-World Setup & Fixes Applied

This repo includes practical fixes discovered while setting up and running BO2 (Plutonium r5369) on Apple Silicon (tested on Apple M4):

1. **Fixed `plutonium.exe` (`Plutonium.Updater.App`) WPF crash on MoltenVK 1.4.2:**
   - `plutonium.exe` crashed before opening its window with `System.Windows.Markup.XamlParseException` in `CreateWindowEx` right after initializing MoltenVK.
   - `setup.sh` now sets `HKCU\Software\Wine\AppDefaults\plutonium.exe\Direct3D` (`renderer = gl`) alongside `plutonium-launcher-win32.exe`.
2. **Fixed hang at `Loading fastfile code_pre_gfx_zm`:**
   - Under `ntdll.so.fixed`, Plutonium r5369 hung at `Loading fastfile code_pre_gfx_zm`.
   - Launching with `NTDLL=legacy ./launch.sh` switches to `ntdll.so.legacy` and initializes D3D11/DXMT cleanly (`D3D_FEATURE_LEVEL_11_0`).
3. **Non-Steam / Downloads game folder support (`BO2_DIR`):**
   - Verified with a standalone BO2 folder (`~/Downloads/Black Ops 2`) using `BO2_DIR="$HOME/Downloads/Black Ops 2" ./setup.sh`, which maps it to `Z:\Users\<user>\Downloads\Black Ops 2` for the Plutonium launcher.
4. **Working macOS Desktop launcher (`Plutonium.command`):**
   - A `.app` bundle with a shell script `CFBundleExecutable` silently fails under modern macOS LaunchServices.
   - Using a double-clickable `.command` script opens Terminal directly and runs `NTDLL=legacy ./launch.sh`.
5. **Moving the project folder (`winetemp-*` symlink cache):**
   - Moving the repo directory after setup leaves a stale `ntdll.so` symlink inside `/private/var/folders/.../T/winetemp-*`, causing `wine: could not load ntdll.so`.
   - Clearing `winetemp-*` from `$TMPDIR` resolves it immediately.

---

## Requirements

- Apple Silicon Mac (M1 or later) with Rosetta 2:
  ```bash
  softwareupdate --install-rosetta
  ```
- Your own copy of the supported games
- A [Plutonium](https://plutonium.pw) account

## Quick Start

```bash
git clone https://github.com/dentedlmfao/plutonium-on-mac.git
cd plutonium-on-mac
```

Run setup (pass `BO1_DIR` / `BO2_DIR` if your games are not in Steam's default library):

```bash
BO2_DIR="$HOME/Downloads/Black Ops 2" ./setup.sh
```

1. `setup.sh` downloads the Wine engine, Sikarugir template, DXMT, and Plutonium's installer (verified with SHA-256 in `manifest.txt` and Authenticode signature checks).
2. When Plutonium's installer opens, **sign in with your Plutonium account, then close it**.
3. On first launch in the Plutonium launcher, paste the `Z:\...` game path printed by `setup.sh`.

## Launching

Start Plutonium from Terminal with `NTDLL=legacy`:

```bash
NTDLL=legacy ./launch.sh
```

### Desktop Double-Click Launcher

```bash
cat <<'EOF' > ~/Desktop/Plutonium.command
#!/bin/bash
cd "$HOME/Desktop/plutonium-on-mac" || exit 1
NTDLL=legacy ./launch.sh
EOF
chmod +x ~/Desktop/Plutonium.command
```

## Options & Commands

| Option | Effect |
|---|---|
| `NTDLL=legacy` | Use legacy breakpoint emulation (fixes `Loading fastfile` hangs) |
| `HUD=1` | Enable Apple's Metal performance HUD (FPS + frame times) |
| `MAXFPS=<n>` | Cap frame rate (e.g. `MAXFPS=60` or `MAXFPS=120`) |
| `WINDOWED=1` / `FULLSCREEN=1` | Override display mode |
| `TWEAKS=0` | Keep BO1's blur, distortion, and stock frame cap |
| `X87=0` | Disable `x87sidecar` acceleration |
| `MOUSE_COALESCING=1` | Enable macOS mouse move coalescing |
| `XAUDIO=builtin` | Use Wine's built-in XAudio2 instead of Microsoft's |
| `PLUTONIUM_START=launcher` | Skip Plutonium's updater |
| `VERBOSE=1` | Enable detailed Wine debug logging |

| Command | Action |
|---|---|
| `./launch.sh kill` | Stop all running processes in the prefix |
| `./launch.sh update` | Run Plutonium's updater |
| `./launch.sh log` | Open `logs/last-run.log` |
| `./launch.sh selftest` | Run Wine, DXVK, DXMT, and `x87sidecar` self-tests |
| `./setup.sh uninstall` | Remove `runner/`, `prefix/`, `downloads/`, and `logs/` |

## Self-Test Verification

`./launch.sh selftest` verified on Apple Silicon (`arm64` + Rosetta 2):
- `ntdll fixed`: **35 passed** (including `x87-sidecar-test`, `d3d11-dxmt-test`, all `d3d9-*` DXVK tests, `recv-test`, `lazy-exec-test`, and all `breakpoint-test` checks), 1 timing-sensitive failure (`pulse-test`), 1 skipped (`xinput-test`, no controller connected).
- `ntdll legacy`: **1 passed**.

## License

This project is licensed under the [GPL-3.0 License](LICENSE).
