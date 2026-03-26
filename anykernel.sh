### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=FloppyKernel Beta for Exynos 2100 devices by @Flopster101
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=r9s
supported.versions=12.0-16.0
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties


### AnyKernel install
## boot files attributes
boot_attributes() {
set_perm_recursive 0 0 755 644 $RAMDISK/*;
set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
} # end attributes

# boot shell variables
BLOCK=/dev/block/by-name/boot;
IS_SLOT_DEVICE=0;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

# Helper logging functions for structured format
printed_blank=0
print_blank_once() {
  if [ "$printed_blank" -eq 0 ]; then
    ui_print " "
    printed_blank=1
  fi
}
feature_ok() { print_blank_once; ui_print "[*] $1"; }
feature_info() { print_blank_once; ui_print "[*] $1"; }
feature_warn() { print_blank_once; ui_print "[!] $1"; }

apply_bpf_spoof() {
  local mode=$1
  local hex_0="756e616d655f6270665f73706f6f663d30"
  local hex_1="756e616d655f6270665f73706f6f663d31"
  local hex_2="756e616d655f6270665f73706f6f663d32"
  local target_hex="$hex_0"

  case "$mode" in
    1) target_hex="$hex_1" ;;
    2) target_hex="$hex_2" ;;
    *) target_hex="$hex_0" ;;
  esac

  [ -f "$AKHOME/Image" ] || return 0

  $BIN/magiskboot hexpatch "$AKHOME/Image" "$hex_0" "$target_hex" >/dev/null 2>&1
  $BIN/magiskboot hexpatch "$AKHOME/Image" "$hex_1" "$target_hex" >/dev/null 2>&1
  $BIN/magiskboot hexpatch "$AKHOME/Image" "$hex_2" "$target_hex" >/dev/null 2>&1
}

check_bpf_spoofing() {
  if [ ! -f "$AKHOME/bpf_spoof.conf" ]; then
    return 0
  fi

  if [ "$cache_mounted" -eq 1 ] && [ -f /cache/fk_feat ] && grep -q "uname_bpf_spoof" /cache/fk_feat 2>/dev/null; then
    feature_info "BpfSpoof already configured in /cache/fk_feat, skipping detection."
    return 0
  fi

  best_len=0
  best_line_num=99999999
  best_entry=""
  best_action=""
  best_mode=""
  best_message=""
  best_index=99999999

  cfg_index=0
  while IFS= read -r entry || [ -n "$entry" ]; do
    cfg_index=$((cfg_index + 1))
    entry="$(echo "$entry" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ -z "$entry" ] && continue
    case "$entry" in \#*) continue ;; esac
    scope="$(echo "$entry" | cut -d'~' -f1 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    pattern_raw="$(echo "$entry" | cut -d'~' -f2 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    action="$(echo "$entry" | cut -d'~' -f3 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    mode="$(echo "$entry" | cut -d'~' -f4 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    message="$(echo "$entry" | cut -d'~' -f5- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

    if [ -z "$scope" ] || [ -z "$pattern_raw" ] || [ -z "$action" ] || [ -z "$mode" ]; then
      feature_warn "Malformed bpf_spoof.conf entry (skipping): $entry"
      continue
    fi

    case "$pattern_raw" in
      re:*) pattern="${pattern_raw#re:}"; grep_opts="-E" ;;
      ire:*) pattern="${pattern_raw#ire:}"; grep_opts="-Ei" ;;
      if:*) pattern="${pattern_raw#if:}"; grep_opts="-Fi" ;;
      *) pattern="$pattern_raw"; grep_opts="-F" ;;
    esac

    scope_lc="$(echo "$scope" | tr '[:upper:]' '[:lower:]')"
    case "$scope_lc" in
      vendor) targets="/vendor/build.prop" ;;
      system) targets="/system/build.prop /system_root/system/build.prop" ;;
      both) targets="/vendor/build.prop /system/build.prop /system_root/system/build.prop" ;;
      /*) targets="$scope" ;;
      *) targets="$scope" ;;
    esac

    for file_check in $targets; do
      if [ -f "$file_check" ]; then
        match_info=$(grep $grep_opts -n -- "$pattern" "$file_check" 2>/dev/null | head -n1)
        if [ -n "$match_info" ]; then
          match_line=$(echo "$match_info" | cut -d: -f1)
          plen=$(printf "%s" "$pattern" | wc -c)
          if [ "$plen" -gt "$best_len" ] || { [ "$plen" -eq "$best_len" ] && [ "$match_line" -lt "$best_line_num" ]; } || { [ "$plen" -eq "$best_len" ] && [ "$match_line" -eq "$best_line_num" ] && [ "$cfg_index" -lt "$best_index" ] 2>/dev/null; }; then
            best_len=$plen
            best_line_num=$match_line
            best_entry="$entry"
            best_action="$action"
            best_mode="$mode"
            best_message="$message"
            best_index=$cfg_index
          fi
        fi
      fi
    done
  done < "$AKHOME/bpf_spoof.conf"

  if [ -n "$best_entry" ]; then
    feature_info "$best_message"
    if [ "$best_action" = "auto" ]; then
      feature_ok "Enabling feature: uname BPF spoof (mode $best_mode)"
      apply_bpf_spoof "$best_mode"
    else
      feature_warn "You might need to manually enable BpfSpoof (recommended mode: $best_mode)"
    fi
  fi
}

mount -o ro /system_root 2>/dev/null || mount -o ro /dev/block/mapper/system /system_root 2>/dev/null

# Check if /cache is mounted, try to mount if not
cache_mounted=0;
if mountpoint -q /cache 2>/dev/null; then
  cache_mounted=1;
else
  if mount /cache 2>/dev/null; then
    cache_mounted=1;
  fi
fi

# Check for feature flags in /cache/fk_feat
if [ "$cache_mounted" -eq 1 ] && [ -f /cache/fk_feat ]; then
  if grep -q "uname_bpf_spoof=" /cache/fk_feat 2>/dev/null; then
    val=$(grep -o 'uname_bpf_spoof=[0-9]*' /cache/fk_feat | head -n1 | cut -d= -f2)
    feature_ok "Enabling feature: uname BPF spoof (mode $val)"
    apply_bpf_spoof "$val"
  elif grep -q "uname_bpf_spoof" /cache/fk_feat 2>/dev/null; then
    feature_ok "Enabling feature: uname BPF spoof (mode 1)"
    apply_bpf_spoof 1
  fi
fi

# Run BPF spoof detection
check_bpf_spoofing

# boot install
split_boot; # use split_boot to skip ramdisk unpack, e.g. for devices with init_boot ramdisk

flash_boot; # use flash_boot to skip ramdisk repack, e.g. for devices with init_boot ramdisk
## end boot install

flash_generic vendor_boot;
