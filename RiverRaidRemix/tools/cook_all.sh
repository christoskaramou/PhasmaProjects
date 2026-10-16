#!/bin/bash
# Cook every generated OBJ in meshsrc/ into project/Assets/Objects/*.pemesh (4 in parallel)
cd "$(dirname "$0")/../bin"
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json
ls ../meshsrc/*.obj | xargs -P 3 -I{} bash -c 'n=$(basename {} .obj); timeout 120 xvfb-run -a ./PhasmaCook {} ../project/Assets/Objects/$n.pemesh 2>&1 | grep -o "Cooked.*" || echo "FAILED $n"'
