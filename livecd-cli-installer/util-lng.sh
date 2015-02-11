#!/bin/bash

# kernel_cmdline(){
#     for param in $(/bin/cat /proc/cmdline); do
#         case "${param}" in
#             $1=*) echo "${param##*=}"; return 0 ;;
#             $1) return 0 ;;
#             *) continue ;;
#         esac
#     done
#     [ -n "${2}" ] && echo "${2}"
#     return 1
# }

get_country(){
  local COUNTRY=$(kernel_cmdline lang)
  echo $COUNTRY
}

get_keyboard(){
  local KEYBOARD=$(kernel_cmdline keytable)
  echo $KEYBOARD
}

get_layout(){
  local LAYOUT=$(kernel_cmdline layout)
  echo $LAYOUT
}

find_legacy_keymap(){
  file="/opt/livecd/kbd-model-map"
  while read -r line || [[ -n $line ]]; do  
    if [[ -z $line ]] || [[ $line == \#* ]]; then
      continue
    fi
    
    mapping=( $line ); # parses columns
    if [[ ${#mapping[@]} != 5 ]]; then
      continue
    fi
    
    if  [[ "$KEYMAP" != "${mapping[0]}" ]]; then
      continue
    fi
    
    if [[ "${mapping[3]}" = "-" ]]; then
      mapping[3]=""
    fi
    
    X11_LAYOUT=${mapping[1]}
    X11_MODEL=${mapping[2]}
    X11_VARIANT=${mapping[3]}
    x11_OPTIONS=${mapping[4]}
  done < $file
}

write_x11_config_file(){
  # find a x11 layout that matches the keymap
  # in isolinux if you select a keyboard layout and a language that doesnt match this layout,
  # it will provide the correct keymap, but not kblayout value
  local X11_LAYOUT=
  local X11_MODEL="pc105"
  local X11_VARIANT=""
  local X11_OPTIONS="terminate:ctrl_alt_bksp"  
  find_legacy_keymap 
  
  # layout not found, use KBLAYOUT
  if [[ -z "$X11_LAYOUT" ]]; then
    X11_LAYOUT="$KBLAYOUT"    
  fi
  
  # create X11 keyboard layout config
  mkdir -p "${DESTDIR}/etc/X11/xorg.conf.d"
  if [ -e /run/openrc ]; then
    local XORGKBLAYOUT="${DESTDIR}/etc/X11/xorg.conf.d/20-keyboard.conf"
  else
    local XORGKBLAYOUT="${DESTDIR}/etc/X11/xorg.conf.d/00-keyboard.conf"
  fi
  
  echo "" >> "$XORGKBLAYOUT"
  echo "Section \"InputClass\"" > "$XORGKBLAYOUT"
  echo " Identifier \"system-keyboard\"" >> "$XORGKBLAYOUT"
  echo " MatchIsKeyboard \"on\"" >> "$XORGKBLAYOUT"
  echo " Option \"XkbLayout\" \"$X11_LAYOUT\"" >> "$XORGKBLAYOUT"
  echo " Option \"XkbModel\" \"$X11_MODEL\"" >> "$XORGKBLAYOUT"
  echo " Option \"XkbVariant\" \"$X11_VARIANT\"" >> "$XORGKBLAYOUT"
  echo " Option \"XkbOptions\" \"$X11_OPTIONS\"" >> "$XORGKBLAYOUT"
  echo "EndSection" >> "$XORGKBLAYOUT"

  # fix por keyboardctl
  if [ -f "${DESTDIR}/etc/keyboard.conf" ]; then
    sed -i -e "s/^XKBLAYOUT=.*/XKBLAYOUT=\"${X11_LAYOUT}\"/g" ${DESTDIR}/etc/keyboard.conf
  fi  
}

set_locale(){
  # hack to be able to set the locale on bootup
  local LOCALE=$(get_country)
  local KEYMAP=$(get_keyboard)
  local KBLAYOUT=$(get_layout)

  # set a default value, in case something goes wrong, or a language doesn't have
  # good defult settings
  [ -n "$LOCALE" ] || LOCALE="en_US"
  [ -n "$KEYMAP" ] || KEYMAP="us"
  [ -n "$KBLAYOUT" ] || KBLAYOUT="us"

  # set keymap
  if [ -e /run/openrc ]; then
    sed -i "s/keymap=.*/keymap=\"${KEYMAP}\"/" ${DESTDIR}/etc/conf.d/keymaps
  else
    echo "KEYMAP=us" > ${DESTDIR}/etc/vconsole.conf
    sed -i "s/^KEYMAP=.*/KEYMAP=\"${KEYMAP}\"/" ${DESTDIR}/etc/vconsole.conf
  fi
  
  # load keymaps
  loadkeys "$KEYMAP"

  write_x11_config_file
  
  # set systemwide language
  echo "LANG=${LOCALE}.UTF-8" > ${DESTDIR}/etc/locale.conf
  echo "LC_MESSAGES=${LOCALE}.UTF-8" >> ${DESTDIR}/etc/locale.conf
  echo "LANG=${LOCALE}.UTF-8" >> ${DESTDIR}/etc/environment

  # generate LOCALE
  local TLANG=${LOCALE%.*} # remove everything after the ., including the dot from LOCALE
  sed -i -r "s/#(${TLANG}.*UTF-8)/\1/g" ${DESTDIR}/etc/locale.gen
  # add also American English as safe default
  sed -i -r "s/#(en_US.*UTF-8)/\1/g" ${DESTDIR}/etc/locale.gen
}

printk(){
    case ${1} in
        "on")  echo 4 >/proc/sys/kernel/printk ;;
        "off") echo 0 >/proc/sys/kernel/printk ;;
    esac
}