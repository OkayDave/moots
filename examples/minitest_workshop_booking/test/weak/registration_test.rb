# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../lib/workshop_booking/registration"

# Demonstrates a plausible suite that misses important policy boundaries.
class RegistrationTest < Minitest::Test
  def test_confirms_available_seats
    registration = WorkshopBooking::Registration.new(
      capacity: 20,
      booked: 5,
      waitlist_enabled: true
    )

    assert_equal :confirmed, registration.status(requested_seats: 2)
    assert_equal 7, registration.projected_booked(requested_seats: 2)
  end

  def test_waitlists_when_full
    registration = WorkshopBooking::Registration.new(
      capacity: 20,
      booked: 20,
      waitlist_enabled: true
    )

    assert_equal :waitlisted, registration.status(requested_seats: 1)
  end
end
