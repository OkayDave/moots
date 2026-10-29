# frozen_string_literal: true

require_relative "../../lib/parcel_shop/quote"

RSpec.describe ParcelShop::Quote do
  it "quotes an ordinary parcel" do
    total = described_class.new(
      subtotal_pence: 2_000,
      weight_grams: 1_000,
      express: false
    ).total_pence

    expect(total).to eq(2_500)
  end

  it "quotes a heavy express parcel" do
    total = described_class.new(
      subtotal_pence: 6_000,
      weight_grams: 6_000,
      express: true
    ).total_pence

    expect(total).to eq(7_150)
  end
end
