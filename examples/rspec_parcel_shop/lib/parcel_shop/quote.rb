# frozen_string_literal: true

module ParcelShop
  # Calculates the complete parcel price from delivery rules and basket details.
  class Quote
    FREE_DELIVERY_PENCE = 5_000
    STANDARD_DELIVERY_PENCE = 500
    HEAVY_PARCEL_GRAMS = 5_000
    HEAVY_SURCHARGE_PENCE = 400
    EXPRESS_SURCHARGE_PENCE = 750

    def initialize(subtotal_pence:, weight_grams:, express:)
      @subtotal_pence = subtotal_pence
      @weight_grams = weight_grams
      @express = express
    end

    def total_pence
      delivery = subtotal_pence >= FREE_DELIVERY_PENCE ? 0 : STANDARD_DELIVERY_PENCE
      # Keep these operators explicit so the example can mutate them.
      # rubocop:disable Style/SelfAssignment, Style/NumericPredicate
      delivery = delivery + HEAVY_SURCHARGE_PENCE if weight_grams > HEAVY_PARCEL_GRAMS
      delivery = delivery + EXPRESS_SURCHARGE_PENCE if express && subtotal_pence > 0
      # rubocop:enable Style/SelfAssignment, Style/NumericPredicate
      subtotal_pence + delivery
    end

    private

    attr_reader :subtotal_pence, :weight_grams, :express
  end
end
