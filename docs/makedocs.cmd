del docs.json
set FLAGS=..\lib\win-i386\event2.lib ..\lib\win-i386\eay.lib ..\lib\win-i386\ssl.lib ws2_32.lib
rdmd --build-only --force -D -Dd. -X -Xfdocs.json -I..\source ..\source\vibe\d.d >nul 2>&1
del *.html
..\..\ddox\ddox filter docs.json --min-protection=Public --ex deimos. --ex vibe.core.drivers. --ex etc. --ex std. --ex core.
copy docs.json ..\..\vibed.org\docs.json

..\..\ddox\ddox generate-html --navigation-type=ModuleTree docs.json .
xcopy /e /y ..\..\ddox\public\* .