package haxeLanguageServer.server;

enum ResultHandler {
    /**
        Data is passed on as-is, with 0x01 / 0x02 chars from Haxe.
        Used for socket communication to ensure exit codes etc are correct.
    **/
    Raw(callback:(result:DisplayResult)->Void);

    /**
        Data is processed into Strings and separated
        into successful results (`callback`) and errors (`errback`).
    **/
    Processed(callback:(result:DisplayResult)->Void, errback:(error:String)->Void);
}
