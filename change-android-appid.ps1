# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

# Script to change Android application ID for Sanmill Flutter app
# Usage: .\change-android-appid.ps1 -OldAppId <old_appid> -NewAppId <new_appid>
# Example: .\change-android-appid.ps1 -OldAppId "com.calcitem.sanmill" -NewAppId "com.calcitem.sanmill68"

param(
    [Parameter(Mandatory=$true)]
    [string]$OldAppId,
    
    [Parameter(Mandatory=$true)]
    [string]$NewAppId
)

# Function to print colored messages
function Print-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Green
}

function Print-Warn {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Print-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# Validate appid format
if ($OldAppId -notmatch '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$') {
    Print-Error "Invalid old appid format: $OldAppId"
    exit 1
}

if ($NewAppId -notmatch '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$') {
    Print-Error "Invalid new appid format: $NewAppId"
    exit 1
}

Print-Info "Changing Android Application ID from '$OldAppId' to '$NewAppId'"

# Convert appid to path (com.calcitem.sanmill -> com\calcitem\sanmill)
$OldPath = $OldAppId -replace '\.', '\'
$NewPath = $NewAppId -replace '\.', '\'

# Convert appid to JNI format (com.calcitem.sanmill -> com_calcitem_sanmill)
$OldJni = $OldAppId -replace '\.', '_'
$NewJni = $NewAppId -replace '\.', '_'

$FlutterAppDir = "src\ui\flutter_app"
$AndroidDir = "$FlutterAppDir\android"

# Check if flutter app directory exists
if (-not (Test-Path $FlutterAppDir)) {
    Print-Error "Flutter app directory not found: $FlutterAppDir"
    exit 1
}

# Step 1: Update build.gradle files
Print-Info "Step 1: Updating build.gradle files..."
$GradleFiles = @(
    "$AndroidDir\app\build.gradle",
    "$AndroidDir\app\build.gradle_github",
    "$AndroidDir\app\build.gradle_fdroid"
)

foreach ($gradleFile in $GradleFiles) {
    if (Test-Path $gradleFile) {
        Print-Info "  Updating $gradleFile"
        $content = Get-Content $gradleFile -Raw
        $content = $content -replace "namespace `"$OldAppId`"", "namespace `"$NewAppId`""
        $content = $content -replace "applicationId `"$OldAppId`"", "applicationId `"$NewAppId`""
        Set-Content -Path $gradleFile -Value $content -NoNewline
    } else {
        Print-Warn "  File not found: $gradleFile"
    }
}

# Step 2: Update AndroidManifest.xml files
Print-Info "Step 2: Updating AndroidManifest.xml files..."
$ManifestFiles = @(
    "$AndroidDir\app\src\main\AndroidManifest.xml",
    "$AndroidDir\app\src\debug\AndroidManifest.xml",
    "$AndroidDir\app\src\profile\AndroidManifest.xml"
)

foreach ($manifestFile in $ManifestFiles) {
    if (Test-Path $manifestFile) {
        Print-Info "  Updating $manifestFile"
        $content = Get-Content $manifestFile -Raw
        $content = $content -replace "package=`"$OldAppId`"", "package=`"$NewAppId`""
        Set-Content -Path $manifestFile -Value $content -NoNewline
    } else {
        Print-Warn "  File not found: $manifestFile"
    }
}

# Step 3: Update Java files and move to new directory
Print-Info "Step 3: Updating Java files..."
$OldJavaDir = "$AndroidDir\app\src\main\java\$OldPath"
$NewJavaDir = "$AndroidDir\app\src\main\java\$NewPath"

if (Test-Path $OldJavaDir) {
    # Create new directory
    Print-Info "  Creating new directory: $NewJavaDir"
    New-Item -ItemType Directory -Force -Path $NewJavaDir | Out-Null
    
    # Update package declaration in Java files and copy to new location
    Get-ChildItem -Path $OldJavaDir -Filter "*.java" | ForEach-Object {
        Print-Info "  Processing $($_.Name)"
        $content = Get-Content $_.FullName -Raw
        $content = $content -replace "package $OldAppId;", "package $NewAppId;"
        $content = $content -replace "`"$OldAppId/", "`"$NewAppId/"
        Set-Content -Path "$NewJavaDir\$($_.Name)" -Value $content -NoNewline
    }
    
    # Remove old directory
    Print-Info "  Removing old directory: $OldJavaDir"
    Remove-Item -Path $OldJavaDir -Recurse -Force
} else {
    Print-Warn "  Old Java directory not found: $OldJavaDir"
}

# Step 4: Update Flutter Dart MethodChannel names
Print-Info "Step 4: Updating Flutter Dart MethodChannel names..."
$DartFiles = @(
    "$FlutterAppDir\lib\game_page\services\engine\engine.dart",
    "$FlutterAppDir\lib\shared\services\native_methods.dart",
    "$FlutterAppDir\lib\shared\services\system_ui_service.dart"
)

foreach ($dartFile in $DartFiles) {
    if (Test-Path $dartFile) {
        Print-Info "  Updating $dartFile"
        $content = Get-Content $dartFile -Raw
        $content = $content -replace "'$OldAppId/", "'$NewAppId/"
        $content = $content -replace "`"$OldAppId/", "`"$NewAppId/"
        Set-Content -Path $dartFile -Value $content -NoNewline
    } else {
        Print-Warn "  File not found: $dartFile"
    }
}

# Step 5: Update JNI function names in C++ code
Print-Info "Step 5: Updating JNI function names in C++ code..."
$JniFile = "$FlutterAppDir\command\mill_engine.cpp"

if (Test-Path $JniFile) {
    Print-Info "  Updating $JniFile"
    $content = Get-Content $JniFile -Raw
    $content = $content -replace "Java_${OldJni}_MillEngine_", "Java_${NewJni}_MillEngine_"
    Set-Content -Path $JniFile -Value $content -NoNewline
} else {
    Print-Warn "  File not found: $JniFile"
}

# Step 6: Summary
Print-Info ""
Print-Info "=========================================="
Print-Info "Application ID change completed!"
Print-Info "=========================================="
Print-Info "Old Application ID: $OldAppId"
Print-Info "New Application ID: $NewAppId"
Print-Info ""
Print-Info "Modified files:"
Print-Info "  - $($GradleFiles.Count) build.gradle files"
Print-Info "  - $($ManifestFiles.Count) AndroidManifest.xml files"
Print-Info "  - Java files in $NewJavaDir"
Print-Info "  - $($DartFiles.Count) Dart files"
Print-Info "  - 1 C++ JNI file"
Print-Info ""
Print-Warn "Next steps:"
Print-Warn "  1. Review changes: git diff"
Print-Warn "  2. Run formatting: .\format.sh s"
Print-Warn "  3. Test the app to ensure everything works"
Print-Warn "  4. Commit changes: git add . && git commit"
Print-Info ""

