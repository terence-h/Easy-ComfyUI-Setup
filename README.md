# Easy ComfyUI Setup (Windows)

Automated setup for [ComfyUI](https://github.com/Comfy-Org/ComfyUI) with CUDA-aware dependency installation, environment setup, and helper launch scripts for daily use. Works for both PowerShell 5.1 and PowerShell 7.

## Versions Installed
| | Version |
| --- | --- |
| Python | 3.12.13 |
| PyTorch | 2.12.0 |
| Triton | 3.7 |
| SageAttention | 2.2.0 |
| ComfyUI | based on your selection, defaults to latest |

## Requirements

| | Windows |
| --- | --- |
| OS | Windows 10/11 |
| GPU | NVIDIA with CUDA 13.0 or newer (GTX 16xx, RTX 20xx and above) |
| Tooling | `winget` (used to install Git/uv if not installed) |

[Git](https://git-scm.com/) is version control system used to manage repositories. This is used in this project to download ComfyUI and version management.
[uv](https://docs.astral.sh/uv/) is a Python package and project manager. This is used in this project for it's speed over standard Python pip.

If CUDA is not detected or the detected version is below 13.0, installation will not proceed.

## How to Use

1. Download `Setup_ComfyUI.ps1`.
2. Open **PowerShell** at the directory you want your ComfyUI to be located at.
3. Allow script execution just for this PowerShell session:
   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   ```
4. Run the setup script:
   ```powershell
   .\Setup_ComfyUI.ps1
   ```
5. Follow prompts (see [User Prompts](#common-prompts) below).
6. After setup completes, go to the created ComfyUI (or whatever you have named) folder and start:
   ```powershell
   .\start.bat
   ```

## User Prompts

- Enter [ComfyUI version tag](https://github.com/Comfy-Org/ComfyUI/tags) (or leave blank for latest).
- Select default attention backend (PyTorch attention or SageAttention).
- Optionally disable dynamic VRAM (Y/N, default N).
- Optionally set custom output/input directories (absolute paths, leave
  blank to keep defaults).
- Optionally set an extra model search path (recommended for multiple
  ComfyUI installations).

## Optional Shared Model Search Path

If you provide a shared model directory (for example `C:\ComfyUI_Models`), the setup script will:

1. Create the root folder if it does not exist.
2. Create all required model subfolders referenced by ComfyUI's extra-model-path config.
3. Generate `extra_model_paths.yaml` in the cloned ComfyUI root with your path as `base_path`.

Leave the prompt blank to skip this step.

NOTE: This does not work for custom node packs. For example, `ComfyUI-JoyCaption`'s downloaded models are downloaded into the default ComfyUI models folder.

## Generated Scripts

| Script | Purpose |
| --- | --- |
| `start.bat` | Activates `.venv` and launches ComfyUI with `--enable-manager`, the selected attention argument, and any optional launch arguments chosen during setup (`--disable-dynamic-vram`, `--output-directory`, `--input-directory`). |
| `update_latest.bat` | Pulls latest from `origin master`, then reinstalls requirements. |
| `update_stable.bat` | Checks out latest `v*` tag from ComfyUI repository, then reinstalls requirements. |
| `switch_comfyui_version.bat` | Prompts for a version tag and switches ComfyUI to that version, then reinstalls requirements. |
| `reinstall_torchcuda_triton_sageattn.bat` | Re-detects CUDA and force-reinstalls Torch / Triton / SageAttention. |