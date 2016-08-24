#!/bin/bash
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

kernel_cmdline(){
	for param in $(cat /proc/cmdline); do
		case "${param}" in
			$1=*) echo "${param##*=}"; return 0 ;;
			$1) return 0 ;;
			*) continue ;;
		esac
	done
	[ -n "${2}" ] && echo "${2}"
	return 1
}

get_country(){
	echo $(kernel_cmdline lang)
}

get_keyboard(){
	echo $(kernel_cmdline keytable)
}

get_layout(){
	echo $(kernel_cmdline layout)
}

get_timer_ms(){
	echo $(date +%s%3N)
}

# $1: start timer
elapsed_time_ms(){
	echo $(echo $1 $(get_timer_ms) | awk '{ printf "%0.3f",($2-$1)/1000 }')
}

load_live_config(){

	[[ -f $1 ]] || return 1

	live_conf="$1"

	[[ -r ${live_conf} ]] && source ${live_conf}

	[[ -z ${autologin} ]] && autologin=true

	[[ -z ${username} ]] && username="manjaro"

	[[ -z ${password} ]] && password="manjaro"

	[[ -z ${addgroups} ]] && addgroups=""

	[[ -z ${login_shell} ]] && login_shell="/bin/bash"

	[[ -z ${iso_name} ]] && iso_name="manjaro"

	[[ -z ${default_desktop_executable} ]] && default_desktop_executable="none"

	[[ -z ${default_desktop_file} ]] && default_desktop_file="none"

	[[ -z ${smb_workgroup} ]] && smb_workgroup="Manjaro"

	return 0
}

is_valid_de(){
	if [[ ${default_desktop_executable} != "none" ]] && \
	[[ ${default_desktop_file} != "none" ]]; then
		return 0
	else
		return 1
	fi
}

configure_accountsservice(){
	local path=/var/lib/AccountsService/users
	if [ -d "${path}" ]; then
		echo "[User]" > ${path}/$1
		echo "XSession=${default_desktop_file}" >> ${path}/$1
		if [[ -f "/var/lib/AccountsService/icons/$1.png" ]]; then
			echo "Icon=/var/lib/AccountsService/icons/$1.png" >> ${path}/$1
		fi
	fi
}

set_sddm_ck(){
        local halt='/usr/bin/shutdown -h -P now' \
        reboot='/usr/bin/shutdown -r now'
        sed -e "s|^.*HaltCommand=.*|HaltCommand=${halt}|" \
            -e "s|^.*RebootCommand=.*|RebootCommand=${reboot}|" \
            -e "s|^.*MinimumVT=.*|MinimumVT=7|" \
            -i "/etc/sddm.conf"
        gpasswd -a sddm video &> /dev/null
}

 set_lightdm_greeter(){
	local greeters=$(ls /usr/share/xgreeters/*greeter.desktop) name
	for g in ${greeters[@]};do
		name=${g##*/}
		name=${name%%.*}
		case ${name} in
			lightdm-gtk-greeter) break ;;
			lightdm-*-greeter)
				sed -i -e "s/^.*greeter-session=.*/greeter-session=${name}/" /etc/lightdm/lightdm.conf
			;;
		esac
	done
 }

 set_lightdm_ck(){
	sed -i -e 's/^.*minimum-vt=.*/minimum-vt=7/' /etc/lightdm/lightdm.conf
	sed -i -e 's/pam_systemd.so/pam_ck_connector.so nox11/' /etc/pam.d/lightdm-greeter
 }

 configure_samba(){
	if [[ -f /usr/bin/samba ]]; then
		local conf=/etc/samba/smb.conf
		cp /etc/samba/smb.conf.default $conf
		sed -e "s|^.*workgroup =.*|workgroup = ${smb_workgroup}|" -i $conf
	fi
}

configure_displaymanager(){
	# Try to detect desktop environment
	# Configure display manager
	if [[ -f /usr/bin/lightdm ]]; then
		groupadd -r autologin
		[[ -f /usr/bin/openrc ]] && set_lightdm_ck
		set_lightdm_greeter
		if $(is_valid_de); then
			sed -i -e "s/^.*user-session=.*/user-session=$default_desktop_file/" /etc/lightdm/lightdm.conf
		fi
		if ${autologin}; then
			gpasswd -a ${username} autologin &> /dev/null
			sed -i -e "s/^.*autologin-user=.*/autologin-user=${username}/" /etc/lightdm/lightdm.conf
			sed -i -e "s/^.*autologin-user-timeout=.*/autologin-user-timeout=0/" /etc/lightdm/lightdm.conf
			sed -i -e "s/^.*pam-autologin-service=.*/pam-autologin-service=lightdm-autologin/" /etc/lightdm/lightdm.conf
		fi
	elif [[ -f /usr/bin/gdm ]]; then
		configure_accountsservice "gdm"
		if ${autologin}; then
			sed -i -e "s/\[daemon\]/\[daemon\]\nAutomaticLogin=${username}\nAutomaticLoginEnable=True/" /etc/gdm/custom.conf
		fi
	elif [[ -f /usr/bin/mdm ]]; then
		if $(is_valid_de); then
			sed -i "s|default.desktop|$default_desktop_file.desktop|g" /etc/mdm/custom.conf
		fi
	elif [[ -f /usr/bin/sddm ]]; then
		[[ -f /usr/bin/openrc ]] && set_sddm_ck
		if $(is_valid_de); then
			sed -i -e "s|^Session=.*|Session=$default_desktop_file.desktop|" /etc/sddm.conf
		fi
		if ${autologin}; then
			sed -i -e "s|^User=.*|User=${username}|" /etc/sddm.conf
		fi
	elif [[ -f /usr/bin/lxdm ]]; then
		if $(is_valid_de); then
			sed -i -e "s|^.*session=.*|session=/usr/bin/$default_desktop_executable|" /etc/lxdm/lxdm.conf
		fi
		if ${autologin}; then
			sed -i -e "s/^.*autologin=.*/autologin=${username}/" /etc/lxdm/lxdm.conf
		fi
	fi
}

gen_pw(){
	echo $(perl -e 'print crypt($ARGV[0], "password")' ${password})
}

configure_user(){
	# set up user and password
	if [[ -n ${password} ]]; then
		useradd -m -G ${addgroups} -p $(gen_pw) -s ${login_shell} ${username}
	else
		useradd -m -G ${addgroups} -s ${login_shell} ${username}
	fi
}

configure_environment(){
	local img_path="/bootmnt/${iso_name}/${arch}"

	cd ${img_path}
	case $(ls ${img_path}) in
		cinnamon*|deepin*|gnome*|i3*|lxde*|mate*|netbook*|openbox*|pantheon*|xfce*)
			echo "QT_STYLE_OVERRIDE=gtk" >> /etc/environment
			if [[ -f "/usr/lib/qt/plugins/styles/libqgtk2style.so" ]]; then
				sed -i '/QT_STYLE_OVERRIDE=gtk/d' /etc/environment
				echo "QT_STYLE_OVERRIDE=gtk2" >> /etc/environment
			fi
			if [[ -f "/usr/lib/qt/plugins/platformthemes/libqt5ct.so" ]]; then
				sed -i '/QT_STYLE_OVERRIDE=gtk/d' /etc/environment
				echo "QT_QPA_PLATFORMTHEME=qt5ct" >> /etc/environment
			fi
		;;
	esac
}

configure_pamac() {
	if [[ -f /etc/NetworkManager/dispatcher.d/99_update_pamac_tray ]]; then
		rm -f /etc/NetworkManager/dispatcher.d/99_update_pamac_tray
	fi
}

find_legacy_keymap(){
	file="${DATADIR}/kbd-model.map"
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

write_x11_config(){
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
	mkdir -p "/etc/X11/xorg.conf.d"

	local XORGKBLAYOUT="/etc/X11/xorg.conf.d/00-keyboard.conf"

	echo "" >> "$XORGKBLAYOUT"
	echo "Section \"InputClass\"" > "$XORGKBLAYOUT"
	echo " Identifier \"system-keyboard\"" >> "$XORGKBLAYOUT"
	echo " MatchIsKeyboard \"on\"" >> "$XORGKBLAYOUT"
	echo " Option \"XkbLayout\" \"$X11_LAYOUT\"" >> "$XORGKBLAYOUT"
	echo " Option \"XkbModel\" \"$X11_MODEL\"" >> "$XORGKBLAYOUT"
	echo " Option \"XkbVariant\" \"$X11_VARIANT\"" >> "$XORGKBLAYOUT"
	echo " Option \"XkbOptions\" \"$X11_OPTIONS\"" >> "$XORGKBLAYOUT"
	echo "EndSection" >> "$XORGKBLAYOUT"
}

configure_language(){
	# hack to be able to set the locale on bootup
	local LOCALE=$(get_country)
	local KEYMAP=$(get_keyboard)
	local KBLAYOUT=$(get_layout)

	# this is needed for efi, it doesn't set any cmdline
	[[ -z "$LOCALE" ]] && LOCALE="en_US"
	[[ -z "$KEYMAP" ]] && KEYMAP="us"
	[[ -z "$KBLAYOUT" ]] && KBLAYOUT="us"

	local TLANG=${LOCALE%.*}

	sed -i -r "s/#(${TLANG}.*UTF-8)/\1/g" /etc/locale.gen

	echo "LANG=${LOCALE}.UTF-8" >> /etc/environment

	if [[ -f /usr/bin/openrc ]]; then
		sed -i "s/keymap=.*/keymap=\"${KEYMAP}\"/" /etc/conf.d/keymaps
	fi
	echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf
	echo "LANG=${LOCALE}.UTF-8" > /etc/locale.conf

	write_x11_config

	loadkeys "${KEYMAP}"

	locale-gen ${TLANG}
}

configure_clock(){
    if [[ -d /run/openrc ]]; then
        ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime
        echo "Europe/London" > /etc/timezone
    fi
}

configure_machine_id(){
	if [ -e "/etc/machine-id" ]; then
		# delete existing machine-id
		echo "Deleting existing machine-id ..." >> /var/log/manjaro-live.log
		rm /etc/machine-id
	fi
	# set unique machine-id
	echo "Setting machine-id ..." >> /var/log/manjaro-live.log
	dbus-uuidgen --ensure=/etc/machine-id
	ln -sf /etc/machine-id /var/lib/dbus/machine-id
}

configure_sudoers_d(){
	echo "%wheel  ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/g_wheel
	echo "root ALL=(ALL) ALL"  > /etc/sudoers.d/u_root
	#echo "${username} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/u_live
}

configure_swap(){
	local swapdev="$(fdisk -l 2>/dev/null | grep swap | cut -d' ' -f1)"
	if [ -e "${swapdev}" ]; then
		swapon ${swapdev}
	fi
}

configure_user_root(){
	# set up root password
	echo "root:${password}" | chroot $1 chpasswd
	cp /etc/skel/.{bash_profile,bashrc,bash_logout,extend.bashrc} /root/
	if [[ -d /etc/skel/.config ]]; then
		cp -a /etc/skel/.config /root/
	fi
}

configure_alsa(){
	# amixer binary
	local alsa_amixer="chroot $1 /usr/bin/amixer"

	# enable all known (tm) outputs
	$alsa_amixer -c 0 sset "Master" 70% unmute &>/dev/null
	$alsa_amixer -c 0 sset "Front" 70% unmute &>/dev/null
	$alsa_amixer -c 0 sset "Side" 70% unmute &>/dev/null
	$alsa_amixer -c 0 sset "Surround" 70% unmute &>/dev/null
	$alsa_amixer -c 0 sset "Center" 70% unmute &>/dev/null
	$alsa_amixer -c 0 sset "LFE" 70% unmute &> /dev/null
	$alsa_amixer -c 0 sset "Headphone" 70% unmute &>/dev/null
	$alsa_amixer -c 0 sset "Speaker" 70% unmute &>/dev/null
	$alsa_amixer -c 0 sset "PCM" 70% unmute &>/dev/null
	$alsa_amixer -c 0 sset "Line" 70% unmute &>/dev/null
	$alsa_amixer -c 0 sset "External" 70% unmute &>/dev/null
	$alsa_amixer -c 0 sset "FM" 50% unmute &> /dev/null
	$alsa_amixer -c 0 sset "Master Mono" 70% unmute &>/dev/null
	$alsa_amixer -c 0 sset "Master Digital" 70% unmute &>/dev/null
	$alsa_amixer -c 0 sset "Analog Mix" 70% unmute &> /dev/null
	$alsa_amixer -c 0 sset "Aux" 70% unmute &> /dev/null
	$alsa_amixer -c 0 sset "Aux2" 70% unmute &> /dev/null
	$alsa_amixer -c 0 sset "PCM Center" 70% unmute &> /dev/null
	$alsa_amixer -c 0 sset "PCM Front" 70% unmute &> /dev/null
	$alsa_amixer -c 0 sset "PCM LFE" 70% unmute &> /dev/null
	$alsa_amixer -c 0 sset "PCM Side" 70% unmute &> /dev/null
	$alsa_amixer -c 0 sset "PCM Surround" 70% unmute &> /dev/null
	$alsa_amixer -c 0 sset "Playback" 70% unmute &> /dev/null
	$alsa_amixer -c 0 sset "PCM,1" 70% unmute &> /dev/null
	$alsa_amixer -c 0 sset "DAC" 70% unmute &> /dev/null
	$alsa_amixer -c 0 sset "DAC,0" 70% unmute &> /dev/null
	$alsa_amixer -c 0 sset "DAC,0" -12dB &> /dev/null
	$alsa_amixer -c 0 sset "DAC,1" 70% unmute &> /dev/null
	$alsa_amixer -c 0 sset "DAC,1" -12dB &> /dev/null
	$alsa_amixer -c 0 sset "Synth" 70% unmute &> /dev/null
	$alsa_amixer -c 0 sset "CD" 70% unmute &> /dev/null
	$alsa_amixer -c 0 sset "Wave" 70% unmute &> /dev/null
	$alsa_amixer -c 0 sset "Music" 70% unmute &> /dev/null
	$alsa_amixer -c 0 sset "AC97" 70% unmute &> /dev/null
	$alsa_amixer -c 0 sset "Analog Front" 70% unmute &> /dev/null
	$alsa_amixer -c 0 sset "VIA DXS,0" 70% unmute &> /dev/null
	$alsa_amixer -c 0 sset "VIA DXS,1" 70% unmute &> /dev/null
	$alsa_amixer -c 0 sset "VIA DXS,2" 70% unmute &> /dev/null
	$alsa_amixer -c 0 sset "VIA DXS,3" 70% unmute &> /dev/null

	# set input levels
	$alsa_amixer -c 0 sset "Mic" 70% mute &>/dev/null
	$alsa_amixer -c 0 sset "IEC958" 70% mute &>/dev/null

	# special stuff
	$alsa_amixer -c 0 sset "Master Playback Switch" on &>/dev/null
	$alsa_amixer -c 0 sset "Master Surround" on &>/dev/null
	$alsa_amixer -c 0 sset "SB Live Analog/Digital Output Jack" off &>/dev/null
	$alsa_amixer -c 0 sset "Audigy Analog/Digital Output Jack" off &>/dev/null
}
