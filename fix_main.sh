#!/bin/bash

WRONG=~/Documents/Personal-Github/neurotrap/android/app/src/main/kotlin/com/neurotrap/neurotrap/MainActivity.kt
RIGHT_DIR=~/Documents/Personal-Github/neurotrap/android/app/src/main/kotlin/com/neurotrap/ids
RIGHT=$RIGHT_DIR/MainActivity.kt

if [ -f "$WRONG" ]; then
  echo "🔧 Fixing MainActivity location..."
  mkdir -p "$RIGHT_DIR"
  mv "$WRONG" "$RIGHT"
  sed -i '' 's/package com.neurotrap.neurotrap/package com.neurotrap.ids/' "$RIGHT"
  rm -rf ~/Documents/Personal-Github/neurotrap/android/app/src/main/kotlin/com/neurotrap/neurotrap
  echo "✅ Fixed!"
else
  echo "✅ MainActivity already in correct location"
fi
