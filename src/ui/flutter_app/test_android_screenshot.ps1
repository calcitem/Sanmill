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

# Timeout for each individual locale test run (applied by PowerShell Wait-Job)
# Should be slightly longer than any expected legitimate run time.
$psTimeoutSeconds = 360 # 6 minutes (adjust as needed)
# Timeout for flutter test itself (internal, might not always interrupt hangs)
$flutterTestTimeout = "5m"
# ---------------------

# Check for connected Android devices
Write-Host "Checking for connected Android devices..." -ForegroundColor Cyan
$devices = (& adb devices) | Where-Object { $_ -match "device$" }

if ($devices.Count -eq 0) {
    Write-Host "ERROR: No connected Android devices found. Please ensure your device is connected and USB debugging is enabled." -ForegroundColor Red
    exit 1
} elseif ($devices.Count -gt 1) {
    Write-Host "WARNING: Multiple devices found. Please connect only one device or use -s to specify." -ForegroundColor Yellow
    & adb devices
    $continue = Read-Host "Continue? (y/n)"
    if ($continue -ne "y") {
        exit 1
    }
}

# Attempt to read package name from app/build.gradle
$packageNameLine = Get-Content -Path android\app\build.gradle | Where-Object { $_ -match "applicationId" }
if ($packageNameLine) {
    $packageName = $packageNameLine -replace '.*applicationId\s+"([^"]+)".*', '$1'
} else {
    $packageName = "com.calcitem.sanmill"
    Write-Host "Using default package name: $packageName" -ForegroundColor Yellow
}

# Define the target screenshot directory on device
$targetDir = "/storage/emulated/0/Pictures/Sanmill"
Write-Host "Target screenshot directory on device: $targetDir" -ForegroundColor Cyan

# Clean up old screenshots *on device* only once at the beginning
Write-Host "Cleaning up old screenshots on device ($targetDir)..." -ForegroundColor Cyan
& adb shell "rm -rf $targetDir/*"

# Create the directory on device if it doesn't exist
Write-Host "Ensuring screenshot directory exists on device..." -ForegroundColor Cyan
& adb shell "mkdir -p $targetDir"

# Define the local base directory for screenshots
$localBaseDir = "screenshots"

# Ensure the local base directory exists, DO NOT clean it up
Write-Host "Ensuring local base directory exists: $localBaseDir" -ForegroundColor Cyan
if (-not (Test-Path -Path $localBaseDir)) {
    New-Item -Path $localBaseDir -ItemType Directory | Out-Null
}

# Clean Flutter build cache
# Write-Host "Running flutter clean..." -ForegroundColor Cyan
# & flutter clean

# Install package once before running tests
Write-Host "Installing app with proper permissions..." -ForegroundColor Cyan
& flutter install

# List to keep track of failed locales in PowerShell
$failedLocalesPS = [System.Collections.Generic.List[string]]::new()
$successfulLocalesPS = [System.Collections.Generic.List[string]]::new()
# Hashtable to store cumulative screenshot counts per locale (pulled files)
$localeCountsPulled = @{}
$totalPulled = 0


# --- Loop through locales, run test, and pull screenshots ---
Write-Host "Starting screenshot tests and pulling for specified locales..." -ForegroundColor Cyan

foreach ($locale in $localesToTest) {
    Write-Host "--------------------------------------------------" -ForegroundColor Magenta
    Write-Host "Running test for locale: $locale (Timeout: $flutterTestTimeout)" -ForegroundColor Magenta
    Write-Host "--------------------------------------------------"

    # Construct the command string (optional, mainly for logging now)
    $testCommandLog = "flutter test integration_test/localization_screenshot_test.dart --dart-define=TEST_LOCALE=$locale --timeout $flutterTestTimeout --no-pub --reporter=compact"
    Write-Host "Executing: $testCommandLog" -ForegroundColor Yellow # Log the command being executed

    # Run integration test for the single locale using --dart-define
    # Call flutter directly and pass arguments separately
    flutter test integration_test/localization_screenshot_test.dart --dart-define=TEST_LOCALE=$locale --timeout $flutterTestTimeout --no-pub --reporter=compact

    # Check the exit code of the flutter test command
    $exitCode = $LASTEXITCODE # Store exit code immediately
    $testSucceeded = ($exitCode -eq 0)

    if ($testSucceeded) {
        Write-Host "SUCCESS: Test for locale $locale completed successfully." -ForegroundColor Green
        $successfulLocalesPS.Add($locale)
    } else {
        Write-Host "FAILURE: Test for locale $locale failed (Exit Code: $exitCode). Check logs above. May have timed out." -ForegroundColor Red
        $failedLocalesPS.Add($locale)
        # Continue to attempt pulling screenshots even if the test failed/timed out
        Write-Host "Attempting to pull any generated screenshots for $locale despite test failure..." -ForegroundColor Yellow
    }

    # --- Pull screenshots SPECIFICALLY for this locale ---
    Write-Host "Searching for screenshots matching '$locale*.png' in $targetDir on device..." -ForegroundColor Cyan
    $pattern = "$targetDir/${locale}_*.png"
    # Use pattern matching with find. Escape '*' if necessary, though often not needed here.
    $paths = & adb shell "find $targetDir -name '${locale}_*.png' 2>/dev/null || echo ''"
    $localePaths = $paths | Where-Object { $_ -ne "" -and $_ -ne "Not found" }

    if ($localePaths.Count -eq 0) {
        Write-Host "No screenshots found matching '$locale*.png' for this locale run." -ForegroundColor Yellow
    } else {
        Write-Host "Found $($localePaths.Count) screenshots for $locale! Pulling files..." -ForegroundColor Green

        # Define the local target directory for this locale
        $localLocaleDir = "$localBaseDir/$locale"

        # Create the local locale directory if it doesn't exist
        if (-not (Test-Path -Path $localLocaleDir)) {
            Write-Host "Creating local directory: $localLocaleDir" -ForegroundColor Cyan
            New-Item -Path $localLocaleDir -ItemType Directory | Out-Null
        }

        # Pull the found files
        $localePulledCount = 0
        foreach ($path in $localePaths) {
            $path = $path.Trim()
            if ($path) {
                Write-Host "Pulling: $path to $localLocaleDir" -ForegroundColor Green
                & adb pull "$path" $localLocaleDir
                $localePulledCount++
                $totalPulled++ # Increment total count
            }
        }
         # Update the cumulative count for this locale
        if ($localeCountsPulled.ContainsKey($locale)) {
            $localeCountsPulled[$locale] += $localePulledCount
        } else {
            $localeCountsPulled[$locale] = $localePulledCount
        }
        Write-Host "Pulled $localePulledCount screenshots for $locale." -ForegroundColor Green

    }
     # Optional short delay between locales
     # Start-Sleep -Seconds 2
} # End foreach locale loop

Write-Host "--------------------------------------------------" -ForegroundColor Magenta
Write-Host "All locale test runs and pulls completed." -ForegroundColor Magenta
Write-Host "--------------------------------------------------"

# --- Generate the final log file content ---
Write-Host "Generating final log file..." -ForegroundColor Cyan
$logContent = @()
$logContent += "Screenshot Generation Summary:"
$logContent += "=============================="
$logContent += "Tested Locales:"
$logContent += "------------------------------"
# Use the original list of locales intended for testing for the log
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
$logFilePath = "$localBaseDir/log.txt"
$logContent | Out-File -FilePath $logFilePath -Encoding utf8
Write-Host "Log file created at $logFilePath" -ForegroundColor Green

Write-Host "DONE! Screenshots are saved in locale-specific subfolders within $localBaseDir." -ForegroundColor Green
Write-Host "Summary logged to $logFilePath" -ForegroundColor Green

# Optional: Exit with non-zero code if any locale failed
if ($failedLocalesPS.Count -gt 0) {
    Write-Host "Exiting with error code because some locales failed." -ForegroundColor Red
    exit 1
} else {
    exit 0
}