#!/bin/bash
cd "$(dirname "$0")/../bin"
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json
mkdir -p ../project/Assets/Objects
for f in ../meshsrc/*.obj; do
  n=$(basename "$f" .obj)
  timeout 120 xvfb-run -a ./PhasmaCook "$f" "../project/Assets/Objects/$n.pemesh" 2>&1 | grep -o "Cooked.*" || echo "FAILED $n"
done
