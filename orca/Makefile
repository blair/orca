all:	README orca.man

orca.man:	orca
	pod2man $< > $@

README:		orca
	pod2text $< > $@
