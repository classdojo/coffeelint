###
CoffeeLint

Copyright (c) 2011 Matthew Perpick.
Modified 2012 by gareth@classdojo.com (Gareth Aye)
CoffeeLint is freely distributable under the MIT license.
###


coffeelint = require("./coffeelint")
CoffeeScript = require("coffee-script")

# A class that performs regex checks on each line of the source.
class LineLinter
  constructor: (source, config, tokensByLine) ->
    @source = source
    @config = config
    @tokensByLine = tokensByLine
    @lines = @source.split("\n")
    @lineCount = @lines.length
    @line = null
    @lineNumber = 0

  lint: () ->
    errors = []
    for line, lineNumber in @lines
      @lineNumber = lineNumber
      @line = line
      errors = errors.concat(@lintLine())
    return errors

  # Return an array of errors in the current line.
  lintLine: () ->
    # Only check lines that have compiled tokens. This helps
    # us ignore tabs in the middle of multi line strings, heredocs, etc.
    # since they are all reduced to a single token whose line number
    # is the start of the expression.
    if not @lineHasToken()
      return []

    errors = []
    errors.push(@checkTabs())
    errors.push(@checkTrailingWhitespace())
    errors.push(@checkLineLength())
    errors.push(@checkTrailingSemicolon())
    errors.push(@checkLineEndings())
    errors.push(@checkComments())
    return errors.filter (error) -> error != null

  checkTabs: () ->
    # TODO(gareth): Why [0]?
    indentation = @line.split(coffeelint.Regexes.INDENTATION)[0]
    if "\t" in indentation
      return @createLineError("no_tabs")
    else
      return null

  checkTrailingWhitespace: () ->
    whitespace = coffeelint.Regexes.TRAILING_WHITESPACE.test(@line)
    if whitespace
      return @createLineError("no_trailing_whitespace")
    else
      return null

  checkLineLength: () ->
    rule = "max_line_length"
    max = @config[rule]?.value
    if max and max < @line.length
      return @createLineError(rule)
    else
      return null

  checkTrailingSemicolon: () ->
    # Don't throw errors when the contents of  multiline strings,
    # regexes and the like end in ";"
    semicolon = coffeelint.Regexes.TRAILING_SEMICOLON.test(@line)
    [first..., last] = @getLineTokens()
    newline = last and last.newLine?
    if semicolon and not newline
      return @createLineError("no_trailing_semicolons")
    else
      return null

  checkLineEndings: () ->
    rule = "line_endings"
    ending = @config[rule]?.value

    if not ending or @isLastLine() or not @line
      return null

    lastChar = @line[@line.length - 1]
    valid = if ending == "windows"
      lastChar == "\r"
    else if ending == "unix"
      lastChar != "\r"
    else
      throw new Error("unknown line ending type: #{ending}")
    if not valid
      return @createLineError(rule, {context:"Expected #{ending}"})
    else
      return null

  checkComments: () ->
    # Check for block config statements enable and disable
    result = coffeelint.Regexes.CONFIG_STATEMENT.exec(@line)
    if result?
      cmd = result[1]
      rules = []
      if result[2]?
        for r in result[2].split(",")
          rules.push r.replace(/^\s+|\s+$/g, "")
      blockConfig[cmd][@lineNumber] = rules
    return null

  createLineError: (rule, attrs = {}) ->
    attrs.lineNumber = @lineNumber + 1 # Lines are indexed by zero.
    attrs.level = @config[rule]?.level
    coffeelint.createError(rule, attrs)

  isLastLine: () ->
    return @lineNumber == @lineCount - 1

  # Return true if the given line actually has tokens.
  lineHasToken: () ->
    return @tokensByLine[@lineNumber]?

  # Return tokens for the given line number.
  getLineTokens: () ->
    @tokensByLine[@lineNumber] || []

module.exports = LineLinter
