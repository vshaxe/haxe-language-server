package jsonrpc;

/**
    Reserved error codes.
**/
@:publicFields
class ErrorCodes {
    /**
        Invalid JSON was received by the server.
        An error occurred on the server while parsing the JSON text.
    **/
    static inline var ParseError = -32700;

    /**
        The JSON sent is not a valid Request object.
    **/
    static inline var InvalidRequest = -32600;

    /**
        The method does not exist / is not available.
    **/
    static inline var MethodNotFound = -32601;

    /**
        Invalid method parameter(s).
    **/
    static inline var InvalidParams = -32602;

    /**
        Internal JSON-RPC error.
    **/
    static inline var InternalError = -32603;
}
