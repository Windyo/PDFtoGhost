![Version](https://img.shields.io/badge/Version-0.0.1-blue.svg)
![MinGhostVersion](https://img.shields.io/badge/Min%20Ghost%20v.-%3E%3D%200.9.0-red.svg)

#PDFtoGhost
A Horrible shell script which takes a list of pdfs written in a file and posts them to Ghost.

==============

This is a shell script I wrote to push PDFs to ghost automatically.
It depends on moreutils and jq to work.

````shell
pdftoghost.sh [[-f] [-a (http://blog.mysite.eu ghostlogin ghostpassword customfilters)]]
````

The PDF formatting routine probably won't work for anyone's use but mine, and should probably be re-written.

The parts which can be reused are the auth routine and the cURL post which allow to write posts to Ghost and publish them.