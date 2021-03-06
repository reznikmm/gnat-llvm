GPRBUILD=gprbuild -v

# number of processors
PROCS=0

RM=rm -f
RMDIR=rm -rf
MV=mv -f
MKDIR=mkdir -p
CHMOD=chmod
AR=ar q
LN_S=ln -sf

GNATMAKE=gnatmake

GPROPT=-XBuild=Production

GNAT_SRC=$(pwd)/gnat_src
ADAINCLUDE=lib/rts-llvm/adainclude
ADALIB=lib/rts-llvm/adalib

pwd:=$(shell pwd)

ifneq ($(wildcard $(pwd)/../llvm/llvm-obj/bin/llvm-config),)
  LLVM_CONFIG=$(pwd)/../llvm/llvm-obj/bin/llvm-config
else
  LLVM_CONFIG=llvm-config
endif

LDFLAGS=$(shell $(LLVM_CONFIG) --libs all --ldflags --system-libs) \
  -static-libstdc++
CXXFLAGS=
ALL_CXXFLAGS=$(shell $(LLVM_CONFIG) --cxxflags) $(CXXFLAGS)

ifeq ($(OS),Windows_NT)
  LN_S=cp -p
  LDFLAGS+=-Wl,--stack=0x2000000
endif

compare=cmp --ignore-initial=16

.PHONY: setup force clean

all: setup build
	$(MAKE) quicklib

LOCAL_RT_FILES=../link.c s-rident.ads gnat.ads g-dynhta.ads g-dynhta.adb \
  g-sets.ads g-sets.adb g-lists.ads g-lists.adb \
  g-graphs.ads g-graphs.adb g-htable.adb g-byorma.adb g-speche.adb \
  g-spchge.adb g-u3spch.adb g-comlin.ads g-comlin.adb g-dirope.adb \
  g-os_lib.ads g-os_lib.adb g-regexp.ads g-string.ads g-io.adb g-casuti.adb \
  g-hesora.adb g-io_aux.ads g-io_aux.adb

setup:
	$(MKDIR) obj obj-tools bin
	for f in `cd $(GNAT_SRC); ls xtreeprs.adb xnmake.adb xutil.ad? *-tmpl xsnamest.adb sinfo.ads treeprs.adt nmake.adt xoscons.adb xutil.ads xutil.adb`; \
	do \
	  cp -p $(GNAT_SRC)/$$f obj-tools; \
	done
	cd obj-tools && $(GNATMAKE) -q -j0 xtreeprs xnmake xsnamest xoscons && \
	./xtreeprs && ./xnmake && ./xsnamest && \
	$(MV) nmake.ads nmake.adb treeprs.ads ../obj && \
	$(MV) snames.ns ../obj/snames.ads && $(MV) snames.nb ../obj/snames.adb
	for f in $(LOCAL_RT_FILES); do \
	  $(LN_S) $(GNAT_SRC)/libgnat/$$f obj; \
	done
	./check_for_LLVM_aliasing_bug.sh

build: setup force
	$(GPRBUILD) -Pgnat_llvm -j$(PROCS) \
	  -largs $(LDFLAGS) -cargs:c++ $(ALL_CXXFLAGS)
	$(GPRBUILD) -Ptools -j$(PROCS)

build-uninit: setup force
	$(GPRBUILD) -XBuild=Uninitialized -Pgnat_llvm -j$(PROCS) \
	  -largs $(LDFLAGS) -cargs:c++ $(ALL_CXXFLAGS)
	$(GPRBUILD) -Ptools -j$(PROCS)

build-opt: setup force
	$(GPRBUILD) $(GPROPT) -Pgnat_llvm -j$(PROCS) \
	  -largs $(LDFLAGS) -cargs:c++ $(ALL_CXXFLAGS)
	$(GPRBUILD) $(GPROPT) -Ptools -j$(PROCS)

# Bootstrap targets

CXX_PREFIX=$(shell dirname $(dir $(shell which gcc)))
LD_PATH=$(shell dirname $(shell gcc --print-prog-name=cc1))
LIBSTDCXX_PATH=$(CXX_PREFIX)/lib64

stage1: 
	$(MAKE) GPRBUILD="gprbuild -v -gnatwns" build gnatlib-automated
	$(RMDIR) stage1
	$(MKDIR) stage1
	$(MV) obj obj-tools bin lib stage1

stage2: stage1
	PATH=$(pwd)/stage1/bin:$(LD_PATH):$$PATH $(MAKE) CXX_PREFIX=$(CXX_PREFIX) GNATMAKE=$(pwd)/stage1/bin/llvm-gnatmake GPRBUILD="gprbuild -v --target=llvm -largs -L$(LIBSTDCXX_PATH) -margs" build gnatlib-automated
	$(RMDIR) stage2
	$(MKDIR) stage2
	$(MV) obj obj-tools bin lib stage2

stage3: stage2
	PATH=$(pwd)/stage2/bin:$(LD_PATH):$$PATH $(MAKE) CXX_PREFIX=$(CXX_PREFIX) GNATMAKE=$(pwd)/stage2/bin/llvm-gnatmake GPRBUILD="gprbuild -v --target=llvm -largs -L$(LIBSTDCXX_PATH) -margs" build gnatlib-automated
	@echo "Comparing stage2 and stage3 objects"
	$(MAKE) bootstrap-compare

bootstrap: stage3

.PHONY: bootstrap-compare

bootstrap-compare:
	@rm -rf bootstrap-compare
	@mkdir -p bootstrap-compare
	@for f in `cd stage2/obj && echo *.o`; do \
	  objcopy --strip-debug stage2/obj/$$f bootstrap-compare/stage2-$$f; \
	  objcopy --strip-debug obj/$$f bootstrap-compare/stage3-$$f; \
	  $(compare) bootstrap-compare/stage?-$$f || exit 1; \
	done
	@rm -rf bootstrap-compare
	@echo "Comparison successful."

force:

clean:
	$(RMDIR) obj obj-tools lib stage1 stage2 bootstrap-compare

# Full runtime

target=$(shell gcc -dumpmachine)

target_list=$(filter-out gnu,$(subst -, ,$(target)))
target_cpu=$(word 1,$(target_list))

ifeq ($(words $(target_list)),2)
  target_vendor=
  target_os=$(word 2,$(target_list))
else
  target_vendor=$(word 2,$(target_list))
  target_os=$(word 3,$(target_list))
endif

objext=.o
arext=.a
soext=.so
AR_FOR_TARGET=ar
AR_FLAGS=q
RANLIB_FOR_TARGET=ranlib
RTSDIR=$(pwd)/lib/rts-native/adainclude
RTSLIB=$(pwd)/lib/rts-native/adalib
RTSOBJ=$(pwd)/lib/rts-native/obj
ADAFLAGS=-gnatpg
ADA_INCLUDES=-nostdinc -I../adainclude
CFLAGS=-O2 -g
EXTRALIBFLAGS=
GNATLIBCFLAGS=-DIN_RTS=1 -fexceptions -gdwarf-aranges -DSTANDALONE \
  $(EXTRALIBFLAGS)
ALL_ADAFLAGS=$(CFLAGS) $(ADAFLAGS) $(ADA_INCLUDES) $(EXTRALIBFLAGS)
INCLUDES=-I../adainclude -I../include

ADAC=$(pwd)/bin/llvm-gcc
CROSSC=clang
CROSSGCC=gcc
COMPILE=$(ADAC) -c -gnatpg -nostdinc -I../adainclude

FORCE_DEBUG_ADAFLAGS = -g
NO_INLINE_ADAFLAGS = -fno-inline
NO_OMIT_ADAFLAGS = -fno-omit-frame-pointer
NO_SIBLING_ADAFLAGS=-fno-optimize-sibling-calls

# -fno-toplevel-reorder is actually ignored by LLVM, keep it for reference
# purposes. Achieve instead an equivalent effect by disabling all
# optimizations.
NO_REORDER_ADAFLAGS=-fno-toplevel-reorder -O0

OSCONS_CC=$(CROSSGCC)
OSCONS_CPP=$(OSCONS_CC) -E -C -DTARGET=\"$(target)\" -iquote $(GNAT_SRC) \
  $(GNAT_SRC)/s-oscons-tmplt.c > s-oscons-tmplt.i
OSCONS_EXTRACT=$(OSCONS_CC) -S s-oscons-tmplt.i

vpath %.adb ../adainclude
vpath %.ads ../adainclude
vpath %.c   ../adainclude
vpath %.h   ../adainclude

include $(GNAT_SRC)/Makefile.rtl

.SUFFIXES: .adb .ads

.c.o:
	$(CC) -c $(CFLAGS) $(GNATLIBCFLAGS) $(INCLUDES) $<

.adb.o:
	$(ADAC) -c $(ALL_ADAFLAGS) $<

.ads.o:
	$(ADAC) -c $(ALL_ADAFLAGS) $<

gnatlib: build
	$(RMDIR) $(RTSLIB) $(RTSDIR) $(RTSOBJ)
	$(MAKE) CFLAGS="$(CFLAGS)" EXTRALIBFLAGS="$(EXTRALIBFLAGS)" quicklib

gnatlib-automated: build
	$(RMDIR) $(RTSLIB) $(RTSDIR) $(RTSOBJ)
	$(MAKE) CFLAGS="$(CFLAGS)" EXTRALIBFLAGS="$(EXTRALIBFLAGS)" \
	  LN_S="cp -p" quicklib
	$(RMDIR) $(RTSOBJ)

gnatlib-shared:
	$(MAKE) GNAT_SRC=$(GNAT_SRC) -C $(RTSLIB) -f $(pwd)/Makefile \
	  ADAC=$(ADAC) CC=$(CROSSC) EXTRALIBFLAGS="-fPIC $(EXTRALIBFLAGS)" \
	  $(GNATRTL_OBJS) $(LIBGNAT_OBJS) $(EXTRA_ADALIB_OBJS)
	@cd $(RTSLIB) && $(CROSSC) -shared $(GNATRTL_NONTASKING_OBJS) $(LIBGNAT_OBJS) -o libgnat$(soext)
	@cd $(RTSLIB) && $(CROSSC) -shared $(GNATRTL_TASKING_OBJS) -o libgnarl$(soext)
	@cd $(RTSLIB) && $(CHMOD) a-wx *.ali && $(RM) *.o

gnatlib-bc:
	$(MAKE) GNAT_SRC=$(GNAT_SRC) -C $(RTSLIB) -f $(pwd)/Makefile \
	  ADAC=$(ADAC) CC=$(CROSSC) \
	  EXTRALIBFLAGS="-emit-llvm $(EXTRALIBFLAGS)" \
	  $(GNATRTL_OBJS) $(LIBGNAT_OBJS) $(EXTRA_ADALIB_OBJS)
	@echo "creating libgnat.bc"
	@cd $(RTSLIB) && llvm-link $(subst .o,.bc,$(GNATRTL_NONTASKING_OBJS) $(LIBGNAT_OBJS)) -o=libgnat.bc-tmp
	@echo "creating libgnarl.bc"
	@cd $(RTSLIB) && llvm-link $(subst .o,.bc,$(GNATRTL_TASKING_OBJS)) -o=libgnarl.bc-tmp
	@cd $(RTSLIB) && $(RM) *.bc && $(MV) libgnat.bc-tmp libgnat.bc && $(MV) libgnarl.bc-tmp libgnarl.bc

quicklib: $(RTSDIR)
	if [ -d $(RTSOBJ) ]; then \
	  $(MV) $(RTSOBJ)/*.o $(RTSLIB); \
	fi
	$(MAKE) GNAT_SRC=$(GNAT_SRC) -C $(RTSLIB) -f $(pwd)/Makefile \
	  ADAC=$(ADAC) CC=$(CROSSC) \
	  CFLAGS="$(CFLAGS)" EXTRALIBFLAGS="$(EXTRALIBFLAGS)" \
	  $(GNATRTL_OBJS) $(LIBGNAT_OBJS) $(EXTRA_ADALIB_OBJS)
# Create libgnat/libgnarl.a
	$(RM) $(RTSLIB)/libgnat$(arext) $(RTSLIB)/libgnarl$(arext)
	@cd $(RTSLIB) && $(AR_FOR_TARGET) $(AR_FLAGS) libgnat$(arext) \
	  $(GNATRTL_NONTASKING_OBJS) $(LIBGNAT_OBJS)
	$(RANLIB_FOR_TARGET) $(RTSLIB)/libgnat$(arext)
	@cd $(RTSLIB) && $(AR_FOR_TARGET) $(AR_FLAGS) libgnarl$(arext) \
	  $(GNATRTL_TASKING_OBJS)
	$(RANLIB_FOR_TARGET) $(RTSLIB)/libgnarl$(arext)
	$(RMDIR) $(RTSOBJ)
	$(MKDIR) $(RTSOBJ)
	cd $(RTSLIB) && $(CHMOD) a-wx *.ali && $(MV) *.o $(RTSOBJ)

$(RTSDIR): bin/llvm-gnat1
	$(RMDIR) $(RTSLIB) $(RTSOBJ)
	$(MKDIR) $(RTSLIB)
	$(MAKE) setup-rts
	cp -pr include $(RTSLIB)/..
	cd $(RTSLIB) && $(OSCONS_CPP) && $(OSCONS_EXTRACT) && \
	  $(pwd)/obj-tools/xoscons s-oscons && \
	  $(MV) s-oscons.ads $(RTSDIR) && $(MV) s-oscons.h $(RTSDIR) && \
	  $(RM) s-oscons-tmplt.*
	$(MV) $(RTSDIR)/a-numaux.adb $(RTSDIR)/a-numaux.adb.orig
	sed -e's/%%/%/g' -e's/"=t"/"={st}"/' -e's/"u"/"{st(1)}"/' \
	  $(RTSDIR)/a-numaux.adb.orig > $(RTSDIR)/a-numaux.adb
	$(RM) a-numaux.adb.orig

tracebak.o: tracebak.c tb-gcc.c
	$(CC) -c $(CFLAGS) $(GNATLIBCFLAGS) \
	  $(ALL_CPPFLAGS) $(INCLUDES) $(NO_OMIT_ADAFLAGS) $<

# Need to keep functions ordered on g-debpoo.o since labels are used to
# exclude subprograms from traceback computation.

g-debpoo.o: g-debpoo.adb g-debpoo.ads
	$(ADAC) -c $(ALL_ADAFLAGS) $(NO_REORDER_ADAFLAGS) $<

# Optionally include sub makefile

-include Makefile.zfp
