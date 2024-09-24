defmodule LeastCostFeed.Helpers do
  import Ecto.Changeset

  def get_list(changeset, detail_name) do
    list =
      if is_nil(get_change(changeset, detail_name)) do
        Map.fetch!(changeset.data, detail_name)
      else
        get_change(changeset, detail_name)
      end

    if is_struct(list, Ecto.Association.NotLoaded), do: [], else: list
  end

  def my_fetch_field!(data, field) do
    func = if is_struct(data, Ecto.Changeset) do
      &fetch_field!/2
    else
      &Map.fetch!/2
    end

    func.(data, field)
  end
end
