#!/bin/bash

set -Eeuo pipefail
shopt -s extglob

PROJECT=`find . -name "*.xcodeproj" -maxdepth 1 | head -n 1`
SHARED_DATA="$PROJECT/xcshareddata"
TEMPLATE_FILE="$SHARED_DATA/IDETemplateMacros.plist"

move_configs() {
  echo "- move xcconfigs one lvl up"

  mkdir -p "Supporting Files"
  find "Application/Supporting Files/" -name "*.xcconfig" -exec git mv '{}' "Supporting Files/" \;
}

fix_gemfile() {
  echo "- modify Gemfile (replace rome with alexandria)"

  sed -i '' "s/gem .cocoapods-rome.*/gem 'cocoapods-alexandria', '~> 0.1'/g" Gemfile
  if grep -q "gem .cocoapods.*1.\\d\\..*" Gemfile; then
    sed -i '' "s/gem .cocoapods.,.*/gem 'cocoapods', '~> 1.10.0'/g" Gemfile
  fi
  bundler install --quiet
}

fix_podfile() {
  echo "- modify Podfile"

  if grep -qi "rome" Podfile; then
    echo "ℹ️  Removing the Rome plugin from your Podfile, please check we didn't remove too much!"
  fi

  sed -i '' -e ':a' -e 'N' -e '$!ba' \
    -e 's/raise .Please.*Bundler.\n//g' \
    -e 's/# Pre-compile pods\n//g' Podfile
  sed -i '' "/platform :ios.*/ a\\
inhibit_all_warnings!\\
ensure_bundler! '> 2.0'\\
plugin 'cocoapods-alexandria'\\
" Podfile

  if grep -qi "post_install" Podfile; then
    echo "ℹ️  It seems like your Podfile already contains a 'post_install' hook. We've tried adding the copy acknowledgements step, but please verify everything is correct!"
    
    TARGET_NAME=`cat Podfile | grep -Ei "target .(.*)." | head -n 1 | cut -d " " -f 2 | cut -c 2- | rev | cut -c 2- | rev`
    sed -i '' -e ':a' -e 'N' -e '$!ba' \
      -e "s/plugin .cocoapods-rome.*//g" Podfile
    sed -i '' "/post_install .*/ a\\
  require 'fileutils'\\
  FileUtils.cp_r('Pods/Target Support Files/Pods-${TARGET_NAME}/Pods-${TARGET_NAME}-Acknowledgements.plist', 'Application/Resources/Settings.bundle/Acknowledgements.plist', :remove_destination => true)\\
\\
" Podfile
  else
    sed -i '' -e ':a' -e 'N' -e '$!ba' \
      -e "s/plugin .cocoapods-rome.*\(FileUtils.cp_r.*remove_destination => true.\).*/post_install do |installer|\\
  require 'fileutils'\\
  \1\\
end/g" Podfile
  fi

  if grep -q "^\\s*project .*," Podfile; then
    echo "ℹ️  It seems like your Podfile already contains a 'project ...' definition. Make sure it defines all your debug/release configurations (with the correct names)!"
  else
    sed -i '' "s/\(target .\(.*\). do\)/\1\\
  project '\2',\\
    'Development-Debug' => :debug, 'Development-Release' => :release,\\
    'Staging-Debug' => :debug, 'Staging-Release' => :release,\\
    'Production-Debug' => :debug, 'Production-Release' => :release\\
/" Podfile
    echo "ℹ️  Added a 'project ...' definition to your Podfile. Please verify that it is correct."
  fi
}

fix_project() {
  echo "- modify project.yml"

  sed -i '' -e ':a' -e 'N' -e '$!ba' -e 's/ *configFiles:\n *[^:]*[^.]*[A-Za-z].xcconfig\n\( *[^:]*[^.]*[A-Za-z].xcconfig\n\)*//g' project.yml
  sed -i '' "s/\(\( *\)- path: Rome\)/\1\\
\2  optional: true/" project.yml
  sed -i '' "s/Application\/\(Supporting Files\/.*xcconfig\)/\1/g" project.yml

  if grep -q "dependencies:" project.yml; then
    echo "ℹ️  Seems like you manually added dependencies to your project. This SHOULD no longer be necessary, so we'll remove it for now."
    sed -i '' -e ':a' -e 'N' -e '$!ba' -e 's/[ #]*dependencies:\n.*\n\( *settings:\n\)/\1/g' project.yml
  fi
}

nuke_xcode() {
  echo "- remove xcodeproj"

  git rm -rfq "$PROJECT"
  mkdir -p "$SHARED_DATA"
  cat > "$TEMPLATE_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>FILEHEADER</key>
    <string>
// ___PACKAGENAME___
// Copyright © 2021 Appwise
//</string>
</dict>
</plist>
EOF
}

fix_bitrise() {
  if test -f bitrise.yml; then
    echo "- fix bitrise.yml"

    sed -i '' "s/\(\( *\)bundle install\)/\1\\
\2curl -L -o \/tmp\/xcodegen.zip \"https:\/\/github.com\/yonaskolb\/XcodeGen\/releases\/download\/2.18.0\/xcodegen.zip\" \&\& unzip -q \/tmp\/xcodegen.zip -d \/tmp \&\& \/tmp\/xcodegen\/install.sh/" bitrise.yml
  fi
}

finish_git() {
  echo "- tweak gitignore and commit changes"
  cat >> .gitignore <<EOF

# Xcode projects (because we use XcodeGen)
*.xcodeproj
*.xcworkspace
EOF
  git add -f .gitignore Gemfile Gemfile.lock Podfile Podfile.lock project.yml projectDependencies.yml "$TEMPLATE_FILE"
  if test -f bitrise.yml; then
    git add -f bitrise.yml
  fi
  git commit -m "Switch from CocoaPods Rome to Alexandria"
}

move_configs
fix_gemfile
fix_podfile
fix_project
nuke_xcode
bundler exec pod install
finish_git

echo
echo "🎉  Done!"

if test -f "bitrise.yml"; then
  echo
  echo "Please ask your SysOps to add the XcodeGen install step in Bitrise!"
fi
