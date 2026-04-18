# Easy ComfyUI Setup (Windows & Linux)

Automated setup for [ComfyUI](https://github.com/Comfy-Org/ComfyUI) with
CUDA-aware dependency installation, environment setup, and helper launch
scripts for daily use.

| Platform | Setup script | Generated launchers |
| --- | --- | --- |
| Windows | `Setup_ComfyUI.ps1` | `.bat` files |
| Linux   | `Setup_ComfyUI.sh`  | `.sh` files (compatible with bash and fish callers) |

Both scripts share the same prompts, banner version (`v1.0.4`), and feature
set. The Linux script can be invoked from either bash or fish — the kernel
runs it under bash via the shebang regardless of the calling shell.

## Features

- Detects CUDA version from `nvidia-smi` automatically:
  - **12.6**
  - **12.8**
  - **13.x**
- Installs missing prerequisites with prompts:
  - **Windows**: Git and uv via `winget`
  - **Linux**: uv via the official installer (`curl -LsSf https://astral.sh/uv/install.sh | sh`); Git is detected and the appropriate `apt` / `dnf` / `pacman` / `zypper` install command is shown for the user to run
- Clones ComfyUI:
  - Latest version (default)
  - Or a specific tag (for example `0.0.2` or `v0.18.3`)
- Creates a Python **3.12** virtual environment with `uv venv`.
- Installs pinned GPU packages:
  - `torch==2.10.0`
  - `torchvision==0.25.0`
  - `torchaudio==2.10.0`
- Installs `requirements.txt` and `manager_requirements.txt`.
- Installs Triton:
  - **Windows**: `triton-windows<3.7`
  - **Linux**: upstream `triton`
- Installs attention backends based on CUDA support:
  - SageAttention 2 (CUDA 12.8 / 13.x)
  - FlashAttention 2 (CUDA 13.x)

  On Windows the script downloads pre-built wheels. On Linux they are pulled
  from PyPI (`sageattention` and `flash-attn`); FlashAttention may compile
  from source on first install.
- Optional launch argument setup:
  - Disable dynamic VRAM (`--disable-dynamic-vram`)
  - Custom output directory (`--output-directory "..."`)
  - Custom input directory (`--input-directory "..."`)
- Optional shared model path setup:
  - Prompts for an extra model search path (leave blank to skip)
  - Creates `extra_model_paths.yaml` in the cloned ComfyUI root
  - Creates the required model subfolders under that shared directory
  - Recommended for multiple ComfyUI installs to avoid duplicate model files

## CUDA Compatibility

| CUDA version | Torch index URL | SageAttention 2 | FlashAttention 2 |
| --- | --- | --- | --- |
| 12.6 | `https://download.pytorch.org/whl/cu126` | No | No |
| 12.8 | `https://download.pytorch.org/whl/cu128` | Yes | No |
| 13.x | `https://download.pytorch.org/whl/cu130` | Yes | Yes |

If CUDA is not detected or not supported, installation will not proceed.

## Requirements

| | Windows | Linux |
| --- | --- | --- |
| OS | Windows 10/11 | Any modern distro (Debian/Ubuntu, RHEL/Fedora, Arch, openSUSE, ...) |
| GPU | NVIDIA with CUDA 12.6, 12.8, or 13.x | Same |
| Tooling | `winget` (used to install Git/uv if needed) | A supported package manager (`apt`, `dnf`, `pacman`, or `zypper`) for Git; `curl` available for the uv installer |
| Network | Internet connection | Internet connection |

## How to Use

### Windows

1. Clone this repository (or download `Setup_ComfyUI.ps1` only).
2. Open **PowerShell** in the repository folder.
3. If needed, allow script execution just for this PowerShell session:
   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   ```
4. Run the setup script:
   ```powershell
   .\Setup_ComfyUI.ps1
   ```
5. Follow prompts (see [Common Prompts](#common-prompts) below).
6. After setup completes, go to the generated ComfyUI folder and start:
   ```powershell
   .\start.bat
   ```

### Linux

1. Clone this repository (or download `Setup_ComfyUI.sh` only).
2. Make the script executable:
   ```bash
   chmod +x Setup_ComfyUI.sh
   ```
3. Run it from **bash** or **fish**:
   ```bash
   ./Setup_ComfyUI.sh
   ```
   Both shells work the same way — the script always executes under bash via
   the shebang.
4. If Git is missing, the script prints the exact `sudo` command for your
   distribution. Run it, then re-run `./Setup_ComfyUI.sh`.
5. Follow prompts (see [Common Prompts](#common-prompts) below).
6. After setup completes, go to the generated ComfyUI folder and start:
   ```bash
   ./start.sh
   ```

### Common Prompts

- Install missing prerequisites (if needed).
- Choose ComfyUI version tag (or leave blank for latest).
- Select default attention backend (if available).
- Optionally disable dynamic VRAM (Y/N, default N).
- Optionally set custom output/input directories (absolute paths, leave
  blank to keep defaults).
- Optionally set an extra model search path (recommended for multiple
  ComfyUI installations).

## Optional Shared Model Search Path

If you provide a shared model directory (for example `C:\ComfyUI_Models` on
Windows or `/opt/ComfyUI_Models` on Linux), the setup script will:

1. Create the root folder if it does not exist.
2. Create all required model subfolders referenced by ComfyUI's
   extra-model-path config.
3. Generate `extra_model_paths.yaml` in the cloned ComfyUI root with your
   path as `base_path`.

Leave the prompt blank to skip this step.

## Generated Scripts

| Windows | Linux | Purpose |
| --- | --- | --- |
| `start.bat` | `start.sh` | Activates `.venv` and launches ComfyUI with `--enable-manager`, the selected attention argument, and any optional launch arguments chosen during setup (`--disable-dynamic-vram`, `--output-directory`, `--input-directory`). |
| `update_latest.bat` | `update_latest.sh` | Pulls latest from `origin master`, then reinstalls requirements. |
| `update_stable.bat` | `update_stable.sh` | Checks out latest `v*` tag, then reinstalls requirements. |
| `switch_comfyui_version.bat` | `switch_comfyui_version.sh` | Prompts for a version tag and switches ComfyUI to that tag, then reinstalls requirements. |
| `reinstall_torchcuda_triton_sageattn_flashattn.bat` | `reinstall_torchcuda_triton_sageattn_flashattn.sh` | Re-detects CUDA and force-reinstalls Torch / Triton / attention packages. |
