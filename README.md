# Haxe Language Server

[![CI](https://img.shields.io/github/workflow/status/vshaxe/haxe-language-server/CI.svg?logo=github)](https://github.com/vshaxe/haxe-language-server/actions?query=workflow%3ACI)

This is a language server implementing [Language Server Protocol](https://github.com/Microsoft/language-server-protocol) for the [Haxe](http://haxe.org/) language.

The goal of this project is to encapsulate haxe's completion API with all its quirks behind a solid and easy-to-use protocol that can be used by any editor/IDE.

Used by the [Visual Studio Code Haxe Extension](https://github.com/vshaxe/vshaxe). It has also successfully been used in Neovim and Sublime Text<sup>[[1]](https://github.com/vshaxe/vshaxe/issues/171)</sup><sup>[[2]](https://github.com/vshaxe/vshaxe/issues/328)</sup>, but no official extensions exist at this time.

Note that any issues should be reported to [vshaxe](https://github.com/vshaxe/vshaxe) directly (this is also the reason why the issue tracker is disabled). Pull requests are welcome however!

**IMPORTANT**: This requires Haxe 3.4.0 or newer due to usage of [`-D display-stdin`](https://github.com/HaxeFoundation/haxe/pull/5120),
[`--wait stdio`](https://github.com/HaxeFoundation/haxe/pull/5188) and tons of other fixes and additions related to IDE support.

### Building From Source

The easiest way to work on the language server is probably to build it as part of the vshaxe VSCode extension as instructed [here](https://github.com/vshaxe/vshaxe/wiki/Installation#from-source) (even if you ultimately want to use it outside of VSCode), which allows for easy debugging.

However, you can also build it as a standalone project like so:

```
git clone https://github.com/vshaxe/haxe-language-server
cd haxe-language-server
npm install
npx lix run vshaxe-build -t language-server
```

This creates a `bin/server.js` that can be started with `node server.js`.

### Usage with (Neo)vim

There's a large amount of language client plugins for (Neo)vim, but the best choice currently seems to be [coc.nvim](https://github.com/neoclide/coc.nvim). A `coc-settings.json` that is known to work with haxe-language-server looks like this:

```haxe
{
    "languageserver": {
        "haxe": {
            "command": "node",
            "args": ["<path-to-server.js>"],
            "filetypes": ["haxe"],
            "trace.server": "verbose",
            "initializationOptions": {
                "displayArguments": ["build.hxml"]
            },
            "settings": {
                "haxe.executable": "haxe"
            }
        }
    }
}
```

Where `<path-to-server.js>` can either be a `server.js` you built from source or simply downloaded as part of the Haxe Visual Studio Code extension (`"/<you-home-folder>/.vscode/extensions/nadako.vshaxe-<version>/bin/server.js"`).
