#!/bin/bash

set -u
set -e

echo -e "\033[0;32mDeploying updates to GitHub...\033[0m"

# Build the project.
hugo -t after-dark # if using a theme, replace by `hugo -t <yourtheme>`

# Go To Public folder
cd public
# Add changes to git.
git add -A
git rm -f videos/after-dark_720p.mp4 || true

# Commit changes.
msg="rebuilding site `date`"
if [ $# -eq 1 ]
  then msg="$1"
fi
git commit -m "$msg"

# Push source and build repos.
git push origin master

# Come Back
cd ..
