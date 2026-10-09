VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "Release/LuLu_Plus.app/Contents/Info.plist")

printf "\nCreating LuLu_Plus Disk Image...\n\n"

#remove any old ones
rm -f LuLu_Plus_*.dmg

create-dmg \
  --volname "LuLu_Plus v$VERSION" \
  --volicon "LuLu_Plus.icns" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 100 \
  --icon "LuLu_Plus.app" 200 190 \
  --hide-extension "LuLu_Plus.app" \
  --app-drop-link 600 190 \
  "LuLu_Plus_$VERSION.dmg" \
  "Release/"

printf "\nCode signing dmg...\n"

#the identity belongs to whoever builds this, so it comes from the environment, not from this file
if [ -z "$SIGN_IDENTITY" ]; then
    printf "ERROR: set SIGN_IDENTITY to the identity this build is signed with\n"
    printf "       (list the ones this machine has: security find-identity -v -p codesigning)\n"
    exit 1
fi

#code sign
codesign --force --sign "$SIGN_IDENTITY" "LuLu_Plus_$VERSION.dmg"

printf "Done!\n"
