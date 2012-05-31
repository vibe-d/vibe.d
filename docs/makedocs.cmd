del docs.json
set FLAGS=..\lib\win-i386\event2.lib ..\lib\win-i386\eay.lib ..\lib\win-i386\ssl.lib ws2_32.lib
rdmd --build-only -D -Dd. -X -Xfdocs.json -I..\source %FLAGS% ..\source\vibe\d.d >nul 2>&1
del *.html
rdmd -I..\source %FLAGS% source\filter.d
rdmd -g -version=JsonLineNumbers -I..\source %FLAGS% source\docsteroids.d docs.json ddocs.json
copy ddocs.json ..\..\vibed.org\docs.json