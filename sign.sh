#!/bin/bash
# Sign the built dylib with ldid
# Usage: ./sign.sh

DYLIB_PATH=".theos/obj/debug/YLTool.dylib"
if [ -f "$DYLIB_PATH" ]; then
    echo "[+] Signing YLTool.dylib..."
    ldid -S "$DYLIB_PATH"
    echo "[+] Signed successfully!"
else
    echo "[-] Dylib not found. Build first with: make"
fi
