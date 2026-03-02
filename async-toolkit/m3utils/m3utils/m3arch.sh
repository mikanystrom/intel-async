#!/bin/sh
# Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information.
# SPDX-License-Identifier: Apache-2.0

#
# $Id: m3arch.sh,v 1.4 2009/11/08 22:05:28 mika Exp $
#
UNAME=uname
TR=tr

OS=`${UNAME} -s`
PROCESSOR=`${UNAME} -m`
PROCESSOR2=`${UNAME} -p`
# FreeBSD Specific Assumptions at work
VERSION=`${UNAME} -r`
MAJORNUM=`echo $VERSION | awk 'BEGIN {FS=""} {print $1}'`

# Very inaccurate OS detection
if [  "x$OS" = "xFreeBSD" ]; then
  if [ "x$PROCESSOR" = "xamd64" ]; then
    M3ARCH="AMD64_FREEBSD"
  elif [ "x$PROCESSOR" = "xi386" ]; then
    if [ "x$MAJORNUM" = "x3" ]; then
      M3ARCH="FreeBSD3"
    else
      M3ARCH="FreeBSD4"
    fi
  fi
elif [ "x$OS" = "xDarwin" -a "x$PROCESSOR" = "xarm64" ]; then
  M3ARCH="ARM64_DARWIN"
elif [ "x$OS$PROCESSOR2" = "xDarwini386" ]; then
  M3ARCH="I386_DARWIN"
elif [ "x$OS$PROCESSOR2" = "xDarwinpowerpc" ]; then
  M3ARCH="PPC_DARWIN"
elif [ "x$OS" = "xLinux" ]; then
  if [ "x$PROCESSOR" = "xx86_64" ]; then
    M3ARCH="AMD64_LINUX"
  else
    M3ARCH="LINUXLIBC6"
  fi
else
  exit 1
fi
echo $M3ARCH
