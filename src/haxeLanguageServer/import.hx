import haxe.display.FsPath;
import haxe.ds.ReadOnlyArray;
import haxeLanguageServer.documents.*;
import languageServerProtocol.protocol.Protocol;
import languageServerProtocol.textdocument.TextDocument;

using Safety;
using StringTools;

using haxeLanguageServer.extensions.ArrayExtensions;
using haxeLanguageServer.extensions.DocumentUriExtensions;
using haxeLanguageServer.extensions.FsPathExtensions;
using haxeLanguageServer.extensions.FunctionFormattingConfigExtensions;
using haxeLanguageServer.extensions.PositionExtensions;
using haxeLanguageServer.extensions.RangeExtensions;
using haxeLanguageServer.extensions.ResponseErrorExtensions;
using haxeLanguageServer.extensions.StringExtensions;
using haxeLanguageServer.protocol.DotPath;
using haxeLanguageServer.protocol.Extensions;

#if !macro
import haxeLanguageServer.helper.DisplayOffsetConverter;
#end
