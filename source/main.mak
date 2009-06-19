VPATH = ${srcdir}

include ${top_srcdir}/mk/gnu.bsdvars.mk

.SUFFIXES :
.SUFFIXES : .html .xhtml .js .xml .xpl .xbl

RESOURCES = 
TARGETS = url-install

INSTALL = /usr/bin/install

# Rules
all : build

build : ${TARGETS}

install: 
	[ -d ${destpkglibexecdir} ] || ${INSTALL} -d ${destpkglibexecdir}
	for FILE in ${TARGETS}; do\
		${INSTALL} $${FILE} ${destpkglibexecdir}/$${FILE};\
	done

clean : 
	-rm ${TARGETS}

url-install: url-install.pl 
	cp ${.IMPSRC} ${.TARGET}
	
