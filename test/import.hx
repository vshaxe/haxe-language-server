import haxe.display.FsPath;
import languageServerProtocol.Types;
import languageServerProtocol.protocol.Protocol;
import languageServerProtocol.textdocument.TextDocument;
import utest.Assert;
import utest.Test;

using Lambda;
using StringTools;
using haxeLanguageServer.extensions.ArrayExtensions;
using haxeLanguageServer.extensions.DocumentUriExtensions;
using haxeLanguageServer.extensions.FsPathExtensions;
using haxeLanguageServer.extensions.PositionExtensions;
using haxeLanguageServer.extensions.RangeExtensions;
using haxeLanguageServer.extensions.StringExtensions;
