// Fire4Nix first REAL JavaScriptCore shell test. Offline, no files or network.
(function () {
    "use strict";
    var values = [1, 2, 3, 4, 5];
    var squares = values.map(function (value) { return value * value; });
    if (squares.reduce(function (a, b) { return a + b; }, 0) !== 55)
        throw new Error("JSC arithmetic/Array.reduce failed");
    var record = JSON.parse(JSON.stringify({engine: "JavaScriptCore", valid: true}));
    if (record.engine !== "JavaScriptCore" || !record.valid)
        throw new Error("JSC JSON serialization failed");
    if ((9007199254740991n + 2n).toString() !== "9007199254740993")
        throw new Error("JSC BigInt failed");
    print("FIRE4NIX_JSC_RUNTIME=PASS_ES6_ARRAY_MAP_JSON_AND_BIGINT");
}());
