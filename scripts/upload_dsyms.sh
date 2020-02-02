#!/bin/sh
set -e
set -x
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
echo "Signing in"
echo "Uploading compressed dsyms"
morgue put cocoa dsyms.zip --format=symbols --debug
