# Makefile for svfe documentation
#
# Requires: pandoc, a LaTeX distribution (texlive recommended)
#
# Targets:
#   make pdf    -- build all PDFs
#   make clean  -- remove generated files

PANDOC   ?= pandoc
LATEX    ?= xelatex

MANUAL_SRC := svfe-manual.md
MANUAL_PDF := svfe-manual.pdf

SOP_SRC    := sop-report.tex
SOP_PDF    := sop-report.pdf

.PHONY: all pdf clean

all: pdf

pdf: $(MANUAL_PDF) $(SOP_PDF)

$(MANUAL_PDF): $(MANUAL_SRC)
	$(PANDOC) -f markdown -o $@ \
		--pdf-engine=xelatex \
		-V geometry:margin=1in \
		-V fontsize=11pt \
		-V documentclass=article \
		--highlight-style=tango \
		$<

$(SOP_PDF): $(SOP_SRC)
	$(LATEX) -interaction=nonstopmode $<
	$(LATEX) -interaction=nonstopmode $<
	rm -f sop-report.aux sop-report.log sop-report.out

clean:
	rm -f $(MANUAL_PDF) $(SOP_PDF)
	rm -f sop-report.aux sop-report.log sop-report.out
