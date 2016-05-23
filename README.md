# Haxe language server

This is a language server implementing [Visual Studio Code Language Server Protocol](https://github.com/Microsoft/vscode-languageserver-protocol) for the [Haxe](http://haxe.org/) language.

The goal of this project is to encapsulate haxe's completion API with all its quirks behind a solid and easy-to-use protocol that can be used by any editor/IDE.

Used by our new [Haxe Visual Studio Code Extension](https://github.com/vshaxe/vshaxe).

**Status**: Usable but still pretty new, so things may change, check [current issues](https://github.com/vshaxe/haxe-languageserver/issues).

**IMPORTANT**: This requires latest Haxe development version due to usage of [`-D display-stdin`](https://github.com/HaxeFoundation/haxe/pull/5120),
[`--wait stdio`](https://github.com/HaxeFoundation/haxe/pull/5188) and ton of other fixes and additions related to IDE support.
