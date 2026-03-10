#
# Copyright (c) 1999-2006 California Institute of Technology
# Copyright (c) 2006-2009 Generation Capital, Ltd.
# All rights reserved.
#
# Permission to use, copy, modify, and distribute this software
# and its documentation for any purpose and without fee is hereby
# granted, provided that the above copyright notice appear in all
# copies. The California Institute of Technology and 
# Generation Capital, Ltd. make no representations
# about the suitability of this software for any purpose. It is
# provided "as is" without express or implied warranty. Export of this
# software outside of the United States of America may require an
# export license.
#
# $Id: Makefile,v 1.293 2011/02/17 00:42:36 mika Exp $
#

# THIS Makefile IS FOR GNU MAKE ("gmake")

#
# Build order has been revised as of 1/13/2005
#
# New build order reduces dependencies of Modula-3 on C, builds
# Modula-3 first, then C.  Default behavior is to build ONLY
# Modula-3 code in BIN_DIR subdirectories and not to touch
# shared directories.
#
# currently, this is the build order:
#
# Phase I.    Target "std"
# 0. <a hack: .top>
# 1. SHIPDIRS     --   Modula-3 libraries
# 2. M3SUBS       --   Modula-3 programs
#
# Phase II.   Target "withlinks"
# 00. <another hack: .bindir>
# 3. BROWSEREXPS  --   Export misc programs in subdirectories for m3browser
# 4. binlinks     --   make symlinks to programs that were built
# 
# Phase IIb.  Target "regress"
# 3. REGSUBS      --   Modula-3 programs
#
# Phase IIc.  Target "regressfix"
# 3. fix REGSUBS  --   Modula-3 programs
#
# Phase III.  Target "all"
# 5. COMMONDIRS   --   C libraries
# 6. SUBDIRS      --   C programs
#
# The default target is "std"
#
# default is to make with m3build (PM3)
# if you prefer CM3, run "make -DCM3"
# if you want make to continue past errors, run "make -DPROCEED"
#
#
#
# In the long run, we'd like to get rid of COMMONDIRS and SUBDIRS and
# put everything under the control of m3build.
#

# global defs, esp. M3BUILDPROGRAM
include Make.defs

ifdef PROCEED
PROCEEDCMD="true"
else
PROCEEDCMD="false"
endif

COMMONDIRS=processor crt m3yacc prsparse
COMMONS=`./dirsexist.sh -f $(COMMONDIRS)`
REVCOMMONS=`./dirsexist.sh -r $(COMMONDIRS)`

# "SHIPS" are subdirectories containing Modula-3 libraries that
# would normally be shipped to /usr/local/lib/m3.
# We need to make sure that we clean them in reverse order of 
# building since they may depend on other libraries (1 way only)

PARSERLIBS=parserlib/ktoklib parserlib/kyacclib parserlib/klexlib parserlib/ktok parserlib/klex parserlib/kyacc parserlib/kext parserlib/parserlib

SHIPDIRS=commandrw o3texthack cit_util m3browserhack stabletable term $(PARSERLIBS) tasks trie vlsi/angbrmacro defmacro matrix vlsi/magic vlsi/magicextras cptr bool vlsi/sop mst vlsi/boxes vlsi/simplegrid rpc vlsi/router cit_parse paneman drawcontext drawcontext/dcpane vlsi/m3-3 minimize convex integrate splines softmax pattern gatematrix colc tree optree vlsi/operators vlsi/celldb vlsi/matcher vlsi/sysiphus/sysiphus_parse vlsi/sysiphus/sysiphus_lib verif/tuple ld/ld_parse ld cs2/cs2 labeltest m3curses gnuplot xmlparse tz mscheme/schemesig mscheme/scheme-lib mscheme/modula3scheme calarm/sx mscheme/schemereadline calarm/gw calarm/csv lockf newuoa cobyla globe/globelib globe/geodata globe/airports

SHIPS=`./dirsexist.sh -f $(SHIPDIRS)`
REVSHIPS=`./dirsexist.sh -r $(SHIPDIRS)`
M33STUFF=m3-3

SUBDIRS= `./dirsexist.sh -f bas newsim psim pslnew m3hier Parse calarm/jdata/jdatagw`

CS2TARGETS=cs2/othello/digest cs2/othello/play cs2/othello/random cs2/othello/recursive2 cs2/othello/recursive4 cs2/othello/recursive6 cs2/othello/recursive7 cs2/othello/referee cs2/othello/setup

M3SUBS= `./dirsexist.sh -f magraster finite_diff deriv tasktest cit_parse/testprs paneman/kemacs drawcontext/test drawcontext/kgv m3-3/display m3-3/bufchain m3-3/icache et2 testsplines gatematrix/gm angbrmacro/ab cit_util/test_rats cit_util/test_store cit_util/test_bigs tree/test prlink matcher/xprs2stack stackgen sysiphus sysiphus/sysiphlat sysiphus/sysiphix sysiphus/sudafed acat router/pauls router/pauls2 router/pauls3 router/pauls4 router/gentest router/conflictdensity verif dagflat allias myrope magic/magsize playfile decimate cpdag magicextras/testslasher ld/fixdag ld/ld2layoutd $(CS2TARGETS) gnuplot/test`

REGSUBS= `./dirsexist.sh -f sv/svparse sv/svsynth sv/svpp fileupdatewr calarm/m3readline/c calarm/m3readline/test calarm/finlib calarm/finlib/testdate calarm/keylib calarm/alarm calarm/anova postgresql calarm/wavelets calarm/getquotes calarm/transpose_rates calarm/keypaste m3curses/test calarm/wavelets/test color calarm/twslib  calarm/twslib/pricemonitor calarm/hftrading calarm/regresslib calarm/traderulelib calarm/fastrw calarm/fasthf calarm/fastrw/datagen calarm/marketdatadump calarm/marketdatadump/program calarm/ratsql  marching marching/program marching/interpolate calarm/anova/gnuplotter calarm/anova/gnuplotter/test calarm/gridctl  calarm/twslib/twslogger calarm/smarttraderule  calarm/anova/program calarm/anova/anovadelta calarm/anova/tabulate  calarm/picktickers  calarm/twslib/test  calarm/trade calarm/anova/testtex calarm/anova/curves calarm/findate calarm/regress/ximport calarm/regress/tsximport calarm/regress/adjust calarm/regress/qmctl calarm/regress/hcdriver calarm/twslib/test calarm/twslib/switchtickers calarm/regress/bloombimport calarm/autotrade calarm/m2m calarm/pricewatch calarm/twslib/twslive calarm/twslib/twslibtest calarm/twslib/testtrade  calarm/m3gen calarm/fix/gen calarm/fix/fixcommon calarm/fix/fix40 calarm/fix/fix41 calarm/fix/fix42 calarm/twslib/testtrade2/inventory calarm/twslib/testtrade2/tradecore calarm/twslib/testtrade2/fixmonitor calarm/twslib/testtrade2/twsmonitor calarm/twslib/testtrade2/tradingstrategy calarm/mktsim calarm/mktsim/simbrownian calarm/mktsim/tradeisolator calarm/mktsim/fakecloses calarm/excelrtd calarm/twslib/testtest calarm/twslib/testtrade2/serverframework calarm/twslib/testtrade2/client calarm/twslib/testtrade2/server  calarm/excelrtd calarm/excelrtd/simple calarm/simplelock calarm/twslib/testpm calarm/twslib/testtrade2/inventory throttle calarm/pickletest calarm/traderulelib/getmktdata calarm/traderulelib/test_regression calarm/twslib/testtrade2/inventory/program calarm/grabtable calarm/gw/echogw calarm/gw/echopinger calarm/wavelets/test calarm/histogram calarm/trailingave calarm/regress/dcheck calarm/regress/resample ohai/ohailog ohai ohai/mailstats ohai/alarmer mscheme/interactive mscheme/interactive_r mscheme/doc mscheme/sstubgen mscheme/sstubgen/program htmltable calarm/regress/regressparsing calarm/marketmaking/marketmakingcommon calarm/marketmaking/marketmakingtestrule calarm/marketmaking/mmport calarm/marketmaking/mmrv calarm/ratsql/testupdate calarm/gcoms/gcomsdb calarm/gcoms/gcomslib calarm/gcoms/gcomsportfolio calarm/gcoms calarm/gcoms/gcomsdataextractor calarm/gcoms/gcomsinventory calarm/gcoms/gcomsdb/gcomsdbtest calarm/regress/calcmetric calarm/regress/fusedata calarm/gcmonitor/dollarparser calarm/gcmonitor/testdollar calarm/gcmonitor calarm/gcmonitor/examples/checkdumpdates calarm/gcmonitor/examples/checkfileage calarm/dpgui ukcg calarm/regress calarm/regress/regressrunner calarm/regress/processtd calarm/twslib/twslogger/simple calarm/twslib/twslogger/toohlc calarm/dumponeperiod calarm/euromm/eurolib calarm/euromm calarm/euromm/maptickers calarm/tradingscreen calarm/tradingscreen/testtsxml calarm/tradingscreen/tradingscreengw newuoa spice/gds2cast spice/spicelib nb/nbavail regression arithcode spice/unsaferdwr spice/rep16 spice/spicecompress spice/ctlib spice/tracelib spice/ct tcam/varlib tcam/spicebuilderlib spice/asserter spice/prsgen tcam/spicebuilder tcam/schmoozer stod pg pg/pglib pg/pgtool pg/overlaps perlfe sim1588 rdl/rdlparse rdl/svpp pg/pgtool semaphore wm_support wm_net wm_support/idstyles normaldev mismatch svspredict svspredict/histogram svspredict/postsi svspredict/program stdf/generator stdf stdf/stdfparser spice/spiceflat spice/spiceflat/program spice/spiceanalyze spice/vplot simpletoken mpfr/mpfr yield/diesplit parsesupport recursiveparse deflib/1 htmltable/cgidb braceparse/makekeywords braceparse glitch glitch/geneqs calarm/csv/csvalign liberty/parseliberty liberty liberty/libertyqc metalib metalib/arith wrap hammingnn hammingnn/test spice/techc spice/techc/digest spice/spicecompress/demo arithcode/demo spice/spicecompress/spicestream spice/counttrans spice/spicetiming spice/spicetiming/program spice/grabarray spice/tracelib/rewriter spice/tracelib/poweranal spice/spicecompress/demo spice/spicecompress/uncompress spice/variation/varosc spice/variation/varspice spice/variation/varopt spice/variation/varsrch spice/wavelet spice/schemagraph spice/schemagraph/program spice/schemagraph/schemaeval spice/genopt/genoptlib spice/genopt spice/genopt/chopstix spice/genopt/exampleprog spice/ringosc spice/ringosc/lowtemp spice/sislaunch gmp/mpz csp/cspparse csp/cspgrammar csp/cspsimlib csp/src`

BROWSEREXPS = `./dirsexist.sh -f cit_parse/testprs paneman/kemacs drawcontext/dcpane drawcontext/test drawcontext/kgv m3-3/display m3-3/bufchain m3-3/icache`


#
# RULES BELOW HERE
#

intel: at-intel std regress intel-install

at-intel: at-intel.done nanosimrd.done
at-intel.done:
	cd rdl/rdlparse/src; ./mk_inputs.sh
	touch at-intel.done

nanosimrd.done:
	cd spice/fsdb/src ; ./compile || true
	touch nanosimrd.done

std: .top ships m3subs
regress: std regsubs
regressfix: fix regress
withlinks: std .bindir browserexps binlinks
all: withlinks commons subs

clean: cleanm3 cleansubs cleanships cleancommons cleanbuilddirs cleanthis cleandone
fastprep: .top .m3deps
fast: fastprep .todo .fastmake
faster: fastprep .lesstodo .fastmake

.bindir:
	mkdir hack || true 
	cd hack ; echo `./bindir.sh` > ../.bindir 
.top:
	echo TOP=\"$(PWD)\" > .top

.m3deps:
	grep ^import\ \*\( */src/m3makefile */*/src/m3makefile | \
	sed s/\ //g | \
	sed -e s/:import\(\"/:/g -e s/\"\)\.\*//g -e s./src/m3makefile..g | \
	sed s/:ktoklib/:parserlib/g > .m3deps
	grep -v -e ^# otherdeps >> .m3deps

.todo:
	@echo GROUP COMMONS $(COMMONS) > .todo
	@echo GROUP SHIPS $(SHIPS) >> .todo
	@echo GROUP SUBS $(SUBS) >> .todo
	@echo GROUP M3SUBS $(M3SUBS) >> .todo
	@echo M3DIRS $(SHIPS) $(M3SUBS) >> .todo
	@echo M3OPTS $(M3BUILDOPTS) >> .todo

.lesstodo:
	@echo GROUP ALL $(COMMONS) $(SHIPS) $(SUBS) $(M3SUBS) > .todo
	@echo M3DIRS $(SHIPS) $(M3SUBS) >> .todo
	@echo M3OPTS $(M3BUILDOPTS) >> .todo

.fastmake:
	(cd makehack; $(M3BUILDPROGRAM))
	cat .todo .m3deps | makehack/`cat .bindir`/makehack > .fast
	sh .fast

cleandone:
	rm -f *.done

cleanthis:
	rm -f .bindir
	$(MAKE) .bindir
	find . -name `cat .bindir` -print | xargs rm -rf 
	rm -f .bindir .top
	rm -rf hack/.hidden
	rm -rf .browserhack*

cleanbuilddirs:

commons:
	@for s in $(COMMONS); do\
		echo "===> $$s";\
		cd $$s; $(MAKE) ; cd .. ;  \
	done

subs:
	@for s in $(SUBDIRS); do\
		echo "===> $$s";\
		cd $$s; $(MAKE) ; cd .. ;  \
	done

binlinks:
	(cd bin; $(MAKE))


ships: 
	@for s in $(SHIPS); do\
		echo "===> $$s";\
		(cd $$s; $(M3BUILD) || $(PROCEEDCMD); $(M3SHIP));  \
	done

m3subs:
	@for s in $(M3SUBS); do\
		echo "===> $$s";\
		(cd $$s; $(M3BUILD) || $(PROCEEDCMD));  \
	done

regsubs: 
	@for s in $(REGSUBS); do\
		echo "===> $$s";\
		(cd $$s; $(M3BUILD) || $(PROCEEDCMD); $(M3SHIP));  \
	done

browserexps:
	if [ -x m3browserhack ]; then \
		m3browserhack/export.sh $(BROWSEREXPS); \
	fi

cleanships:
	@for s in $(REVSHIPS); do\
		echo "(cleaning) ===> $$s";\
		(cd $$s; $(M3BUILDCLEAN) || true);  \
	done

cleanm3:
	@for s in $(M3SUBS); do\
		echo "(cleaning) ===> $$s";\
		(cd $$s; $(M3BUILDCLEAN) || true);  \
	done

cleancommons:
	@for s in $(REVCOMMONS); do\
		echo "(cleaning) ===> $$s";\
		cd $$s; $(MAKE) clean; cd .. ;  \
	done

cleansubs:
	@for s in $(SUBDIRS); do\
		echo "(cleaning) ===> $$s";\
		cd $$s; $(MAKE) clean; cd .. ;  \
	done

fix:
	cd calarm/fix/gen/src; ./gen.sh

intel-install:
	rm -rf bin.script bin.`uname -m` bin
	./copybins.sh .
	mkdir bin || true
	mv bin.script/* bin.`uname -m`/* bin
	rmdir bin.script bin.`uname -m`

# this is the end of the Makefile
