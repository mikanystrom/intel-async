SRC    = CSPFE_MANUAL.md
TEX    = CSPFE_MANUAL.tex
PDF    = CSPFE_MANUAL.pdf
PANDOC = pandoc

# pandoc flags: standalone LaTeX document, nice code listings, geometry
PFLAGS = --standalone \
         --from markdown \
         --syntax-highlighting=tango \
         -V geometry:margin=1in \
         -V fontsize=11pt \
         -V documentclass=article \
         -V colorlinks=true \
         -V linkcolor=blue \
         -V urlcolor=blue \
         --pdf-engine=pdflatex

.PHONY: pdf tex clean check-pandoc

pdf: check-pandoc $(PDF)

tex: check-pandoc $(TEX)

$(PDF): $(SRC)
	$(PANDOC) $(PFLAGS) --to pdf -o $@ $<

$(TEX): $(SRC)
	$(PANDOC) $(PFLAGS) --to latex -o $@ $<

clean:
	rm -f $(TEX) $(PDF) *.aux *.log *.out

check-pandoc:
	@command -v $(PANDOC) >/dev/null 2>&1 || \
		{ echo "error: pandoc not found — install with: brew install pandoc"; exit 1; }
