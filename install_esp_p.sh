#!/bin/bash
# 手动下载 ESP-IDF 子模块脚本

ESP_IDF_PATH="/home/ubuntu/Workspace/esp-idf"
cd $ESP_IDF_PATH

echo "=== 手动下载缺失的子模块 ==="

# 1. esp32c5-bt-lib
echo "Downloading esp32c5-bt-lib..."
cd components/bt/controller/lib_esp32c5
rm -rf esp32c5-bt-lib
git clone --depth 1 https://github.com/espressif/esp32c5-bt-lib.git esp32c5-bt-lib || echo "Failed: esp32c5-bt-lib"

# 2. esp32c6-bt-lib  
echo "Downloading esp32c6-bt-lib..."
cd ../../lib_esp32c6
rm -rf esp32c6-bt-lib
git clone --depth 1 https://github.com/espressif/esp32c6-bt-lib.git esp32c6-bt-lib || echo "Failed: esp32c6-bt-lib"

# 3. esp32h2-bt-lib
echo "Downloading esp32h2-bt-lib..."
cd ../lib_esp32h2
rm -rf esp32h2-bt-lib
git clone --depth 1 https://github.com/espressif/esp32h2-bt-lib.git esp32h2-bt-lib || echo "Failed: esp32h2-bt-lib"

# 4. esp32c2-bt-lib
echo "Downloading esp32c2-bt-lib..."
cd ../lib_esp32c2
rm -rf esp32c2-bt-lib
git clone --depth 1 https://github.com/espressif/esp32c2-bt-lib.git esp32c2-bt-lib || echo "Failed: esp32c2-bt-lib"

# 5. esp_ble_mesh_lib
echo "Downloading esp_ble_mesh_lib..."
cd $ESP_IDF_PATH/components/bt/esp_ble_mesh/lib
rm -rf lib
git clone --depth 1 https://github.com/espressif/esp-ble-mesh-lib.git lib || echo "Failed: esp_ble_mesh_lib"

# 6. esp_coex_lib
echo "Downloading esp_coex_lib..."
cd $ESP_IDF_PATH/components/esp_coex
rm -rf lib
git clone --depth 1 https://github.com/espressif/esp32-coex-lib.git lib || echo "Failed: esp_coex_lib"

# 7. tlsf
echo "Downloading tlsf..."
cd $ESP_IDF_PATH/components/heap
rm -rf tlsf
git clone --depth 1 https://github.com/mattconte/tlsf.git tlsf || echo "Failed: tlsf"

echo "=== 所有子模块下载完成 ==="
