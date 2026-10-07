defmodule LeastCostFeedWeb.HelpersTest do
  use ExUnit.Case, async: true
  alias LeastCostFeedWeb.Helpers

  # Expected strings were captured from Number.Delimit.number_to_delimited/2
  # (number 1.0.5) before that dependency was dropped.
  describe "number_delimited/2" do
    test "delimits thousands and defaults to 2 decimals" do
      assert Helpers.number_delimited(1_234_567.891) == "1,234,567.89"
      assert Helpers.number_delimited(123_456_789_012.0) == "123,456,789,012.00"
    end

    test "pads to the requested precision" do
      assert Helpers.number_delimited(1_234_567.891, precision: 4) == "1,234,567.8910"
      assert Helpers.number_delimited(0.5) == "0.50"
    end

    test "formats integers and zero" do
      assert Helpers.number_delimited(1000) == "1,000.00"
      assert Helpers.number_delimited(12) == "12.00"
      assert Helpers.number_delimited(0) == "0.00"
      assert Helpers.number_delimited(0.0) == "0.00"
    end

    test "rounds half up on the shortest float representation" do
      assert Helpers.number_delimited(999.995) == "1,000.00"
      assert Helpers.number_delimited(1.005) == "1.01"
    end

    test "keeps the sign of negatives, including ones that round to zero" do
      assert Helpers.number_delimited(-1234.5) == "-1,234.50"
      assert Helpers.number_delimited(-0.004) == "-0.00"
    end

    test "accepts Decimal and numeric strings" do
      assert Helpers.number_delimited(Decimal.new("9876.54321")) == "9,876.54"
      assert Helpers.number_delimited(Decimal.new("1234567.8"), precision: 4) == "1,234,567.8000"
      assert Helpers.number_delimited("1234.5") == "1,234.50"
    end

    test "passes nil through" do
      assert Helpers.number_delimited(nil) == nil
    end
  end
end
