# frozen_string_literal: true

# A standalone subject with one comparison in each method and no Moots dependency.
module ComparisonRules
  def self.same?(actual, expected)
    actual == expected
  end

  def self.different?(actual, expected)
    actual != expected
  end

  def self.above?(value, boundary)
    value > boundary
  end

  def self.at_least?(value, boundary)
    value >= boundary
  end

  def self.below?(value, boundary)
    value < boundary
  end

  def self.at_most?(value, boundary)
    value <= boundary
  end
end
