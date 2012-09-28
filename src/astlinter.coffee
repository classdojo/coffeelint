coffeelint = require("./coffeelint")
CoffeeScript = require("coffee-script")

# A class that performs static analysis of the abstract
# syntax tree.
class ASTLinter
  constructor: (source, config) ->
    @source = source
    @config = config
    @errors = []

  lint: () ->
    try
      @node = CoffeeScript.nodes(@source)
    catch coffeeError
      @errors.push @_parseCoffeeScriptError(coffeeError)
      return @errors
    @lintNode(@node)
    @errors

  # Lint the AST node and return it's cyclomatic complexity.
  lintNode: (node) ->
    # Get the complexity of the current node.
    name = node.constructor.name
    complexity = if name in ["If", "While", "For", "Try"]
      1
    else if name == "Op" and node.operator in ["&&", "||"]
      1
    else if name == "Switch"
      node.cases.length
    else
      0

    # Add the complexity of all child's nodes to this one.
    node.eachChild (childNode) =>
      return false unless childNode
      complexity += @lintNode(childNode)
      return true

    # If the current node is a function, and it's over our limit, add an
    # error to the list.
    rule = @config.cyclomatic_complexity
    if name == "Code" and complexity >= rule.value
      attrs = {
        context: complexity + 1
        level: rule.level
        line: 0
      }
      error = coffeelint.createError "cyclomatic_complexity", attrs
      @errors.push error if error

    # Return the complexity for the benefit of parent nodes.
    return complexity

  _parseCoffeeScriptError: (coffeeError) ->
    rule = coffeelint.Rule["coffeescript_error"]

    message = coffeeError.toString()

    # Parse the line number
    lineNumber = -1
    match = /line (\d)/.exec message
    lineNumber = parseInt match[1], 10 if match?.length > 1
    attrs = {
      message: message
      level: rule.level
      lineNumber: lineNumber
    }
    return  coffeelint.createError "coffeescript_error", attrs

module.exports = ASTLinter
