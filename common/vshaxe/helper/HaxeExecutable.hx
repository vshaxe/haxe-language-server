package vshaxe.helper;

import haxe.extern.EitherType;

typedef HaxeExecutableConfigBase = {
    var path:String;
    var env:haxe.DynamicAccess<String>;
}

private typedef HaxeExecutablePathOrConfigBase = EitherType<String,HaxeExecutableConfigBase>;

typedef HaxeExecutablePathOrConfig = EitherType<
    String,
    {
        >HaxeExecutableConfigBase,
        @:optional var windows:HaxeExecutablePathOrConfigBase;
        @:optional var linux:HaxeExecutablePathOrConfigBase;
        @:optional var osx:HaxeExecutablePathOrConfigBase;
    }
>;

class HaxeExecutable {
    public static var SYSTEM_KEY(default,never) = switch (Sys.systemName()) {
        case "Windows": "windows";
        case "Mac": "osx";
        default: "linux";
    };

    public var config(default,null):HaxeExecutableConfigBase;

    public function new() {
        updateConfig(null);
    }

    public function updateConfig(input:Null<HaxeExecutablePathOrConfig>) {
        config = {
            path: "haxe",
            env: {},
        };

        function merge(conf:HaxeExecutablePathOrConfigBase) {
            if ((conf is String)) {
                config.path = conf;
            } else {
                var conf:HaxeExecutableConfigBase = conf;
                if (conf.path != null)
                    config.path = conf.path;
                if (conf.env != null)
                    config.env = conf.env;
            }
        }

        if (input != null) {
            merge(input);
            var systemConfig = Reflect.field(input, SYSTEM_KEY);
            if (systemConfig != null)
                merge(systemConfig);
        }
    }
}
