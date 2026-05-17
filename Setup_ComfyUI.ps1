Set-Location -Path $PSScriptRoot

function Refresh-PathEnvironment {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}

function Invoke-OrExit {
    param(
        [scriptblock]$Action,
        [string]$ErrorMessage
    )

    & $Action
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[X] $ErrorMessage" -ForegroundColor Red
        exit 1
    }
}

function Read-NumberSelection {
    param(
        [string]$Prompt,
        [string[]]$ValidChoices
    )

    while ($true) {
        $selection = (Read-Host $Prompt).Trim()
        if ($ValidChoices -contains $selection) {
            return $selection
        }

        Write-Host "[!] Invalid choice. Enter one of: $($ValidChoices -join ', ')." -ForegroundColor Yellow
    }
}

function Read-YesNo {
    param(
        [string]$Prompt,
        [bool]$DefaultYes = $false
    )

    $defaultLabel = if ($DefaultYes) { "Y" } else { "N" }

    while ($true) {
        $rawInput = (Read-Host "$Prompt Enter Y or N (default $defaultLabel)").Trim()
        if ([string]::IsNullOrWhiteSpace($rawInput)) {
            return $DefaultYes
        }
        if ($rawInput.Equals("Y", [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
        if ($rawInput.Equals("N", [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }

        Write-Host "[!] Invalid choice. Enter Y or N." -ForegroundColor Yellow
    }
}

function Read-ValidWindowsFolderName {
    param(
        [string]$Prompt,
        [string]$DefaultValue = "ComfyUI"
    )

    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    $reservedNamePattern = '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$'

    while ($true) {
        $rawInput = Read-Host $Prompt
        if ([string]::IsNullOrWhiteSpace($rawInput)) {
            return $DefaultValue
        }

        $folderName = $rawInput.Trim()

        if ($folderName -eq "." -or $folderName -eq "..") {
            Write-Host "[!] Invalid folder name. '.' and '..' are not allowed." -ForegroundColor Yellow
            continue
        }

        if ($folderName.EndsWith(" ") -or $folderName.EndsWith(".")) {
            Write-Host "[!] Invalid folder name. It cannot end with a space or period." -ForegroundColor Yellow
            continue
        }

        if ($folderName.Length -gt 255) {
            Write-Host "[!] Invalid folder name. Maximum length is 255 characters." -ForegroundColor Yellow
            continue
        }

        if ($folderName.IndexOfAny($invalidChars) -ge 0) {
            Write-Host "[!] Invalid folder name. It contains characters not allowed on Windows." -ForegroundColor Yellow
            continue
        }

        if ($folderName -match $reservedNamePattern) {
            Write-Host "[!] Invalid folder name. Reserved Windows names are not allowed (e.g. CON, PRN, AUX, NUL, COM1-9, LPT1-9)." -ForegroundColor Yellow
            continue
        }

        return $folderName
    }
}

function Read-OptionalAbsoluteWindowsPath {
    param(
        [string]$Prompt
    )

    $invalidPathChars = [System.IO.Path]::GetInvalidPathChars()

    while ($true) {
        $rawInput = Read-Host $Prompt
        if ([string]::IsNullOrWhiteSpace($rawInput)) {
            return $null
        }

        $candidatePath = $rawInput.Trim()

        if ($candidatePath.IndexOfAny($invalidPathChars) -ge 0) {
            Write-Host "[!] Invalid directory path. Enter a valid absolute Windows path or leave blank to skip." -ForegroundColor Yellow
            continue
        }

        if (-not ($candidatePath -match '^[a-zA-Z]:\\' -or $candidatePath.StartsWith("\\"))) {
            Write-Host "[!] Please enter an absolute Windows path (for example C:\ComfyUI_Models)." -ForegroundColor Yellow
            continue
        }

        if ((Test-Path -Path $candidatePath) -and -not (Test-Path -Path $candidatePath -PathType Container)) {
            Write-Host "[!] '$candidatePath' exists but is not a directory." -ForegroundColor Yellow
            continue
        }

        return $candidatePath
    }
}

function Get-NormalizedVersionTag {
    param([string]$Version)

    $normalized = $Version
    if ($normalized.StartsWith("v", [System.StringComparison]::OrdinalIgnoreCase)) {
        $normalized = $normalized.Substring(1)
    }

    return "v$normalized"
}

function Install-WingetTool {
    param(
        [string]$Name,
        [string]$WingetId,
        [string]$CommandToVerify
    )

    if (Get-Command $CommandToVerify -ErrorAction SilentlyContinue) {
        Write-Host "[OK] $Name is already installed." -ForegroundColor Green
        return
    }

    Write-Host "[!] $Name was not found." -ForegroundColor Yellow
    Write-Host "1. Yes - install $Name via Winget"
    Write-Host "2. No - do not install (setup will exit)"
    $choice = Read-NumberSelection -Prompt "Install $Name now? Enter 1 or 2" -ValidChoices @("1", "2")

    if ($choice -ne "1") {
        Write-Host "[X] You chose not to install $Name. Setup will exit." -ForegroundColor Red
        exit 1
    }

    winget install --id $WingetId -e --source winget
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[X] $Name installation failed." -ForegroundColor Red
        exit 1
    }

    Refresh-PathEnvironment
    if (-not (Get-Command $CommandToVerify -ErrorAction SilentlyContinue)) {
        Write-Host "[X] $Name is still not available after installation." -ForegroundColor Red
        exit 1
    }

    Write-Host "[OK] $Name installed successfully." -ForegroundColor Green
}

function Exit-UnsupportedCuda {
    param(
        [string]$Reason
    )

    Write-Host "[X] $Reason" -ForegroundColor Red
    Read-Host "Please upgrade CUDA to 13.0 or newer and press Enter to exit"
    exit 1
}

Write-Host "=== Easy ComfyUI Setup v1.0.5 ===" -ForegroundColor Cyan
Write-Host "--- Part 1: Detecting CUDA Version ---" -ForegroundColor Cyan

if (-not (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) {
    Exit-UnsupportedCuda -Reason "nvidia-smi was not found. CUDA version could not be detected."
}

$nvidiaSmiOutput = & nvidia-smi 2>$null
if ($LASTEXITCODE -ne 0 -or -not $nvidiaSmiOutput) {
    Exit-UnsupportedCuda -Reason "Failed to run nvidia-smi to detect CUDA version."
}

$cudaVersionMatch = $nvidiaSmiOutput | Select-String -Pattern "CUDA Version:\s*([0-9]+(?:\.[0-9]+)?)" | Select-Object -First 1
if (-not $cudaVersionMatch) {
    Exit-UnsupportedCuda -Reason "Could not parse CUDA version from nvidia-smi output."
}

$detectedCudaVersion = $cudaVersionMatch.Matches[0].Groups[1].Value
Write-Host "[i] Detected CUDA version: $detectedCudaVersion" -ForegroundColor Green

$sageAttentionWheelUrl = "https://github.com/terence-h/Easy-ComfyUI-Setup/raw/refs/heads/master/sageattention-2.2.0+cu130torch2.12.0-cp312-cp312-win_amd64.whl"

$cudaVersionParts = $detectedCudaVersion.Split('.')
$cudaMajor = [int]$cudaVersionParts[0]
$cudaMinor = if ($cudaVersionParts.Count -ge 2) { [int]$cudaVersionParts[1] } else { 0 }

if ($cudaMajor -lt 13) {
    Exit-UnsupportedCuda -Reason "Detected CUDA $detectedCudaVersion. CUDA 13.0 or newer is required."
}

if ($cudaMajor -eq 13 -and $cudaMinor -le 1) {
    $cudaInstallLabel   = "13.0/13.1 (cu130)"
    $torchIndexUrl      = "https://download.pytorch.org/whl/cu130"
    $torchaudioIndexUrl = $null
} else {
    $cudaInstallLabel   = "13.2+ (cu132)"
    $torchIndexUrl      = "https://download.pytorch.org/whl/cu132"
    $torchaudioIndexUrl = "https://download.pytorch.org/whl/test/cu132"
}

Write-Host "--- Part 2: Checking/Installing Prerequisites ---" -ForegroundColor Cyan

Install-WingetTool -Name "Git" -WingetId "Git.Git" -CommandToVerify "git"
Install-WingetTool -Name "uv"  -WingetId "astral-sh.uv" -CommandToVerify "uv"

Refresh-PathEnvironment

Write-Host "--- Part 3: Cloning Repository ---" -ForegroundColor Cyan
$comfyUiFolderName = Read-ValidWindowsFolderName -Prompt "Enter destination folder name for ComfyUI (leave blank for 'ComfyUI')"
$comfyUiFolderPath = Join-Path -Path "." -ChildPath $comfyUiFolderName

if (Test-Path $comfyUiFolderPath) {
    Write-Host "[X] '$comfyUiFolderPath' already exists. Remove or rename it before running this script." -ForegroundColor Red
    exit 1
}

$repoUrl = "https://github.com/Comfy-Org/ComfyUI.git"
$versionInput = Read-Host "Enter ComfyUI version tag (e.g. 0.0.2 or v0.18.3). Leave blank for latest. See https://github.com/Comfy-Org/ComfyUI/tags for versions available."
$versionInput = $versionInput.Trim()

if ([string]::IsNullOrWhiteSpace($versionInput)) {
    Invoke-OrExit -Action { git clone $repoUrl $comfyUiFolderName } -ErrorMessage "Failed to clone repository."
} else {
    $targetTag = Get-NormalizedVersionTag -Version $versionInput

    $remoteTags = git ls-remote --tags $repoUrl
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[X] Failed to query remote tags from '$repoUrl'." -ForegroundColor Red
        exit 1
    }

    $escapedTargetTag = [regex]::Escape($targetTag)
    $matchingTag = $remoteTags | Where-Object { $_ -match "refs/tags/$escapedTargetTag(\^\{\})?$" }
    if (-not $matchingTag) {
        Write-Host "[X] No matching version found for '$targetTag' in the repository." -ForegroundColor Red
        exit 1
    }

    Invoke-OrExit -Action { git clone --branch $targetTag --single-branch $repoUrl $comfyUiFolderName } -ErrorMessage "Failed to clone repository at tag '$targetTag'."
}

Set-Location -Path $comfyUiFolderPath

Write-Host "--- Part 4: Setting Up Virtual Environment ---" -ForegroundColor Cyan
Invoke-OrExit -Action { uv venv --python 3.12 } -ErrorMessage "Failed to create virtual environment."

Write-Host "--- Part 5: Installing Heavy Dependencies (Torch/CUDA $cudaInstallLabel) ---" -ForegroundColor Cyan
if ($null -eq $torchaudioIndexUrl) {
    Invoke-OrExit -Action { uv pip install torch==2.12.0 torchvision==0.27.0 torchaudio==2.11.0 --index-url $torchIndexUrl } -ErrorMessage "Failed to install torch packages for CUDA $cudaInstallLabel."
} else {
    Invoke-OrExit -Action { uv pip install torch==2.12.0 torchvision==0.27.0 --index-url $torchIndexUrl } -ErrorMessage "Failed to install torch/torchvision for CUDA $cudaInstallLabel."
    Invoke-OrExit -Action { uv pip install torchaudio==2.11.0 --index-url $torchaudioIndexUrl } -ErrorMessage "Failed to install torchaudio for CUDA $cudaInstallLabel."
}

Write-Host "--- Part 6: Installing Requirements ---" -ForegroundColor Cyan
Invoke-OrExit -Action { uv pip install -r requirements.txt } -ErrorMessage "Failed to install requirements.txt."

if (Test-Path "manager_requirements.txt") {
    Invoke-OrExit -Action { uv pip install -r manager_requirements.txt } -ErrorMessage "Failed to install manager_requirements.txt."
}

Write-Host "--- Part 7: Installing Triton and SageAttention ---" -ForegroundColor Cyan
Invoke-OrExit -Action { uv pip install -U "triton-windows<3.8" } -ErrorMessage "Failed to install triton-windows."

Invoke-OrExit -Action { uv pip install $sageAttentionWheelUrl } -ErrorMessage "Failed to install SageAttention 2."

Write-Host "--- Part 8: Selecting Default Attention Backend ---" -ForegroundColor Cyan
Write-Host "[i] SageAttention can be manually enabled per workflow by using ComfyUI-KJNodes's Patch Sage Attention KJ node." -ForegroundColor Yellow
Write-Host "[i] It is recommended to use PyTorch attention by default and patch SageAttention when you need it" -ForegroundColor Yellow

$attentionChoices = @(
    [PSCustomObject]@{
        Key = "1"
        Label = "PyTorch attention (Recommended)"
        Arg = ""
    },
    [PSCustomObject]@{
        Key = "2"
        Label = "SageAttention"
        Arg = "--use-sage-attention"
    }
)

foreach ($choice in $attentionChoices) {
    Write-Host "$($choice.Key). $($choice.Label)"
}

$attentionKeys = $attentionChoices | ForEach-Object { $_.Key }
$selectedAttentionKey = Read-NumberSelection -Prompt "Select default attention backend" -ValidChoices $attentionKeys
$selectedAttention = $attentionChoices | Where-Object { $_.Key -eq $selectedAttentionKey } | Select-Object -First 1
$defaultAttentionArg = $selectedAttention.Arg

$disableDynamicVram = Read-YesNo -Prompt "Disable dynamic VRAM?"

Write-Host "[i] Recommended for multiple ComfyUI installations: use a shared output directory so installs can save generated output at a centralised location." -ForegroundColor Yellow
$outputDirectoryArgPath = Read-OptionalAbsoluteWindowsPath -Prompt "Enter output directory for generated items (e.g. D:\ComfyUI_Output). Leave blank to keep default"
Write-Host "[i] Recommended for multiple ComfyUI installations: use a shared input directory so installs can access all the uploaded files." -ForegroundColor Yellow
$inputDirectoryArgPath = Read-OptionalAbsoluteWindowsPath -Prompt "Enter input directory for input items (images, videos, audio, etc.) (e.g. D:\ComfyUI_Input). Leave blank to keep default"

$startCommandArgsList = @()
if (-not [string]::IsNullOrWhiteSpace($defaultAttentionArg)) {
    $startCommandArgsList += $defaultAttentionArg
}
if ($disableDynamicVram) {
    $startCommandArgsList += "--disable-dynamic-vram"
}
if (-not [string]::IsNullOrWhiteSpace($outputDirectoryArgPath)) {
    $startCommandArgsList += ('--output-directory "{0}"' -f $outputDirectoryArgPath)
}
if (-not [string]::IsNullOrWhiteSpace($inputDirectoryArgPath)) {
    $startCommandArgsList += ('--input-directory "{0}"' -f $inputDirectoryArgPath)
}

$startCommandArgs = ""
if ($startCommandArgsList.Count -gt 0) {
    $startCommandArgs = " " + ($startCommandArgsList -join " ")
}

Write-Host "--- Part 9: Creating Launch & Update Batch Files ---" -ForegroundColor Cyan

# 1. start.bat
$startContent = @"
@echo off
setlocal
cd /d %~dp0
call .venv\Scripts\activate.bat
python main.py --enable-manager $startCommandArgs
REM --output-directory "D:\ComfyUI_Output"
REM --input-directory "D:\ComfyUI_Input"
REM --use-sage-attention
REM --disable-dynamic-vram
REM --front-end-version Comfy-Org/ComfyUI_frontend@1.39.19
"@
$startContent | Out-File -FilePath "start.bat" -Encoding ascii

# 2. update_latest.bat
$updateLatestContent = @"
@echo off
setlocal
cd /d %~dp0
git pull origin master
call .venv\Scripts\activate.bat
uv pip install -r requirements.txt
uv pip install -r manager_requirements.txt
pause
"@
$updateLatestContent | Out-File -FilePath "update_latest.bat" -Encoding ascii

# 3. update_stable.bat
$updateStableContent = @"
@echo off
setlocal
cd /d %~dp0
set "LATEST_TAG="
git fetch --tags
for /f "usebackq delims=" %%t in (``git tag --list "v*" --sort=-v:refname``) do (
    set "LATEST_TAG=%%t"
    goto :got_tag
)
:got_tag
if "%LATEST_TAG%"=="" (
    echo No v* tags found.
    goto :eof
)
echo Latest tag is: %LATEST_TAG%
git checkout "%LATEST_TAG%"
call .venv\Scripts\activate.bat
uv pip install -r requirements.txt
uv pip install -r manager_requirements.txt
pause
"@
$updateStableContent | Out-File -FilePath "update_stable.bat" -Encoding ascii

# 4. switch_comfyui_version.bat
$switchComfyUiVersionContent = @"
@echo off
setlocal
cd /d %~dp0
set "VERSION_INPUT="
set /p VERSION_INPUT="Enter ComfyUI version (e.g. 0.0.1 or v0.18.3): "
if "%VERSION_INPUT%"=="" (
    echo No version entered.
    goto :eof
)
set "VERSION=%VERSION_INPUT%"
if /i "%VERSION_INPUT:~0,1%"=="v" (
    set "VERSION=%VERSION_INPUT:~1%"
)
echo Checking out version: v%VERSION%
git fetch --tags
git checkout "v%VERSION%"
if %errorlevel% neq 0 (
    echo Failed to checkout v%VERSION%. Make sure the tag exists.
    pause
    goto :eof
)
call .venv\Scripts\activate.bat
uv pip install -r requirements.txt
uv pip install -r manager_requirements.txt
echo.
echo Successfully switched to ComfyUI v%VERSION%
pause
"@
$switchComfyUiVersionContent | Out-File -FilePath "switch_comfyui_version.bat" -Encoding ascii

# 5. reinstall_torchcuda_triton_sageattn.bat
$reinstallTorchCudaTritonSageAttnContent = @"
@echo off
setlocal EnableDelayedExpansion
cd /d %~dp0

where nvidia-smi >nul 2>nul
if errorlevel 1 (
    echo [X] nvidia-smi was not found. CUDA version could not be detected.
    echo Please upgrade CUDA to 13.0 or newer, then rerun this script.
    pause
    exit /b 1
)

set "CUDA_VERSION_RAW="
for /f "tokens=3 delims=:|" %%A in ('nvidia-smi ^| findstr /C:"CUDA Version"') do (
    set "CUDA_VERSION_RAW=%%A"
    goto :cuda_detected
)

:cuda_detected
if "!CUDA_VERSION_RAW!"=="" (
    echo [X] Could not parse CUDA version from nvidia-smi output.
    echo Please upgrade CUDA to 13.0 or newer, then rerun this script.
    pause
    exit /b 1
)

set "CUDA_VERSION=!CUDA_VERSION_RAW: =!"
echo [i] Detected CUDA version: !CUDA_VERSION!

for /f "tokens=1,2 delims=." %%a in ("!CUDA_VERSION!") do (
    set "CUDA_MAJOR=%%a"
    set "CUDA_MINOR=%%b"
)
if "!CUDA_MINOR!"=="" set "CUDA_MINOR=0"

if !CUDA_MAJOR! LSS 13 (
    echo [X] Detected CUDA !CUDA_VERSION!. CUDA 13.0 or newer is required.
    pause
    exit /b 1
)

set "SAGE_WHEEL_URL=https://github.com/terence-h/Easy-ComfyUI-Setup/raw/refs/heads/master/sageattention-2.2.0+cu130torch2.12.0-cp312-cp312-win_amd64.whl"
set "TORCHAUDIO_INDEX_URL="
set "USE_CU132=0"
if !CUDA_MAJOR! GTR 13 set "USE_CU132=1"
if !CUDA_MAJOR! EQU 13 if !CUDA_MINOR! GEQ 2 set "USE_CU132=1"

if "!USE_CU132!"=="1" (
    set "TORCH_INDEX_URL=https://download.pytorch.org/whl/cu132"
    set "TORCHAUDIO_INDEX_URL=https://download.pytorch.org/whl/test/cu132"
) else (
    set "TORCH_INDEX_URL=https://download.pytorch.org/whl/cu130"
)

call .venv\Scripts\activate.bat

if "!TORCHAUDIO_INDEX_URL!"=="" (
    uv pip install torch==2.12.0 torchvision==0.27.0 torchaudio==2.11.0 --index-url !TORCH_INDEX_URL! --upgrade --force-reinstall --no-deps
    if errorlevel 1 goto :install_failed
) else (
    uv pip install torch==2.12.0 torchvision==0.27.0 --index-url !TORCH_INDEX_URL! --upgrade --force-reinstall --no-deps
    if errorlevel 1 goto :install_failed
    uv pip install torchaudio==2.11.0 --index-url !TORCHAUDIO_INDEX_URL! --upgrade --force-reinstall --no-deps
    if errorlevel 1 goto :install_failed
)

uv pip install -U "triton-windows<3.8" --upgrade --force-reinstall --no-deps
if errorlevel 1 goto :install_failed

uv pip install "!SAGE_WHEEL_URL!" --upgrade --force-reinstall --no-deps
if errorlevel 1 goto :install_failed

echo [OK] Reinstall completed.
pause
exit /b 0

:install_failed
echo [X] Dependency installation failed.
pause
exit /b 1
"@
$reinstallTorchCudaTritonSageAttnContent | Out-File -FilePath "reinstall_torchcuda_triton_sageattn.bat" -Encoding ascii

Write-Host "[OK] All scripts created successfully." -ForegroundColor Green

Write-Host "--- Part 10: Optional Shared Model Search Path ---" -ForegroundColor Cyan
Write-Host "[i] Recommended for multiple ComfyUI installations: use a shared model directory so installs can reuse one model library and avoid duplicate models." -ForegroundColor Yellow

$extraModelPathsConfigured = $false
$extraModelBasePath = Read-OptionalAbsoluteWindowsPath -Prompt "Enter extra model search path (e.g. C:\ComfyUI_Models). Leave blank to skip"

if (-not [string]::IsNullOrWhiteSpace($extraModelBasePath)) {
    $requiredExtraModelSubfolders = @(
        "checkpoints",
        "text_encoders",
        "clip",
        "clip_vision",
        "configs",
        "controlnet",
        "diffusers",
        "diffusion_models",
        "unet",
        "embeddings",
        "gligen",
        "hypernetworks",
        "ipadapter",
        "latent_upscale_models",
        "loras",
        "model_patches",
        "photomaker",
        "style_models",
        "upscale_models",
        "vae",
        "vae_approx",
        "audio_encoders",
        "LLM",
        "onnx",
        "sams",
        "ultralytics",
        "ultralytics\bbox",
        "ultralytics\segm"
    )

    New-Item -Path $extraModelBasePath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    if (-not (Test-Path -Path $extraModelBasePath -PathType Container)) {
        Write-Host "[X] Failed to create or access '$extraModelBasePath'." -ForegroundColor Red
        exit 1
    }

    foreach ($relativeSubfolder in $requiredExtraModelSubfolders) {
        $targetSubfolderPath = Join-Path -Path $extraModelBasePath -ChildPath $relativeSubfolder
        New-Item -Path $targetSubfolderPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        if (-not (Test-Path -Path $targetSubfolderPath -PathType Container)) {
            Write-Host "[X] Failed to create required model directory '$targetSubfolderPath'." -ForegroundColor Red
            exit 1
        }
    }

    $resolvedExtraModelBasePath = (Resolve-Path -Path $extraModelBasePath).Path
    $yamlBasePath = $resolvedExtraModelBasePath -replace "'", "''"
    $extraModelPathsYamlContent = @"
comfyui:
    base_path: '$yamlBasePath'
    is_default: true
    checkpoints: checkpoints
    text_encoders: |
        text_encoders
        clip
    clip_vision: clip_vision
    configs: configs
    controlnet: controlnet
    diffusers: diffusers
    diffusion_models: |
        diffusion_models
        unet
    embeddings: embeddings
    gligen: gligen
    hypernetworks: hypernetworks
    ipadapter: ipadapter
    latent_upscale_models: latent_upscale_models
    loras: loras
    model_patches: model_patches
    photomaker: photomaker
    style_models: style_models
    upscale_models: upscale_models
    vae: vae
    vae_approx: vae_approx
    audio_encoders: audio_encoders
    LLM: LLM
    onnx: onnx
    sams: sams
    ultralytics: ultralytics
    ultralytics_bbox: ultralytics/bbox
    ultralytics_segm: ultralytics/segm
"@
    $extraModelPathsYamlContent | Out-File -FilePath "extra_model_paths.yaml" -Encoding ascii
    if (-not (Test-Path -Path "extra_model_paths.yaml" -PathType Leaf)) {
        Write-Host "[X] Failed to create extra_model_paths.yaml in '$comfyUiFolderName'." -ForegroundColor Red
        exit 1
    }

    $extraModelPathsConfigured = $true
    Write-Host "[OK] Created extra_model_paths.yaml using shared model path '$resolvedExtraModelBasePath'." -ForegroundColor Green
} else {
    Write-Host "[i] Skipped extra model search path setup."
}

Write-Host "--- Setup Complete! ---" -ForegroundColor Green
Write-Host "All scripts (start.bat, update_latest.bat, update_stable.bat, switch_comfyui_version.bat, reinstall_torchcuda_triton_sageattn.bat) have been created in the '$comfyUiFolderName' folder. Run start.bat to start ComfyUI."
