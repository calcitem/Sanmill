# -*- coding: utf-8 -*-
import os
import glob
import mimetypes
import re
from google.oauth2 import service_account
# --- Using requests transport ---
import requests                     # Import requests
from google.auth.transport.requests import AuthorizedSession # Use requests transport
# --- End using requests transport ---
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload
# Import googleapiclient.errors for more precise API error handling
import googleapiclient.errors
from collections import defaultdict
import time
import datetime

# --- Configuration ---
# !!! Modify the following paths and names !!!
SERVICE_ACCOUNT_FILE = './sanmill-app.json' # Path to your service account JSON key file
PACKAGE_NAME = 'com.calcitem.sanmill'       # Your application package name
IMAGE_PARENT_DIR = './google_play_assets'   # Parent directory containing phoneScreenshots etc.
# Define supported screenshot type directory names (must match Google Play API imageType)
SUPPORTED_IMAGE_TYPES = ('phoneScreenshots', 'sevenInchScreenshots', 'tenInchScreenshots')

# --- Proxy Configuration ---
PROXY_ENABLED = True  # Set to True to enable proxy, False to disable
# Configure proxy address for requests (must include http:// or https://)
PROXY_ADDRESS = 'http://127.0.0.1:7890'
# If proxy requires username/password, format: 'http://user:password@host:port'
# Example: PROXY_ADDRESS = 'http://your_user:your_password@127.0.0.1:7890'

# --- End Configuration ---

# --- Google API Settings ---
SCOPES = ['https://www.googleapis.com/auth/androidpublisher']

# --- Locale Mapping (Keep unchanged) ---
LOCALE_MAPPING = {
    # ... (Your LOCALE_MAPPING dictionary content remains unchanged) ...
    "am_ET": ["am"], "ar_SA": ["ar"], "az_AZ": ["az-AZ"], "be_BY": ["be"], "bg_BG": ["bg"], "bn_BD": ["bn-BD"], "ca_ES": ["ca"], "cs_CZ": ["cs-CZ"], "da_DK": ["da-DK"], "el_GR": ["el-GR"], "en_US": ["en-US", "en-GB", "en-SG", "en-IN", "en-ZA", "en-CA", "en-AU"], "es_ES": ["es-ES", "es-419", "es-US"], "et_EE": ["et"], "fa_IR": ["fa", "fa-AE", "fa-AF", "fa-IR"], "fi_FI": ["fi-FI"], "fr_FR": ["fr-FR", "fr-CA"], "gu_IN": ["gu"], "he_IL": ["iw-IL"], "hi_IN": ["hi-IN"], "hr_HR": ["hr"], "hu_HU": ["hu-HU"], "hy_AM": ["hy-AM"], "id_ID": ["id"], "is_IS": ["is-IS"], "it_IT": ["it-IT"], "km_KH": ["km-KH"], "ko_KR": ["ko-KR"], "lt_LT": ["lt"], "lv_LV": ["lv"], "mk_MK": ["mk-MK"], "ms_MY": ["ms", "ms-MY"], "my_MM": ["my-MM"], "nb_NO": ["no-NO"], "nl_NL": ["nl-NL"], "pl_PL": ["pl-PL"], "pt_BR": ["pt-BR", "pt-PT"], "ro_RO": ["ro"], "ru_RU": ["ru-RU"], "si_LK": ["si-LK"], "sk_SK": ["sk"], "sl_SI": ["sl"], "sq_AL": ["sq"], "sr_RS": ["sr"], "sv_SE": ["sv-SE"], "sw_KE": ["sw"], "ta_IN": ["ta-IN"], "te_IN": ["te-IN"], "th_TH": ["th"], "uk_UA": ["uk"], "ur_PK": ["ur"], "vi_VN": ["vi"], "zh_CN": ["zh-CN", "zh-HK"], "zh_TW": ["zh-TW"], "zu_ZA": ["zu"],
}

# === Start: Add RequestsHttpAdapter and _Response classes (Keep unchanged) ===
class RequestsHttpAdapter:
    """
    Adapter to make requests.Session mimic httplib2.Http.
    Main function: map body/headers etc. parameters to requests calls and return a compatible object.
    """

    def __init__(self, session: requests.Session):
        self.session = session

    def request(self, uri, method='GET', body=None, headers=None,
                redirections=None, connection_type=None):
        """
        Mimics the function signature of httplib2.Http.request.
        """
        if headers is None:
            headers = {}

        # google-api-python-client might add this, requests handles it automatically
        headers.pop('accept-encoding', None)

        data_to_send = body
        if isinstance(body, str):
            # Encode body to bytes if it's a string
            data_to_send = body.encode('utf-8')

        try:
            resp = self.session.request(
                method=method,
                url=uri,
                data=data_to_send,
                headers=headers,
                # 'redirections' and 'connection_type' are not directly mapped in basic requests
                # Allow redirects is default in requests.Session
                # Timeout, verify etc. could be configured on the session itself
            )
            # resp.raise_for_status() # Optional: Raise exception for 4xx/5xx, API client library usually handles this
            return _Response(resp), resp.content
        except requests.exceptions.RequestException as e:
            print(f"!!! Internal Error in RequestsHttpAdapter: {e}")
            # Need to return something that looks like an httplib2 response/error
            # For simplicity, return a custom error response object and empty content
            # Or re-raise, depending on how googleapiclient expects errors
            # return _Response(error=e), b"" # Option 1: Return error response
            raise # Option 2: Re-raise the exception for the API client to handle


class _Response:
    """
    Wraps a requests.Response object to provide attributes/methods similar to httplib2.Response.
    """
    def __init__(self, resp: requests.Response = None, error=None):
        if resp is not None:
            self.resp = resp
            self.status = resp.status_code
            self.reason = resp.reason
            self.headers = resp.headers
            self._content = resp.content
            self._error = None
        else:
            # Create a minimal response object for errors caught in the adapter
            self.resp = None
            self.status = 0 # Or appropriate error code if available from error
            self.reason = str(error) if error else "Adapter Error"
            self.headers = {}
            self._content = b""
            self._error = error

    def __getitem__(self, key):
        # Allow accessing headers like a dictionary
        return self.headers.get(key.lower()) # httplib2 headers are lowercase keys

    def read(self):
        # Method expected by some parts of googleapiclient
        return self._content
# === End: Add RequestsHttpAdapter and _Response classes ===


def authenticate():
    """Authenticate using the service account, using Requests as transport with proxy support."""
    print("--- Starting Authentication (using Requests Transport + Adapter) ---")
    authed_session = None
    try:
        print("  > Loading service account credentials...")
        credentials = service_account.Credentials.from_service_account_file(
            SERVICE_ACCOUNT_FILE, scopes=SCOPES
        )
        print("  ✓ Service account credentials loaded successfully.")

        print("  > Creating authorized HTTP Session...")
        # Use AuthorizedSession from google.auth.transport.requests
        authed_session = AuthorizedSession(credentials)
        print("  ✓ Authorized HTTP Session created successfully.")

        if PROXY_ENABLED:
            print(f"  > Enabling proxy: {PROXY_ADDRESS}")
            # Proxies dict for requests session
            proxies = { 'http': PROXY_ADDRESS, 'https': PROXY_ADDRESS }
            authed_session.proxies = proxies
            # Disable SSL verification if needed (e.g., for MITM proxies, NOT RECOMMENDED for production)
            # authed_session.verify = False
            # print("  ! SSL verification disabled due to proxy settings (if uncommented).")
        else:
            print("  > Proxy is disabled.")

        # Wrap the requests Session with the adapter for googleapiclient
        print("  > Creating Requests to httplib2 adapter...")
        adapter = RequestsHttpAdapter(authed_session)
        print("  ✓ Adapter created successfully.")

        print("  > Building Google Play Developer API service...")
        # Pass the adapter instance as 'http'
        service = build('androidpublisher', 'v3', http=adapter)
        print("✓ Google Play Developer API service built successfully.")
        return service

    except FileNotFoundError:
        print(f"✗ Authentication Failed: Service account key file not found at '{SERVICE_ACCOUNT_FILE}'")
        return None
    except ImportError as e:
         print(f"✗ Authentication Failed: Missing required libraries ({e}). Please ensure 'google-auth', 'google-auth-requests', 'requests', 'google-api-python-client' are installed.")
         return None
    except requests.exceptions.ProxyError as e:
        print(f"✗ Authentication Failed: Proxy Error - {e}")
        print(f"  ! Please check if the proxy server {PROXY_ADDRESS} is running, configured correctly, and allows connections.")
        return None
    except requests.exceptions.RequestException as e:
        # Catch other requests errors (connection, timeout, etc.)
        print(f"✗ Authentication Failed: Network Request Error - {e}")
        return None
    except Exception as e:
        print(f"✗ Authentication or Service Build Failed: {e}")
        import traceback
        traceback.print_exc() # Print detailed traceback for debugging
        print("  Please check:")
        print(f"  1. If the service account key file path '{SERVICE_ACCOUNT_FILE}' is correct.")
        print(f"  2. If the service account JSON file content is valid.")
        print(f"  3. If the 'Google Play Android Developer API' is enabled for this service account in Google Cloud Console.")
        print(f"  4. If the service account has sufficient permissions (e.g., granted access in Play Console).")
        print(f"  5. If the SCOPES ('{SCOPES}') are correct.")
        print(f"  6. If the network connection is stable (including proxy connection if enabled).")
        print(f"  7. If all dependency libraries in your Python environment are installed correctly and are compatible.")
        return None


def scan_locale_directories_for_image_type(image_type_dir_path):
    """
    Scans locale subdirectories (e.g., en_US, zh_CN) within a specific screenshot type directory,
    groups and sorts screenshots based on the filename convention.

    :param image_type_dir_path: Path to the directory for a specific image type (e.g., .../phoneScreenshots)
    :return: A dictionary where keys are source locale strings (e.g., "en_US")
             and values are lists of sorted image info dicts [{'path':..., 'filename':..., 'sequence':...}].
             Returns an empty dict if the directory doesn't exist or no valid locales/images are found.
    """
    print(f"\n--- Starting scan for Locale directories inside screenshot type directory ---")
    print(f"Screenshot Type Directory: {image_type_dir_path}")
    screenshots_by_source_locale = defaultdict(list)
    supported_extensions = ('.png', '.jpg', '.jpeg')
    # Optimized regex: explicitly match file extensions, avoid capturing the dot
    filename_pattern = re.compile(r"^([a-z]{2,3}_[A-Z]{2})_(\d+)_.*\.(" + "|".join(ext.lstrip('.') for ext in supported_extensions) + ")$", re.IGNORECASE)

    # Check if the image type directory exists first
    if not os.path.isdir(image_type_dir_path):
        print(f"Warning: Screenshot type directory '{image_type_dir_path}' does not exist or is not a directory. Skipping scan.")
        return {} # Return empty dict indicating nothing found for this type

    try:
        # List entries within the image_type_dir_path that are directories
        all_entries = [d for d in os.listdir(image_type_dir_path) if os.path.isdir(os.path.join(image_type_dir_path, d))]
         # Filter out hidden directories and sort
        valid_subdirs = sorted([d for d in all_entries if not d.startswith('.')])
        print(f"Found potential Locale subdirectories (alphabetical): {valid_subdirs}")
        if not valid_subdirs:
             print(f"Warning: No valid Locale subdirectories found under '{os.path.basename(image_type_dir_path)}'.")
             return {} # Return empty dict

    except Exception as e:
        print(f"✗ Error: Failed to scan directory '{image_type_dir_path}': {e}")
        return {}

    for locale_dir_name in valid_subdirs:
         # Check if it looks like a Locale directory (xx_YY or xxx_YY)
        if not re.fullmatch(r"[a-z]{2,3}_[A-Z]{2}", locale_dir_name):
            print(f"  - Ignoring directory (name doesn't fully match Locale format xx_YY or xxx_YY): {locale_dir_name}")
            continue

        print(f"\n  Scanning Locale subdirectory: {locale_dir_name}")
        # Construct full path to the current locale directory
        current_locale_path = os.path.join(image_type_dir_path, locale_dir_name)
        found_files = []
        # Search for files with supported extensions (case-insensitive)
        for ext in supported_extensions:
            found_files.extend(glob.glob(os.path.join(current_locale_path, f"*{ext}")))
            found_files.extend(glob.glob(os.path.join(current_locale_path, f"*{ext.upper()}")))

        # Remove duplicates and sort (mainly for consistent logging)
        found_files = sorted(list(set(found_files)))

        if not found_files:
            print(f"  ! No image files ({', '.join(supported_extensions)}) found in this Locale directory.")
            continue # Move to the next locale directory

        image_list = []
        for filepath in found_files:
            filename = os.path.basename(filepath)
            match = filename_pattern.match(filename)
            if match:
                file_locale, sequence_str, _ = match.groups()
                # Compare locale from filename with directory name (case-insensitive for robustness)
                if file_locale.lower() != locale_dir_name.lower():
                    print(f"  ! Warning: Locale in filename '{file_locale}' does not match directory name '{locale_dir_name}' (case-insensitive). Skipping file: {filename}")
                    continue
                try:
                    sequence = int(sequence_str)
                    # Final check if it's actually a file
                    if os.path.isfile(filepath):
                         image_list.append({'path': filepath, 'filename': filename, 'sequence': sequence})
                    else:
                         print(f"  ! Warning: Path '{filepath}' is not a valid file. Skipping.")
                except ValueError:
                    print(f"  ! Warning: Could not extract a valid sequence number from filename '{filename}'. Skipping this file.")
            else:
                print(f"  - Ignoring file (name does not match <locale>_<number>_*.ext format): {filename}")

        if image_list:
            # Sort images by sequence number
            image_list.sort(key=lambda x: x['sequence'])
            # Limit to a maximum of 8 screenshots per Google Play policy
            if len(image_list) > 8:
                print(f"  ! Warning: Found more than 8 valid screenshots. Only the first 8 will be used.")
                image_list = image_list[:8]

            # Store the sorted list for this source locale
            screenshots_by_source_locale[locale_dir_name] = image_list
            print(f"  ✓ Found and sorted screenshots ({len(image_list)} images): {[item['filename'] for item in image_list]}")
        else:
             print(f"  ! No images matching the required naming convention found in this Locale directory.")

    if not screenshots_by_source_locale:
         print(f"\n! No valid screenshots found in any Locale subdirectory of '{os.path.basename(image_type_dir_path)}'.")

    print(f"--- Scan completed for Locale directories within '{os.path.basename(image_type_dir_path)}' ---")
    return screenshots_by_source_locale


def display_summary(summary_data, total_duration):
    """Formats and prints the upload results summary table."""
    print("\n\n========================= Upload Results Summary =========================")
    if not summary_data:
        print("No screenshot types/locales were processed for upload.")
        print(f"Total script execution time: {total_duration:.2f} seconds")
        print("==========================================================================")
        return

    # Define table headers and separator line
    header = "| {:<20} | {:<15} | {:<15} | {:<17} | {:<10} | {:<8} | {:<10} |".format(
        "Image Type", "Target Lang", "Source Dir", "Status", "Uploaded", "Expected", "Time (s)"
    )
    separator = "+" + "-" * 22 + "+" + "-" * 17 + "+" + "-" * 17 + "+" + "-" * 19 + "+" + "-" * 12 + "+" + "-" * 10 + "+" + "-" * 12 + "+"

    print(separator)
    print(header)
    print(separator)

    # Initialize counters for overall statistics
    total_success_locales, total_partial_locales, total_failed_locales, total_skipped_locales = 0, 0, 0, 0
    total_images_uploaded, total_images_expected = 0, 0

    # Sort summary data primarily by image_type, then by target_locale for readability
    for entry in sorted(summary_data, key=lambda x: (x.get('image_type', 'N/A'), x.get('target_locale', 'N/A'))):
        status_icon = ""
        status_text = entry.get('status', 'Unknown')
        if status_text == 'Success': status_icon = "✓ "; total_success_locales += 1
        elif status_text == 'Partial Failure': status_icon = "! "; total_partial_locales += 1
        elif status_text == 'Failure': status_icon = "✗ "; total_failed_locales += 1
        elif status_text == 'Skipped': status_icon = "- "; total_skipped_locales += 1
        else: status_icon = "? " # Handle unexpected status

        # Extract data from the summary entry, providing defaults
        image_type = entry.get('image_type', 'N/A')
        target_locale = entry.get('target_locale', 'N/A')
        source_locale = entry.get('source_locale', 'N/A')
        images_uploaded = entry.get('images_uploaded', 0)
        # 'images_expected' reflects files *found* in the source dir matching the pattern
        images_expected = entry.get('images_expected', 0)
        duration_seconds = entry.get('duration_seconds', 0.0)

        # Format status with icon, ensuring fixed width
        formatted_status = (status_icon + status_text)[:17].ljust(17)

        # Format the row string for the table
        row = "| {:<20} | {:<15} | {:<15} | {:<17} | {:<10} | {:<8} | {:<10.2f} |".format(
            image_type, target_locale, source_locale, formatted_status,
            images_uploaded, images_expected, duration_seconds
        )
        print(row)

        # Accumulate totals
        total_images_uploaded += images_uploaded
        total_images_expected += images_expected

        # Display error message if present, indented under the row
        error_message = entry.get('error_message')
        if error_message:
            # Indent error message for clarity
            # Truncate long messages
            error_display = f"  └─ Error: {error_message[:150]}"
            if len(error_message) > 150: error_display += "..."
            # Print the error message, attempting rough alignment
            print(error_display.rjust(len(separator) + 10)) # Adjust indentation as needed

    print(separator)
    print("\n--- Overall Statistics ---")
    print(f"Total Image Type/Language combinations processed: {len(summary_data)}")
    print(f"  ✓ Fully Successful:  {total_success_locales}")
    print(f"  ! Partial Failures:  {total_partial_locales}")
    print(f"  ✗ Full Failures:     {total_failed_locales}")
    print(f"  - Skipped:           {total_skipped_locales}")
    print(f"Total images uploaded: {total_images_uploaded} / {total_images_expected} (Successful / Expected based on found files)")

    # Format total duration
    total_seconds = round(total_duration)
    total_duration_formatted = str(datetime.timedelta(seconds=total_seconds)) # HH:MM:SS format
    print(f"Total script execution time: {total_duration:.2f} seconds (~{total_duration_formatted})")
    print("==========================================================================")


def upload_screenshots(service, package_name, parent_dir):
    """
    Scans supported screenshot type directories, then their locale subdirectories,
    uploads screenshots to Google Play Console based on locale mapping, saves as draft,
    and finally displays a summary.
    """
    script_start_time = time.time()
    upload_summary = [] # List to store results for each locale/type
    overall_success = True # Track if any part of the process failed critically
    edit_id = None
    final_edit_status = "Unknown" # Track the final state of the Play Console edit

    if not service:
        print("✗ Service not authenticated. Cannot proceed with upload.")
        # Display empty summary with time taken so far
        display_summary(upload_summary, time.time() - script_start_time)
        return

    try:
        # 1. Create a new Edit session in Google Play Console
        print("\n--- Starting: Create Play Console Edit Session ---")
        edit_request = service.edits().insert(packageName=package_name, body={})
        result = edit_request.execute()
        edit_id = result['id']
        print(f"✓ Edit session created successfully. Edit ID: {edit_id}")

        # --- Outer loop: Iterate through supported image types ---
        print(f"\n--- Processing Screenshot Types (Order: {SUPPORTED_IMAGE_TYPES}) ---")
        for current_image_type in SUPPORTED_IMAGE_TYPES:
            print(f"\n==================== Processing Image Type: {current_image_type} ====================")
            image_type_dir_path = os.path.join(parent_dir, current_image_type)

            # --- Scan for locale directories *within* the current image type directory ---
            screenshots_data = scan_locale_directories_for_image_type(image_type_dir_path)

            if not screenshots_data:
                print(f"No valid locale directories or screenshots found in '{image_type_dir_path}'. Skipping this image type.")
                # Optionally, add a 'skipped type' entry to summary if needed
                # upload_summary.append({ 'image_type': current_image_type, 'status': 'Skipped', 'reason': 'No local data found', ... })
                continue # Move to the next image type in SUPPORTED_IMAGE_TYPES

            # Track target locales processed *for this specific image type* to avoid duplicates if mappings overlap
            processed_target_locales_for_type = set()

            # --- Inner loop 1: Iterate through SOURCE locales found for this image type ---
            print(f"\n--- Uploading '{current_image_type}' Screenshots (Sorted by source locale dir) ---")
            for source_locale, images in sorted(screenshots_data.items()):
                print(f"\n>>> Processing Source Locale Directory: {source_locale} (for type '{current_image_type}')")
                # Number of images found and validated for this source locale/type
                locale_images_expected = len(images)
                # Find the target Google Play locales to upload these images to
                target_locales = LOCALE_MAPPING.get(source_locale)

                if not target_locales:
                    print(f"  ! Warning: No mapping found for source locale '{source_locale}' in LOCALE_MAPPING. Skipping this source locale.")
                    # Add a skipped entry to the summary for this source locale
                    upload_summary.append({
                        'image_type': current_image_type,
                        'target_locale': 'N/A', 'source_locale': source_locale,
                        'status': 'Skipped', 'error_message': 'No mapping found in LOCALE_MAPPING',
                        'images_expected': locale_images_expected, 'images_uploaded': 0,
                        'duration_seconds': 0.0
                    })
                    continue # Move to the next source locale

                print(f"  > Source Locale '{source_locale}' ({locale_images_expected} images found) will be uploaded to Target Language(s): {target_locales} (as type '{current_image_type}')")

                # --- Inner loop 2: Iterate through TARGET locales for the current source locale ---
                for target_locale in target_locales:
                    locale_start_time = time.time()
                    locale_status = 'Pending' # Initial status for this target locale/type combo
                    locale_error = None
                    locale_success_count = 0 # Images successfully uploaded for this target/type
                    locale_delete_failed = False # Flag if clearing existing images failed

                    # Prepare summary entry structure
                    summary_entry = {
                        'image_type': current_image_type,
                        'target_locale': target_locale, 'source_locale': source_locale,
                        'images_expected': locale_images_expected, 'images_uploaded': 0,
                        'status': locale_status, 'error_message': None,
                        'duration_seconds': 0.0
                    }

                    # Check if this target locale was already processed *for this image type* by another source locale mapping to it.
                    # This prevents overwriting if multiple sources map to the same target for the same type.
                    # The behavior is to process the first source locale encountered (due to sorting) for a given target/type.
                    if target_locale in processed_target_locales_for_type:
                          print(f"  - Target Language '{target_locale}' (type '{current_image_type}') already processed by another source dir for this type. Skipping duplicate processing.")
                          summary_entry['status'] = 'Skipped'
                          summary_entry['error_message'] = 'Already processed by another source for this type'
                          upload_summary.append(summary_entry)
                          continue # Move to the next target locale

                    print(f"\n  --> Updating Target Language: {target_locale} (Type: {current_image_type})")

                    try:
                        # 2a. Clear existing screenshots for this language AND imageType
                        print(f"      > Clearing existing '{current_image_type}' screenshots for target language '{target_locale}'...")
                        service.edits().images().deleteall(
                            packageName=package_name,
                            editId=edit_id,
                            language=target_locale,
                            imageType=current_image_type # Specify the image type to delete
                        ).execute()
                        print(f"      ✓ Existing '{target_locale}' / '{current_image_type}' screenshots cleared.")
                        time.sleep(1) # Brief pause after delete, might help prevent race conditions

                    except googleapiclient.errors.HttpError as e:
                        error_detail = str(e)
                        # 404 (Not Found) is often acceptable here - means nothing existed to delete.
                        if e.resp.status == 404:
                            print(f"      - No existing resources found to clear for '{target_locale}' / '{current_image_type}' (This is usually OK).")
                        # 400 (Bad Request) might indicate the language/type combination is invalid or not set up in Play Console.
                        elif e.resp.status == 400:
                             print(f"      ! Error clearing '{target_locale}' / '{current_image_type}' screenshots (400 Bad Request): {error_detail}")
                             print(f"      ! Possible reasons: Language '{target_locale}' might not exist in Play Console, type not supported/enabled, or permission issues.")
                             locale_status = 'Failure'
                             locale_error = f"Delete failed (400): {error_detail}"
                             locale_delete_failed = True
                             overall_success = False # Mark overall script as potentially failed
                        else:
                            # Other HTTP errors during delete are likely problems.
                            print(f"      ! Unknown HTTP error while clearing '{target_locale}' / '{current_image_type}' screenshots: {error_detail}")
                            locale_status = 'Failure'
                            locale_error = f"Delete failed ({e.resp.status}): {error_detail}"
                            locale_delete_failed = True
                            overall_success = False # Mark overall script as potentially failed
                    except Exception as e:
                        # Catch non-HTTP errors during delete
                        print(f"      ! Unexpected error while clearing '{target_locale}' / '{current_image_type}' screenshots: {e}")
                        locale_status = 'Failure'
                        locale_error = f"Delete failed (Non-HTTP): {e}"
                        locale_delete_failed = True
                        overall_success = False # Mark overall script as potentially failed

                    # 2b. Upload new screenshots IF delete was successful (or returned 404)
                    if not locale_delete_failed:
                        print(f"      > Starting upload of {locale_images_expected} new screenshot(s) to '{target_locale}' / '{current_image_type}' (from source '{source_locale}')...")
                        upload_index = 0 # Use index for numbering uploads
                        critical_upload_error_occurred = False # Stop uploading for this locale/type on first critical error

                        for image_info in images:
                            upload_index += 1
                            filepath = image_info['path']
                            filename = image_info['filename']
                            print(f"        {upload_index}. Uploading: {filename} ...", end="")

                            # Guess MIME type for the upload
                            mime_type, _ = mimetypes.guess_type(filepath)
                            if not mime_type or not mime_type.startswith('image/'):
                                print(f" [Skipped - Invalid MIME type: {mime_type or 'Unknown'}]")
                                # Mark as partial failure if not already failed
                                if locale_status not in ['Failure', 'Partial Failure']:
                                    locale_status = 'Partial Failure'
                                if not locale_error: # Keep first error message
                                     locale_error = f"Skipped {filename} (Invalid MIME type: {mime_type or 'Unknown'})"
                                overall_success = False # Invalid file found is a partial failure overall
                                continue # Skip this file, try next

                            try:
                                # Prepare media payload
                                media = MediaFileUpload(filepath, mimetype=mime_type, resumable=False) # Resumable=False is often faster for small files
                                # Execute the upload API call
                                upload_result = service.edits().images().upload(
                                    packageName=package_name,
                                    editId=edit_id,
                                    language=target_locale,
                                    imageType=current_image_type, # Specify the image type for upload
                                    media_body=media
                                ).execute()
                                # Check response, although a successful execute() usually means it worked
                                image_id = upload_result.get('image', {}).get('id', 'N/A') # Get uploaded image ID if available
                                print(f" [Success - ID: {image_id}]")
                                locale_success_count += 1
                                time.sleep(0.5) # Brief pause between uploads

                            except googleapiclient.errors.HttpError as e:
                                error_detail = str(e)
                                print(f" [Failed: {error_detail}]")
                                # Mark as partial failure if not already failed
                                if locale_status not in ['Failure', 'Partial Failure']:
                                     locale_status = 'Partial Failure'
                                if not locale_error: # Keep first error message
                                     locale_error = f"Upload failed for {filename}: {error_detail}"
                                critical_upload_error_occurred = True # Treat HTTP errors as critical for this batch
                                overall_success = False # Mark overall script as potentially failed
                                break # Stop uploading further images for THIS locale/type on error

                            except Exception as e:
                                # Catch non-HTTP errors during upload (e.g., file read error)
                                print(f" [Failed (Non-HTTP): {e}]")
                                if locale_status not in ['Failure', 'Partial Failure']:
                                     locale_status = 'Partial Failure'
                                if not locale_error: # Keep first error message
                                     locale_error = f"Upload failed for {filename} (Non-HTTP): {e}"
                                critical_upload_error_occurred = True
                                overall_success = False # Mark overall script as potentially failed
                                break # Stop uploading further images for THIS locale/type on error

                        # After attempting all uploads for this locale/type
                        print(f"      ✓ Upload attempts for '{target_locale}' / '{current_image_type}' finished: {locale_success_count}/{locale_images_expected} successful.")
                        # Determine final status for this locale/type based on upload results
                        if locale_success_count == locale_images_expected:
                             # Only mark as Success if it wasn't already marked as partial/failure (e.g., by MIME type skip)
                             if locale_status == 'Pending':
                                 locale_status = 'Success'
                        elif locale_success_count > 0:
                            locale_status = 'Partial Failure'
                            if not locale_error: locale_error = "Not all images uploaded successfully"
                        else: # locale_success_count == 0
                            locale_status = 'Failure'
                            if not locale_error: locale_error = "All image uploads failed or were skipped"
                            # Ensure overall success reflects this failure if no images were uploaded
                            overall_success = False

                    else: # Delete failed earlier, so skip uploads
                        locale_status = 'Failure' # Status remains Failure from the delete attempt
                        print(f"      ! Skipping upload for '{target_locale}' / '{current_image_type}' because clearing existing screenshots failed.")
                        # overall_success is already False from the delete failure

                    # Mark this target locale as processed *for this image type*
                    processed_target_locales_for_type.add(target_locale)

                    # Update the summary entry with final status, counts, error, and time
                    summary_entry['status'] = locale_status
                    summary_entry['images_uploaded'] = locale_success_count
                    summary_entry['error_message'] = str(locale_error) if locale_error else None
                    summary_entry['duration_seconds'] = time.time() - locale_start_time
                    upload_summary.append(summary_entry)

                # End of loop for target_locales
            # End of loop for source_locales within an image_type
        # End of loop for image_types

        # --- Finalizing the Edit ---
        if not overall_success:
            print("\n! Errors or partial failures were detected during the process.")
            print("! The edit will be validated, but likely NOT automatically committed.")

        # 3. Validate the entire Edit
        print("\n--- Starting: Validate Edit ---")
        try:
            service.edits().validate(packageName=package_name, editId=edit_id).execute()
            print(f"✓ Edit validation successful (Edit ID: {edit_id}).")
            final_edit_status = "Validated"

            # 4. Commit the Edit ONLY if validation passed AND no critical errors occurred
            # Adjust this logic if you want to commit even with partial failures.
            if overall_success:
                print("\n--- Starting: Commit Edit ---")
                try:
                    service.edits().commit(packageName=package_name, editId=edit_id).execute()
                    print(f"✓ Edit committed successfully (Edit ID: {edit_id}). Changes are now in the publishing pipeline.")
                    final_edit_status = "Committed"
                    print("\n**********************************************************************")
                    print(f" Operation Completed Successfully! Edit ID: {edit_id}")
                    print(" Screenshots uploaded and changes committed.")
                    print(" Please check the Play Console for publishing status later.")
                    print("**********************************************************************")
                except googleapiclient.errors.HttpError as commit_e:
                    error_detail = str(commit_e)
                    print(f"✗ Edit Commit Failed: {error_detail}")
                    final_edit_status = "Commit Failed"
                    print(f"! Edit ID: {edit_id}")
                    print("! Validation was successful, but committing the edit failed.")
                    print("! Changes remain in a draft state. Please log in to Play Console to handle manually.")
                except Exception as commit_e:
                    print(f"✗ Unexpected error during Edit Commit: {commit_e}")
                    final_edit_status = "Commit Error"
                    # Handle similarly to HttpError
                    print(f"! Edit ID: {edit_id}. Changes likely remain in draft.")
            else:
                 print("\n! Due to errors detected during processing, the edit was validated but NOT automatically committed.")
                 print(f"! Edit ID: {edit_id}")
                 print("! Please log in to the Play Console, review the draft changes, and manually commit or discard the edit.")
                 final_edit_status = "Validated (Not Committed due to errors)"

        except googleapiclient.errors.HttpError as e:
            error_detail = str(e)
            print(f"✗ Edit Validation Failed: {error_detail}")
            final_edit_status = "Validation Failed"
            print(f"! Edit ID: {edit_id}")
            print("! Uploaded changes have been saved as a draft, but validation found issues.")
            print("! It is CRITICAL to log in to the Play Console, review the draft, and fix errors manually.")
            overall_success = False # Ensure overall status reflects validation failure
        except Exception as e:
            print(f"✗ Unexpected error during Edit Validation: {e}")
            final_edit_status = "Validation Error"
            # Handle similarly to HttpError
            print(f"! Edit ID: {edit_id}. Draft status is uncertain. Please check Play Console.")
            overall_success = False

    except Exception as e:
        # Catch top-level errors (e.g., edit creation failed, unexpected issues in loops)
        print(f"\n✗ A critical error occurred during the operation: {e}")
        import traceback
        traceback.print_exc()
        final_edit_status = "Critical Error"
        overall_success = False # Mark overall failure
        # Attempt to clean up the edit if one was created
        if edit_id:
            print(f"\n>>> Attempting to cancel/delete the incomplete Edit Session ID: {edit_id} ...")
            try:
                service.edits().delete(packageName=package_name, editId=edit_id).execute()
                print(f"✓ Edit session {edit_id} cancelled/deleted.")
                final_edit_status = "Critical Error (Edit Deleted)"
            except Exception as cancel_e:
                print(f"! Failed to cancel/delete edit session {edit_id}: {cancel_e}")
                print(f"! You may need to manually handle the draft with Edit ID: {edit_id} in the Play Console.")
                final_edit_status = "Critical Error (Delete Failed)"
        else:
            print("No edit session was successfully created.")
            final_edit_status = "Critical Error (No Edit ID)"

    finally:
        # Always display the summary at the end
        script_end_time = time.time()
        total_duration = script_end_time - script_start_time
        print(f"\n--- Final Edit Status: {final_edit_status} ---")
        display_summary(upload_summary, total_duration)

# --- Main Program Execution ---
if __name__ == '__main__':
    print("=================================================================")
    print(" Google Play Console Screenshot Upload Script (Multi-Type Support)") # Updated title
    print("=================================================================")
    print(f"Application Package Name (PACKAGE_NAME):   {PACKAGE_NAME}")
    # Show the absolute path for clarity
    print(f"Screenshot Parent Directory (IMAGE_PARENT_DIR): {os.path.abspath(IMAGE_PARENT_DIR)}")
    print(f"Processing Screenshot Type Subdirs:        {SUPPORTED_IMAGE_TYPES}")
    print(f"Service Account Key (SERVICE_ACCOUNT_FILE): {os.path.abspath(SERVICE_ACCOUNT_FILE)}")
    if PROXY_ENABLED:
        print(f"Proxy Settings (PROXY):                    Enabled - {PROXY_ADDRESS}")
    else:
        print(f"Proxy Settings (PROXY):                    Disabled")
    print("-----------------------------------------------------------------")
    print("Starting process. Please ensure the configuration and directory structure are correct!")
    # Optional pause before starting
    # input("Press Enter to continue, or Ctrl+C to cancel...")
    print("-----------------------------------------------------------------")

    # 1. Authenticate and get the API service object
    google_service = authenticate()

    # 2. If authentication successful, proceed with scanning and uploading
    if google_service:
        # Call the main upload function which handles multiple types
        upload_screenshots(google_service, PACKAGE_NAME, IMAGE_PARENT_DIR)
    else:
        # Authentication failed, message already printed in authenticate()
        print("\nAuthentication or service build failed. Cannot proceed with upload operations.")
        print("Please review the error messages above.")

    print("\nScript execution finished.")
