defmodule Adapters.ErlangBinaryDiffTest do
  use ExUnit.Case

  alias ExAudit.Adapters.ErlangBinaryDiff, as: Diff
  doctest Diff

  test "should diff primitives" do
    assert {:primitive_change, :foo, :bar} = Diff.diff(:foo, :bar)
  end

  test "should diff lists" do
    a = [1, 2, 3]
    b = [1, 4, 6, 1]

    assert Diff.diff(a, b) == [
             {:changed_in_list, 1, {:primitive_change, 2, 4}},
             {:changed_in_list, 2, {:primitive_change, 3, 6}},
             {:added_to_list, 3, 1}
           ]

    assert Diff.diff(b, a) == [
             {:changed_in_list, 1, {:primitive_change, 4, 2}},
             {:changed_in_list, 2, {:primitive_change, 6, 3}},
             {:removed_from_list, 3, 1}
           ]
  end

  test "should diff maps" do
    a = %{
      foo: 1,
      bar: 12
    }

    b = %{
      foo: 2,
      bar: 12
    }

    assert Diff.diff(a, b) == %{
             foo: {:changed, {:primitive_change, 1, 2}}
           }
  end

  test "should detect if there were no changes" do
    assert :not_changed == Diff.diff(:foo, :foo)
    assert :not_changed == Diff.diff([], [])
    assert :not_changed == Diff.diff([1, 2], [1, 2])
    assert :not_changed == Diff.diff(%{}, %{})
    assert :not_changed == Diff.diff(%{foo: 1}, %{foo: 1})
  end

  test "should detect deep changes" do
    a = %{
      foo: %{
        value: 13
      },
      baz: 1
    }

    b = %{
      foo: %{
        value: 12
      },
      bar: 12
    }

    assert Diff.diff(a, b) == %{
             foo:
               {:changed,
                %{
                  value: {:changed, {:primitive_change, 13, 12}}
                }},
             bar: {:added, 12},
             baz: {:removed, 1}
           }
  end

  test "structs configured as primitives are treated as primitives" do
    val1 = Date.new(2020, 1, 1)
    val2 = Date.new(2020, 2, 2)

    a = %{foo: val1}
    b = %{foo: val2}

    assert %{foo: {:changed, {:primitive_change, val1, val2}}} == Diff.diff(a, b)
  end

  test "should apply primitive changes" do
    assert_patching(:foo, :bar)
  end

  test "should cope with :not_changed" do
    assert_patching(:foo, :foo)
  end

  test "should apply patches to lists" do
    assert_patching([1, 2, 3], [1, 2, 4, 5])
    assert_patching([1, 2, 3], [])
  end

  test "should apply patches to maps" do
    assert_patching(%{a: 1, b: 2}, %{a: 3, b: 4})
    assert_patching(%{}, %{foo: 3})
    assert_patching(%{foo: 42}, %{})
  end

  test "should apply patches to complex structures" do
    a = [%{foo: [1, 2, 3]}]
    b = [%{foo: [1, 2, 3, 4]}]

    assert_patching(a, b)
  end

  defp assert_patching(a, b) do
    patch = Diff.diff(a, b)
    assert b == Diff.patch(a, patch)
    assert a == Diff.patch(b, Diff.reverse(patch))
  end
end
