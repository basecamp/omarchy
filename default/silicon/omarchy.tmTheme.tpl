<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>name</key>
  <string>Omarchy</string>
  <key>settings</key>
  <array>
    <dict>
      <key>settings</key>
      <dict>
        <key>background</key>
        <string>{{ background }}</string>
        <key>foreground</key>
        <string>{{ foreground }}</string>
        <key>caret</key>
        <string>{{ bright_foreground }}</string>
        <key>selection</key>
        <string>{{ selection }}</string>
        <key>lineHighlight</key>
        <string>{{ lighter_background }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Comment</string>
      <key>scope</key>
      <string>comment, punctuation.definition.comment</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ muted }}</string>
        <key>fontStyle</key>
        <string>italic</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Variable</string>
      <key>scope</key>
      <string>variable, string constant.other.placeholder</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ foreground }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Variable Parameter</string>
      <key>scope</key>
      <string>variable.parameter, entity.name.variable.parameter, meta.function.parameter</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ cyan }}</string>
        <key>fontStyle</key>
        <string>italic</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Variable Property</string>
      <key>scope</key>
      <string>variable.other.property, variable.other.object.property, variable.other.member</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ cyan }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Variable Constant</string>
      <key>scope</key>
      <string>variable.other.constant, constant.other</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ bright_yellow }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Enum Member</string>
      <key>scope</key>
      <string>variable.other.enummember</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ orange }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Invalid</string>
      <key>scope</key>
      <string>invalid, invalid.illegal</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ red }}</string>
        <key>fontStyle</key>
        <string>strikethrough</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Invalid Deprecated</string>
      <key>scope</key>
      <string>invalid.deprecated</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ yellow }}</string>
        <key>fontStyle</key>
        <string>strikethrough</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Keyword</string>
      <key>scope</key>
      <string>keyword, storage.type.class, storage.type.function</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ bright_magenta }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Storage Modifier</string>
      <key>scope</key>
      <string>storage.modifier</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ yellow }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Keyword Control</string>
      <key>scope</key>
      <string>keyword.control, keyword.control.flow</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ bright_magenta }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Keyword Import</string>
      <key>scope</key>
      <string>keyword.control.import, keyword.control.export, keyword.control.from, keyword.control.as</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ blue }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Keyword Operator</string>
      <key>scope</key>
      <string>keyword.operator, keyword.operator.new, keyword.operator.expression, keyword.operator.logical, keyword.operator.comparison</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ bright_blue }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Operator</string>
      <key>scope</key>
      <string>punctuation.accessor, punctuation.separator.key-value</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ bright_blue }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Type</string>
      <key>scope</key>
      <string>storage.type, entity.name.type</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ yellow }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Type Builtin</string>
      <key>scope</key>
      <string>storage.type.primitive, support.type</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ foreground }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Type Class</string>
      <key>scope</key>
      <string>entity.name.type.class, entity.name.class, support.class, entity.other.inherited-class</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ yellow }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Type Interface</string>
      <key>scope</key>
      <string>entity.name.type.interface</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ yellow }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Type Enum</string>
      <key>scope</key>
      <string>entity.name.type.enum</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ yellow }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Type Parameter</string>
      <key>scope</key>
      <string>entity.name.type.parameter</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ yellow }}</string>
        <key>fontStyle</key>
        <string>italic</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Namespace</string>
      <key>scope</key>
      <string>entity.name.namespace, entity.name.type.module</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ blue }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Function</string>
      <key>scope</key>
      <string>entity.name.function, meta.function-call.generic, meta.function-call, variable.function</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ blue }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Function Builtin</string>
      <key>scope</key>
      <string>support.function</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ cyan }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Function Method</string>
      <key>scope</key>
      <string>entity.name.function.method, meta.method.declaration</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ blue }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Function Decorator</string>
      <key>scope</key>
      <string>entity.name.function.decorator, meta.decorator, punctuation.decorator, meta.annotation</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ cyan }}</string>
        <key>fontStyle</key>
        <string>italic</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Punctuation</string>
      <key>scope</key>
      <string>punctuation, meta.brace, meta.bracket</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ dark_foreground }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Constant Numeric</string>
      <key>scope</key>
      <string>constant.numeric, constant.numeric.integer, constant.numeric.float, constant.numeric.hex, constant.numeric.octal, constant.numeric.binary</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ orange }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Constant Boolean</string>
      <key>scope</key>
      <string>constant.language.boolean</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ orange }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Constant Builtin</string>
      <key>scope</key>
      <string>constant.language, constant.language.null, constant.language.undefined</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ cyan }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Constant Character</string>
      <key>scope</key>
      <string>constant.character</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ green }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Constant Character Escape</string>
      <key>scope</key>
      <string>constant.character.escape</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ bright_magenta }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>String</string>
      <key>scope</key>
      <string>string, string.quoted, string.template</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ green }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>String Interpolation</string>
      <key>scope</key>
      <string>punctuation.definition.template-expression, punctuation.section.embedded, meta.embedded.line</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ bright_blue }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>String Regexp</string>
      <key>scope</key>
      <string>string.regexp, constant.other.character-class.regexp, constant.character.escape.regexp</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ bright_cyan }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Support</string>
      <key>scope</key>
      <string>support.type.property-name, support.constant, support.other</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ cyan }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Tag</string>
      <key>scope</key>
      <string>entity.name.tag, meta.tag</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ yellow }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Tag Attribute</string>
      <key>scope</key>
      <string>entity.other.attribute-name</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ foreground }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>CSS Property</string>
      <key>scope</key>
      <string>support.type.property-name.css, support.type.vendored.property-name.css, meta.property-name.css</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ cyan }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>CSS Value</string>
      <key>scope</key>
      <string>support.constant.property-value.css, meta.property-value.css</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ foreground }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>CSS Selector</string>
      <key>scope</key>
      <string>entity.other.attribute-name.class.css, entity.other.attribute-name.id.css</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ yellow }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>CSS Pseudo</string>
      <key>scope</key>
      <string>entity.other.attribute-name.pseudo-class.css, entity.other.attribute-name.pseudo-element.css</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ cyan }}</string>
        <key>fontStyle</key>
        <string>italic</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>CSS Units</string>
      <key>scope</key>
      <string>keyword.other.unit.css</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ orange }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>JSON Key Level 0</string>
      <key>scope</key>
      <string>source.json meta.structure.dictionary.json support.type.property-name.json</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ orange }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>JSON Key Level 1</string>
      <key>scope</key>
      <string>source.json meta.structure.dictionary.json meta.structure.dictionary.value.json meta.structure.dictionary.json support.type.property-name.json</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ yellow }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>JSON Key Level 2</string>
      <key>scope</key>
      <string>source.json meta.structure.dictionary.json meta.structure.dictionary.value.json meta.structure.dictionary.json meta.structure.dictionary.value.json meta.structure.dictionary.json support.type.property-name.json</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ blue }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>JSON Key Level 3</string>
      <key>scope</key>
      <string>source.json meta.structure.dictionary.json meta.structure.dictionary.value.json meta.structure.dictionary.json meta.structure.dictionary.value.json meta.structure.dictionary.json meta.structure.dictionary.value.json meta.structure.dictionary.json support.type.property-name.json</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ bright_magenta }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>JSON Key Level 4</string>
      <key>scope</key>
      <string>source.json meta.structure.dictionary.json meta.structure.dictionary.value.json meta.structure.dictionary.json meta.structure.dictionary.value.json meta.structure.dictionary.json meta.structure.dictionary.value.json meta.structure.dictionary.json meta.structure.dictionary.value.json meta.structure.dictionary.json support.type.property-name.json</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ cyan }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>JSON Key Level 5+</string>
      <key>scope</key>
      <string>source.json meta.structure.dictionary.json meta.structure.dictionary.value.json meta.structure.dictionary.json meta.structure.dictionary.value.json meta.structure.dictionary.json meta.structure.dictionary.value.json meta.structure.dictionary.json meta.structure.dictionary.value.json meta.structure.dictionary.json meta.structure.dictionary.value.json meta.structure.dictionary.json support.type.property-name.json</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ green }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Markdown Heading</string>
      <key>scope</key>
      <string>markup.heading, entity.name.section.markdown, punctuation.definition.heading.markdown</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ blue }}</string>
        <key>fontStyle</key>
        <string>bold</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Markdown Bold</string>
      <key>scope</key>
      <string>markup.bold, punctuation.definition.bold.markdown</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ foreground }}</string>
        <key>fontStyle</key>
        <string>bold</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Markdown Italic</string>
      <key>scope</key>
      <string>markup.italic, punctuation.definition.italic.markdown</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ foreground }}</string>
        <key>fontStyle</key>
        <string>italic</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Markdown Link</string>
      <key>scope</key>
      <string>markup.underline.link, string.other.link.title.markdown, string.other.link.description.markdown</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ blue }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Markdown Code</string>
      <key>scope</key>
      <string>markup.inline.raw, markup.fenced_code.block, markup.raw.block</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ green }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Markdown Quote</string>
      <key>scope</key>
      <string>markup.quote, punctuation.definition.quote.begin.markdown</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ muted }}</string>
        <key>fontStyle</key>
        <string>italic</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Markdown List</string>
      <key>scope</key>
      <string>punctuation.definition.list.begin.markdown, markup.list.numbered, markup.list.unnumbered</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ cyan }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Diff Inserted</string>
      <key>scope</key>
      <string>markup.inserted, punctuation.definition.inserted</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ green }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Diff Deleted</string>
      <key>scope</key>
      <string>markup.deleted, punctuation.definition.deleted</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ red }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Diff Changed</string>
      <key>scope</key>
      <string>markup.changed, punctuation.definition.changed</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ orange }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>This/Self</string>
      <key>scope</key>
      <string>variable.language.this, variable.language.self, variable.language.special.self</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ foreground }}</string>
        <key>fontStyle</key>
        <string>italic</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Object Keys</string>
      <key>scope</key>
      <string>meta.object-literal.key, string.unquoted.label.js</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ foreground }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Rust Lifetime</string>
      <key>scope</key>
      <string>entity.name.type.lifetime.rust, punctuation.definition.lifetime.rust</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ cyan }}</string>
        <key>fontStyle</key>
        <string>italic</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Rust Macro</string>
      <key>scope</key>
      <string>entity.name.function.macro.rust, support.function.macro.rust</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ cyan }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Shell Variable</string>
      <key>scope</key>
      <string>variable.other.normal.shell, variable.other.positional.shell, variable.other.bracket.shell</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ foreground }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Shell Command</string>
      <key>scope</key>
      <string>entity.name.command.shell</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ blue }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Shell Builtin</string>
      <key>scope</key>
      <string>support.function.builtin.shell</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ cyan }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>YAML Key</string>
      <key>scope</key>
      <string>entity.name.tag.yaml</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ cyan }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>TOML Key</string>
      <key>scope</key>
      <string>keyword.key.toml, support.type.property-name.toml</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ cyan }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>TOML Table</string>
      <key>scope</key>
      <string>entity.other.attribute-name.table.toml, support.type.property-name.table.toml</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ yellow }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>INI Section</string>
      <key>scope</key>
      <string>entity.name.section.group-title.ini, punctuation.definition.entity.ini</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ yellow }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>INI Key</string>
      <key>scope</key>
      <string>keyword.other.definition.ini</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ cyan }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Make Target</string>
      <key>scope</key>
      <string>entity.name.function.target.makefile</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ blue }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Make Variable</string>
      <key>scope</key>
      <string>variable.other.makefile</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ foreground }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Go Package</string>
      <key>scope</key>
      <string>entity.name.package.go</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ blue }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Python Self</string>
      <key>scope</key>
      <string>variable.parameter.function.language.special.self.python</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ foreground }}</string>
        <key>fontStyle</key>
        <string>italic</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Python Magic</string>
      <key>scope</key>
      <string>support.function.magic.python, support.variable.magic.python</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ cyan }}</string>
        <key>fontStyle</key>
        <string>italic</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>PHP Variable</string>
      <key>scope</key>
      <string>variable.other.php, punctuation.definition.variable.php</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ foreground }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>C Preprocessor</string>
      <key>scope</key>
      <string>meta.preprocessor.c, meta.preprocessor.include.c, keyword.control.directive.include.c</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ cyan }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>C# Attribute</string>
      <key>scope</key>
      <string>meta.attribute.csharp, entity.name.type.attribute.csharp</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ cyan }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>SQL Keyword</string>
      <key>scope</key>
      <string>keyword.other.DML.sql, keyword.other.DDL.sql</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ bright_magenta }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>GraphQL Type</string>
      <key>scope</key>
      <string>support.type.graphql, entity.name.type.graphql</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ yellow }}</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>GraphQL Field</string>
      <key>scope</key>
      <string>variable.graphql, variable.other.graphql</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>{{ foreground }}</string>
      </dict>
    </dict>
  </array>
  <key>uuid</key>
  <string>4c0b0b8f-2f6a-4a3e-9c1a-omarchy000001</string>
</dict>
</plist>
