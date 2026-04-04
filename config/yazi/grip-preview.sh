#!/bin/zsh
# Preview Markdown file with grip in browser
file="$1"
[[ -z "$file" ]] && exit 1

# Kill existing grip processes
pkill -f "grip" 2>/dev/null
sleep 0.3

# Start grip server (port 6419 is grip's default)
grip "$file" 0 &
sleep 0.8

# Open in default browser
open "http://localhost:6419"
