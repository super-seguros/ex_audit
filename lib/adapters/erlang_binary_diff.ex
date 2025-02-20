defmodule ExAudit.Adapters.ErlangBinaryDiff do
  @behaviour ExAudit.Adapters.DiffAdapter

  @type addition :: {:added, term}
  @type removal :: {:removed, term}
  @type change :: {:changed, changes}
  @type primitive_change :: {:primitive_change, removed :: term, added :: term}
  @type list_addition :: {:added_to_list, index :: integer, term}
  @type list_removal :: {:removed_from_list, index :: integer, term}
  @type list_change :: {:changed_in_list, index :: integer, changes}
  @type no_change :: :not_changed
  @type changes ::
          addition
          | removal
          | change
          | list_addition
          | list_removal
          | list_change
          | no_change
          | primitive_change
          | %{any: changes}
          | [changes]

  @undefined :"$undefined"

  @doc """
  Creates a patch that can be used to go from a to b with the ExAudit.Patch.patch function
  """
  @spec diff(term, term) :: changes
  def diff(a, b)

  def diff(a, a) do
    :not_changed
  end

  def diff(%{__struct__: a_struct} = a, %{__struct__: b_struct} = b) do
    if primitive_struct?(a_struct) and primitive_struct?(b_struct) do
      {:primitive_change, a, b}
    else
      diff(Map.from_struct(a), Map.from_struct(b))
    end
  end

  def diff(%{} = a, %{} = b) do
    all_keys =
      (Map.keys(a) ++ Map.keys(b))
      |> Enum.uniq()

    changes =
      Enum.map(all_keys, fn key ->
        value_a = Map.get(a, key, @undefined)
        value_b = Map.get(b, key, @undefined)

        case {value_a, value_b} do
          {a, a} ->
            nil

          {@undefined, b} ->
            {key, {:added, b}}

          {a, @undefined} ->
            {key, {:removed, a}}

          {a, b} ->
            {key, {:changed, diff(a, b)}}
        end
      end)
      |> Enum.reject(&is_nil/1)

    case length(changes) do
      0 -> :not_changed
      _ -> Enum.into(changes, %{})
    end
  end

  def diff(a, b) when is_list(a) and is_list(b) do
    indexes = 0..:erlang.max(length(a) - 1, length(b) - 1)

    changes =
      for i <- indexes, into: [] do
        value_a = Enum.at(a, i, @undefined)
        value_b = Enum.at(b, i, @undefined)

        case {value_a, value_b} do
          {a, a} ->
            nil

          {@undefined, b} ->
            {:added_to_list, i, b}

          {a, @undefined} ->
            {:removed_from_list, i, a}

          {a, b} ->
            {:changed_in_list, i, diff(a, b)}
        end
      end

    changes = Enum.reject(changes, &is_nil/1)

    case length(changes) do
      0 -> :not_changed
      _ -> changes
    end
  end

  def diff(a, b) do
    {:primitive_change, a, b}
  end

  @doc """
  Reverts a patch so that it can undo a change
  """
  @spec reverse(changes) :: changes
  def reverse(:not_changed), do: :not_changed

  def reverse({:primitive_change, a, b}), do: {:primitive_change, b, a}

  def reverse({:added, a}), do: {:removed, a}

  def reverse({:removed, a}), do: {:added, a}

  def reverse({:changed, changes}), do: {:changed, reverse(changes)}

  def reverse({:added_to_list, index, value}), do: {:removed_from_list, index, value}

  def reverse({:removed_from_list, index, value}), do: {:added_to_list, index, value}

  def reverse({:changed_in_list, index, changes}), do: {:changed_in_list, index, reverse(changes)}

  def reverse(changes) when is_map(changes) do
    changes
    |> Enum.map(fn {key, change} -> {key, reverse(change)} end)
    |> Enum.into(%{})
  end

  def reverse(changes) when is_list(changes) do
    changes
    |> Enum.reverse()
    |> Enum.map(&reverse/1)
  end

  @doc """
  Applies the patch to the given term
  """
  def patch(_, {:primitive_change, _, b}) do
    b
  end

  def patch(a, :not_changed) do
    a
  end

  def patch(list, changes) when is_list(list) and is_list(changes) do
    changes
    |> Enum.reverse()
    |> Enum.reduce(list, fn
      {:added_to_list, i, el}, list ->
        List.insert_at(list, i, el)

      {:removed_from_list, i, _}, list ->
        List.delete_at(list, i)

      {:changed_in_list, i, change}, list ->
        List.update_at(list, i, &patch(&1, change))
    end)
  end

  def patch(map, changes) when is_map(map) and is_map(changes) do
    changes
    |> Enum.reduce(map, fn
      {key, {:added, b}}, map ->
        Map.put(map, key, b)

      {key, {:removed, _}}, map ->
        Map.delete(map, key)

      {key, {:changed, changes}}, map ->
        Map.update!(map, key, &patch(&1, changes))
    end)
  end

  ## PRIVATE

  defp primitive_struct?(type) do
    primitive_structs = Application.get_env(:ex_audit, :primitive_structs, [])

    type in primitive_structs
  end
end
