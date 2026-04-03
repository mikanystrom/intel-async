.SUFFIXES:
.NOTPARALLEL:
.DELETE_ON_ERROR:

# Makefile for CM3 white model build

MODEL_ROOT:=$(realpath ../../../..)
META_HOME:=$(realpath ../../../../..)/m3utils

OS_TARG=$(shell uname -m | sed 's/arm64/ARM64/' | sed 's/x86_64/AMD64/')_$(shell uname -s | tr a-z A-Z | sed 's/DARWIN/DARWIN/')
CM3?=cm3

SVPP=${META_HOME}/rdl/svpp/$(OS_TARG)/svpp
PERLFE=${META_HOME}/perlfe/$(OS_TARG)/perlfe

NEBULON?=

MBY_C_ROOT=../c
MBY_C_TARGDIR=$(MBY_C_ROOT)/$(OS_TARG)
MBY_C_LIB=$(MBY_C_TARGDIR)/libmby_c_model.a

WM_SUPPORT_ROOT=wm_support
WM_SUPPORT_TARGDIR=$(WM_SUPPORT_ROOT)/$(OS_TARG)
WM_SUPPORT=$(WM_SUPPORT_ROOT)/$(OS_TARG)/.done

WM_NET_ROOT=$(realpath wm_net)
WM_NET_TARGDIR=$(WM_NET_ROOT)/$(OS_TARG)
WM_NET_LIB=$(WM_NET_TARGDIR)/libwm_net.a

GENVIEWS_ROOT=genviews
GENVIEWS_TARGDIR=$(GENVIEWS_ROOT)/$(OS_TARG)
GENVIEWS=$(GENVIEWS_TARGDIR)/genviews

FIELDVISITOR_ROOT=genviews/fieldvisitor
FIELDVISITOR_TARGDIR=$(FIELDVISITOR_ROOT)/$(OS_TARG)
FIELDVISITOR=$(FIELDVISITOR_TARGDIR)/fieldvisitor

MBY_MAPFIELDS=mby.mapfields

SCALA_GEN=foo
C_GEN=bar
SCM_GEN=boo

STRUCTGEN_ROOT=structgen
STRUCTGEN_TARGDIR=$(STRUCTGEN_ROOT)/$(OS_TARG)
STRUCTGEN=$(STRUCTGEN_TARGDIR)/structgen

STRUCTGEN_SHARED=$(WM_NET_ROOT)/src/structgen_shared.scm
STRUCTGEN_M3=$(WM_NET_ROOT)/src/structgen_m3.scm
STRUCTS_M3=$(WM_NET_ROOT)/src/structs_m3.scm
STRUCTGEN_SCALA=$(WM_NET_ROOT)/src/structgen_scala.scm
STRUCTS_SCALA=$(WM_NET_ROOT)/src/structs_scala.scm
STRUCTGEN_TOP=$(WM_NET_ROOT)/src/structs.scm

M3_STRUCTS=$(WM_NET_TARGDIR)/derived.m3m
SCALA_STRUCTS=$(WM_NET_ROOT)/scala_generated/derived_scala.filelist
SCALA_IMPLICITS=$(WM_NET_ROOT)/scala_generated/Implicits.scala

MBY_TOP_RDL=../../../../tools/srdl/mby/mby_top_map.rdl
MBY_BUILD_ROOT=$(GENVIEWS_ROOT)/src/build/mby
MBY_BUILD_C_ROOT=$(GENVIEWS_ROOT)/src/build_c/mby_c
MBYLIB=$(MBY_BUILD_ROOT)/$(OS_TARG)/libmby.a

MBY_SCM=$(GENVIEWS_ROOT)/src/build_c/mby_c/src/mby_top_map.scm

MODEL_SERVER_ROOT=model_server
MODEL_SERVER_TARGDIR=$(MODEL_SERVER_ROOT)/$(OS_TARG)
MODEL_SERVER=$(MODEL_SERVER_TARGDIR)/modelserver
META_STRUCTS=$(MODEL_SERVER_ROOT)/src/mby_struct/$(OS_TARG)/libmby_struct.a
INTERLANG=$(MODEL_SERVER_ROOT)/src/interlang.scm

# Note: to override the path to hlp_top_map.rdl, use make HLP_TOP_RDL=<path>
ifeq ($(HLP_TOP_RDL),)
HLP_TOP_RDL=/p/hlp/hlp_release/drops/hlp-DROP_1P2-17ww50d/src/srdl/hlp_top_map.rdl
endif
HLP_BUILD_ROOT=$(GENVIEWS_ROOT)/src/build/hlp
HLPLIB=$(HLP_BUILD_ROOT)/$(OS_TARG)/libhlp.a

TOP=.top
TOP_TEMPLATE=top_template

# TEST_TARG=$(GENVIEWS_ROOT)/src/build/AMD64_LINUX/testme

# test: $(TEST_TARG)
# 	$(TEST_TARG)

.PHONY: all
all: mains fulcrum_consts

.PHONY: mains
mains: mby_mains hlp_mains model_server doc

top: $(TOP)
$(TOP): $(TOP_TEMPLATE)
	sed "s#MODEL_ROOT#$(MODEL_ROOT)#" $< | sed "s#META_HOME#$(META_HOME)#" > $@

mby_mains: $(GENVIEWS) $(MBYLIB) $(C_GEN)
	$(MAKE) CM3=$(CM3) -C $(GENVIEWS_ROOT)/src/mby_mains

hlp_mains: $(HLPLIB)

$(WM_SUPPORT): $(wildcard $(WM_SUPPORT_ROOT)/src/*) $(TOP)
	pushd $(WM_SUPPORT_ROOT)/src && $(CM3) -x
	touch $@

wm_support: $(WM_SUPPORT)

$(GENVIEWS): $(wildcard $(GENVIEWS_ROOT)/src/*) $(WM_SUPPORT) $(TOP)
	pushd $(GENVIEWS_ROOT)/src && $(CM3) -x

$(FIELDVISITOR): $(wildcard $(GENVIEWS_ROOT)/src/*) $(GENVIEWS) $(MBYLIB) $(HLPLIB)
	pushd $(FIELDVISITOR_ROOT)/src && $(CM3) -x

%.mapfields: $(FIELDVISITOR) $(MBYLIB)
	mkdir -p $(dir $@)
	$(FIELDVISITOR) -m $(notdir $(basename $@)) -o $@

%_consts_pkg.vh: %.mapfields $(GENVIEWS)
	$(eval top = $(notdir $(subst _consts_pkg.vh,,$@)))
	mkdir -p $(dir $@)
	$(GENVIEWS) -L sv-fulcrum -bits 28 -top $(top) -o $(dir $@) -f $< -i $(MBY_POSTPROC) -packagename $(notdir $(basename $@)) -of $(notdir $@)

$(STRUCTGEN): $(wildcard $(STRUCTGEN_ROOT)/src/*) $(WM_SUPPORT) $(TOP)
	pushd $(STRUCTGEN_ROOT)/src && $(CM3) -x

$(M3_STRUCTS): $(STRUCTGEN) $(STRUCTGEN_SHARED) $(STRUCTGEN_M3) $(STRUCTGEN_TOP)
	mkdir -p $(dir $@)
	pushd $(WM_NET_ROOT)/src && $(realpath $<) $(STRUCTGEN_SHARED) $(STRUCTGEN_M3) $(STRUCTS_M3) $(STRUCTGEN_TOP)

$(SCALA_STRUCTS): $(STRUCTGEN) $(STRUCTGEN_SHARED) $(STRUCTGEN_SCALA) $(STRUCTS_SCALA) $(STRUCTGEN_TOP)
	mkdir -p $(dir $@)
	pushd $(WM_NET_ROOT)/src && $(realpath $<) $(STRUCTGEN_SHARED) $(STRUCTGEN_SCALA) $(STRUCTS_SCALA) $(STRUCTGEN_TOP)
	rm -rf $(SCALA_IMPLICITS)
	$(eval tmp_scala_implicits = $(shell mktemp))
	echo "package com.intel.cg.hpfd.madisonbay.wm.server.dto" > $(tmp_scala_implicits)
	echo "import java.io._" >> $(tmp_scala_implicits)
	echo "object Implicits {" >> $(tmp_scala_implicits)
	grep -h implicit $(WM_NET_ROOT)/scala_generated/{Fm,Iosf}* >> $(tmp_scala_implicits)
	echo "}" >> $(tmp_scala_implicits)
	mv $(tmp_scala_implicits) $(SCALA_IMPLICITS)

$(META_STRUCTS): $(STRUCTGEN) $(INTERLANG) $(MBY_SCM) $(C_GEN)
	mkdir -p $(MODEL_SERVER_ROOT)/src/mby_struct/src
	mkdir -p $(MODEL_SERVER_ROOT)/src/wm_meta_common/src
	pwd
	cd $(MODEL_SERVER_ROOT)/src && ../../structgen/$(OS_TARG)/structgen interlang.scm exit
	cd $(MODEL_SERVER_ROOT)/src/wm_meta_common/src && $(CM3) -x
	cd $(MODEL_SERVER_ROOT)/src/mby_struct/src && $(CM3) -x

rpc_structs: $(M3_STRUCTS) $(SCALA_STRUCTS) $(META_STRUCTS)

MBY_POSTPROC = work/mby_postproc.rdl
$(MBY_POSTPROC): $(MBY_TOP_RDL) $(wildcard $(dir $(MBY_TOP_RDL))/*.rdl)
	mkdir -p work
	${SVPP} --path $(NEBULON)/include:$(dir $<) < $< > work/i1.rdl
	${PERLFE} < work/i1.rdl > work/i2.rdl
	export PERL5LIB=$(dir $<).. && cat work/i2.rdl | perl > $@

$(MBY_SCM): $(MBY_POSTPROC) $(GENVIEWS) rpc_structs $(META_STRUCTS)
	mkdir -p $(MBY_BUILD_ROOT)/src
	$(GENVIEWS_TARGDIR)/genviews -L m3 -top mby_top_map -o $(MBY_BUILD_ROOT)/src < $<
	cp $(GENVIEWS_ROOT)/src/boilerplate/m3overrides $(MBY_BUILD_ROOT)/src
	sed 's/THELIB/mby/' $(GENVIEWS_ROOT)/src/boilerplate/m3makefile > $(MBY_BUILD_ROOT)/src/m3makefile

$(MBYLIB): $(MBY_POSTPROC) $(GENVIEWS) rpc_structs $(MBY_SCM)
	cd $(MBY_BUILD_ROOT)/src && $(CM3) -x

$(SCALA_GEN): $(MBY_POSTPROC) $(GENVIEWS)
	mkdir -p $(MBY_BUILD_ROOT)/src
	$(GENVIEWS_TARGDIR)/genviews -L scala -top mby_top_map -o $(MBY_BUILD_ROOT)/src < $<

scalagen: $(SCALA_GEN)

$(C_GEN): $(MBY_POSTPROC) $(GENVIEWS)
	mkdir -p $(MBY_BUILD_C_ROOT)/src
	$(GENVIEWS_TARGDIR)/genviews -L c -top mby_top_map -o $(MBY_BUILD_C_ROOT)/src < $<
	cd $(MBY_BUILD_C_ROOT)/src && $(CM3) -x

cgen: $(C_GEN)

$(MBY_C_LIB): $(C_GEN)
	$(MAKE) -C ../c DEBUG=1 VERBOSE=1 -j 30 all

$(SCM_GEN): $(MBY_POSTPROC) $(GENVIEWS) 
	mkdir -p $(MBY_BUILD_SCM_ROOT)/src
	$(GENVIEWS_TARGDIR)/genviews -L scm -top mby_top_map -o $(MBY_BUILD_SCM_ROOT)/src < $<

scmgen: $(SCM_GEN)

$(MBY_CAPI_LIB): $(SCM_GEN)
	echo

$(HLPLIB): $(HLP_TOP_RDL) $(GENVIEWS)
	mkdir -p work
	${SVPP} --path $(NEBULON)/include:$(dir $<) < $< > work/i1.rdl
	${PERLFE} < work/i1.rdl > work/i2.rdl
	export PERL5LIB=$(dir $<) && cat work/i2.rdl | perl > work/i3.rdl
	mkdir -p $(HLP_BUILD_ROOT)/src
	$(GENVIEWS_TARGDIR)/genviews -L m3 -top hlp_top_map -o $(HLP_BUILD_ROOT)/src < work/i3.rdl
	cp $(GENVIEWS_ROOT)/src/boilerplate/m3overrides $(HLP_BUILD_ROOT)/src
	sed 's/THELIB/hlp/' $(GENVIEWS_ROOT)/src/boilerplate/m3makefile > $(HLP_BUILD_ROOT)/src/m3makefile
	cd $(HLP_BUILD_ROOT)/src && $(CM3) -x

$(WM_NET_LIB): $(STRUCTGEN) $(GENVIEWS) $(HLPLIB)
	cd wm_net && $(CM3) -x


$(MODEL_SERVER): $(WM_NET_LIB) $(WM_SUPPORT) $(HLPLIB) $(MBYLIB) $(MBY_C_LIB)
	cd model_server && $(CM3) -x

model_server: $(MODEL_SERVER)
fieldvisitor: $(FIELDVISITOR)

CONSTS_TARGDIR = $(MODEL_ROOT)/target/gen_mby_wm_m3/
FULCRUM_CONSTS = $(addprefix $(CONSTS_TARGDIR),mby_ppe_rx_top_map_consts_pkg.vh mby_ppe_tx_top_map_consts_pkg.vh)
CONSTS_HDL     = $(CONSTS_TARGDIR)/mby_fulcrum_legacy_rtl.hdl

$(CONSTS_HDL):  genviews/fieldvisitor/src/mby_fulcrum_legacy_rtl.hdl $(FULCRUM_CONSTS)
	cp $< $@

fulcrum_consts: $(FULCRUM_CONSTS) $(CONSTS_HDL)

doc:
	$(MAKE) -C $(MBY_C_ROOT)/doc 

$(TEST_TARG): $(GENVIEWS)
	pushd $(GENVIEWS_ROOT)/src && ./test.sh

clean:
	rm -rf $(WM_SUPPORT_TARGDIR)
	rm -rf $(GENVIEWS_TARGDIR)
	rm -rf $(GENVIEWS_ROOT)/src/build
	rm -rf $(GENVIEWS_ROOT)/src/build_c
	rm -rf $(GENVIEWS_ROOT)/src/work
	rm -rf $(MODEL_SERVER_ROOT)/src/mby_struct
	rm -rf $(MODEL_SERVER_ROOT)/src/wm_meta_common
	rm -rf $(WM_NET_ROOT)/scala_generated
	rm -rf *.mapfields
	rm -rf *_consts_pkg.vh
	$(MAKE) -C $(MBY_C_ROOT)/doc clean
	find . -name $(OS_TARG) | xargs rm -rf
	find ../c -name $(OS_TARG) | xargs rm -rf
	rm -f $(TOP)
