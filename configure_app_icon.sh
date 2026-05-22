#!/bin/bash

# Configuration
INPUT_IMAGE="/Users/teknopark/.gemini/antigravity/brain/32983e51-047f-4293-951a-af412c7d6bcd/faceless_app_icon_1779493948320.png"
APP_ICON_SET_DIR="/Users/teknopark/Desktop/mobil/1- appstore/4- Faceless Reels Generator/Faceless/Resources/Assets.xcassets/AppIcon.appiconset"
OUTPUT_IMAGE="$APP_ICON_SET_DIR/AppIcon.png"
CONTENTS_JSON="$APP_ICON_SET_DIR/Contents.json"

echo "Resizing image to 1024x1024 and converting to PNG..."
mkdir -p "$APP_ICON_SET_DIR"
sips -z 1024 1024 "$INPUT_IMAGE" --out "$OUTPUT_IMAGE"

echo "Updating Contents.json..."
cat <<EOF > "$CONTENTS_JSON"
{
  "images" : [
    {
      "filename" : "AppIcon.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

echo "App Icon configuration complete!"
