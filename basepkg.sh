#!/usr/bin/env sh
#
# Copyright (c) 2016,2017 Yuuki Enomoto  
# All rights reserved.  
#   
# Redistribution and use in source and binary forms, with or without  
# modification, are permitted provided that the following conditions are met:  
#   
# * Redistributions of source code must retain the above copyright notice, 
#   this list of conditions and the following disclaimer.  
#   
# * Redistributions in binary form must reproduce the above copyright notice,  
#   this list of conditions and the following disclaimer in the documentation  
#   and/or other materials provided with the distribution.  
#   
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"  
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE  
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE  
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE  
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL  
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR  
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER  
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,  
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE  
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.  

# POSIX Utilities
AWK="/usr/bin/awk"
BASENAME="/usr/bin/basename"
CAT="/bin/cat"
CHGRP="/bin/chgrp"
CHMOD="/bin/chmod"
CHOWN="/sbin/chown"
CUT="/usr/bin/cut"
DATE="/bin/date"
ECHO="/bin/echo"
ENV="/usr/bin/env"
EXPR="/bin/expr"
FILE="/usr/bin/file"
GREP="/usr/bin/grep"
LS="/bin/ls"
MKDIR="/bin/mkdir"
MV="/bin/mv"
RM="/bin/rm"
RMDIR="/bin/rmdir"
SED="/usr/bin/sed"
SH="/bin/sh"
SORT="/usr/bin/sort"
TEST="/bin/test"
TOUCH="/usr/bin/touch"
TR="/usr/bin/tr"
UNAME="/usr/bin/uname"
UNIQ="/usr/bin/uniq"
XARGS="/usr/bin/xargs"

# Non POSIX Utilities
HOSTNAME="/bin/hostname"
MKTEMP="/usr/bin/mktemp"
STAT="/usr/bin/stat"
TAR="/bin/tar"
PKG_ADD="/usr/pkg/sbin/pkg_add"
PKG_CREATE="/usr/pkg/sbin/pkg_create"
PKG_DELETE="/usr/pkg/sbin/pkg_delete"

# Immutable variables
progname=${0##*/}
host="$(${HOSTNAME})"
machine="$(${UNAME} -m)"
machine_arch="$(${UNAME} -p)"
opsys="$(${UNAME})"
osversion="$(${UNAME} -r)"
pkgtoolversion="$(${PKG_ADD} -V)"
rcsid="\$NetBSD: basepkg.sh,v 0.01 `${DATE} '+%Y/%m/%d %H:%M:%S'` uki Exp $"
utcdate="$(${ENV} TZ=UTC LOCALE=C ${DATE} '+%Y-%m-%d %H:%M')"
user="${USER:-root}"
param="usr/include/sys/param.h"
lists="distrib/sets/lists"
comments="distrib/sets/comments"
descrs="distrib/sets/descrs"
deps="distrib/sets/deps"
tmp_deps="/tmp/culldeps"
basedir="basepkg/root"

err()
{
  ${ECHO} "[$(${DATE} +'%Y-%m-%dT%H:%M:%S')] $@" >&2
}

osrelease() {
  path=$0
  exec < ${destdir}/${param}

  while
    read define ver_tag rel_num comment_start NetBSD rel_text rest; do
      [ "${define}" = "#define" ] || continue;
      [ "${ver_tag}" = "__NetBSD_Version__" ] || continue
      break
  done
  rel_num=${rel_num%??}
  rel_MMmm=${rel_num%????}
  rel_MM=${rel_MMmm%??}
  rel_mm=${rel_MMmm#${rel_MM}}
  IFS=.
  set -- - $rel_text
  beta=${3#[0-9]}
  beta=${beta#[0-9]}
  shift 3
  IFS=' '
  set -- $rel_MM ${rel_mm#0}$beta $*
  IFS=.
  echo "$*"
}

# "extract" option use following function.
extract_base_binaries()
{
  i=""
  for i in `${LS} ${sets} | ${GREP} 'tgz$' | ${SED} 's/\.tgz//g'`; do
    if [ ! -d ${destdir} ]; then
      ${MKDIR} -p ${destdir}
    fi
    ${TAR} zxvf ${sets}/${i}.tgz -C ${destdir}
  done
}

# "dir" option use following functions.
split_category_from_lists()
{
  i=""
  j=""
  for i in ${category}; do
    if [ ! -d ./${i} ]; then
      ${MKDIR} ./${i}
    fi
    if [ -f ./${i}/FILES ]; then
      ${RM} -f ./${i}/FILES
    fi
    for j in `${LS} ${src}/${lists} | ${GREP} -v "^[A-Z]"`; do
      ${GREP} -E "${i}-[a-z]+-[a-z]+" ${src}/${lists}/${j}/mi | \
      ${AWK} '$3 !~ /obsolete/ {print}' | \
      ${SED} -e 's/^\.\///' -e '/^#/d' >> ./${i}/FILES
  
      if [ -f ${src}/${lists}/${j}/md.${machine} ]; then
        ${GREP} -E "${i}-[a-z]+-[a-z]+" ${src}/${lists}/${j}/md.${machine} | \
        ${AWK} '$3 !~ /obsolete/ {print}' | \
        ${SED} -e 's/^\.\///' -e '/^#/d' >> ./${i}/FILES
      fi
    done
  done
}

make_directories_of_package()
{
  i=""
  for i in ${category}; do
    ${AWK} '{print $2}' ./${i}/FILES | ${SORT} | ${UNIQ} | \
    ${XARGS} -n 1 -I % ${MKDIR} ./${i}/%
  done
}

# "list" option use following function.
make_contents_list()
{
  i=""
  for i in ${category}; do
    ${AWK} ' 
    # $1 - file name
    # $2 - package name
    $2 ~ /\./ {
      gsub(/\./, "-", $2)
    }
    {
      if($2 in lists)
        lists[$2] = $1 " " lists[$2]
      else
        lists[$2] = $1
    }
    END {
      for(pkg in lists)
        print pkg, lists[pkg]
    }' ${i}/FILES > ./${i}/CATEGORIZED
  done
  i=""
  j=""
  for i in ${category}; do
    for j in `${LS} ./${i} | ${GREP} '^[a-z]'`; do
      ${GREP} "${j}" ./${i}/CATEGORIZED | ${TR} ' ' '\n' | \
      ${AWK} 'NR != 1{print $0}' | ${SORT} | \
      ${GREP} -v -E "x${i}-[a-z]+-[a-z]+" > ./${i}/${j}/${j}.FILES
    done
  done
}

# "pkg" option use following functions.
make_BUILD_INFO()
{
  ${CAT} > ./$1/+BUILD_INFO << _BUILD_INFO_
OPSYS=${opsys}
OS_VERSION=${osversion}
OBJECT_FMT=ELF
MACHINE_ARCH=${machine_arch}
PKGTOOLS_VERSION=${pkgtoolversion}
_BUILD_INFO_
}

culc_deps()
{
  ${GREP} -E "^$1" ${src}/${deps} > /dev/null 2>&1
  if [ $? -eq 1 ]; then
    err "$1:Unknown package dependency."
    return 1
  fi
  ${GREP} -E "^$1" ${src}/${deps} | ${CUT} -d ' ' -f 2 | while read depend; do
    if [ ! "${depend}" ]; then
      return 1
    fi
    ${ECHO} "@pkgdep ${depend}>=`osrelease`" >> ${tmp_deps}
    if [ "${depend}" = "base-sys-root" ]; then
      return 0
    fi
    culc_deps ${depend}
  done
}

make_CONTENTS()
{
  TMPFILE=`${MKTEMP} -q`
  if [ $? -ne 0 ]; then
    err "$0: Can't create temp file, exiting..."
    exit 1
  fi
  setname=`${ECHO} $1 | ${CUT} -d '/' -f 1 | ${SED} 's/\./-/g'`
  pkgname=`${ECHO} $1 | ${CUT} -d '/' -f 2 | ${SED} 's/\./-/g'`
  ${ECHO} "@name ${pkgname}-`osrelease`" > ./$1/+CONTENTS
  ${ECHO} "@comment Packaged at ${utcdate} UTC by ${user}@${host}" \
  >> ./$1/+CONTENTS
  ${ECHO} "@comment Packaged using ${progname} ${rcsid}" >> ./$1/+CONTENTS
  if [ -f ${tmp_deps} ]; then
    ${RM} -f ${tmp_deps}
  fi
  culc_deps ${pkgname}
  if [ -f ${tmp_deps} ]; then
    ${SORT} ${tmp_deps} | ${UNIQ} >> ./$1/+CONTENTS
  fi
  ${ECHO} "@cwd ${prefix}/${basedir}" >> ./$1/+CONTENTS
  ${CAT} ./$1/${pkgname}.FILES | while read i; do
    if [ -d ${destdir}/${i} ]; then
      filename=`${ECHO} ${i} | ${SED} 's%\/%\\\/%g'`
      ${AWK} '$1 ~ /^\.\/'"${filename}"'$/{print $0}' ${destdir}/etc/mtree/set.${setname} | \
      ${SED} 's%^\.\/%%' | \
      ${AWK} '
      {
        print "@exec install -d -o root -g wheel -m "substr($5, 6) " "$1
      }
      ' >> ${TMPFILE}
    elif [ ! -f ${destdir}/${i} ]; then
      continue
    else
      ${ECHO} ${i} >> ${TMPFILE}
    fi
  done
  ${SORT} ${TMPFILE} >> ./$1/+CONTENTS
  ${RM} -f ${TMPFILE}
}

make_DESC_and_COMMENT()
{
  pkgname=`${ECHO} $1 | ${CUT} -d '/' -f 2 | ${SED} 's/\./-/g'`
  ${GREP} -e "^${pkgname}" ${src}/${descrs} | \
    ${SED} -e "s/${pkgname}//" | ${TR} -d '\t' > ./$1/+DESC
  ${GREP} -e "^${pkgname}" ${src}/${comments} | \
    ${SED} -e "s/${pkgname}//" | ${TR} -d '\t' > ./$1/+COMMENT
}

make_INSTALL()
{
  setname=`${ECHO} $1 | ${CUT} -d '/' -f 1 | ${SED} 's/\./-/g'`
  pkgname=`${ECHO} $1 | ${CUT} -d '/' -f 2 | ${SED} 's/\./-/g'`
  if [ -f ${setname}/${pkgname}/+INSTALL ]; then
    ${MV} ${setname}/${pkgname}/+INSTALL ${setname}/${pkgname}/+INSTALL.old
  fi
  if [ -f ${setname}/${pkgname}/+CONTENTS ]; then
    ${GREP} -v -e "^@" ${setname}/${pkgname}/+CONTENTS | while read file; do
      if [ `${ECHO} ${file} | ${CUT} -d "/" -f 1` = "etc" ]; then
        install_type="CONF"
      elif [ `${ECHO} ${file} | ${CUT} -d "/" -f 1` = "boot.cfg" ]; then
        install_type="CONF"
      else
        install_type="FILE"
      fi
      if [ -f /${file} ]; then
        mode_user_group=`${STAT} -f '%p %u %g' ${destdir}/${file} | \
        ${SED} 's/^[0-9]\{3\}//'`
      else
        mode_user_group=""
      fi
      ${ECHO} "# ${install_type}: /${file} ${file} ${mode_user_group}" \
      >> ${setname}/${pkgname}/+INSTALL
    done
    if [ -f ${setname}/${pkgname}/+INSTALL.old ]; then
      ${RM} -f ${setname}${pkgname}/+INSTALL.old
    fi
  else
    return 1
  fi
}

do_pkg_create()
{
  setname=`${ECHO} $1 | ${CUT} -d '/' -f 1 | ${SED} 's/\./-/g'`
  pkgname=`${ECHO} $1 | ${CUT} -d '/' -f 2 | ${SED} 's/\./-/g'`
  if [ -f $1/+INSTALL ]; then
    install_script="-i $1/+INSTALL"
  else
    install_script=""
  fi
  ${PKG_CREATE} -v -l -U -B $1/+BUILD_INFO -c $1/+COMMENT \
  -d $1/+DESC -f $1/+CONTENTS ${install_script} -p ${destdir} -K ${pkgdb} ${pkgname}
  if [ $? != 0 ]; then
    return $?
  fi
  if [ ! -d ${packages} ]; then
    ${MKDIR} ${packages}
  fi
  if [ ! -d ${packages}/All ]; then
    ${MKDIR} -p ${packages}/All
  fi
  ${MV} ./${pkgname}.tgz \
  ${packages}/All/${pkgname}-`osrelease`.tgz
}

make_packages()
{
  i=""
  j=""
  for i in ${category}; do
    for j in `${LS} ./${i} | ${GREP} -E '^[a-z]+'`; do
      ${ECHO} "Package ${i}/${j} Creating..."
      if [ ${new_package} = "true" ]; then
        make_BUILD_INFO ${i}/${j}
        make_CONTENTS ${i}/${j}
        make_DESC_and_COMMENT ${i}/${j}
        make_INSTALL ${i}/${j}
      fi
      do_pkg_create ${i}/${j}
    done
  done
}

# "install" option use following functions.
do_pkg_add()
{
  pkg_add_options=""
  ${TEST} -d ${prefix}/${basedir} || ${MKDIR} -p ${prefix}/${basedir}
  ${TEST} ${force} = "true" && pkg_add_options="-f"
  ${TEST} ${update} = "true" && pkg_add_options="-u ${pkg_add_options}"
  ${TEST} ${replace} = "true" && pkg_add_options="-U ${pkg_add_options}"
  pkg_add_options="-K ${pkgdb} -p ${prefix}/${basedir} ${pkg_add_options}"
  ${PKG_ADD} ${pkg_add_options} $@ || exit 1
  if [ $touch_system = "true" ]; then
    i=""
    for i in $@; do
      ${SED} -n "/^\# CONF: /{s/^\# CONF: //;p;}" \
      ${pkgdb}/`${BASENAME} ${i} | ${SED} 's/\.tgz$//'`/+INSTALL | ${SORT} -u |
      while read dst source mode user group; do
        case ${dst} in
          "") continue ;;
          [!/]*) dst="/${dst}" ;;
        esac
        case ${source} in
          "") continue ;;
          [!/]*) source="${prefix}/${basedir}/${source}" ;;
        esac
        if [ -f ${source} -a ! -f ${dst} ]; then
          case ${mode} in
            "") ;;
            *) ${CHMOD} ${mode} ${source} ;;
          esac
          case ${user} in
            "") ;;
            *) ${CHOWN} ${user} ${source} ;;
          esac
          case ${group} in
            "") ;;
            *) ${CHGRP} ${group} ${source} ;;
          esac
          mv ${source} ${dst}
        elif [ -f ${source} -a -f ${dst} ]; then
          ${ECHO} "${dst} is already exist. Ignore..."
        fi
      done
      ${SED} -n "/^\# FILE: /{s/^\# FILE: //;p;}" \
      ${pkgdb}/`${BASENAME} ${i} | ${SED} 's/\.tgz$//'`/+INSTALL | ${SORT} -u |
      while read dst source mode user group; do
        case ${dst} in
          "") continue ;;
          [!/]*) dst="/${dst}" ;;
        esac
        case ${source} in
          "") continue ;;
          [!/]*) source="${prefix}/${basedir}/${source}" ;;
        esac
        if [ -f ${source} ]; then
          case ${mode} in
            "") ;;
            *) ${CHMOD} ${mode} ${source} ;;
          esac
          case ${user} in
            "") ;;
            *) ${CHOWN} ${user} ${source} ;;
          esac
          case ${group} in
            "") ;;
            *) ${CHGRP} ${group} ${source} ;;
          esac
          ${MV} ${source} ${dst}
        fi
      done
    done
  fi
}

# "delete" option use following functions.
do_pkg_delete()
{
  if [ $touch_system = "true" ]; then
    real_prefix="/"
  else
    real_prefix="${prefix}/${basedir}"
  fi
  if [ ${force} = "true" ]; then
    pkg_delete_options="-f"
  else
    pkg_delete_options=""
  fi
  pkg_delete_options="-K ${pkgdb} -p ${real_prefix} ${pkg_delete_options}"
  ${PKG_DELETE} ${pkg_delete_options} $@ || exit 1
}

# "clean" option use following functions.
clean_packages()
{
  ${TEST} -d ${packages}/All || exit 1
  ls ${packages}/All | ${GREP} -E 'tgz$' | ${XARGS} -I % rm -f ${packages}/All/%
  ${RMDIR} ${packages}/All
  ${TEST} -d ${packages} || exit 1
  ${RMDIR} ${packages}
}

clean_categories()
{
  i=""
  j=""
  for i in ${category}; do
    ${TEST} -f ./${i}/FILES && ${RM} -f ./${i}/FILES
    ${TEST} -f ./${i}/CATEGORIZED && ${RM} -f ./${i}/CATEGORIZED
    for j in `ls ./${i}`; do
      ${TEST} -f ./${i}/${j}/+BUILD_INFO && ${RM} -f ./${i}/${j}/+BUILD_INFO
      ${TEST} -f ./${i}/${j}/+COMMENT && ${RM} -f ./${i}/${j}/+COMMENT
      ${TEST} -f ./${i}/${j}/+CONTENTS && ${RM} -f ./${i}/${j}/+CONTENTS
      ${TEST} -f ./${i}/${j}/+DESC && ${RM} -f ./${i}/${j}/+DESC
      ${TEST} -f ./${i}/${j}/${j}.FILES && ${RM} -f ./${i}/${j}/${j}.FILES
      ${TEST} -f ./${i}/${j}/+INSTALL && ${RM} -f ./${i}/${j}/+INSTALL
      ${TEST} -f ./${i}/${j}/+INSTALL.old && ${RM} -f ./${i}/${j}/+INSTALL.old
      ${RMDIR} ./${i}/${j}
    done
    ${RMDIR} ./${i}
  done
}

# self-explanatorily :-)
usage()
{
  ${CAT} <<_usage_

Usage: ${progname} [--sets sets_dir] [--src src_dir] [--system]
                   [--pkg packages_dir] [--category category]
                   [--prefix prefix] [--pkgdb database_dir]
                   [--force] [--update] [--replace] operation

 Operation:
    extract             Extract base binary.
    pkg                 Create packages.
    install             Install packages to ${prefix}/${basedir}.
                        If --system option using, install package to /.
    delete              Uninstall packages at ${prefix}/${basedir}.
                        If --system option using, delete package from /.
    cleanpkg            Remove all packages.

 Operation for Developer:
    dir                 Create packages directory.
    list                Create packages list.
    cleandir            Remove all categorized directories.

 Options:
    --help              Show this message and exit.
    --sets              Set sets to extract tarballs.
                        [Default: /usr/obj/releasedir/${machine}/binary/sets]
    --src               Set src to NetBSD source directory.
                        [Default: /usr/src]
    --obj               Set obj to NetBSD binaries.
                        [Default: ${PWD}]
    --pkg               Set packages root directory; sets a PACKAGES pattern.
                        [Default: ./packages]
    --category          Set category.
                        [Default: "base comp etc games man misc text"]
    --prefix            Set package's prefix.
                        [Default: "/usr/pkg"]
    --system            If install/delete operation with this option,
                        install to/delete from /.
    --pkgdb             Set pkgdb to package's database.
                        [Default: "/var/db/basepkg"]
    --new               Set new_package to create 
                        file of package's information newly.
    --force             Add "-f" option to pkg_add and pkg_delete command.
    --update            Add "-u" option to pkg_add and pkg_delete command.
    --replace           Add "-U" option to pkg_add command.

_usage_
  exit 1
}

get_optarg()
{
  ${EXPR} "x$1" : "x[^=]*=\\(.*\\)"
}

# parse long-options
while [ $# -gt 0 ]; do
  case $1 in
    -h|--help)
      usage; exit ;;
    --sets=*)
      sets=`get_optarg "$1"` ;;
    --sets)
      ${TEST} -z $2 && err "What is $1 parameter?" ; exit 1
      sets=$2
      shift ;;
    --src=*)
      src=`get_optarg "$1"` ;;
    --src)
      ${TEST} -z $2 && err "What is $1 parameter?" ; exit 1
      src=$2
      shift ;;
    --obj)
      ${TEST} -z $2 && err "What is $1 parameter?" ; exit 1
      obj=$2
      shift ;;
    --obj=*)
      obj=`get_optarg "$1"` ;;
    --pkg=*)
      packages=`get_optarg "$1"` ;;
    --pkg)
      ${TEST} -z $2 && err "What is $1 parameter?" ; exit 1
      packages=$2
      shift ;;
    --category=*)
      category=`get_optarg "$1"` ;;
    --category)
      ${TEST} -z $2 && err "What is $1 parameter?" ; exit 1
      category="$2"
      shift ;;
    --prefix=*)
      prefix=`get_optarg "$1"` ;;
    --prefix)
      ${TEST} -z $2 && err "What is $1 parameter?" ; exit 1
      prefix="$2"
      shift ;;
    --system)
      touch_system="true"
      pkgdb="/var/db/basepkg" ;;
    --new)
      new_package="true" ;;
    --pkgdb=*)
      pkgdb=`get_optarg "$1"` ;;
    --pkgdb)
      ${TEST} -z $2 && err "What is $1 parameter?" ; exit 1
      pkgdb="$2"
      shift ;;
    --force)
      force="true" ;;
    --update)
      update="true" ;;
    --replace)
      replace="true" ;;
    -|--)
      break ;;
    *)
      break ;;
  esac
  shift
done

# Initialization
set -u
umask 0022
export LC_ALL=C LANG=C

${TEST} $# -eq 0 && usage

# Mutable variables
src=${src:="/usr/src"}
obj=${obj:="${PWD}"}
destdir="${obj}/destdir.${machine}"
packages=${packages:="./packages"}
sets=${sets:="/usr/obj/releasedir/${machine}/binary/sets"}
pkgdb=${pkgdb:="/usr/pkg/basepkg/root/var/db/basepkg"}
category=${category:="base comp etc games man misc text"}
prefix=${prefix:="/usr/pkg"}
touch_system=${touch_system:="false"}
new_package=${new_package:="false"}
force=${force:="false"}
update=${update:="false"}
replace=${replace:="false"}

# operation
case $1 in
  extract)
    extract_base_binaries ;;
  dir) 
    split_category_from_lists
    make_directories_of_package ;;
  list)
    make_contents_list ;;
  pkg)     
    if [ ${new_package} = "true" ]; then
      clean_categories
      split_category_from_lists
      make_directories_of_package
      make_contents_list
    elif [ ! -f ${packages}/.touched ]; then
      split_category_from_lists
      make_directories_of_package
      make_contents_list
    fi
    make_packages
    touch ${packages}/.touched ;;
  install)
    shift
    do_pkg_add $@ ;;
  delete)
    shift
    do_pkg_delete $@ ;;
  cleanpkg)
    clean_packages ;;
  cleandir)
    clean_categories ;;
  *)
    usage ;;
esac

exit 0
