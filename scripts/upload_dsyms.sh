#!/bin/sh

echo "Remove dsyms directory if already exists."
cd "${BUILT_PRODUCTS_DIR}"
echo "$PWD"
if [ -d dsyms ]; then rm -Rf dsyms; fi
if [ -d dsyms.zip ]; then rm -Rf dsyms.zip; fi

echo "Print directory content"
ls ./
echo "Making dsyms directory"
mkdir dsyms
echo "Copying dsyms files"
cp -r **/*.dSYM dsyms
cp -r *.dSYM dsyms
echo "Compressing dsyms files"
zip -r dsyms.zip dsyms
echo "Uploading compressed dsyms"
command -v morgue >/dev/null 2>&1 || { echo >&2 "morgue - Backtrace command line interface needs to be installed: https://github.com/backtrace-labs/backtrace-morgue  Aborting."; exit 1; }
morgue put cocoa dsyms.zip --format=symbols --debug
