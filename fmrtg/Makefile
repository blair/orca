all:	README fmrtg.man

fmrtg.man:	fmrtg
	pod2man $< > $@

README:		fmrtg
	pod2text $< > $@
