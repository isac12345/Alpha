#!/system/bin/sh
# Copyright (C) 2021-2022 Matt Yang
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file excepywxt in compliance with the License.
# You may obtain a copy of the License at
#      http://www.apache.org/licenses/LICENSE-2.0
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


lock_val() {
    for p in $2; do
        if [ -f "$p" ]; then
            chown root:root "$p" 2>/dev/null
            chmod 0666 "$p" 2>/dev/null
            echo "$1" >"$p"
            chmod 0444 "$p" 2>/dev/null
        fi
    done
}

mask_val() {
    touch /data/local/tmp/mount_mask
    for p in $2; do
        if [ -f "$p" ]; then
            umount "$p" 2>/dev/null
            chmod 0666 "$p" 2>/dev/null
            echo "$1" >"$p"
            mount --bind /data/local/tmp/mount_mask "$p"
        fi
    done
}

mask_val() {
for p in $2; do
if [ -f "$p" ]; then
echo "$1" >"$p"
fi
done
}

mutate() {
    for p in $2; do
        if [ -f "$p" ]; then
            chmod 0666 "$p"
            echo "$1" >"$p"
        fi
    done
}

lock() {
    if [ -f "$1" ]; then
        chown root:root "$p"
        chmod 0444 "$1"
    fi
}

has_val_in_list() {
    for item in $2; do
        if [ "$1" == "$item" ]; then
            echo "true"
            return
        fi
    done
    echo "false"
}


read_cfg_value() {
    local value=""
    if [ -f "$PANEL_FILE" ]; then
        value="$(grep -i "^$1=" "$PANEL_FILE" | head -n 1 | tr -d ' ' | cut -d= -f2)"
    fi
    echo "$value"
}

write_panel() {
    echo "$1" >>"$PANEL_FILE"
}

clear_panel() {
    true >"$PANEL_FILE"
}

wait_until_login() {
    while [ "$(getprop sys.boot_completed)" != "1" ]; do
        sleep 1
    done

    local test_file="/sdcard/Android/.PERMISSION_TEST"
    true >"$test_file"
    while [ ! -f "$test_file" ]; do
        true >"$test_file"
        sleep 1
    done
    rm "$test_file"
}


log() {
    echo "$1" >>"$LOG_FILE"
}

clear_log() {
    true >"$LOG_FILE"
}
