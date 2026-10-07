defmodule LeastCostFeedWeb.PageControllerTest do
  use LeastCostFeedWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Least Cost Feed(LCF)"
  end
end
