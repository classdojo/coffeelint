###
CoffeeLint

Copyright (c) 2011 Matthew Perpick.
Modified 2012 by gareth@classdojo.com (Gareth Aye)
CoffeeLint is freely distributable under the MIT license.
###


ASTLinter = require("./astlinter")
LexicalLinter = require("./lexicallinter")
LineLinter = require("./linelinter")


# Coffeelint's namespace.
coffeelint = {}

if exports?
  # If we're running in node, export our module and load dependencies.
  coffeelint = exports
  CoffeeScript = require("coffee-script")
else
  # If we're in the browser, export out module to global scope.
  # Assume CoffeeScript is already loaded.
  this.coffeelint = coffeelint
  CoffeeScript = this.CoffeeScript


# The current version of Coffeelint.
coffeelint.VERSION = "0.5.2"


# CoffeeLint error levels.
coffeelint.Level =
  ERROR: "error"
  WARN: "warn"
  IGNORE: "ignore"


# CoffeeLint's default rule configuration.
coffeelint.Rule =
  identifier:
    level: coffeelint.Level.ERROR
    message: "ID doesn't match [a-zA-Z][a-zA-Z\d]+ or [A-Z](_?[A-Z\d]*)*"
  no_tabs:
    level: coffeelint.Level.ERROR
    message: "Line contains tab indentation"
  no_trailing_whitespace:
    level: coffeelint.Level.ERROR
    message: "Line ends with trailing whitespace"
  max_line_length:
    value: 80
    level: coffeelint.Level.ERROR
    message: "Line exceeds maximum allowed length"
  camel_case_classes:
    level: coffeelint.Level.ERROR
    message: "Class names should be camel cased"
  indentation:
    value: 2
    level: coffeelint.Level.ERROR
    message: "Line contains inconsistent indentation"
  no_implicit_braces:
    level: coffeelint.Level.IGNORE
    message: "Implicit braces are forbidden"
  no_trailing_semicolons:
    level: coffeelint.Level.ERROR
    message: "Line contains a trailing semicolon"
  no_plusplus:
    level: coffeelint.Level.IGNORE
    message: "The increment and decrement operators are forbidden"
  no_throwing_strings:
    level: coffeelint.Level.ERROR
    message: "Throwing strings is forbidden"
  cyclomatic_complexity:
    value: 10
    level: coffeelint.Level.IGNORE
    message: "The cyclomatic complexity is too damn high"
  no_backticks:
    level: coffeelint.Level.ERROR
    message: "Backticks are forbidden"
  line_endings:
    level: coffeelint.Level.IGNORE
    value: "unix" # or "windows"
    message: "Line contains incorrect line endings"
  no_implicit_parens:
    level: coffeelint.Level.IGNORE
    message: "Implicit parens are forbidden"
  space_operators:
    level: coffeelint.Level.IGNORE
    message: "Operators must be spaced properly"
  coffeescript_error:
    level: coffeelint.Level.ERROR
    message: "" # The default coffeescript error is fine.


# Some repeatedly used regular expressions.
coffeelint.Regexes =
  IDENTIFIER: /^[a-zA-Z][a-zA-Z\d]*$/
  CONSTANT: /^[A-Z](_?[A-Z\d]*)*$/
  TRAILING_WHITESPACE: /[^\s]+[\t ]+\r?$/
  INDENTATION: /\S/
  CAMEL_CASE: /^[A-Z][a-zA-Z\d]*$/
  TRAILING_SEMICOLON: /;\r?$/
  CONFIG_STATEMENT: /coffeelint:\s*(disable|enable)(?:=([\w\s,]*))?/


# Patch the source properties onto the destination.
extend = (destination, sources...) ->
  for source in sources
    (destination[k] = v for k, v of source)
  return destination

# Patch any missing attributes from defaults to source.
defaults = (source, defaults) ->
  extend({}, defaults, source)


# Create an error object for the given rule with the given attributes.
coffeelint.createError = (rule, attrs = {}) ->
  level = attrs.level
  if level not in [coffeelint.Level.ERROR, coffeelint.Level.IGNORE,
                   coffeelint.Level.WARN]
    throw new Error("unknown level #{level}")

  if level in [coffeelint.Level.ERROR, coffeelint.Level.WARN]
    attrs.rule = rule
    return defaults(attrs, coffeelint.Rule[rule])
  else
    return null

# Store suppressions in the form of { line #: type }
blockConfig =
  enable: {}
  disable: {}


# Check the source against the given configuration and return an array
# of any errors found. An error is an object with the following
# properties:
#
#   {
#     rule:       "Name of the violated rule",
#     lineNumber: "Number of the line that caused the violation",
#     level:      "The error level of the violated rule",
#     message:    "Information about the violated rule",
#     context:    "Optional details about why the rule was violated"
#   }
#
coffeelint.lint = (source, userConfig = {}) ->
  lines = source.split("\n")

  # Merge default and user configuration.
  config = {}
  for k, v of coffeelint.Rule
    config[k] = defaults(userConfig[k], v)

  # Check ahead for inline enabled rules
  initiallyDisabled = []
  for line in lines
    s = coffeelint.Regexes.CONFIG_STATEMENT.exec(line)
    if s? and s.length > 2 and "enable" in s
      for r in s[1..]
        unless r in ["enable","disable"]
          unless r of config and config[r].level in ["warn","error"]
            initiallyDisabled.push(r)
            config[r] = { level: "error" }

   # Do AST linting first so all compile errors are caught.
  astLinter = new ASTLinter(source, config)
  astErrors = astLinter.lint()

  # Do lexical linting.
  lexicalLinter = new LexicalLinter(source, config)
  lexErrors = lexicalLinter.lint()

  # Do line linting.
  tokensByLine = lexicalLinter.tokensByLine
  lineLinter = new LineLinter(source, config, tokensByLine)
  lineErrors = lineLinter.lint()

  # Sort by line number and return.
  errors = lexErrors.concat(lineErrors, astErrors)
  errors.sort((a, b) -> a.lineNumber - b.lineNumber)

  # Helper to remove rules from disabled list
  difference = (a, b) ->
    j = 0
    while j < a.length
      if a[j] in b
        a.splice(j, 1)
      else
        j++

  # Disable/enable rules for inline blocks
  allErrors = errors
  errors = []
  disabled = initiallyDisabled
  nextLine = 0
  for i in [0...lines.length]
    for cmd of blockConfig
      rules = blockConfig[cmd][i]
      {
        "disable": ->
          disabled = disabled.concat(rules)
        "enable": ->
          difference(disabled, rules)
          disabled = initiallyDisabled if rules.length is 0
      }[cmd]() if rules?
    # advance line and append relevent messages
    while nextLine is i and allErrors.length > 0
      nextLine = allErrors[0].lineNumber - 1
      e = allErrors[0]
      if e.lineNumber is i + 1 or not e.lineNumber?
        e = allErrors.shift()
        errors.push e unless e.rule in disabled

  blockConfig =
    "enable": {}
    "disable": {}

  return errors
