#!/bin/sh -x
# Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information.
# SPDX-License-Identifier: Apache-2.0


SRC=hif_top_map_crif.xml

time ../AMD64_LINUX/genpg -skipholes -bits 48 -sv full.sv -copyrightpath ${MODEL_ROOT}/scripts/intelcopyright.txt -crif ${SRC} -G 8 MST_PG0 MST_PG1 MST_PG2 MST_PG3 MST_PG4 MST_PG5 MST_PG6 MST_PG7 -defpgnm DEFAULT_PG -basestrapbits some_pkg::BASE_STRAP_BITS --template hlp_pg_template.sv.tmpl 


