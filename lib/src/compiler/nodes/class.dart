part of calzone.compiler;

class Class implements Renderable {
  final Map<String, List<Parameter>> functions = {};
  Map<String, dynamic> data;

  final List<String> staticFields;
  final List<String> getters;
  final List<String> setters;

  final List<String> inheritedFrom;

  final String name;
  final String libraryName;

  Class(this.name, this.libraryName, {this.staticFields: const [], this.getters: const [], this.setters: const [], this.inheritedFrom: const []});

  render(Compiler compiler, StringBuffer output) {
    List<String> names = [];
    List<StringBuffer> methods = [];

    StringBuffer constructor = new StringBuffer();
    StringBuffer prototype = new StringBuffer();
    StringBuffer global = new StringBuffer();

    _handleClassChildren(Class c, Map memberData, {bool isTopLevel: true}) {
      var mangledFields = compiler.mangledNames.getClassFields(c.libraryName, c.name);
      if(mangledFields == null)
        mangledFields = [];

      List<String> accessors = [];
      Map<String, Map> getters = {};
      Map<String, Map> setters = {};

      for (var child in memberData["children"]) {
        child = child.split("/");

        var type = child[0];
        var id = child[1];

        var data = compiler.info.getElement(type, id);
        var name = data["name"];

        if (type == "function") {
          if (names.contains(name) || name.startsWith("_")) continue;
          names.add(name);

          if (data["kind"] == "constructor" && isTopLevel) {
            var isDefault = name.length == 0;
            var buf = isDefault ? constructor : global;
            if (!isDefault) global.write("mdex.${this.data["name"]}.$name = function() {");
            buf.write("var __obj__ = (");

            var code = data["code"] == null || data["code"].length == 0
                ? "function(){}"
                : "${compiler.mangledNames.getLibraryObject(libraryName)}.${data["code"].split(":")[0].trim()}";

            var func = this.data["name"];
            (new Func(data, _getParamsFromInfo(compiler, data["type"], compiler.analyzer.getFunctionParameters(c.libraryName, func, memberData["name"])),
                code: code,
                withSemicolon: false,
                transform: FunctionTransformation.NONE)).render(compiler, buf);
            buf.write(").apply(this, arguments);");
            if (!isDefault) global.write("return mdex.${this.data["name"]}._(__obj__);};");
            continue;
          }

          if (data["kind"] == "constructor" && !isTopLevel) continue;

          var params = _getParamsFromInfo(compiler, data["type"], compiler.analyzer.getFunctionParameters(c.libraryName, data["name"], memberData["name"]));

          if (c != null && c.getters.contains(data["name"]) && params.length == 0) {
            if (!accessors.contains(name)) accessors.add(name);
            getters[name] = data;
            continue;
          }

          if (c != null && c.setters.contains(data["name"]) && params.length == 1) {
            if (!accessors.contains(name)) accessors.add(name);
            setters[name] = data;
            continue;
          }

          if (data["code"].length > 0) {
            if (NAME_REPLACEMENTS.containsKey(data["name"])) {
              if (memberData["children"]
                  .map((f) => compiler.info.getElement(f.split("/")[0], f.split("/")[1]))
                  .contains(NAME_REPLACEMENTS[data["name"]])) continue;
              data["name"] = NAME_REPLACEMENTS[data["name"]];
              name = data["name"];
            }

            if (data["modifiers"]["static"] || data["modifiers"]["factory"]) {
              if (isTopLevel)
                (new Func(data, params,
                    code: "init.allClasses.${data["code"].split(":")[0]}",
                    prefix: "mdex.${this.data["name"]}")).render(compiler, global);
            } else {
              prototype.write(data["name"] + ": ");
              (new Func(data, params,
                  binding: "this[clOb]",
                  code: "this[clOb].${data["code"].split(":")[0]}",
                  withSemicolon: false)).render(compiler, prototype);
              prototype.write(",");

              StringBuffer buf = new StringBuffer();
              methods.add(buf);

              var dartName = data["code"].split(":")[0];

              buf.write("if(proto.indexOf('$name') > -1) { overrideFunc(this, '$name', '$dartName'); }");
            }
          }
        }

        if (type == "field") {
          if (names.contains(data["name"])) continue;
          names.add(data["name"]);

          if (c == null) continue;

          if (!c.staticFields.contains(data["name"])) {
            var mangledName = mangledFields.length > 0 ? mangledFields.removeAt(0) : null;

            if (data["name"].startsWith("_")) continue;

            prototype.write("get ${data["name"]}() {");

            compiler.baseTransformer.handleReturn(prototype, "this[clOb].$mangledName", data["type"]);

            prototype.write("},set ${data["name"]}(v) {");
            compiler.baseTransformer.transformTo(prototype, "v", data["type"]);
            prototype.write("this[clOb].$mangledName = v;},");
          } else {
            if (data["name"].startsWith("_")) continue;

            // TODO
            // (new ClassProperty(data, c, isStatic: true)).render(compiler, functions);
          }
        }
      }

      for (var accessor in accessors) {
        if (getters[accessor] != null) {
          prototype.write("get $accessor() {");

          var pOutput = new StringBuffer();
          pOutput.write("(");
          (new Func(getters[accessor], _getParamsFromInfo(compiler, getters[accessor]["type"]),
              binding: "this[clOb]",
              transform: FunctionTransformation.NONE,
              withSemicolon: false)).render(compiler, pOutput);
          pOutput.write(").apply(this, arguments)");

          compiler.baseTransformer.handleReturn(prototype, pOutput.toString(), getters[accessor]["type"]);
          prototype.write("},");
        }

        if (setters[accessor] != null) {
          prototype.write("set $accessor(v) {");
          compiler.baseTransformer.transformTo(prototype, "v", setters[accessor]["type"]);
          prototype.write("(");
          (new Func(setters[accessor], _getParamsFromInfo(compiler, setters[accessor]["type"]),
              binding: "this[clOb]",
              withSemicolon: false)).render(compiler, prototype);
          prototype.write(").call(this, v);},");
        } else if (getters[accessor] != null) {
          prototype.write("set $accessor(v) {");
          compiler.baseTransformer.transformTo(prototype, "v", getters[accessor]["type"]);
          prototype.write("this[clOb].${getters[accessor]['code'].split(':')[0]} = function() { return v; };},");
        }
      }
    }

    _handleClassChildren(this, data);

    this.inheritedFrom.forEach((superClass) {
        var classObj = compiler.analyzer.getClass(null, superClass);
        if (classObj != null)
          _handleClassChildren(classObj,
              compiler.classes[superClass] != null ?
                  compiler.classes[superClass].key.data :
                  compiler.classes[classObj.libraryName + "." + superClass].key.data,
              isTopLevel: false);
      });

    output.write("mdex.$name = function() {");
    output.write(constructor.toString());

    output.write("this[clOb] = __obj__;");

    output.write("};");

    var proto = prototype.toString();
    // cut off trailing comma
    if(proto.length > 0) {
      output.write("mdex.$name.prototype = {");
      output.write(proto.substring(0, proto.length - 1));
      output.write("};");
    }
    output.write("mdex.$name.prototype[clIw] = true;");

    output.write("""
    mdex.$name.class = obfr(function() {
        function $name() {
          mdex.$name.apply(this, arguments);
          var proto = Object.keys(Object.getPrototypeOf(this));
    """);

    methods.forEach((method) => output.write(method.toString()));

    output.write("""
        }

        $name.prototype = Object.create(mdex.$name.prototype);
        $name.prototype["constructor"] = $name;

        return $name;
    }());
    """);

    output.write(global.toString());

    output.write("mdex.$name[clCl] = ");
    output.write("function(__obj__) {var returned = Object.create(mdex.$name.prototype);");
    output.write("returned[clOb] = __obj__;");
    output.write("return returned;};");
  }
}
