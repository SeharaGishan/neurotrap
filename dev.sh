#!/bin/bash
set -e

echo "🔧 Checking MainActivity..."
~/Documents/Personal-Github/neurotrap/fix_main.sh

echo "🚀 Running NeuroTrap..."
cd ~/Documents/Personal-Github/neurotrap
flutter run -d R5CX831PZXH
