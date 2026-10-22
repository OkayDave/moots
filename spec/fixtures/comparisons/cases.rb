# frozen_string_literal: true

# Handwritten behavioral expectations, independent of the subject and mutator maps.
module ComparisonCases
  STRONG = {
    same?: [[4, 5, false], [5, 5, true], [6, 5, false]],
    different?: [[4, 5, true], [5, 5, false], [6, 5, true]],
    above?: [[4, 5, false], [5, 5, false], [6, 5, true]],
    at_least?: [[4, 5, false], [5, 5, true], [6, 5, true]],
    below?: [[4, 5, true], [5, 5, false], [6, 5, false]],
    at_most?: [[4, 5, true], [5, 5, true], [6, 5, false]]
  }.freeze

  # These suites still assert real behavior but miss equality at each boundary.
  WEAK = {
    same?: [[4, 5, false], [6, 5, false]],
    different?: [[4, 5, true], [6, 5, true]],
    above?: [[4, 5, false], [6, 5, true]],
    at_least?: [[4, 5, false], [6, 5, true]],
    below?: [[4, 5, true], [6, 5, false]],
    at_most?: [[4, 5, true], [6, 5, false]]
  }.freeze
end
