# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../lib/workshop_booking/registration"

# Exercises every decision boundary in the workshop registration policy.
class RegistrationTest < Minitest::Test
  def registration(capacity: 10, booked: 7, waitlist_enabled: true)
    WorkshopBooking::Registration.new(
      capacity: capacity,
      booked: booked,
      waitlist_enabled: waitlist_enabled
    )
  end

  def test_rejects_zero_and_negative_requests
    assert_equal :invalid, registration.status(requested_seats: 0)
    assert_equal :invalid, registration.status(requested_seats: -1)
  end

  def test_confirms_a_request_that_exactly_fills_the_workshop
    assert_equal :confirmed, registration.status(requested_seats: 3)
  end

  def test_waitlists_a_small_request_when_the_workshop_is_full
    assert_equal :waitlisted, registration(booked: 10).status(requested_seats: 2)
  end

  def test_declines_requests_above_the_waitlist_limit
    assert_equal :declined, registration(booked: 10).status(requested_seats: 3)
  end

  def test_declines_when_the_waitlist_is_disabled
    result = registration(booked: 10, waitlist_enabled: false).status(requested_seats: 1)

    assert_equal :declined, result
  end

  def test_projects_the_new_booked_total
    assert_equal 9, registration.projected_booked(requested_seats: 2)
  end
end
