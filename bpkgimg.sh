#!/bin/sh

test -d /usr/src || exit 1

BOOTDISK="wd0"
IMAGEMB="2048" # 2048MB
SWAPMB="128" # 128MB

IMAGESECTORS="$(expr ${IMAGEMB} \* 1024 \* 1024 / 512)"
SWAPSECTORS="$(expr ${SWAPMB} \* 1024 \* 1024 / 512 || true)"

LABELSECTORS="0"

FSSECTORS="$(expr ${IMAGESECTORS} - ${SWAPSECTORS} - ${LABELSECTORS})"
FSSIZE="$(expr ${FSSECTORS} \* 512)"

HEADS="64"
SECTORS="32"
CYLINDERS="$(expr ${IMAGESECTORS} / \( ${HEADS} \* ${SECTORS} \))"
SECPERCYLINDERS="$(expr ${HEADS} \* ${SECTORS})"
MBRHEADS="255"
MBRSECTORS="63"
MBRCYLINDERS="$(expr ${IMAGESECTORS} / \( ${MBRHEADS} \* ${MBRSECTORS} \))"
MBRNETBSD="169"

BSDPARTSECTORS=$(expr ${IMAGESECTORS} - ${LABELSECTORS})
FSOFFSET=${LABELSECTORS}
SWAPOFFSET="$(expr ${LABELSECTORS} + ${FSSECTORS})"

FSCYLINDERS="$(expr ${FSSECTORS} / \( ${HEADS} \* ${SECTORS} \))"
SWAPCYLINDERS="$(expr ${SWAPSECTORS} / \( ${HEADS} \* ${SECTORS} \)) || true"

FSTAB_IN="/usr/src/distrib/common/bootimage/fstab.in"
SPEC_IN="/usr/src/distrib/common/bootimage/spec.in"

IMGMAKEFSOPTIONS="-o bsize=16384,fsize=2048,density=8192"

WORKDIR="${PWD}/bpkg"
WORKSPEC="bpkg.spec"
WORKFSTAB="bpkg.fstab"
WORKRCCONF="bpkg.rc.conf"
WORKFS="bpkg.rootfs"
TARGETFS="imgroot.fs"

mkdir ${WORKDIR}
pkg_add -K /var/db/basepkg -P ${WORKDIR} packages/7.1.0_PATCH/amd64/base-*.tgz
pkg_add -K /var/db/basepkg -P ${WORKDIR} -I packages/7.1.0_PATCH/amd64/etc-*.tgz
cp -f ${WORKDIR}/usr/mdec/boot ${WORKDIR}

sed "s/@@BOOTDISK@@/${BOOTDISK}/" < ${FSTAB_IN} > ${WORKFSTAB}
cp ${WORKFSTAB} ${WORKDIR}/etc/fstab

sed "s/rc_configured=NO/rc_configured=YES/" < ${WORKDIR}/etc/rc.conf > ${WORKRCCONF}
cp ${WORKRCCONF} ${WORKDIR}/etc/rc.conf

cat ${WORKDIR}/etc/mtree/* | sed -e 's/ size=[0-9]*//' > ${WORKSPEC}
sh ${WORKDIR}/dev/MAKEDEV -s all | sed -e '/^\. type=dir/d' -e 's,^\.,./dev,' >> ${WORKSPEC}
cat ${SPEC_IN} >> ${WORKSPEC}
echo "./boot type=file uname=root gname=wheel mode=04444" >> ${WORKSPEC}

chmod +r ${WORKDIR}/var/spool/ftp/hidden
makefs -M ${FSSIZE} -m ${FSSIZE} \
       -B 1234 \
       -F ${WORKSPEC} -N ${WORKDIR}/etc \
       ${IMGMAKEFSOPTIONS} ${WORKFS} ${WORKDIR}

installboot -v -m amd64 ${WORKFS} ${WORKDIR}/usr/mdec/bootxx_ffsv1

DISKPROTO_IN="/usr/src/distrib/common/bootimage/diskproto.in"

MBR_DEFAULT_BOOTCODE="mbr"
OMIT_SWAPIMG="no"

WORKMBR="bpkg.mbr"
WORKSWAP="bpkg.swap"
WORKLABEL="bpkg.diskproto"
WORKIMG="bpkg.img"

sed \
    -e "s/@@SECTORS@@/${SECTORS}/" \
    -e "s/@@HEADS@@/${HEADS}/" \
    -e "s/@@SECPERCYLINDERS@@/${SECPERCYLINDERS}/" \
    -e "s/@@CYLINDERS@@/${CYLINDERS}/" \
    -e "s/@@IMAGESECTORS@@/${IMAGESECTORS}/" \
    -e "s/@@FSSECTORS@@/${FSSECTORS}/" \
    -e "s/@@FSOFFSET@@/${FSOFFSET}/" \
    -e "s/@@SWAPSECTORS@@/${SWAPSECTORS}/" \
    -e "s/@@SWAPOFFSET@@/${SWAPOFFSET}/" \
    -e "s/@@BSDPARTSECTORS@@/${BSDPARTSECTORS}/" \
    < ${DISKPROTO_IN} > ${WORKLABEL}.tmp
mv ${WORKLABEL}.tmp ${WORKLABEL}

cp ${TARGETFS} ${WORKIMG}

dd if=/dev/zero of=${WORKSWAP} seek=$(expr ${SWAPSECTORS} - 1) count=1
cat ${WORKSWAP} >> ${WORKIMG}
disklabel -R -F ${WORKIMG} ${WORKLABEL}
