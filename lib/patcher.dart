library calzone.patcher;

import "dart:io";
import "dart:async";
import "dart:convert";

var _SCRAPER = r"""
function objEach(obj, cb, thisArg) {
  if(typeof thisArg !== 'undefined') {
    cb = cb.bind(thisArg);
  }

  var count = 0;
  var keys = Object.keys(obj);
  var length = keys.length;

  for(; count < length; count++) {
    var key = keys[count];
    cb(obj[key], key, obj);
  }
}

var map = {
  libraries: {},
  mangledGlobalNames: {}
};

var alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";

objEach(init.mangledGlobalNames, function(key, value) {
  if(key.indexOf(" ") >= 0 || key.indexOf(":") >= 0)
    return;

  var alphadex = 25;
  while(--alphadex >= 0) {
    if(eval("typeof(" + alphabet[alphadex] + ")") === "object" && eval("typeof(" + alphabet[alphadex] + "." + value + ")") !== "undefined") {
      key = alphabet[alphadex] + "." + key;
      alphadex = -1;
    }
  }

  if(typeof(map.mangledGlobalNames[key]) !== 'undefined') {
    map.mangledGlobalNames[key] = [].concat(map.mangledGlobalNames[key]).push(value);
  } else {
    map.mangledGlobalNames[key] = value;
  }
});

init.libraries.forEach(function(elm) {
  var library = {
    names: {}
  };

  var length = elm.length;
  elm.forEach(function(elm, index) {
    if(index == 0) {
      library.name = elm;
    }

    if(index === length - 1) {
      var alphadex = 25;
      while(--alphadex >= 0) {
        if(eval("typeof(" + alphabet[alphadex] + ")") === "object" && eval(alphabet[alphadex]) === elm)
          library.obj = alphabet[alphadex];
      }
    }

    if(Array.isArray(elm)) {
      elm.forEach(function(name) {
        if(init.allClasses[name] && init.mangledGlobalNames[name]) {
          library.names[init.mangledGlobalNames[name]] = {
            name: name,
            fields: init.allClasses[name]['$__fields__']
          };

          if(library.obj) {
            Object.keys(map.mangledGlobalNames).forEach(function(globalName) {
              if(globalName.indexOf(library.obj + '.') === 0) {
                var value = map.mangledGlobalNames[globalName];
                if(Array.isArray(value)) {
                  value.forEach(function(subvalue) {
                    if(init.allClasses[name]['$__fields__'].indexOf(subvalue) >= 0) {
                      if(value.length == 1) {
                        delete map.mangledGlobalNames[globalName];
                      } else {
                        var index = value.indexOf(subvalue);
                        map.mangledGlobalNames[globalNames].slice(index, index++);
                      }
                      map.mangledGlobalNames[globalName + '.' + init.mangledGlobalNames[name]] = subvalue;
                    }
                  });
                } else if(init.allClasses[name]['$__fields__'].indexOf(value) >= 0) {
                  delete map.mangledGlobalNames[globalName];
                  map.mangledGlobalNames[globalName + '.' + init.mangledGlobalNames[name]] = value;
                }
              }
            });
          }
        } else if(init.mangledGlobalNames[name] && init.mangledGlobalNames[name].indexOf('new ') === 0) {
          library.names[init.mangledGlobalNames[name].split(':')[0]] = {
            name: name
          };
        }
      });
    }
  });

  map.libraries[library.name] = library;
});

console.log(JSON.stringify(map));
""";

var _NODE_PREAMBLE = """
global.location = { href: "file://" + process.cwd() + "/" };
global.scheduleImmediate = setImmediate;
global.self = global;
global.require = require;
global.process = process;

global.dartMainRunner = function(main, args) {
  main(args.slice(Math.min(args.length, 2)));
};

// Support for deferred loading.
global.dartDeferredLibraryLoader = function(uri, successCallback, errorCallback) {
  try {
    load(uri);
    successCallback();
  } catch (error) {
    errorCallback(error);
  }
};
""";

class PatcherTarget {
  static const PatcherTarget NODE = const PatcherTarget._("node");
  static const PatcherTarget BROWSER = const PatcherTarget._("browser");

  final String _name;

  const PatcherTarget._(this._name);

  static PatcherTarget fromString(String str) {
    if(str == "node")
      return PatcherTarget.NODE;
    if(str == "browser")
      return PatcherTarget.BROWSER;
    throw new StateError("unknown target");
  }

  String toString() => this._name;
}

class Patcher {
  final PatcherTarget target;
  final bool isMinified;

  final List<String> _compiledFile;
  final Map<String, dynamic> _infoFile;
  final List<String> _wrapperFile;

  Patcher(dynamic compiledFile, dynamic infoFile, dynamic wrapperFile, {this.target: PatcherTarget.BROWSER, this.isMinified: false}):
      _compiledFile = compiledFile is String ? new File(compiledFile).readAsLinesSync() : compiledFile.split("\n"),
      _infoFile = infoFile is String ? JSON.decode(new File(infoFile).readAsStringSync()) : infoFile,
      _wrapperFile = wrapperFile is String ? new File(wrapperFile).readAsLinesSync() : wrapperFile;

  String patch() {
    var data = _compiledFile;

    if (target == PatcherTarget.NODE) {
      // node preamble
      data.insert(0, _NODE_PREAMBLE);
    }

    var index = data.length;
    var reversed = []..addAll(data.reversed);

    var foundTypeCheck = false;
    var foundMain = false;

    if(isMinified) {
      var json = _infoFile;

      var main = "main";
      var _isTest = "_isTest";

      _iterate(number) {
        var iter = json["elements"]["library"][number]["children"].where((child) => child.contains("function"));
        iter = iter.toList();

        var classes = json["elements"]["library"][number]["children"].where((child) => child.contains("class"));

        for(var c in classes) {
          c = c.split("/");

          var type = c[0];
          var id = c[1];

          var data = json["elements"][type][id];

          iter.addAll(data["children"].where((child) => child.contains("function")));
        }

        for(var func in iter) {
          func = func.split("/");

          var type = func[0];
          var id = func[1];

          var childData = json["elements"][type][id];

          if(childData["name"] == "main")
            main = childData["code"].split(":")[0].trim();

          if(childData["name"] == "_isTest") {
            _isTest = childData["code"].split(":")[0].trim();
          }
        }
      }

      for(var library in json["elements"]["library"].values) {
        if(library["id"] == "library/0") {
          _iterate("0");
        }

        if(library["name"] == "_js_helper") {
          _iterate(library["id"].split("/")[1]);
          break;
        }
      }

      for (var line in reversed) {
        index--;
        if (line.endsWith('})()') && data.length - index < 4) {
          data[index] = line.substring(0, line.length - 4) + ';';
          data.insertAll(index + 1, []..addAll(_wrapperFile)..add('})()'));
        }

        if (line.startsWith("$_isTest:")) {
          data[index + 1] = "return true},";
          foundTypeCheck = true;
          if(foundMain && foundTypeCheck)
            break;
        }

        if (line.startsWith("$main:")) {
          data.replaceRange(index, index + 3, ["Q:[function(a){},\"\$1\",\"ao\",2,0,279],"]);
          foundMain = true;
          if(foundMain && foundTypeCheck)
            break;
        }
      }
    } else {
      for (var line in reversed) {
        index--;
        if (line.contains("// END invoke [main].")) {
          data.insertAll(index, _wrapperFile);
          continue;
        }

        if (line.contains("buildFunctionType: function(returnType, parameterTypes, optionalParameterTypes) {")) {
          data[index + 1] = "var proto = Object.create(new H.RuntimeFunctionType(returnType, parameterTypes, optionalParameterTypes, null)); proto._isTest\$1 = function() { return true; }; return proto;";
          foundTypeCheck = true;
          if(foundMain && foundTypeCheck)
            break;
        }

        if (line.contains("main: [function(args) {")) {
          data.removeRange(index + 1, index + 4);
          foundMain = true;
          if(foundMain && foundTypeCheck)
            break;
        }
      }
    }

    return data.join("\n");
  }
}

class Scraper extends Patcher {
  Scraper(dynamic compiledFile, dynamic infoFile, {isMinified: false}):
      super(compiledFile, infoFile, _SCRAPER.split("\n"),
          target: PatcherTarget.NODE,
          isMinified: isMinified);

  Future<String> scrape() async {
    var patch = super.patch();

    var process = await Process.start("node", []);
    process.stdin.write(patch);
    await process.stdin.flush();
    process.stdin.close();

    String returned = "";

    await process.stderr.forEach((data) => stderr.writeln(UTF8.decode(data)));
    await process.stdout.forEach((data) => returned += UTF8.decode(data));

    return returned;
  }
}