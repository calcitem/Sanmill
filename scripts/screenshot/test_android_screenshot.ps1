# test_android_screenshot.ps1

# --- Configuration ---
# Set to $true to use the full list of locales, $false for the short list
$useFullLocaleList = $true # Set to $true for full run

# Short list for quick testing
$localesToTestShort = @(
    "en_US",
    "de_DE",
    "zh_CN"
)

# Full list of locales (languageCode_CountryCode)
$localesToTestFull = @(
    "am_ET", # Amharic - Ethiopia
    "ar_SA", # Arabic - Saudi Arabia
    "az_AZ", # Azerbaijani - Azerbaijan
    "be_BY", # Belarusian - Belarus
    "bg_BG", # Bulgarian - Bulgaria
    "bn_BD", # Bengali - Bangladesh
    "ca_ES", # Catalan - Spain
    "cs_CZ", # Czech - Czech Republic
    "da_DK", # Danish - Denmark
    "de_DE", # German - Germany
    "el_GR", # Greek - Greece
    "en_US", # English - United States
    "es_ES", # Spanish - Spain
    "et_EE", # Estonian - Estonia
    "fa_IR", # Persian - Iran
    "fi_FI", # Finnish - Finland
    "fr_FR", # French - France
    "gu_IN", # Gujarati - India
    "he_IL", # Hebrew - Israel
    "hi_IN", # Hindi - India
    "hr_HR", # Croatian - Croatia
    "hu_HU", # Hungarian - Hungary
    "hy_AM", # Armenian - Armenia
    "id_ID", # Indonesian - Indonesia
    "is_IS", # Icelandic - Iceland
    "it_IT", # Italian - Italy
    "ja_JP", # Japanese - Japan
    "km_KH", # Khmer - Cambodia
    "kn_IN", # Kannada - India
    "ko_KR", # Korean - South Korea
    "lt_LT", # Lithuanian - Lithuania
    "lv_LV", # Latvian - Latvia
    "mk_MK", # Macedonian - North Macedonia
    "ms_MY", # Malay - Malaysia
    "my_MM", # Burmese - Myanmar
    "nl_NL", # Dutch - Netherlands
    "nb_NO", # Norwegian Bokmål - Norway
    "pl_PL", # Polish - Poland
    "pt_BR", # Portuguese - Brazil
    "ro_RO", # Romanian - Romania
    "ru_RU", # Russian - Russia
    "si_LK", # Sinhala - Sri Lanka
    "sk_SK", # Slovak - Slovakia
    "sl_SI", # Slovenian - Slovenia
    "sq_AL", # Albanian - Albania
    "sr_RS", # Serbian - Serbia
    "sv_SE", # Swedish - Sweden
    "sw_KE", # Swahili - Kenya
    "ta_IN", # Tamil - India
    "te_IN", # Telugu - India
    "th_TH", # Thai - Thailand
    "tr_TR", # Turkish - Turkey
    "uk_UA", # Ukrainian - Ukraine
    "ur_PK", # Urdu - Pakistan
    "vi_VN", # Vietnamese - Vietnam
    "zh_CN", # Chinese - Simplified (Mainland China)
    "zh_TW", # Chinese - Traditional (Taiwan)
    "zu_ZA"  # Zulu - South Africa
)

# Select which list to use based on the flag
if ($useFullLocaleList) {
    $localesToTest = $localesToTestFull
    Write-Host "Using FULL locale list ($($localesToTest.Count) locales)." -ForegroundColor Yellow
} else {
    $localesToTest = $localesToTestShort
    Write-Host "Using SHORT locale list ($($localesToTest.Count) locales). Set `$useFullLocaleList = `$true for full run." -ForegroundColor Yellow
}

# Timeout settings
$psTimeoutSeconds = 360  # PowerShell job timeout
$flutterTestTimeout = "5m"  # Flutter test internal timeout

# ---------------------------------------------------------
# Define relative paths to Flutter app directory and build.gradle
# Adjust this if your directory structure differs
$flutterAppDir = "..\..\src\ui\flutter_app"
$buildGradlePath = Join-Path $flutterAppDir "android\app\build.gradle"
$integrationTestPath = Join-Path $flutterAppDir "integration_test\localization_screenshot_test.dart"
# ---------------------------------------------------------

# Check for connected Android devices
Write-Host "Checking for connected Android devices..." -ForegroundColor Cyan
$devices = (& adb devices) | Where-Object { $_ -match "device$" }

if ($devices.Count -eq 0) {
    Write-Host "ERROR: No connected Android devices found. Please ensure your device is connected and USB debugging is enabled." -ForegroundColor Red
    exit 1
} elseif ($devices.Count -gt 1) {
    Write-Host "WARNING: Multiple devices found. Please connect only one device or specify with -s." -ForegroundColor Yellow
    & adb devices
    $continue = Read-Host "Continue? (y/n)"
    if ($continue -ne "y") {
        exit 1
    }
}

# Attempt to read package name from android/app/build.gradle at the Flutter app directory
if (Test-Path $buildGradlePath) {
    $packageNameLine = Get-Content -Path $buildGradlePath | Where-Object { $_ -match "applicationId" }
    if ($packageNameLine) {
        $packageName = $packageNameLine -replace '.*applicationId\s+"([^"]+)".*', '$1'
    } else {
        Write-Host "No applicationId found in build.gradle. Using default package name." -ForegroundColor Yellow
        $packageName = "com.calcitem.sanmill"
    }
} else {
    Write-Host "Cannot find build.gradle at path: $buildGradlePath" -ForegroundColor Red
    Write-Host "Using default package name: com.calcitem.sanmill" -ForegroundColor Yellow
    $packageName = "com.calcitem.sanmill"
}

Write-Host "Using package name: $packageName" -ForegroundColor Cyan

# Define screenshot directory on device
$targetDir = "/storage/emulated/0/Pictures/Sanmill"
Write-Host "Target screenshot directory on device: $targetDir" -ForegroundColor Cyan

# Clean up old screenshots on device
Write-Host "Cleaning up old screenshots on device ($targetDir)..." -ForegroundColor Cyan
& adb shell "rm -rf $targetDir/*"

# Ensure directory on device
Write-Host "Ensuring screenshot directory exists on device..." -ForegroundColor Cyan
& adb shell "mkdir -p $targetDir"

# Define the local base directory for screenshots
$localBaseDir = "screenshots"

# Ensure the local base directory exists, DO NOT clean it up
Write-Host "Ensuring local base directory exists: $localBaseDir" -ForegroundColor Cyan
if (-not (Test-Path -Path $localBaseDir)) {
    New-Item -Path $localBaseDir -ItemType Directory | Out-Null
}

# ---------------------------------------------------------
# Install the app with proper permissions
# We do this once. Since 'flutter install' needs to run from
# the Flutter project directory, we'll temporarily move there.
# ---------------------------------------------------------
Push-Location $flutterAppDir
Write-Host "`nInstalling app from Flutter project directory: $flutterAppDir" -ForegroundColor Cyan
& flutter install
Pop-Location

# Lists to track success/failure
$failedLocalesPS = [System.Collections.Generic.List[string]]::new()
$successfulLocalesPS = [System.Collections.Generic.List[string]]::new()

# Track pulled screenshots
$localeCountsPulled = @{}
$totalPulled = 0

Write-Host "`nStarting screenshot tests and pulling for specified locales..." -ForegroundColor Cyan
foreach ($locale in $localesToTest) {
    Write-Host "--------------------------------------------------" -ForegroundColor Magenta
    Write-Host "Running test for locale: $locale (Timeout: $flutterTestTimeout)" -ForegroundColor Magenta
    Write-Host "--------------------------------------------------"

    # We'll run 'flutter test' from the Flutter app directory
    Push-Location $flutterAppDir
    $testCommandLog = "flutter test integration_test/localization_screenshot_test.dart --dart-define=TEST_LOCALE=$locale --timeout $flutterTestTimeout --no-pub --reporter=compact"
    Write-Host "Executing: $testCommandLog" -ForegroundColor Yellow

    flutter test `
        "integration_test/localization_screenshot_test.dart" `
        --dart-define="TEST_LOCALE=$locale" `
        --timeout $flutterTestTimeout `
        --no-pub `
        --reporter=compact

    $exitCode = $LASTEXITCODE
    Pop-Location  # Return to the original script directory

    if ($exitCode -eq 0) {
        Write-Host "SUCCESS: Test for locale $locale completed successfully." -ForegroundColor Green
        $successfulLocalesPS.Add($locale)
    } else {
        Write-Host "FAILURE: Test for locale $locale failed (Exit Code: $exitCode). Check logs above." -ForegroundColor Red
        $failedLocalesPS.Add($locale)
        Write-Host "Attempting to pull any generated screenshots for $locale despite test failure..." -ForegroundColor Yellow
    }

    # Pull screenshots for this locale
    Write-Host "Searching for screenshots matching '$locale*.png' in $targetDir on device..." -ForegroundColor Cyan
    $paths = & adb shell "find $targetDir -name '${locale}_*.png' 2>/dev/null || echo ''"
    $localePaths = $paths | Where-Object { $_ -ne "" -and $_ -ne "Not found" }

    if ($localePaths.Count -eq 0) {
        Write-Host "No screenshots found matching '$locale*.png' for this locale run." -ForegroundColor Yellow
    } else {
        Write-Host "Found $($localePaths.Count) screenshots for $locale! Pulling files..." -ForegroundColor Green
        $localLocaleDir = Join-Path $localBaseDir $locale

        if (-not (Test-Path -Path $localLocaleDir)) {
            Write-Host "Creating local directory: $localLocaleDir" -ForegroundColor Cyan
            New-Item -Path $localLocaleDir -ItemType Directory | Out-Null
        }

        $localePulledCount = 0
        foreach ($path in $localePaths) {
            $cleanPath = $path.Trim()
            if ($cleanPath) {
                Write-Host "Pulling: $cleanPath to $localLocaleDir" -ForegroundColor Green
                & adb pull "$cleanPath" $localLocaleDir
                $localePulledCount++
                $totalPulled++
            }
        }

        if ($localeCountsPulled.ContainsKey($locale)) {
            $localeCountsPulled[$locale] += $localePulledCount
        } else {
            $localeCountsPulled[$locale] = $localePulledCount
        }

        Write-Host "Pulled $localePulledCount screenshots for $locale." -ForegroundColor Green
    }
}

Write-Host "--------------------------------------------------" -ForegroundColor Magenta
Write-Host "All locale test runs and pulls completed." -ForegroundColor Magenta
Write-Host "--------------------------------------------------"

# Generate the final log file
Write-Host "Generating final log file..." -ForegroundColor Cyan
$logContent = @()
$logContent += "Screenshot Generation Summary:"
$logContent += "=============================="
$logContent += "Tested Locales:"
$logContent += "------------------------------"

foreach ($locale in $localesToTest) {
    $status = if ($failedLocalesPS.Contains($locale)) { "FAILED" } else { "SUCCESS" }
    $pulledCount = if ($localeCountsPulled.ContainsKey($locale)) { $localeCountsPulled[$locale] } else { 0 }
    $logContent += "Locale: $locale - Test Status: $status - Screenshots Pulled: $pulledCount"
}

$logContent += "=============================="
$logContent += "Summary:"
$logContent += "------------------------------"
$logContent += "Successful Locales: $($successfulLocalesPS.Count) ($($successfulLocalesPS -join ', '))"
$logContent += "Failed Locales    : $($failedLocalesPS.Count) ($($failedLocalesPS -join ', '))"
$logContent += "Total Screenshots Pulled: $totalPulled"

$logFilePath = Join-Path $localBaseDir "log.txt"
$logContent | Out-File -FilePath $logFilePath -Encoding utf8

Write-Host "Log file created at $logFilePath" -ForegroundColor Green
Write-Host "DONE! Screenshots are saved in locale-specific subfolders within '$localBaseDir'." -ForegroundColor Green
Write-Host "Summary logged to '$logFilePath'." -ForegroundColor Green

# Optional: Exit with non-zero code if any locale failed
if ($failedLocalesPS.Count -gt 0) {
    Write-Host "Exiting with error code because some locales failed." -ForegroundColor Red
    exit 1
} else {
    exit 0
}
