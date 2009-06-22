srcdir = @srcdir@
VPATH = @srcdir@

SUBDIRS = source 

include @top_srcdir@/mk/gnu.bsdvars.mk

.SUFFIXES :
.SUFFIXES : .html .xhtml .js .xml .exbl

# Rules
all : build

build :
	for DIR in ${SUBDIRS}; do make -C $${DIR} build; done

clean :
	for DIR in ${SUBDIRS}; do make -C $${DIR} clean; done

install : 
	for DIR in ${SUBDIRS}; do make -C $${DIR} install; done

