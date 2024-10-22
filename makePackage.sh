#!/bin/bash

npx lix run vshaxe-build --target language-server

mv bin/server.js bin/haxe-language-server.min.js

npx lix run vshaxe-build --target language-server --debug

mv bin/server.js bin/haxe-language-server.js
sed -i -e 's/server.js.map/haxe-language-server.js.map/' bin/haxe-language-server.js

mv bin/server.js.map bin/haxe-language-server.js.map
sed -i -e 's/server.js/haxe-language-server.js/' bin/haxe-language-server.js.map
