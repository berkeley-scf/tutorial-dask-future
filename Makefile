overview.html: overview.Rmd
	Rscript -e "library(knitr); knit2html('overview.Rmd')"

R-future.html: R-future.Rmd
	Rscript -e "library(knitr); knit2html('R-future.Rmd')"
	pandoc -s --webtex -t slidy -o R-future-slides.html R-future.md

python-dask.html: python-dask.md
	pandoc -s -o python-dask.html python-dask.md
	pandoc -s --webtex -t slidy -o python-dask-slides.html python-dask.md

clean:
	rm -f {overview,R-future}.md overview.html {R-future,python-dask}{,-slides}.html
