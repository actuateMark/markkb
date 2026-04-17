#!/bin/bash
# Staleness Check Script
# Identifies notes older than 30 days in the knowledgebase

# Find all `.md` files with `updated:` timestamps
find /home/mork/Documents/worklog/knowledgebase -type f -name "*.md" -exec grep -l 'updated:' {} \; | \n  xargs -I {} sh -c 'echo "{}"; grep -o 'updated:[^ ]*' {} | cut -d":" -f2 | awk -F"-" '{print $1}' | \n  grep -E '2023-0[4-9]|2023-1[0-2]' | wc -l