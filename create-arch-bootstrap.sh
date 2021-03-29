#!/usr/bin/env bash

# Dependencies: wget tar gzip
# Root rights are required

if [ $EUID != 0 ]; then
	echo "Root rights are required!"

	exit 1
fi

script_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

mount_chroot () {
	# First unmount just in case
	umount -Rl "${bootstrap}"

	mount --bind "${bootstrap}" "${bootstrap}"
	mount --bind /dev "${bootstrap}"/dev
	mount --bind /dev/shm "${bootstrap}"/dev/shm
	mount --bind /dev/pts "${bootstrap}"/dev/pts
	mount --bind /proc "${bootstrap}"/proc
	mount --bind /sys "${bootstrap}"/sys
	mount --bind /etc/resolv.conf "${bootstrap}"/etc/resolv.conf
}

unmount_chroot () {
	umount -Rl "${bootstrap}"
}

run_in_chroot () {
	chroot "${bootstrap}" /usr/bin/env LANG=en_US.UTF-8 TERM=xterm PATH="/bin:/sbin:/usr/bin:/usr/sbin" "$@"
}

generate_localegen () {
	cat <<EOF > locale.gen
aa_DJ.UTF-8 UTF-8
aa_ER UTF-8
aa_ER@saaho UTF-8
aa_ET UTF-8
af_ZA.UTF-8 UTF-8
agr_PE UTF-8
ak_GH UTF-8
am_ET UTF-8
an_ES.UTF-8 UTF-8
anp_IN UTF-8
ar_AE.UTF-8 UTF-8
ar_BH.UTF-8 UTF-8
ar_DZ.UTF-8 UTF-8
ar_EG.UTF-8 UTF-8
ar_IN UTF-8
ar_IQ.UTF-8 UTF-8
ar_JO.UTF-8 UTF-8
ar_KW.UTF-8 UTF-8
ar_LB.UTF-8 UTF-8
ar_LY.UTF-8 UTF-8
ar_MA.UTF-8 UTF-8
ar_OM.UTF-8 UTF-8
ar_QA.UTF-8 UTF-8
ar_SA.UTF-8 UTF-8
ar_SD.UTF-8 UTF-8
ar_SS UTF-8
ar_SY.UTF-8 UTF-8
ar_TN.UTF-8 UTF-8
ar_YE.UTF-8 UTF-8
ayc_PE UTF-8
az_AZ UTF-8
az_IR UTF-8
as_IN UTF-8
ast_ES.UTF-8 UTF-8
be_BY.UTF-8 UTF-8
be_BY@latin UTF-8
bem_ZM UTF-8
ber_DZ UTF-8
ber_MA UTF-8
bg_BG.UTF-8 UTF-8
bhb_IN.UTF-8 UTF-8
bho_IN UTF-8
bho_NP UTF-8
bi_VU UTF-8
bn_BD UTF-8
bn_IN UTF-8
bo_CN UTF-8
bo_IN UTF-8
br_FR.UTF-8 UTF-8
brx_IN UTF-8
bs_BA.UTF-8 UTF-8
byn_ER UTF-8
ca_AD.UTF-8 UTF-8
ca_ES.UTF-8 UTF-8
ca_ES@valencia UTF-8
ca_FR.UTF-8 UTF-8
ca_IT.UTF-8 UTF-8
ce_RU UTF-8
chr_US UTF-8
ckb_IQ UTF-8
crh_UA UTF-8
cs_CZ.UTF-8 UTF-8
csb_PL UTF-8
cv_RU UTF-8
cy_GB.UTF-8 UTF-8
da_DK.UTF-8 UTF-8
de_AT.UTF-8 UTF-8
de_BE.UTF-8 UTF-8
de_CH.UTF-8 UTF-8
de_DE.UTF-8 UTF-8
de_IT.UTF-8 UTF-8
de_LI.UTF-8 UTF-8
de_LU.UTF-8 UTF-8
doi_IN UTF-8
dsb_DE UTF-8
dv_MV UTF-8
dz_BT UTF-8
el_GR.UTF-8 UTF-8
el_CY.UTF-8 UTF-8
en_AG UTF-8
en_AU.UTF-8 UTF-8
en_BW.UTF-8 UTF-8
en_CA.UTF-8 UTF-8
en_DK.UTF-8 UTF-8
en_GB.UTF-8 UTF-8
en_HK.UTF-8 UTF-8
en_IE.UTF-8 UTF-8
en_IL UTF-8
en_IN UTF-8
en_NG UTF-8
en_NZ.UTF-8 UTF-8
en_PH.UTF-8 UTF-8
en_SC.UTF-8 UTF-8
en_SG.UTF-8 UTF-8
en_US.UTF-8 UTF-8
en_ZA.UTF-8 UTF-8
en_ZM UTF-8
en_ZW.UTF-8 UTF-8
eo UTF-8
es_AR.UTF-8 UTF-8
es_BO.UTF-8 UTF-8
es_CL.UTF-8 UTF-8
es_CO.UTF-8 UTF-8
es_CR.UTF-8 UTF-8
es_CU UTF-8
es_DO.UTF-8 UTF-8
es_EC.UTF-8 UTF-8
es_ES.UTF-8 UTF-8
es_GT.UTF-8 UTF-8
es_HN.UTF-8 UTF-8
es_MX.UTF-8 UTF-8
es_NI.UTF-8 UTF-8
es_PA.UTF-8 UTF-8
es_PE.UTF-8 UTF-8
es_PR.UTF-8 UTF-8
es_PY.UTF-8 UTF-8
es_SV.UTF-8 UTF-8
es_US.UTF-8 UTF-8
es_UY.UTF-8 UTF-8
es_VE.UTF-8 UTF-8
et_EE.UTF-8 UTF-8
eu_ES.UTF-8 UTF-8
fa_IR UTF-8
ff_SN UTF-8
fi_FI.UTF-8 UTF-8
fil_PH UTF-8
fo_FO.UTF-8 UTF-8
fr_BE.UTF-8 UTF-8
fr_CA.UTF-8 UTF-8
fr_CH.UTF-8 UTF-8
fr_FR.UTF-8 UTF-8
fr_LU.UTF-8 UTF-8
fur_IT UTF-8
fy_NL UTF-8
fy_DE UTF-8
ga_IE.UTF-8 UTF-8
gd_GB.UTF-8 UTF-8
gez_ER UTF-8
gez_ER@abegede UTF-8
gez_ET UTF-8
gez_ET@abegede UTF-8
gl_ES.UTF-8 UTF-8
gu_IN UTF-8
gv_GB.UTF-8 UTF-8
ha_NG UTF-8
hak_TW UTF-8
he_IL.UTF-8 UTF-8
hi_IN UTF-8
hif_FJ UTF-8
hne_IN UTF-8
hr_HR.UTF-8 UTF-8
hsb_DE.UTF-8 UTF-8
ht_HT UTF-8
hu_HU.UTF-8 UTF-8
hy_AM UTF-8
ia_FR UTF-8
id_ID.UTF-8 UTF-8
ig_NG UTF-8
ik_CA UTF-8
is_IS.UTF-8 UTF-8
it_CH.UTF-8 UTF-8
it_IT.UTF-8 UTF-8
iu_CA UTF-8
ja_JP.UTF-8 UTF-8
ka_GE.UTF-8 UTF-8
kab_DZ UTF-8
kk_KZ.UTF-8 UTF-8
kl_GL.UTF-8 UTF-8
km_KH UTF-8
kn_IN UTF-8
ko_KR.UTF-8 UTF-8
kok_IN UTF-8
ks_IN UTF-8
ks_IN@devanagari UTF-8
ku_TR.UTF-8 UTF-8
kw_GB.UTF-8 UTF-8
ky_KG UTF-8
lb_LU UTF-8
lg_UG.UTF-8 UTF-8
li_BE UTF-8
li_NL UTF-8
lij_IT UTF-8
ln_CD UTF-8
lo_LA UTF-8
lt_LT.UTF-8 UTF-8
lv_LV.UTF-8 UTF-8
lzh_TW UTF-8
mag_IN UTF-8
mai_IN UTF-8
mai_NP UTF-8
mfe_MU UTF-8
mg_MG.UTF-8 UTF-8
mhr_RU UTF-8
mi_NZ.UTF-8 UTF-8
miq_NI UTF-8
mjw_IN UTF-8
mk_MK.UTF-8 UTF-8
ml_IN UTF-8
mn_MN UTF-8
mni_IN UTF-8
mnw_MM UTF-8
mr_IN UTF-8
ms_MY.UTF-8 UTF-8
mt_MT.UTF-8 UTF-8
my_MM UTF-8
nan_TW UTF-8
nan_TW@latin UTF-8
nb_NO.UTF-8 UTF-8
nds_DE UTF-8
nds_NL UTF-8
ne_NP UTF-8
nhn_MX UTF-8
niu_NU UTF-8
niu_NZ UTF-8
nl_AW UTF-8
nl_BE.UTF-8 UTF-8
nl_NL.UTF-8 UTF-8
nn_NO.UTF-8 UTF-8
nr_ZA UTF-8
nso_ZA UTF-8
oc_FR.UTF-8 UTF-8
om_ET UTF-8
om_KE.UTF-8 UTF-8
or_IN UTF-8
os_RU UTF-8
pa_IN UTF-8
pa_PK UTF-8
pap_AW UTF-8
pap_CW UTF-8
pl_PL.UTF-8 UTF-8
ps_AF UTF-8
pt_BR.UTF-8 UTF-8
pt_PT.UTF-8 UTF-8
quz_PE UTF-8
raj_IN UTF-8
ro_RO.UTF-8 UTF-8
ru_RU.UTF-8 UTF-8
ru_UA.UTF-8 UTF-8
rw_RW UTF-8
sa_IN UTF-8
sah_RU UTF-8
sat_IN UTF-8
sc_IT UTF-8
sd_IN UTF-8
sd_IN@devanagari UTF-8
se_NO UTF-8
sgs_LT UTF-8
shn_MM UTF-8
shs_CA UTF-8
si_LK UTF-8
sid_ET UTF-8
sk_SK.UTF-8 UTF-8
sl_SI.UTF-8 UTF-8
sm_WS UTF-8
so_DJ.UTF-8 UTF-8
so_ET UTF-8
so_KE.UTF-8 UTF-8
so_SO.UTF-8 UTF-8
sq_AL.UTF-8 UTF-8
sq_MK UTF-8
sr_ME UTF-8
sr_RS UTF-8
sr_RS@latin UTF-8
ss_ZA UTF-8
st_ZA.UTF-8 UTF-8
sv_FI.UTF-8 UTF-8
sv_SE.UTF-8 UTF-8
sw_KE UTF-8
sw_TZ UTF-8
szl_PL UTF-8
ta_IN UTF-8
ta_LK UTF-8
tcy_IN.UTF-8 UTF-8
te_IN UTF-8
tg_TJ.UTF-8 UTF-8
th_TH.UTF-8 UTF-8
the_NP UTF-8
ti_ER UTF-8
ti_ET UTF-8
tig_ER UTF-8
tk_TM UTF-8
tl_PH.UTF-8 UTF-8
tn_ZA UTF-8
to_TO UTF-8
tpi_PG UTF-8
tr_CY.UTF-8 UTF-8
tr_TR.UTF-8 UTF-8
ts_ZA UTF-8
tt_RU UTF-8
tt_RU@iqtelif UTF-8
ug_CN UTF-8
uk_UA.UTF-8 UTF-8
unm_US UTF-8
ur_IN UTF-8
ur_PK UTF-8
uz_UZ.UTF-8 UTF-8
uz_UZ@cyrillic UTF-8
ve_ZA UTF-8
vi_VN UTF-8
wa_BE.UTF-8 UTF-8
wae_CH UTF-8
wal_ET UTF-8
wo_SN UTF-8
xh_ZA.UTF-8 UTF-8
yi_US.UTF-8 UTF-8
yo_NG UTF-8
yue_HK UTF-8
yuw_PG UTF-8
zh_CN.UTF-8 UTF-8
zh_HK.UTF-8 UTF-8
zh_SG.UTF-8 UTF-8
zh_TW.UTF-8 UTF-8
zu_ZA.UTF-8 UTF-8
EOF
}

generate_mirrorlist () {
	cat <<EOF > mirrorlist
Server = https://ftp.halifax.rwth-aachen.de/archlinux/\$repo/os/\$arch
Server = https://mirror.pseudoform.org/\$repo/os/\$arch
Server = https://archlinux.thaller.ws/\$repo/os/\$arch
Server = https://mirror.chaoticum.net/arch/\$repo/os/\$arch
Server = https://mirror.f4st.host/archlinux/\$repo/os/\$arch
EOF
}

cd "${script_dir}" || exit 1

bootstrap="${script_dir}"/root.x86_64

chaoticaur_keyring="https://random-mirror.chaotic.cx/chaotic-aur/x86_64/chaotic-keyring-20201229-1-any.pkg.tar.zst"
chaoticaur_mirrorlist="https://random-mirror.chaotic.cx/chaotic-aur/x86_64/chaotic-mirrorlist-20210317-1-any.pkg.tar.zst"

packagelist="base base-devel nano mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon \
			vulkan-icd-loader lib32-vulkan-icd-loader nvidia-utils \
			lib32-nvidia-utils lib32-alsa-plugins wine-staging mesa-demos \
			vulkan-tools gst-plugins-good gst-plugins-bad gst-plugins-ugly \
			lib32-gst-plugins-good ttf-dejavu ttf-liberation lib32-openal \
			lib32-vkd3d vkd3d lib32-libva vulkan-intel lib32-vulkan-intel \
			winetricks lutris steam firefox mpv geany pcmanfm ppsspp dolphin-emu \
			git wget htop qbittorrent speedcrunch gpicview qpdfview squashfs-tools \
			file-roller xorg-xwayland steam-native-runtime nvidia-prime \
			meson mingw-w64-gcc gamemode lib32-gamemode cmake jre8-openjdk \
			libva-mesa-driver playonlinux libva-intel-driver lib32-libva-intel-driver \
			intel-media-driver"

chaotic_packagelist="wine-tkg-staging-fsync-git steamtinkerlaunch"

current_release="$(wget -q "https://archlinux.org/download/" -O - | grep "Current Release" | tail -c -16 | head -c +10)"

echo "Downloading ${current_release} release"
wget -q --show-progress -O arch.tar.gz "https://mirror.rackspace.com/archlinux/iso/${current_release}/archlinux-bootstrap-${current_release}-x86_64.tar.gz"
tar xf arch.tar.gz
rm arch.tar.gz

mount_chroot

generate_localegen
generate_mirrorlist

rm "${bootstrap}"/etc/locale.gen
cp locale.gen "${bootstrap}"/etc/locale.gen
rm locale.gen

rm "${bootstrap}"/etc/pacman.d/mirrorlist
cp mirrorlist "${bootstrap}"/etc/pacman.d/mirrorlist
rm mirrorlist

echo >> "${bootstrap}"/etc/pacman.conf
echo "[multilib]" >> "${bootstrap}"/etc/pacman.conf
echo "Include = /etc/pacman.d/mirrorlist" >> "${bootstrap}"/etc/pacman.conf

run_in_chroot pacman-key --init
run_in_chroot pacman-key --populate archlinux
run_in_chroot pacman -Syu --noconfirm
run_in_chroot pacman --noconfirm -S ${packagelist}
run_in_chroot locale-gen

if [ -n "${chaotic_packagelist}" ]; then
	run_in_chroot wget -O /opt/chaoticaur-keyring.tar.zst "${chaoticaur_keyring}"
	run_in_chroot wget -O /opt/chaoticaur-mirrorlist.tar.zst "${chaoticaur_mirrorlist}"
	run_in_chroot pacman --noconfirm -U /opt/chaoticaur-keyring.tar.zst
	run_in_chroot pacman --noconfirm -U /opt/chaoticaur-mirrorlist.tar.zst

	echo >> "${bootstrap}"/etc/pacman.conf
	echo "[chaotic-aur]" >> "${bootstrap}"/etc/pacman.conf
	echo "Include = /etc/pacman.d/chaotic-mirrorlist" >> "${bootstrap}"/etc/pacman.conf

	run_in_chroot pacman -Syu --noconfirm

	run_in_chroot pacman --noconfirm -Rdd wine-staging
	run_in_chroot pacman -S ${chaotic_packagelist}
fi

rm "${bootstrap}"/var/cache/pacman/pkg/*
mkdir "${bootstrap}"/media

unmount_chroot

clear
echo "Done"
