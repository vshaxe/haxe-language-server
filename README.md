# Haxe Language Server

[![Build Status](https://travis-ci.org/vshaxe/haxe-languageserver.svg?branch=master)](https://travis-ci.org/vshaxe/haxe-languageserver)

This is a language server implementing [Language Server Protocol](https://github.com/Microsoft/language-server-protocol) for the [Haxe](http://haxe.org/) language.

The goal of this project is to encapsulate haxe's completion API with all its quirks behind a solid and easy-to-use protocol that can be used by any editor/IDE.

Used by our new [Haxe Visual Studio Code Extension](https://github.com/vshaxe/vshaxe).

Note that any issues should be reported to [vshaxe](https://github.com/vshaxe/vshaxe) directly (this is also the reason why the issue tracker is disabled). Pull requests are welcome however!

**IMPORTANT**: This requires Haxe 3.4.0 or newer due to usage of [`-D display-stdin`](https://github.com/HaxeFoundation/haxe/pull/5120),
[`--wait stdio`](https://github.com/HaxeFoundation/haxe/pull/5188) and tons of other fixes and additions related to IDE support.