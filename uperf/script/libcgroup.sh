#!/system/bin/sh
# Copyright (C) 2021-2022 Matt Yang
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#      http://www.apache.org/licenses/LICENSE-2.0
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

ps_ret=""


change_task_cgroup() {
    local comm
    for temp_pid in $(echo "$ps_ret" | grep -i -E "$1" | awk '{print $1}'); do
        for temp_tid in $(ls "/proc/$temp_pid/task/"); do
            comm="$(cat /proc/$temp_pid/task/$temp_tid/comm)"
            echo "$temp_tid" >"/dev/$3/$2/tasks"
        done
    done
}

change_proc_cgroup() {
    local comm
    for temp_pid in $(echo "$ps_ret" | grep -i -E "$1" | awk '{print $1}'); do
        comm="$(cat /proc/$temp_pid/comm)"
        echo $temp_pid >"/dev/$3/$2/cgroup.procs"
    done
}

change_thread_cgroup() {
    local comm
    for temp_pid in $(echo "$ps_ret" | grep -i -E "$1" | awk '{print $1}'); do
        for temp_tid in $(ls "/proc/$temp_pid/task/"); do
            comm="$(cat /proc/$temp_pid/task/$temp_tid/comm)"
            if [ "$(echo $comm | grep -i -E "$2")" != "" ]; then
                echo "$temp_tid" >"/dev/$4/$3/tasks"
            fi
        done
    done
}

change_main_thread_cgroup() {
    local comm
    for temp_pid in $(echo "$ps_ret" | grep -i -E "$1" | awk '{print $1}'); do
        comm="$(cat /proc/$temp_pid/comm)"
        echo $temp_pid >"/dev/$3/$2/tasks"
    done
}

change_task_affinity() {
    local comm
    for temp_pid in $(echo "$ps_ret" | grep -i -E "$1" | awk '{print $1}'); do
        for temp_tid in $(ls "/proc/$temp_pid/task/"); do
            comm="$(cat /proc/$temp_pid/task/$temp_tid/comm)"
            taskset -p "$2" "$temp_tid" >>$LOG_FILE
        done
    done
}

change_thread_affinity() {
    local comm
    for temp_pid in $(echo "$ps_ret" | grep -i -E "$1" | awk '{print $1}'); do
        for temp_tid in $(ls "/proc/$temp_pid/task/"); do
            comm="$(cat /proc/$temp_pid/task/$temp_tid/comm)"
            if [ "$(echo $comm | grep -i -E "$2")" != "" ]; then
                taskset -p "$3" "$temp_tid" >>$LOG_FILE
            fi
        done
    done
}

change_task_nice() {
    for temp_pid in $(echo "$ps_ret" | grep -i -E "$1" | awk '{print $1}'); do
        for temp_tid in $(ls "/proc/$temp_pid/task/"); do
            renice -n +40 -p "$temp_tid"
            renice -n -19 -p "$temp_tid"
            renice -n "$2" -p "$temp_tid"
        done
    done
}

change_thread_nice() {
    local comm
    for temp_pid in $(echo "$ps_ret" | grep -i -E "$1" | awk '{print $1}'); do
        for temp_tid in $(ls "/proc/$temp_pid/task/"); do
            comm="$(cat /proc/$temp_pid/task/$temp_tid/comm)"
            if [ "$(echo $comm | grep -i -E "$2")" != "" ]; then
                renice -n +40 -p "$temp_tid"
                renice -n -19 -p "$temp_tid"
                renice -n "$3" -p "$temp_tid"
            fi
        done
    done
}

change_task_rt() {
    for temp_pid in $(echo "$ps_ret" | grep -i -E "$1" | awk '{print $1}'); do
        for temp_tid in $(ls "/proc/$temp_pid/task/"); do
            comm="$(cat /proc/$temp_pid/task/$temp_tid/comm)"
            chrt -f -p "$2" "$temp_tid" >>$LOG_FILE
        done
    done
}

change_thread_rt() {
    local comm
    for temp_pid in $(echo "$ps_ret" | grep -i -E "$1" | awk '{print $1}'); do
        for temp_tid in $(ls "/proc/$temp_pid/task/"); do
            comm="$(cat /proc/$temp_pid/task/$temp_tid/comm)"
            if [ "$(echo $comm | grep -i -E "$2")" != "" ]; then
                chrt -f -p "$3" "$temp_tid" >>$LOG_FILE
            fi
        done
    done
}

change_task_high_prio() {
    change_task_nice "$1" "-15"
}

change_thread_high_prio() {
    change_thread_nice "$1" "$2" "-15"
}

unpin_thread() {
    change_thread_cgroup "$1" "$2" "" "cpuset"
}

pin_thread_on_pwr() {
    change_thread_cgroup "$1" "$2" "background" "cpuset"
}

pin_thread_on_mid() {
    unpin_thread "$1" "$2"
    change_thread_affinity "$1" "$2" "7f"
}

pin_thread_on_perf() {
    unpin_thread "$1" "$2"
    change_thread_affinity "$1" "$2" "f0"
}

unpin_proc() {
    change_task_cgroup "$1" "" "cpuset"
}

pin_proc_on_pwr() {
    change_task_cgroup "$1" "background" "cpuset"
}

pin_proc_on_mid() {
    unpin_proc "$1"
    change_task_affinity "$1" "7f"
}

pin_proc_on_perf() {
    unpin_proc "$1"
    change_task_affinity "$1" "f0"
}

rebuild_process_scan_cache() {
    ps_ret="$(ps -Ao pid,args)"
}
