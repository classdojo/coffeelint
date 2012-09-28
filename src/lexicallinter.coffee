###
CoffeeLint

Copyright (c) 2011 Matthew Perpick.
Modified 2012 by gareth@classdojo.com (Gareth Aye)
CoffeeLint is freely distributable under the MIT license.
###


coffeelint = require("./coffeelint")
CoffeeScript = require("coffee-script")

# A class that performs checks on the output of CoffeeScript's lexer.
class LexicalLinter
  constructor: (source, config) ->
    @source = source
    @tokens = CoffeeScript.tokens(source)
    @config = config
    @i = 0        # The index of the current token we're linting.
    @tokensByLine = {}  # A map of tokens by line.
    @arrayTokens = []   # A stack tracking the array token pairs.
    @parenTokens = []   # A stack tracking the parens token pairs.
    @callTokens = []   # A stack tracking the call token pairs.
    @lines = source.split("\n")

  # Return a list of errors encountered in the given source.
  lint: () ->
    errors = []
    for token, i in @tokens
      @i = i
      error = @lintToken(token)
      errors.push(error) if error
    return errors

  # Return an error if the given token fails a lint check, false otherwise.
  lintToken: (token) ->
    [type, value, lineNumber] = token

    @tokensByLine[lineNumber] ?= []
    @tokensByLine[lineNumber].push(token)
    # CoffeeScript loses line numbers of interpolations and multi-line
    # regexes, so fake it by using the last line number we know.
    @lineNumber = lineNumber or @lineNumber or 0

    # Now lint it.
    switch type
      when "IDENTIFIER" then @lintIdentifier(token)
      when "INDENT" then @lintIndentation(token)
      when "CLASS" then @lintClass(token)
      when "{" then @lintBrace(token)
      when "++", "--" then @lintIncrement(token)
      when "THROW" then @lintThrow(token)
      when "[", "]" then @lintArray(token)
      when "(", ")" then @lintParens(token)
      when "JS" then @lintJavascript(token)
      when "CALL_START", "CALL_END" then @lintCall(token)
      when "+", "-" then @lintPlus(token)
      when "=", "MATH", "COMPARE", "LOGIC" then @lintMath(token)
      else null

  lintIdentifier: (token) ->
    name = token[1]
    if coffeelint.Regexes.IDENTIFIER.test(name)
      return null
    else if coffeelint.Regexes.CONSTANT.test(name)
      return null
    return @createLexError("identifier", { context: "identifier: #{name}" })

  # Lint the given array token.
  lintArray: (token) ->
    # Track the array token pairs
    if token[0] == "["
      @arrayTokens.push(token)
    else if token[0] == "]"
      @arrayTokens.pop()
    # Return null, since we're not really linting anything here.
    null

  lintParens: (token) ->
    if token[0] == "("
      p1 = @peek(-1)
      n1 = @peek(1)
      n2 = @peek(2)
      # String interpolations start with "" + so start the type co-ercion,
      # so track if we're inside of one. This is most definitely not
      # 100% true but what else can we do?
      i = n1 and n2 and n1[0] == "STRING" and n2[0] == "+"
      token.isInterpolation = i
      @parenTokens.push(token)
    else
      @parenTokens.pop()
    # We're not linting, just tracking interpolations.
    null

  isInInterpolation: () ->
    for t in @parenTokens
      return true if t.isInterpolation
    return false

  isInExtendedRegex: () ->
    for t in @callTokens
      return true if t.isRegex
    return false

  lintPlus: (token) ->
    # We can't check this inside of interpolations right now, because the
    # plusses used for the string type co-ercion are marked not spaced.
    return null if @isInInterpolation() or @isInExtendedRegex()

    p = @peek(-1)
    unaries = ["TERMINATOR", "(", "=", "-", "+", ",", "CALL_START",
          "INDEX_START", "..", "...", "COMPARE", "IF",
          "THROW", "LOGIC", "POST_IF", ":", "[", "INDENT"]
    isUnary = if not p then false else p[0] in unaries
    if (isUnary and token.spaced) or
          (not isUnary and not token.spaced and not token.newLine)
      @createLexError("space_operators", {context: token[1]})
    else
      null

  lintMath: (token) ->
    if not token.spaced and not token.newLine
      @createLexError("space_operators", {context: token[1]})
    else
      null

  lintCall: (token) ->
    if token[0] == "CALL_START"
      p = @peek(-1)
      # Track regex calls, to know (approximately) if we're in an
      # extended regex.
      token.isRegex = p and p[0] == "IDENTIFIER" and p[1] == "RegExp"
      @callTokens.push(token)
      if token.generated
        return @createLexError("no_implicit_parens")
      else
        return null
    else
      @callTokens.pop()
      return null

  lintBrace: (token) ->
    if token.generated
      # Peek back to the last line break. If there is a class
      # definition, ignore the generated brace.
      i = -1
      loop
        t = @peek(i)
        if not t? or t[0] == "TERMINATOR"
          return @createLexError("no_implicit_braces")
        if t[0] == "CLASS"
          return null
        i -= 1
    else
      return null

  lintJavascript:(token) ->
    @createLexError("no_backticks")

  lintThrow: (token) ->
    [n1, n2] = [@peek(), @peek(2)]
    # Catch literals and string interpolations, which are wrapped in
    # parens.
    nextIsString = n1[0] == "STRING" or (n1[0] == "(" and n2[0] == "STRING")
    @createLexError("no_throwing_strings") if nextIsString

  lintIncrement: (token) ->
    attrs = {context: "found #{token[0]}"}
    @createLexError("no_plusplus", attrs)

  # Return an error if the given indentation token is not correct.
  lintIndentation: (token) ->
    [type, numIndents, lineNumber] = token

    return null if token.generated?

    # HACK: CoffeeScript's lexer insert indentation in string
    # interpolations that start with spaces e.g. "#{ 123 }"
    # so ignore such cases. Are there other times an indentation
    # could possibly follow a "+"?
    previous = @peek(-2)
    isInterpIndent = previous and previous[0] == "+"

    # Ignore the indentation inside of an array, so that
    # we can allow things like:
    #   x = ["foo",
    #       "bar"]
    previous = @peek(-1)
    isArrayIndent = @inArray() and previous?.newLine

    # Ignore indents used to for formatting on multi-line expressions, so
    # we can allow things like:
    #   a = b =
    #   c = d
    previousSymbol = @peek(-1)?[0]
    isMultiline = previousSymbol in ["=", ","]

    # Summarize the indentation conditions we'd like to ignore
    ignoreIndent = isInterpIndent or isArrayIndent or isMultiline

    # Compensate for indentation in function invocations that span multiple
    # lines, which can be ignored.
    if @isChainedCall()
      previousLine = @lines[@lineNumber - 1]
      previousIndentation = previousLine.match(/^(\s*)/)[1].length
      numIndents -= previousIndentation

    # Now check the indentation.
    expected = @config["indentation"].value
    if not ignoreIndent and numIndents != expected
      context = "Expected #{expected} " +
            "got #{numIndents}"
      @createLexError("indentation", {context})
    else
      null

  lintClass: (token) ->
    # TODO: you can do some crazy shit in CoffeeScript, like
    # class func().ClassName. Don't allow that.

    # Don't try to lint the names of anonymous classes.
    return null if token.newLine? or @peek()[0] in ["INDENT", "EXTENDS"]

    # It's common to assign a class to a global namespace, e.g.
    # exports.MyClassName, so loop through the next tokens until
    # we find the real identifier.
    className = null
    offset = 1
    until className
      if @peek(offset + 1)?[0] == "."
        offset += 2
      else if @peek(offset)?[0] == "@"
        offset += 1
      else
        className = @peek(offset)[1]

    # Now check for the error.
    if not coffeelint.Regexes.CAMEL_CASE.test(className)
      attrs = {context: "class name: #{className}"}
      @createLexError("camel_case_classes", attrs)
    else
      null

  createLexError: (rule, attrs = {}) ->
    attrs.lineNumber = @lineNumber + 1
    attrs.level = @config[rule].level
    attrs.line = @lines[@lineNumber]
    coffeelint.createError(rule, attrs)

  # Return the token n places away from the current token.
  peek: (n = 1) ->
    @tokens[@i + n] || null

  # Return true if the current token is inside of an array.
  inArray: () ->
    return @arrayTokens.length > 0

  # Return true if the current token is part of a property access
  # that is split across lines, for example:
  #   $("body")
  #     .addClass("foo")
  #     .removeClass("bar")
  isChainedCall: () ->
    # Get the index of the second most recent new line.
    lines = (i for token, i in @tokens[..@i] when token.newLine?)

    lastNewLineIndex = if lines then lines[lines.length - 2] else null

    # Bail out if there is no such token.
    return false if not lastNewLineIndex?

    # Otherwise, figure out if that token or the next is an attribute
    # look-up.
    tokens = [@tokens[lastNewLineIndex], @tokens[lastNewLineIndex + 1]]

    return !!(t for t in tokens when t and t[0] == ".").length

module.exports = LexicalLinter
