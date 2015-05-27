part of calzone.compiler;

class BaseTypeTransformer implements TypeTransformer {
  final List<String> types = [];
  final Compiler _compiler;

  BaseTypeTransformer(this._compiler);

  transformTo(StringBuffer output, String name, String type) => transformToDart(output, null, name, _getTypeTree(type), _compiler._globals);
  transformFrom(StringBuffer output, String name, String type) => transformFromDart(output, null, name, _getTypeTree(type), _compiler._globals);

  @override
  transformToDart(StringBuffer output, TypeTransformer base, String name, List tree, List<String> globals) {
    var type = tree[0];
    if (_PRIMITIVES.contains(type)) return;

    if (_compiler._wrappedClasses.containsKey(type)) {
      output.write("$name = $name.obj;");
      return;
    }

    for (TypeTransformer transformer in _compiler.typeTransformers) {
      if (transformer.types.contains(type))
        transformer.transformToDart(output, this, name, tree, _compiler._globals);
    }
  }

  @override
  transformFromDart(StringBuffer output, TypeTransformer base, String name, List tree, List<String> globals) {
    var type = tree[0];
    if (_PRIMITIVES.contains(type)) return;

    if (_compiler._wrappedClasses.containsKey(type)) {
      output.write("$name = Object.create(module.exports.$type.prototype);");

      _compiler._handleClassField(output, {"name": "isWrapped", "value": "true"}, name);

      _compiler._handleClassField(output, {
        "name": "obj",
        "value": "Object.create(init.allClasses.$type.prototype)"
      }, name);

      output.write("$name = module.exports.$type.fromObj($name);");
      return;
    }

    for (TypeTransformer transformer in _compiler.typeTransformers) {
      if (transformer.types.contains(tree[0]))
        transformer.transformFromDart(output, this, name, tree, globals);
    }
  }
}