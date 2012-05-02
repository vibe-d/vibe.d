del docs.json
rdmd --build-only -D -Dd. -X -Xfdocs.json -I..\source ..\source\vibe\d.d >nul 2>&1
del *.html
rdmd -I..\source source\filter.d
rdmd -g -version=JsonLineNumbers -I..\source source\docsteroids.d docs.json ddocs.json
copy ddocs.json ..\..\vibed.org\docs.json