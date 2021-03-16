overview.html: overview.md
	pandoc -s -o overview.html overview.md
	pandoc -s --webtex -t slidy -o overview-slides.html overview.md

R-future.html: R-future.Rmd
	Rscript -e "library(knitr); knit2html('R-future.Rmd')"
	pandoc -s --webtex -t slidy -o R-future-slides.html R-future.md

python-dask.html: python-dask.md
	pandoc -s -o python-dask.html python-dask.md
	pandoc -s --webtex -t slidy -o python-dask-slides.html python-dask.md

python-ray.html: python-ray.md
	pandoc -s -o python-ray.html python-ray.md
	pandoc -s --webtex -t slidy -o python-ray-slides.html python-ray.md


clean:
	rm -f {overview,R-future}.md {overview,R-future,python-dask,python-ray}{,-slides}.html
