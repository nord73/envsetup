#!/bin/bash
# scripts/test_app_detection.sh
# Test script to verify macOS app detection logic

set -e

echo "=== macOS App Detection Test ==="
echo

# Create temporary test environment
TEST_HOME="/tmp/test_app_detection_$$"
mkdir -p "$TEST_HOME/Applications"

cleanup() {
  rm -rf "$TEST_HOME"
}
trap cleanup EXIT

# Test 1: Detect app in user directory
echo "Test 1: Detecting app in ~/Applications"
touch "$TEST_HOME/Applications/Visual Studio Code.app"

app_display_name="Visual Studio Code"
app_name="visual-studio-code"

app_in_user_dir=false
for pattern in "$app_display_name" "$(echo "$app_display_name" | sed 's/-/ /g')" "$(echo "$app_name" | sed 's/-/ /g')"; do
  if find "$TEST_HOME/Applications" -maxdepth 1 -iname "*${pattern}*.app" 2>/dev/null | grep -q .; then
    app_in_user_dir=true
    break
  fi
done

if [ "$app_in_user_dir" = true ]; then
  echo "   ✓ Test 1 passed: App detected in user directory"
else
  echo "   ✗ Test 1 failed: App not detected in user directory"
  exit 1
fi

# Test 2: App doesn't exist
echo "Test 2: App not present"
rm -f "$TEST_HOME/Applications/Visual Studio Code.app"

app_in_user_dir=false
for pattern in "$app_display_name" "$(echo "$app_display_name" | sed 's/-/ /g')" "$(echo "$app_name" | sed 's/-/ /g')"; do
  if find "$TEST_HOME/Applications" -maxdepth 1 -iname "*${pattern}*.app" 2>/dev/null | grep -q .; then
    app_in_user_dir=true
    break
  fi
done

if [ "$app_in_user_dir" = false ]; then
  echo "   ✓ Test 2 passed: App correctly not detected when absent"
else
  echo "   ✗ Test 2 failed: False positive detection"
  exit 1
fi

# Test 3: Case-insensitive detection
echo "Test 3: Case-insensitive detection"
touch "$TEST_HOME/Applications/visual studio code.app"

app_in_user_dir=false
for pattern in "$app_display_name" "$(echo "$app_display_name" | sed 's/-/ /g')" "$(echo "$app_name" | sed 's/-/ /g')"; do
  if find "$TEST_HOME/Applications" -maxdepth 1 -iname "*${pattern}*.app" 2>/dev/null | grep -q .; then
    app_in_user_dir=true
    break
  fi
done

if [ "$app_in_user_dir" = true ]; then
  echo "   ✓ Test 3 passed: Case-insensitive detection works"
else
  echo "   ✗ Test 3 failed: Case-insensitive detection doesn't work"
  exit 1
fi

# Test 4: Detect app with hyphenated name (Brave Browser)
echo "Test 4: Detecting Brave Browser"
rm -f "$TEST_HOME/Applications/visual studio code.app"
touch "$TEST_HOME/Applications/Brave Browser.app"

app_display_name="Brave Browser"
app_name="brave-browser"

app_in_user_dir=false
for pattern in "$app_display_name" "$(echo "$app_display_name" | sed 's/-/ /g')" "$(echo "$app_name" | sed 's/-/ /g')"; do
  if find "$TEST_HOME/Applications" -maxdepth 1 -iname "*${pattern}*.app" 2>/dev/null | grep -q .; then
    app_in_user_dir=true
    break
  fi
done

if [ "$app_in_user_dir" = true ]; then
  echo "   ✓ Test 4 passed: Brave Browser detected correctly"
else
  echo "   ✗ Test 4 failed: Brave Browser not detected"
  exit 1
fi

# Test 5: Testing uninstall script app bundle finding logic
echo "Test 5: Testing uninstall app bundle detection"

# Simulate finding app in user dir
mkdir -p "$TEST_HOME/Applications" "/tmp/test_system_apps_$$"
touch "$TEST_HOME/Applications/Google Chrome.app"

APP_NAME="google-chrome"
APP_DISPLAY_NAME="Google Chrome"

# Find the .app bundle in ~/Applications or /Applications
APP_BUNDLE=$(find "$TEST_HOME/Applications" -maxdepth 1 \( -iname "*${APP_DISPLAY_NAME}*.app" -o -iname "*${APP_NAME}*.app" \) 2>/dev/null | head -1)

if [ -z "$APP_BUNDLE" ]; then
  # Check system Applications directory
  APP_BUNDLE=$(find "/tmp/test_system_apps_$$" -maxdepth 1 \( -iname "*${APP_DISPLAY_NAME}*.app" -o -iname "*${APP_NAME}*.app" \) 2>/dev/null | head -1)
fi

if [ -n "$APP_BUNDLE" ] && [[ "$APP_BUNDLE" == "$TEST_HOME/Applications/"* ]]; then
  echo "   ✓ Test 5 passed: App found in user directory"
else
  echo "   ✗ Test 5 failed: App not found or in wrong location"
  exit 1
fi

# Test 6: Testing system app detection
echo "Test 6: Testing system app directory detection"
rm -f "$TEST_HOME/Applications/Google Chrome.app"
touch "/tmp/test_system_apps_$$/Google Chrome.app"

APP_BUNDLE=$(find "$TEST_HOME/Applications" -maxdepth 1 \( -iname "*${APP_DISPLAY_NAME}*.app" -o -iname "*${APP_NAME}*.app" \) 2>/dev/null | head -1)

if [ -z "$APP_BUNDLE" ]; then
  # Check system Applications directory
  APP_BUNDLE=$(find "/tmp/test_system_apps_$$" -maxdepth 1 \( -iname "*${APP_DISPLAY_NAME}*.app" -o -iname "*${APP_NAME}*.app" \) 2>/dev/null | head -1)
fi

if [ -n "$APP_BUNDLE" ] && [[ "$APP_BUNDLE" == "/tmp/test_system_apps_$$/"* ]]; then
  echo "   ✓ Test 6 passed: App found in system directory"
else
  echo "   ✗ Test 6 failed: App not found in system directory"
  exit 1
fi

# Cleanup system test directory
rm -rf "/tmp/test_system_apps_$$"

echo
echo "=== All Tests Passed ==="
echo "App detection logic is working correctly!"
