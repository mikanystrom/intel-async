# Makefile for svfe documentation
#
# Requires: pandoc, a LaTeX distribution (texlive recommended)
#
# Targets:
#   make pdf    -- build PDF via pandoc + LaTeX
#   make clean  -- remove generated files

PANDOC   ?= pandoc
SOURCES  := svfe-manual.md
PDF      := svfe-manual.pdf

.PHONY: all pdf clean

all: pdf

pdf: $(PDF)

$(PDF): $(SOURCES)
	$(PANDOC) -f markdown -o $@ \
		--pdf-engine=xelatex \
		-V geometry:margin=1in \
		-V fontsize=11pt \
		-V documentclass=article \
		--highlight-style=tango \
		$<

clean:
	rm -f $(PDF)
