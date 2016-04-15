# Haxe language server

This is a language server implementing [VS Code language server protocol](https://github.com/Microsoft/vscode-languageserver-protocol) for [Haxe](http://haxe.org/) language.

**Status**: very much work in progress. Hacks and experiments everywhere.

This only works with latest development version of Haxe (3.3) due to new [`-D display-stdin` feature](https://github.com/HaxeFoundation/haxe/pull/5120).

The goal of this project is to encapsulate haxe's completion API with all its quirks behind a solid and easy-to-use
protocol that can be used by any editor/IDE.
