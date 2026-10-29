# frozen_string_literal: true

require_relative "../../lib/parcel_shop/quote"

RSpec.describe ParcelShop::Quote do
  def quote(subtotal_pence:, weight_grams: 1_000, express: false)
    described_class.new(
      subtotal_pence: subtotal_pence,
      weight_grams: weight_grams,
      express: express
    ).total_pence
  end

  it "charges standard delivery below the free-delivery threshold" do
    expect(quote(subtotal_pence: 4_999)).to eq(5_499)
  end

  it "gives free delivery at the exact threshold" do
    expect(quote(subtotal_pence: 5_000)).to eq(5_000)
  end

  it "applies the heavy surcharge only above the weight boundary" do
    expect(quote(subtotal_pence: 5_000, weight_grams: 5_000)).to eq(5_000)
    expect(quote(subtotal_pence: 5_000, weight_grams: 5_001)).to eq(5_400)
  end

  it "adds express delivery to a non-empty order" do
    expect(quote(subtotal_pence: 5_000, express: true)).to eq(5_750)
  end

  it "does not charge express delivery for an empty basket" do
    expect(quote(subtotal_pence: 0, express: true)).to eq(500)
  end
end
